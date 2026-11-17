#!/usr/bin/env python3
# =============================================================================
# verilog2spice.py : netlist Verilog structurelle (OpenROAD) -> SPICE pour le LVS
#
# Pourquoi : run_lvs.py (KLayout, PDK IHP) n'accepte comme schéma que du SPICE/CDL,
# alors qu'OpenROAD écrit du Verilog (openroad/out/<proj>_lvs.v, avec VDD/VSS).
# Ce script lit le Verilog, récupère l'ordre des broches de chaque cellule dans les
# fichiers CDL du PDK (cellules standard, IO, SRAM), et écrit un fichier SPICE
# contenant : les sous-circuits CDL réellement utilisés + le sous-circuit du top.
#
# Hypothèses (vraies pour la sortie de write_verilog d'OpenROAD, à vérifier au 1er run) :
#   - un seul module à plat (pas de hiérarchie) ; les instances sont des cellules du PDK
#   - connexions nommées .PIN(net) ; bus de macros écrits .PIN({a, b, ...}) ou .PIN[i](net)
#   - noms échappés (\foo[3] ) possibles
# Les cellules absentes des CDL (ex. bondpads, remplissage) sont ignorées avec un
# avertissement "cellule inconnue" : elles n'ont pas de dispositifs à comparer.
#
# Usage :
#   verilog2spice.py --verilog croc_lvs.v --top croc_chip --out croc_schematic.cir \
#                    --cdl a.cdl --cdl b.cdl ...  [--strict]
# =============================================================================
import argparse
import collections
import re
import sys

ID = r'(?:\\\S+|[A-Za-z_][\w$]*)'          # identifiant Verilog (échappé ou non)


def info(msg):
    print(f"[verilog2spice] {msg}")


def warn(msg):
    print(f"[verilog2spice] [WARNING] {msg}")


# ----------------------------------------------------------------------------
# Lecture des CDL : ordre des broches + texte brut de chaque .SUBCKT
# ----------------------------------------------------------------------------
def norm_pin(p):
    """CDL/SPICE peut écrire A<0> ou A[0] : on normalise en A[0], sans casse."""
    return p.replace('<', '[').replace('>', ']').lower()


def read_cdl(paths):
    """Retourne {nom_minuscule: (nom, [broches], [lignes brutes])}."""
    cells = {}
    for path in paths:
        with open(path, errors='replace') as f:
            raw = f.read().splitlines()
        # fusion des lignes de continuation '+'
        merged = []
        for line in raw:
            if line.startswith('+') and merged:
                merged[-1] += ' ' + line[1:].strip()
            else:
                merged.append(line)
        cur = None
        for line in merged:
            s = line.strip()
            low = s.lower()
            if low.startswith('.subckt'):
                toks = s.split()
                name = toks[1]
                pins = []
                for t in toks[2:]:
                    if '=' in t:       # début des paramètres
                        break
                    if t == '/':
                        continue
                    pins.append(t)
                cur = (name, pins, [s])
            elif low.startswith('.ends') and cur:
                cur[2].append(s)
                cells[cur[0].lower()] = cur
                cur = None
            elif cur is not None:
                cur[2].append(line)
    return cells


def called_subckts(lines):
    """Noms de sous-circuits appelés (lignes X...) dans le corps d'un sous-circuit."""
    out = []
    for line in lines[1:]:
        s = line.strip()
        if not s or s[0] not in 'xX':
            continue
        toks = s.split()
        if '/' in toks:
            out.append(toks[toks.index('/') + 1])
        else:
            out.append([t for t in toks[1:] if '=' not in t][-1])
    return out


# ----------------------------------------------------------------------------
# Lecture du Verilog
# ----------------------------------------------------------------------------
def clean_verilog(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    text = re.sub(r'//[^\n]*', ' ', text)
    text = re.sub(r'\(\*.*?\*\)', ' ', text, flags=re.S)
    return text.replace('endmodule', 'endmodule;')


def net_name(tok):
    """\\foo[3]  ->  foo[3]  (le nom échappé et le nom indexé désignent le même net)."""
    tok = tok.strip()
    return tok[1:] if tok.startswith('\\') else tok


class Module:
    def __init__(self, name):
        self.name = name
        self.port_order = []          # noms tels que dans l'en-tête (bus non étendus)
        self.ranges = {}              # nom -> (msb, lsb) pour les bus déclarés
        self.direction = {}           # nom -> input/output/inout
        self.instances = []           # (cellule, instance, {broche: expr})
        self.alias = {}               # union-find des 'assign'

    # -- étend une expression Verilog en liste de nets (MSB d'abord) ----------
    def expand(self, expr):
        expr = expr.strip()
        if not expr:
            return []
        if expr.startswith('{') and expr.endswith('}'):
            out = []
            for part in re.split(r',(?![^\[]*\])', expr[1:-1]):
                out += self.expand(part)
            return out
        if re.match(r"^\d+'[bBhHdD]", expr) or re.match(r'^\d+$', expr):
            return ['__CONST_' + expr.replace("'", '_') + '__']
        m = re.match(r'^(' + ID + r')\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]$', expr)
        if m:                                           # sélection partielle foo[3:0]
            msb, lsb = int(m.group(2)), int(m.group(3))
            step = -1 if msb >= lsb else 1
            return [f"{net_name(m.group(1))}[{i}]" for i in range(msb, lsb + step, step)]
        name = net_name(expr)
        if name in self.ranges and not re.search(r'\[\d+\]$', name):
            msb, lsb = self.ranges[name]
            step = -1 if msb >= lsb else 1
            return [f"{name}[{i}]" for i in range(msb, lsb + step, step)]
        return [name]

    # -- alias (assign) --------------------------------------------------------
    def find(self, n):
        while n in self.alias:
            n = self.alias[n]
        return n

    def union(self, lhs, rhs):
        a, b = self.find(lhs), self.find(rhs)
        if a == b:
            return
        # on garde comme représentant un port si possible
        if self.is_port(a) and not self.is_port(b):
            self.alias[b] = a
        else:
            self.alias[a] = b

    def is_port(self, n):
        base = re.sub(r'\[\d+\]$', '', n)
        return base in self.direction


def parse_verilog(path, top):
    with open(path, errors='replace') as f:
        text = clean_verilog(f.read())
    modules = {}
    cur = None
    for stmt in text.split(';'):
        s = ' '.join(stmt.split()) if '\\' not in stmt else stmt.strip()
        s = s.strip()
        if not s:
            continue
        if s.startswith('endmodule'):
            cur = None
            continue
        m = re.match(r'^module\s+(' + ID + r')\s*\((.*)\)$', s, flags=re.S)
        if m:
            cur = Module(net_name(m.group(1)))
            modules[cur.name] = cur
            cur.port_order = [net_name(p) for p in re.findall(ID, m.group(2))]
            continue
        if cur is None:
            continue
        m = re.match(r'^(input|output|inout|wire|tri|supply0|supply1)\s*'
                     r'(?:\[\s*(\d+)\s*:\s*(\d+)\s*\])?\s*(.*)$', s, flags=re.S)
        if m:
            kind, msb, lsb, names = m.groups()
            for n in re.findall(ID, names):
                n = net_name(n)
                if msb is not None:
                    cur.ranges[n] = (int(msb), int(lsb))
                if kind in ('input', 'output', 'inout'):
                    cur.direction[n] = kind
            continue
        m = re.match(r'^assign\s+(.+?)\s*=\s*(.+)$', s, flags=re.S)
        if m:
            lhs, rhs = cur.expand(m.group(1)), cur.expand(m.group(2))
            if len(lhs) != len(rhs):
                warn(f"assign ignoré (largeurs différentes) : {s[:80]}")
            else:
                for a, b in zip(lhs, rhs):
                    cur.union(a, b)
            continue
        m = re.match(r'^(' + ID + r')\s+(?:#\s*\(.*?\)\s*)?(' + ID + r')\s*\((.*)\)$', s, flags=re.S)
        if m:
            cell, inst, body = net_name(m.group(1)), net_name(m.group(2)), m.group(3)
            conns = {}
            for pm in re.finditer(r'\.\s*(' + ID + r'(?:\[\d+\])?)\s*\(\s*(.*?)\s*\)\s*(?:,|$)',
                                  body, flags=re.S):
                conns[net_name(pm.group(1))] = pm.group(2)
            cur.instances.append((cell, inst, conns))
            continue
        warn(f"instruction Verilog non reconnue, ignorée : {s[:80]}")
    if top not in modules:
        sys.exit(f"[verilog2spice] ERREUR : module top '{top}' introuvable "
                 f"(modules lus : {', '.join(modules) or 'aucun'})")
    return modules[top]


# ----------------------------------------------------------------------------
# Écriture SPICE
# ----------------------------------------------------------------------------
def net_safe(name):
    """Un '/' isolé a un sens en CDL : on le remplace dans les noms de nets."""
    return re.sub(r'\s', '_', name.replace('/', '.'))


def spice_safe(name):
    """Pas d'espace ni de caractère spécial dans les noms d'instance."""
    return re.sub(r'[^A-Za-z0-9_.$\[\]]', '_', name)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument('--verilog', required=True)
    ap.add_argument('--top', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--cdl', action='append', required=True, help='fichier CDL (répétable)')
    ap.add_argument('--strict', action='store_true',
                    help='code retour 1 si une cellule est absente des CDL')
    args = ap.parse_args()

    lib = read_cdl(args.cdl)
    info(f"{len(lib)} sous-circuits lus dans {len(args.cdl)} fichier(s) CDL")
    top = parse_verilog(args.verilog, args.top)
    info(f"module '{top.name}' : {len(top.instances)} instances")

    # ports du top, bus étendus (MSB d'abord)
    ports = []
    for p in top.port_order:
        ports += top.expand(p) if p in top.ranges else [p]
    ports = [net_safe(top.find(p)) for p in ports]

    lines, used_cells = [], collections.OrderedDict()
    unknown = collections.Counter()
    floating = 0
    seen = collections.Counter()

    for cell, inst, conns in top.instances:
        entry = lib.get(cell.lower())
        if entry is None:
            unknown[cell] += 1
            continue
        name, pins, _ = entry
        used_cells[name.lower()] = entry
        # connexions étendues en bits : { 'a_addr[3]': 'net', ... }
        bits = {}
        for pin, expr in conns.items():
            nets = top.expand(expr)
            if len(nets) == 1 and norm_pin(pin) in {norm_pin(p) for p in pins}:
                bits[norm_pin(pin)] = nets[0]
            elif len(nets) == 1 and re.search(r'\[\d+\]$', pin):
                bits[norm_pin(pin)] = nets[0]
            else:
                n = len(nets)
                for i, net in enumerate(nets):          # nets[0] = MSB
                    bits[norm_pin(f"{pin}[{n - 1 - i}]")] = net
        nets_out = []
        for p in pins:
            net = bits.get(norm_pin(p))
            if net is None:
                floating += 1
                net = f"__nc_{spice_safe(inst)}_{spice_safe(p)}"
            nets_out.append(net_safe(top.find(net)))
        iname = 'X' + spice_safe(inst)
        seen[iname] += 1
        if seen[iname] > 1:
            iname += f"__{seen[iname]}"
        lines.append(f"{iname} {' '.join(nets_out)} {name}")

    # fermeture transitive : sous-circuits appelés par les sous-circuits utilisés
    todo = list(used_cells.values())
    while todo:
        _, _, body = todo.pop()
        for called in called_subckts(body):
            e = lib.get(called.lower())
            if e and e[0].lower() not in used_cells:
                used_cells[e[0].lower()] = e
                todo.append(e)

    with open(args.out, 'w') as f:
        f.write(f"* Netlist SPICE générée par verilog2spice.py\n* source : {args.verilog}\n")
        for _, (_, _, body) in used_cells.items():
            f.write('\n'.join(body) + '\n')
        f.write(f"\n.SUBCKT {top.name} {' '.join(ports)}\n")
        f.write('\n'.join(lines) + '\n')
        f.write(f".ENDS {top.name}\n.END\n")

    info(f"{len(lines)} instances écrites, {len(used_cells)} sous-circuits CDL inclus -> {args.out}")
    if floating:
        warn(f"{floating} broche(s) de cellule non connectée(s) dans le Verilog (laissées flottantes)")
    for cell, n in unknown.most_common():
        warn(f"cellule inconnue (ignorée) : {cell} x{n}")
    if unknown and args.strict:
        sys.exit(1)


if __name__ == '__main__':
    main()
