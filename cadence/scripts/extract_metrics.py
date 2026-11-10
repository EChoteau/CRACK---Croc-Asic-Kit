#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# CRACK - Extraction des métriques de synthèse (VAL-22 : script unique)
#
# Lit les rapports des deux flots et écrit les métriques dans un format commun
# (JSON pour les scripts, TXT lisible, CSV pour un tableur), puis compare.
#
#   extract_metrics.py genus   <run_dir>        run du flot licence (cadence/runs/...)
#   extract_metrics.py yosys   <yosys_dir>      dossier yosys/ du flot open (reports/)
#   extract_metrics.py compare <a.json> <b.json> [-o fichier.txt]
#   extract_metrics.py sweep   <*.json ...>     [-o sweep.txt]   (tableau du balayage)
#
# Options communes :
#   --lib-dir <dir>   dossier des .lib (défaut : technology/lib ou ihp13/pdk/lib)
#   -o <fichier>      sortie (défaut : à côté des rapports, voir chaque commande)
#
# Equité (VAL-22) : les comptes et surfaces par catégorie (séquentiel, logique,
# buffers, inverseurs, SRAM, pads...) sont RECALCULÉS de la même façon pour les
# deux flots, à partir du nombre d'instances par cellule x surface de la cellule
# dans la liberty typ. Les valeurs propres à chaque outil sont gardées à part
# (préfixe "tool_").
#
# Compatible Python 2.7 et 3.x, bibliothèque standard uniquement.
# =============================================================================
from __future__ import print_function, division

import argparse
import csv
import glob
import io
import json
import os
import re
import sys
import time

CRACK_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CROC_ROOT = os.path.dirname(CRACK_ROOT)


# -----------------------------------------------------------------------------
# Utilitaires
# -----------------------------------------------------------------------------
def _say(line):
    """print robuste : au CIME, LANG=C rend la sortie ASCII (accents refusés)."""
    try:
        print(line)
    except UnicodeEncodeError:
        enc = getattr(sys.stdout, "encoding", None) or "ascii"
        print(line.encode(enc, "replace").decode(enc))


def info(msg):
    _say("[CRACK][INFO] " + msg)


def warn(msg):
    _say("[CRACK][WARNING] " + msg)


def csv_open(path):
    """Fichier CSV en UTF-8, indépendant de la langue du système (py2 et py3)."""
    if sys.version_info[0] >= 3:
        return io.open(path, "w", encoding="utf-8", newline="")
    return open(path, "wb")


def read(path):
    """Contenu d'un fichier texte, '' s'il n'existe pas."""
    if not path or not os.path.isfile(path):
        return ""
    with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def to_num(s):
    try:
        v = float(s)
        return int(v) if v.is_integer() and "." not in s and "e" not in s.lower() else v
    except (TypeError, ValueError):
        return None


def default_lib_dir():
    for d in (os.path.join(CROC_ROOT, "technology", "lib"),
              os.path.join(CROC_ROOT, "ihp13", "pdk", "lib")):
        if os.path.isdir(d):
            return d
    return None


# -----------------------------------------------------------------------------
# Liberty : surface + type de chaque cellule (lecture légère, sans parseur)
# -----------------------------------------------------------------------------
RE_CELL = re.compile(r'^\s*cell\s*\(\s*"?([A-Za-z0-9_]+)"?\s*\)')
RE_AREA = re.compile(r'^\s*area\s*:\s*([0-9.eE+-]+)')
RE_SEQ = re.compile(r'^\s*(ff|latch|ff_bank|latch_bank|statetable)\s*\(')
RE_SCAN = re.compile(r'^\s*test_cell\s*\(')


def load_liberty(lib_dir):
    """{cellule: {"area": float, "seq": bool, "scan": bool}} pour les .lib typ."""
    cells = {}
    if not lib_dir:
        warn("dossier liberty introuvable : surfaces recalculées indisponibles")
        return cells
    files = sorted(glob.glob(os.path.join(lib_dir, "*typ*.lib")))
    if not files:
        warn("aucune liberty *typ*.lib dans " + lib_dir)
    for f in files:
        cur = None
        with io.open(f, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = RE_CELL.match(line)
                if m:
                    cur = m.group(1)
                    cells.setdefault(cur, {"area": None, "seq": False, "scan": False})
                    continue
                if cur is None:
                    continue
                m = RE_AREA.match(line)
                if m and cells[cur]["area"] is None:
                    cells[cur]["area"] = float(m.group(1))
                elif RE_SEQ.match(line):
                    cells[cur]["seq"] = True
                elif RE_SCAN.match(line):
                    cells[cur]["scan"] = True
    info("liberty : %d cellules lues dans %s" % (len(cells), lib_dir))
    return cells


def classify(name, lib):
    """Catégorie commune aux deux flots."""
    n = name.lower()
    if n.startswith("rm_ihpsg13"):
        return "sram"
    if "iopad" in n or n.startswith("bondpad"):
        return "pad"
    meta = lib.get(name, {})
    if meta.get("seq") or re.search(r"_(s?df|dl[hl])", n):
        return "seq"
    if "_tie" in n:
        return "tie"
    if "_inv_" in n:
        return "inverter"
    if "_buf_" in n or "dlygate" in n:
        return "buffer"
    return "logic"


def cell_metrics(hist, lib):
    """Métriques communes calculées depuis l'histogramme {cellule: nombre}."""
    m = {}
    cats = ["seq", "logic", "inverter", "buffer", "tie", "sram", "pad"]
    count = dict((c, 0) for c in cats)
    area = dict((c, 0.0) for c in cats)
    missing = []
    for cell, n in hist.items():
        c = classify(cell, lib)
        count[c] += n
        a = lib.get(cell, {}).get("area")
        if a is None:
            missing.append(cell)
        else:
            area[c] += n * a
    scan = sum(n for cell, n in hist.items() if lib.get(cell, {}).get("scan"))
    std = ["seq", "logic", "inverter", "buffer", "tie"]

    m["cells_total"] = sum(hist.values())
    m["cells_std"] = sum(count[c] for c in std)
    m["cells_comb"] = count["logic"] + count["inverter"] + count["buffer"] + count["tie"]
    for c in cats:
        m["cells_" + c] = count[c]
    m["cells_seq_scan"] = scan
    m["cell_types_used"] = len(hist)

    m["area_std_um2"] = round(sum(area[c] for c in std), 3)
    m["area_comb_um2"] = round(area["logic"] + area["inverter"] + area["buffer"] + area["tie"], 3)
    for c in cats:
        m["area_" + c + "_um2"] = round(area[c], 3)
    m["area_total_um2"] = round(sum(area.values()), 3)
    if m["area_std_um2"]:
        m["ratio_seq_area_pct"] = round(100.0 * area["seq"] / m["area_std_um2"], 2)
        m["ratio_bufinv_area_pct"] = round(
            100.0 * (area["buffer"] + area["inverter"]) / m["area_std_um2"], 2)
    if missing:
        warn("surface inconnue (absente des .lib) : " + ", ".join(sorted(missing)))
    return m


# -----------------------------------------------------------------------------
# Genus
# -----------------------------------------------------------------------------
def parse_genus_gates(txt, lib):
    """04_gates.rpt : 1er tableau 'Gate  Instances  Area  Library'."""
    hist = {}
    in_tab = False
    for line in txt.splitlines():
        if re.match(r"^\s*Gate\s+Instances", line):
            in_tab = True
            continue
        if not in_tab:
            continue
        if line.startswith("total"):
            break
        t = line.split()
        if len(t) >= 3 and t[1].isdigit() and not line.startswith("-"):
            hist[t[0]] = hist.get(t[0], 0) + int(t[1])
    return hist


def parse_genus_qor(txt, m):
    # Tableau "Analysis View / Cost Group / Critical Path Slack / TNS / Violating"
    # (lignes entre l'en-tête et "Total")
    view = None
    in_tab = False
    for line in txt.splitlines():
        if re.match(r"^\s*Analysis\s+Cost\s+Critical", line):
            in_tab = True
            continue
        if not in_tab:
            continue
        if line.startswith("Total") or line.startswith("Instance Count"):
            break
        t = line.split()
        if not t or line.startswith("-") or t[0] == "View":
            continue
        if t[0].startswith("view_"):
            view = t[0]
            t = t[1:]
        if view is None or len(t) < 4:
            continue
        group = t[0]
        if t[1] == "No":          # "No paths"
            continue
        m["tool_slack_%s_%s_ps" % (view, group)] = to_num(t[1])
        m["tool_tns_%s_%s_ps" % (view, group)] = to_num(t[2])
        m["tool_viol_paths_%s_%s" % (view, group)] = to_num(t[3])
    pats = {
        "tool_leaf_instances": r"Leaf Instance Count\s+(\d+)",
        "tool_seq_instances": r"Sequential Instance Count\s+(\d+)",
        "tool_comb_instances": r"Combinational Instance Count\s+(\d+)",
        "tool_hier_instances": r"Hierarchical Instance Count\s+(\d+)",
        "tool_cell_area_um2": r"^Cell Area\s+([\d.]+)",
        "tool_net_area_um2": r"^Net Area\s+([\d.]+)",
        "tool_total_area_um2": r"Total Area \(Cell\+Physical\+Net\)\s+([\d.]+)",
        "tool_max_fanout": r"Max Fanout\s+(\d+)",
        "tool_avg_fanout": r"Average Fanout\s+([\d.]+)",
        "tool_runtime_cpu_s": r"^Runtime\s+([\d.]+)",
        "tool_runtime_elapsed_s": r"Elapsed Runtime\s+([\d.]+)",
        "tool_peak_mem_mb": r"Genus peak memory usage\s+([\d.]+)",
    }
    for k, p in pats.items():
        r = re.search(p, txt, re.M)
        if r:
            m[k] = to_num(r.group(1))
    r = re.search(r"Max Fanout\s+\d+\s+\((\S+)\)", txt)
    if r:
        m["tool_max_fanout_net"] = r.group(1)


def parse_genus_timing_summary(txt, m):
    for line in txt.splitlines():
        r = re.match(r"\s*Group\s*:\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", line)
        if r and r.group(2) != "N/A":
            g = r.group(1)
            m["tool_wns_%s_ps" % g] = to_num(r.group(2))
            m["tool_tns_%s_ps" % g] = to_num(r.group(3))
            m["tool_fep_%s" % g] = to_num(r.group(4))
        r = re.match(r"\s*View:\s*ALL\s+(\S+)\s+(\S+)\s+(\d+)", line)
        if r:
            m["wns_setup_ps"] = to_num(r.group(1))
            m["tns_setup_ps"] = to_num(r.group(2))
            m["fep_setup"] = to_num(r.group(3))
        r = re.match(r"\s*Check:\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", line)
        if r and r.group(2) != "N/A":
            c = r.group(1)
            m["drv_%s_worst" % c] = to_num(r.group(2))
            m["drv_%s_total" % c] = to_num(r.group(3))
            m["drv_%s_count" % c] = to_num(r.group(4))


def parse_genus_power(txt, m):
    for line in txt.splitlines():
        t = line.split()
        if len(t) >= 6 and t[0] in ("memory", "register", "latch", "logic", "bbox",
                                    "clock", "pad", "pm", "Subtotal"):
            k = "total" if t[0] == "Subtotal" else t[0]
            m["power_%s_mw" % k] = round(float(t[4]) * 1e3, 4)
            if k == "total":
                m["power_leakage_mw"] = round(float(t[1]) * 1e3, 6)
                m["power_internal_mw"] = round(float(t[2]) * 1e3, 4)
                m["power_switching_mw"] = round(float(t[3]) * 1e3, 4)


def parse_genus_clocks(txt, m):
    for line in txt.splitlines():
        t = line.split()
        if len(t) == 8 and t[0].startswith("view_") and t[5].startswith("domain"):
            m["clk_%s_period_ps" % t[1]] = to_num(t[2])
            m["clk_%s_registers" % t[1]] = to_num(t[7])


def parse_genus_blocks(txt):
    """04_area_hier.rpt -> {instance: {module, cells, cell_area, total_area}}."""
    blocks = {}
    for line in txt.splitlines():
        t = line.split()
        if len(t) == 6 and t[2].isdigit():
            blocks[t[0]] = {"cells": int(t[2]), "cell_area_um2": to_num(t[3]),
                            "total_area_um2": to_num(t[5])}
        elif len(t) == 5 and t[1].isdigit():  # top (pas de nom de module)
            blocks[t[0]] = {"cells": int(t[1]), "cell_area_um2": to_num(t[2]),
                            "total_area_um2": to_num(t[4])}
    return blocks


def kv_file(path):
    d = {}
    for line in read(path).splitlines():
        t = line.split(None, 1)
        if len(t) == 2:
            d[t[0]] = t[1].strip()
    return d


def extract_genus(run_dir, lib):
    rpt = os.path.join(run_dir, "genus", "reports")
    if not os.path.isdir(rpt):
        sys.exit("[CRACK][ERROR] pas de genus/reports dans " + run_dir)
    ri = kv_file(os.path.join(run_dir, "run_info.txt"))
    m = {"flow": "licence", "tool": "genus",
         "tool_version": read(os.path.join(rpt, "tool_version.txt")).replace("genus", "").strip()
         or "inconnue",
         "run": ri.get("run_name", os.path.basename(run_dir.rstrip("/"))),
         "tech": ri.get("tech", ""), "git_commit": ri.get("git_commit", ""),
         "clk_sys_target_ns": to_num(ri.get("clk_sys_ns", "")),
         "profile": ri.get("profile", "iso")}

    hist = parse_genus_gates(read(os.path.join(rpt, "04_gates.rpt")), lib)
    if not hist:
        warn("04_gates.rpt absent ou vide")
    m.update(cell_metrics(hist, lib))
    parse_genus_qor(read(os.path.join(rpt, "04_qor.rpt")), m)
    parse_genus_timing_summary(read(os.path.join(rpt, "04_timing_summary.rpt")), m)
    parse_genus_power(read(os.path.join(rpt, "04_power.rpt")), m)
    parse_genus_clocks(read(os.path.join(rpt, "04_clocks.rpt")), m)

    rt = re.search(r"genus_runtime_s\s+(\d+)", read(os.path.join(rpt, "runtime.txt")))
    if rt:
        m["runtime_s"] = int(rt.group(1))
    elif "tool_runtime_elapsed_s" in m:
        m["runtime_s"] = m["tool_runtime_elapsed_s"]

    hier = read(os.path.join(rpt, "03_hierarchy.rpt"))
    if hier:
        m["hier_instances_kept"] = len([l for l in hier.splitlines()
                                        if l.strip() and not l.startswith("#")])
    regs = read(os.path.join(rpt, "04_registers.rpt"))
    r = re.match(r"#\s*(\d+)", regs)
    if r:
        m["tool_registers"] = int(r.group(1))

    # Fréquence max estimée sur clk_sys : période - slack (indicative, synthèse)
    sl = m.get("tool_slack_view_tt_clk_sys_ps")
    if m.get("clk_sys_target_ns"):
        m["clk_sys_target_mhz"] = round(1000.0 / m["clk_sys_target_ns"], 2)
    if sl is not None and m.get("clk_sys_target_ns"):
        per = m["clk_sys_target_ns"] * 1000.0
        m["fmax_clk_sys_est_mhz"] = round(1e6 / (per - sl), 2) if per - sl > 0 else None

    blocks = parse_genus_blocks(read(os.path.join(rpt, "04_area_hier.rpt")))
    return {"metrics": m, "cells": hist, "blocks": blocks}


# -----------------------------------------------------------------------------
# Yosys
# -----------------------------------------------------------------------------
def parse_yosys_stat(txt, lib):
    """Histogramme des cellules dans un rapport 'stat' (formats anciens et
    récents). Si le rapport est hiérarchique, seule la section
    '=== design hierarchy ===' (totaux aplatis) est lue."""
    i = txt.find("=== design hierarchy ===")
    if i >= 0:
        txt = txt[i:]
    hist = {}
    for line in txt.splitlines():
        t = line.split()
        names = [x for x in t if x in lib]
        ints = [x for x in t if x.isdigit()]
        if len(names) == 1 and ints:
            hist[names[0]] = hist.get(names[0], 0) + int(ints[0])
    return hist


def extract_yosys(ydir, lib, proj="croc"):
    rpt = os.path.join(ydir, "reports")
    if not os.path.isdir(rpt):
        sys.exit("[CRACK][ERROR] pas de reports/ dans " + ydir +
                 " (lancer d'abord le flot open : ./run_synthesis.sh --synth)")
    area_txt = read(os.path.join(rpt, proj + "_area.rpt"))
    if not area_txt:
        sys.exit("[CRACK][ERROR] %s_area.rpt introuvable dans %s" % (proj, rpt))
    m = {"flow": "open", "tool": "yosys", "tool_version": "inconnue",
         "run": os.path.abspath(ydir), "tech": os.environ.get("CROC_PDK", ""),
         "clk_sys_target_ns": 10.0}
    hist = parse_yosys_stat(area_txt, lib)
    if not hist:
        warn("aucune cellule reconnue dans %s_area.rpt (format ?)" % proj)
    m.update(cell_metrics(hist, lib))

    areas = re.findall(r"Chip area for (top )?module '\\?([^']+)':\s*([\d.]+)", area_txt)
    tops = [a for a in areas if a[0]]
    if tops or areas:
        m["tool_cell_area_um2"] = to_num((tops or areas)[-1][2])

    regs = read(os.path.join(rpt, proj + "_registers.rpt"))
    if regs:
        m["tool_registers"] = len([l for l in regs.splitlines() if l.strip()])
    for line in read(os.path.join(rpt, proj + "_synth.rpt")).splitlines():
        r = re.search(r"Found and reported (\d+) problems", line)
        if r:
            m["tool_check_problems"] = int(r.group(1))
    m["timing_note"] = "pas de STA dans Yosys (timing mesuré par OpenSTA au P&R)"
    return {"metrics": m, "cells": hist, "blocks": {}}


# -----------------------------------------------------------------------------
# Ecriture
# -----------------------------------------------------------------------------
SECTIONS = [
    ("Identification", r"^(flow|tool|tool_version|run|tech|git_commit|clk_sys_target_ns|clk_sys_target_mhz|profile)$"),
    ("Timing (setup, coin tt)", r"^(wns|tns|fep|fmax|tool_wns|tool_tns|tool_fep|tool_slack|tool_viol|clk_)"),
    ("Règles électriques (DRV)", r"^drv_"),
    ("Cellules (calcul commun)", r"^(cells_|cell_types)"),
    ("Surface (calcul commun, liberty typ)", r"^(area_|ratio_)"),
    ("Surface / comptes (outil)", r"^tool_(cell_area|net_area|total_area|leaf|seq_inst|comb|hier|registers|max_fanout|avg_fanout|check)"),
    ("Puissance (outil, sans activité)", r"^power_"),
    ("Exécution", r"^(runtime|tool_runtime|tool_peak)"),
    ("Divers", r".*"),
]


def write_txt(data, path):
    m = data["metrics"]
    done = set()
    out = []
    out.append("# Métriques de synthèse CRACK - %s (%s)" % (m.get("tool"), m.get("flow")))
    out.append("# généré le %s par cadence/scripts/extract_metrics.py" % time.strftime("%Y-%m-%d %H:%M"))
    for title, pat in SECTIONS:
        keys = [k for k in sorted(m) if k not in done and re.match(pat, k)]
        if not keys:
            continue
        out.append("")
        out.append("== " + title)
        for k in keys:
            out.append("  %-42s %s" % (k, m[k]))
            done.add(k)
    if data.get("blocks"):
        out.append("")
        out.append("== Surface par bloc (outil)")
        for b, v in sorted(data["blocks"].items(), key=lambda x: -(x[1].get("total_area_um2") or 0)):
            out.append("  %-50s %8s cellules  %14s µm²" % (b, v["cells"], v["total_area_um2"]))
    out.append("")
    out.append("== Histogramme des cellules")
    for c, n in sorted(data["cells"].items(), key=lambda x: -x[1]):
        out.append("  %-42s %8d" % (c, n))
    with io.open(path, "w", encoding="utf-8") as fh:
        fh.write(u"\n".join(out) + u"\n")


def save(data, base):
    d = os.path.dirname(base)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with io.open(base + ".json", "w", encoding="utf-8") as fh:
        fh.write(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False))
    write_txt(data, base + ".txt")
    with csv_open(base + ".csv") as fh:
        w = csv.writer(fh)
        w.writerow(["metric", "value"])
        for k in sorted(data["metrics"]):
            w.writerow([k, data["metrics"][k]])
    info("métriques : %s.{txt,json,csv}" % base)


def compare(a_path, b_path, out_path):
    a = json.load(io.open(a_path, encoding="utf-8"))
    b = json.load(io.open(b_path, encoding="utf-8"))
    ma, mb = a["metrics"], b["metrics"]
    la = "%s/%s" % (ma.get("flow"), ma.get("tool"))
    lb = "%s/%s" % (mb.get("flow"), mb.get("tool"))
    keys = sorted(set(ma) | set(mb))
    rows = []
    for k in keys:
        va, vb = ma.get(k, ""), mb.get(k, "")
        d = dp = ""
        if isinstance(va, (int, float)) and isinstance(vb, (int, float)) \
                and not isinstance(va, bool):
            d = round(vb - va, 3)
            dp = ("%+.1f %%" % (100.0 * (vb - va) / abs(va))) if va else ""
        rows.append((k, va, vb, d, dp))

    out = ["# Comparaison CRACK : A = %s   B = %s" % (la, lb),
           "# A : %s" % a_path, "# B : %s" % b_path,
           "# Delta = B - A. Les métriques 'cells_*' et 'area_*' sont calculées",
           "# de la même façon pour les deux flots (liberty typ). Les 'tool_*'",
           "# sont les valeurs propres à chaque outil (définitions différentes).",
           ""]
    out.append("%-42s %16s %16s %14s %10s" % ("métrique", "A", "B", "B-A", "B/A"))
    out.append("-" * 102)
    done = set()
    for title, pat in SECTIONS:
        sec = [r for r in rows if r[0] not in done and re.match(pat, r[0])]
        if not sec:
            continue
        out.append("")
        out.append("== " + title)
        for r in sec:
            out.append("%-42s %16s %16s %14s %10s" % r)
            done.add(r[0])

    # Différences d'histogramme (cellules)
    ca, cb = a.get("cells", {}), b.get("cells", {})
    diff = sorted(set(ca) | set(cb), key=lambda c: -abs(cb.get(c, 0) - ca.get(c, 0)))
    out.append("")
    out.append("== Cellules : plus grosses différences d'utilisation")
    out.append("%-42s %10s %10s %10s" % ("cellule", "A", "B", "B-A"))
    for c in diff[:40]:
        out.append("%-42s %10d %10d %+10d" % (c, ca.get(c, 0), cb.get(c, 0), cb.get(c, 0) - ca.get(c, 0)))
    only_a = sorted(c for c in ca if c not in cb)
    only_b = sorted(c for c in cb if c not in ca)
    out.append("")
    out.append("Cellules utilisées seulement par A : " + (", ".join(only_a) or "-"))
    out.append("Cellules utilisées seulement par B : " + (", ".join(only_b) or "-"))

    with io.open(out_path, "w", encoding="utf-8") as fh:
        fh.write(u"\n".join(out) + u"\n")
    with csv_open(os.path.splitext(out_path)[0] + ".csv") as fh:
        w = csv.writer(fh)
        w.writerow(["metric", la, lb, "delta", "delta_pct"])
        for r in rows:
            w.writerow(r)
    info("comparaison : %s (+ .csv)" % out_path)


# -----------------------------------------------------------------------------
# Balayage : une ligne par run, colonnes = métriques clés
# -----------------------------------------------------------------------------
SWEEP_COLS = [
    "flow", "tool", "profile", "tech", "clk_sys_target_ns", "clk_sys_target_mhz",
    "wns_setup_ps", "tns_setup_ps", "fep_setup", "tool_wns_reg2reg_ps",
    "fmax_clk_sys_est_mhz",
    "cells_std", "cells_seq", "cells_seq_scan", "cells_comb", "cells_buffer", "cells_inverter",
    "area_std_um2", "area_seq_um2", "area_comb_um2", "ratio_bufinv_area_pct",
    "tool_cell_area_um2", "tool_net_area_um2",
    "drv_max_transition_count", "drv_max_capacitance_count",
    "power_total_mw", "power_logic_mw", "power_register_mw",
    "runtime_s", "tool_peak_mem_mb", "run",
]


def sweep(jsons, out_path):
    rows = []
    for j in jsons:
        try:
            rows.append(json.load(io.open(j, encoding="utf-8"))["metrics"])
        except Exception as e:  # run incomplet : on le signale et on continue
            warn("ignoré : %s (%s)" % (j, e))
    rows.sort(key=lambda m: (m.get("flow", ""), m.get("profile", ""),
                             -(m.get("clk_sys_target_mhz") or 0)))
    rows.reverse()
    base = os.path.splitext(out_path)[0]
    with csv_open(base + ".csv") as fh:
        w = csv.writer(fh)
        w.writerow(SWEEP_COLS)
        for m in rows:
            w.writerow([m.get(c, "") for c in SWEEP_COLS])
    short = [("flow", 8), ("profile", 7), ("clk_sys_target_mhz", 8), ("wns_setup_ps", 9),
             ("tns_setup_ps", 11), ("fep_setup", 6), ("area_std_um2", 12),
             ("cells_std", 8), ("cells_seq_scan", 8), ("power_total_mw", 8), ("runtime_s", 7)]
    hdr = ["flot", "profil", "MHz", "WNS ps", "TNS ps", "FEP", "surf std µm²",
           "cellules", "scan", "P mW", "temps s"]
    out = ["# Balayage en fréquence CRACK (synthèse) - %d run(s)" % len(rows),
           "# WNS/TNS : setup coin tt, valeurs de l'outil (indicatives avant P&R)",
           "# surf std : cellules standard, calcul commun (liberty typ)", ""]
    out.append("  ".join(h.rjust(n) for h, (_, n) in zip(hdr, short)))
    out.append("-" * (sum(n for _, n in short) + 2 * len(short)))
    for m in rows:
        out.append("  ".join(str(m.get(k, "-")).rjust(n) for k, n in short))
    # Fmax constatée : plus haute fréquence tenue (WNS >= 0) par flot/profil
    out.append("")
    best = {}
    for m in rows:
        key = "%s/%s" % (m.get("flow"), m.get("profile", "-"))
        w_ = m.get("wns_setup_ps")
        f_ = m.get("clk_sys_target_mhz")
        if isinstance(w_, (int, float)) and w_ >= 0 and f_:
            best[key] = max(best.get(key, 0), f_)
    for k in sorted(best):
        out.append("Plus haute fréquence tenue (WNS >= 0) %-16s : %s MHz" % (k, best[k]))
    with io.open(base + ".txt", "w", encoding="utf-8") as fh:
        fh.write(u"\n".join(out) + u"\n")
    info("balayage : %s.{txt,csv}" % base)


# -----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Métriques de synthèse CRACK (Genus / Yosys)")
    ap.add_argument("mode", choices=["genus", "yosys", "compare", "sweep"])
    ap.add_argument("paths", nargs="+", help="run_dir | yosys_dir | a.json b.json | *.json (sweep)")
    ap.add_argument("--lib-dir", default=None)
    ap.add_argument("--proj", default=os.environ.get("PROJ_NAME", "croc"))
    ap.add_argument("-o", "--out", default=None, help="base de sortie (sans extension) ou .txt pour compare")
    args = ap.parse_args()

    if args.mode == "sweep":
        sweep(args.paths, args.out or "sweep_synth.txt")
        return
    if args.mode == "compare":
        if len(args.paths) != 2:
            sys.exit("[CRACK][ERROR] compare attend deux fichiers .json")
        compare(args.paths[0], args.paths[1], args.out or "compare_synth.txt")
        return

    lib = load_liberty(args.lib_dir or default_lib_dir())
    p = os.path.abspath(args.paths[0])
    if args.mode == "genus":
        data = extract_genus(p, lib)
        save(data, args.out or os.path.join(p, "metrics", "synth_genus"))
    else:
        data = extract_yosys(p, lib, args.proj)
        save(data, args.out or os.path.join(p, "reports", "metrics_yosys"))


if __name__ == "__main__":
    main()
