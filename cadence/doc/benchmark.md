# Benchmark des flots d'implémentation physique : méthode, expériences, limites

Projet CRACK (Croc), Phelma MT 3A, 2026-2027.
Ce document explique **comment on compare** le flot open-source (Yosys / OpenROAD /
KLayout) et le flot licence (Cadence Genus / Innovus / outils de signoff du CIME), en
IHP130 puis en AMS 0.35 µm. Il sert de base au protocole figé (VAL-19) et aux
rapports L6 (benchmark IHP130) et L8 (AMS035 vs IHP130).

Les réglages précis de chaque flot sont dans `recap_flows.md`.
Les exigences de référence : cahier des charges (O4, O6, ENF4) et plan de
validation (VAL-11, VAL-19 à VAL-24).

---

## 1. Ce qu'un benchmark doit faire

Un benchmark ne consiste pas à « lancer les deux outils et regarder qui a le
meilleur chiffre ». Un chiffre isolé ne prouve rien : il dépend des contraintes,
des réglages, de la façon de mesurer, et parfois du hasard. Un benchmark utile :

1. **pose des questions précises** avant de lancer quoi que ce soit ;
2. **fige les conditions** (mêmes entrées, mêmes contraintes, même budget de
   réglage) et les écrit avant la campagne ;
3. **mesure tout le monde de la même façon** (mêmes définitions, même outil de
   mesure quand c'est possible) ;
4. **balaie** au lieu de prendre un seul point (un outil peut gagner à 50 MHz et
   perdre à 150 MHz) ;
5. **vérifie que le résultat se reproduit** ;
6. **dit honnêtement ce qu'on ne peut pas conclure**.

## 2. Les questions auxquelles on répond

| # | Question | Pour qui |
|---|---|---|
| Q1 | À contraintes et budget de réglage égaux, quel écart de **performance, surface, puissance** (PPA) entre flot open et flot licence en IHP130 ? | l'enseignant : le flot open suffit-il pour un tape-out étudiant ? |
| Q2 | **Où** se crée cet écart : synthèse ou placement-routage ? | comprendre les outils, savoir où investir |
| Q3 | Que gagne-t-on en **poussant** le flot licence (efforts max) ? | marge apportée par la licence quand on s'y investit |
| Q4 | Quel est le **coût d'usage** de chaque flot : temps de calcul, interventions manuelles, facilité d'installation au CIME, reproductibilité ? | les promotions suivantes |
| Q5 | Comment le **même design** se comporte-t-il en AMS 0.35 µm face à IHP130 ? Les conclusions de Q1 tiennent-elles dans une autre techno ? | O5/O6 du cahier des charges |

## 3. Vocabulaire minimal

| Terme | Sens |
|---|---|
| PPA | *Performance, Power, Area* : les trois grandeurs principales d'un circuit |
| Slack | marge de timing d'un chemin : temps disponible − temps nécessaire. Positif = OK |
| WNS / TNS | *Worst / Total Negative Slack* : pire marge, somme des marges négatives. WNS ≥ 0 et TNS = 0 = timing tenu |
| Fréquence cible | fréquence demandée dans le SDC (`clk_sys`) |
| Fréquence atteinte | fréquence que le circuit tient vraiment : 1 / (période − WNS) |
| Fmax d'un flot | plus haute fréquence cible pour laquelle le flot livre un circuit **propre** (timing tenu, DRC/LVS OK) |
| Setup / hold | un signal doit arriver assez tôt (setup, coins lents) mais pas trop tôt (hold, coins rapides) |
| STA | *Static Timing Analysis* : calcul du timing de tous les chemins sans simulation |
| SPEF | fichier des parasites (R, C des fils) extraits du layout, utilisé par la STA |
| Signoff | vérifications finales avant fabrication : DRC, LVS, antennes, densité, STA sur parasites extraits |
| Utilisation | surface des cellules / surface du cœur |
| Front de Pareto | ensemble des points où on ne peut pas gagner sur un critère sans perdre sur un autre (ex. surface vs fréquence) |

## 4. Ce qu'on compare : des flots, à plusieurs étapes

On compare des **flots complets** (outils + scripts + réglages), pas des outils
isolés dans le vide. On relève les métriques **à chaque étape**, mais le verdict se
fait sur le circuit **fini** :

```
RTL ──► synthèse ──► floorplan ──► placement ──► CTS ──► routage ──► signoff
          │                          │            │         │           │
       métriques                 métriques    métriques  métriques   VERDICT
     (explication)                 (explication)                    (Q1, Q3)
```

Pourquoi ne pas conclure en sortie de synthèse ? Parce que :

- Yosys ne fait pas d'analyse de timing et ne lit pas le SDC : il n'y a pas de
  timing open à comparer à ce stade ;
- une netlist plus petite peut être plus dure à placer et router ;
- les fils, absents en synthèse, pèsent lourd dans le timing final.

Les métriques intermédiaires servent à **expliquer** d'où vient l'écart final
(Q2), pas à le mesurer.

## 5. Règles d'équité (protocole)

Elles sont détaillées dans `recap_flows.md` (« Principe du benchmark ») :

| Identique dans les deux flots | Libre pour chaque outil |
|---|---|
| RTL, file list, defines, top | ses algorithmes d'optimisation |
| bibliothèques, coins (tt setup, ff hold) | ses réglages **par défaut** (profil `iso`) |
| SDC complet, contraintes CDC | les cellules qu'il choisit parmi celles autorisées |
| hiérarchie conservée, cellules interdites | |
| floorplan : die, padring, placement des SRAM, grille d'alimentation | |
| fréquences du balayage | |

### 5.1 Contraintes actuellement imposées aux deux flots

Ces valeurs viennent du flot open (source) et sont reprises à l'identique dans le
flot licence. Le détail ligne par ligne, avec les fichiers, est dans
`recap_flows.md` (sections indiquées).

| Contrainte | Valeur | Source flot open | Reprise flot licence | Récap |
|---|---|---|---|---|
| Design | top `croc_chip`, 167 fichiers RTL de `yosys/src/croc.flist`, mêmes defines (+ `IHP_SG13CMOS5L=1`) | `env.sh`, `croc.flist` | `config/design_croc.tcl`, `config/tech/ihp130_sg13cmos5l.tcl` | §1 |
| Techno | IHP sg13cmos5l : stdcells sg13g2, IO sg13cmos5l, 2 SRAM 512×32 | `env.sh`, `init_tech_sg13cmos5l.tcl` | `config/tech/ihp130_*.tcl` | §2 |
| Coins | synthèse et setup : **tt** (1,20 V, 25 °C) ; hold : **ff** (1,32 V, −40 °C) | `init_tech_*.tcl` (`define_corners tt ff`) | MMMC `common/mmmc.tcl` | §2 |
| Horloge système `clk_sys` (`clk_i`) | **10 ns = 100 MHz** (variable du balayage) | `openroad/src/constraints.sdc` (`TCK_SYS`) | `constraints/croc_constraints.tcl` (`--clk`) | §3 |
| Horloge JTAG `clk_jtg` | 25 ns (40 MHz) | idem | idem | §3 |
| Horloge temps réel `clk_rtc` | 50 ns (20 MHz) | idem | idem | §3 |
| Relation entre horloges | les 3 horloges asynchrones entre elles | idem | idem | §3 |
| Incertitude / transition horloge | 0,1 ns / 0,2 ns | idem | idem | §3 |
| Entrées/sorties GPIO, UART | délai min 10 %, max 30 % de la période `clk_sys` | idem | idem | §3 |
| JTAG | entrées 10 % / 30 %, `tdo` 10 % / 20 % de la période `clk_jtg` | idem | idem | §3 |
| `status_o`, `unused*` | 10 % de `clk_sys` | idem | idem | §3 |
| Resets (`rst_ni`, `testmode_i`, `jtag_trst_ni`) | entrée max 10 % de `clk_jtg`, pas de check hold, max_delay d'une période | idem | idem | §3 |
| Charge sur les sorties | 15 pF | idem | idem | §3 |
| Pilotage des entrées | pad `sg13cmos5l_IOPadOut16mA` | idem | idem | §3 |
| CDC JTAG ↔ système | `set_max_delay 3 ns` sur les chemins des `cdc_2phase` du DMI | `constraints.sdc` + `instances.tcl` | `constraints/croc_cdc.tcl` | §3 |
| Hiérarchie conservée | 22 modules (`croc_soc`, `core_wrap`, `gpio`, `obi_uart`, `tc_clk*`, `cdc*`, `sync`…), le reste aplati | `yosys_synthesis.tcl` | `config/design_croc.tcl` | §4.2 |
| Cellules interdites | celles marquées `dont_use` dans la liberty + pads `sg13cmos5l_IOPad*` à l'optimisation | `.lib`, `init_tech_*.tcl` | `.lib`, `TECH(dont_use)` | §4.4 |
| Cellules protégées | cellules instanciées à la main dans `tc_clk*` | attribut `keep` | `preserve` | §4.4 |
| Tie cells | `sg13g2_tiehi` / `sg13g2_tielo` | `init_tech_*.tcl` | `TECH(tiehi_cell/tielo_cell)` | §4.4 |
| Floorplan | die 1916 × 1916 µm, marge cœur 330 µm, padring, SRAM placées en haut à gauche et à droite, grille d'alimentation | `01_floorplan.tcl`, `padring.tcl`, `power_grid_*.tcl` | à reproduire dans Innovus | §5 |

**À noter** : côté open, le SDC n'est lu qu'à partir d'OpenROAD (Yosys n'en lit pas,
il vise seulement 10 ns en interne). Côté licence, Genus l'applique dès la synthèse.
Les contraintes sont donc les mêmes, mais pas appliquées au même moment
(`recap_flows.md`, « Points à garder en tête »).

Le **floorplan** fait partie des contraintes. Si chaque flot dessinait son propre
floorplan, on comparerait deux floorplans et plus deux outils. On reproduit donc
celui du flot open (`openroad/scripts/01_floorplan.tcl`) dans Innovus.

**Protocole figé** (VAL-19) : avant la campagne, on écrit et on date un fichier
`benchmark_protocole.md` (version du RTL = commit git, SDC, fréquences, métriques,
profils, outils et versions). On n'y touche plus pendant la campagne. Toute
exception va dans le journal des écarts.

## 6. Mesurer de la même façon : l'arbitre commun

Chaque outil calcule le timing avec son propre moteur, ses propres parasites, ses
propres approximations. Comparer « WNS selon Innovus » à « WNS selon OpenROAD »,
c'est comparer aussi deux thermomètres. D'où un **arbitre commun** (VAL-11) :

> on repasse les deux layouts finaux dans **le même** extracteur et **le même**
> outil de STA, avec le même SDC.

Choix proposé :

| Élément | Arbitre | Pourquoi |
|---|---|---|
| Lecture du layout | DEF de chaque flot lu dans OpenROAD | format commun, Innovus sait écrire du DEF |
| Extraction des parasites | OpenRCX avec les règles IHP (`IHP_rcx_patterns.rules`, à récupérer) | seul modèle RC IHP disponible ; Cadence n'a pas de QRC IHP (décision D1) |
| STA | OpenSTA, coins tt (setup) et ff (hold) | même moteur pour les deux |
| Contre-vérification | STA native de chaque flot (Innovus/Tempus, OpenROAD) | mesurer l'écart arbitre / outil (VAL-11) |

Attention : le flot open **n'extrait pas** les parasites aujourd'hui (lignes
commentées dans `openroad/scripts/05_finishing.tcl`, la commande abîmerait des
patches métal). Son timing « final » repose sur une estimation après routage
global. L'arbitre doit donc travailler sur une **copie** du layout, uniquement
pour l'analyse. À valider en phase 0 : disponibilité du fichier de règles OpenRCX
IHP au CIME.

Pour la **surface**, la définition commune existe déjà (`extract_metrics.py`) :
nombre d'instances par cellule × surface dans la liberty typ, identique pour les deux
flots.

Pour la **puissance**, les deux outils l'estiment par défaut sans activité réelle.
Pour une comparaison juste, on fournit à chaque flot **la même activité** : un VCD/SAIF
issu de la simulation gate-level d'un même programme de test (option, en lien
avec VAL-04/VAL-12). Sans ça, la puissance n'est qu'indicative.

## 7. Les métriques

### 7.1 Métriques principales (verdict, mesurées par l'arbitre après signoff)

| Métrique | Définition | Remarque |
|---|---|---|
| **Fmax** | plus haute fréquence du balayage où : WNS ≥ 0 et TNS = 0 en setup (tt) **et** en hold (ff), 0 violation DRC/LVS | la métrique reine |
| Fréquence atteinte | 1 / (période − WNS) à chaque point | utile entre deux points du balayage |
| Surface cellules standard | calcul commun (`area_std_um2`) | hors pads et SRAM, identiques des deux côtés |
| Utilisation du cœur | surface cellules / surface cœur | même cœur pour les deux (floorplan commun) |
| Puissance | totale, dynamique, fuite, à fréquence et activité égales | seulement avec la même activité |
| Propreté | violations DRC, LVS, antennes, DRV (transition, capacité) restantes | un flot « rapide mais sale » ne gagne pas |

### 7.2 Métriques explicatives (à chaque étape)

| Étape | Métriques |
|---|---|
| Synthèse | nombre de cellules par catégorie (séquentiel, logique, buffers, inverseurs, scan), surface, WNS Genus |
| Placement | densité, congestion estimée, WNS/TNS estimés |
| CTS | skew, latence d'horloge, nombre de buffers d'horloge |
| Routage | longueur de fils, vias, congestion, violations avant réparation |

### 7.3 Métriques d'usage (Q4)

| Métrique | Comment |
|---|---|
| Temps de calcul par étape | horodatage dans les logs, même machine (cimeld21), machine peu chargée |
| Mémoire maximale | rapports outils |
| Interventions manuelles | compteur tenu à la main : chaque fois qu'il a fallu modifier un script ou relancer à la main |
| Reproductibilité | relancer le même run, comparer (§8, E4) |
| Mise en place au CIME | heures passées, obstacles (runbook L3) |

## 8. Les expériences

### E1 : IHP130, open vs licence `iso`, balayage en fréquence (Q1)

- Fréquences : un premier passage grossier, par exemple **50, 80, 100, 125, 150, 200 MHz**,
  puis 2 ou 3 points resserrés autour de la Fmax trouvée (pas de 5 à 10 MHz).
  Minimum 3 points par flot (VAL-23).
- Chaque point = un run complet RTL → signoff, mesuré par l'arbitre.
- **Prérequis côté open** : rendre la période paramétrable (`period_ps` dans
  `yosys/scripts/yosys_synthesis.tcl`, `TCK_SYS` dans `openroad/src/constraints.sdc`).
- Côté licence : `sweep_synth.sh` existe pour la synthèse et sera étendu au P&R.
- Résultat : courbes **surface vs fréquence** et **WNS vs fréquence** pour les deux
  flots, Fmax de chacun.

### E2 : licence `max` (Q3)

- Même balayage, profil `max` (efforts maximaux), mêmes contraintes.
- Résultat : décalage de la courbe licence et de sa Fmax entre `iso` et `max`.
- À présenter **à part** : on ne compare pas `licence max` à `open iso` sans le dire.

### E3 : matrice croisée (Q2)

On échange les netlists entre les flots, à une ou deux fréquences clés (par
exemple 100 MHz et la Fmax open) :

|  | P&R OpenROAD | P&R Innovus |
|---|---|---|
| **Netlist Yosys** | flot open | mixte A |
| **Netlist Genus** | mixte B | flot licence |

- Si « mixte B » (Genus + OpenROAD) se rapproche du flot licence, l'écart vient
  surtout de la **synthèse**.
- Si « mixte A » (Yosys + Innovus) s'en rapproche, il vient surtout du **P&R**.
- Coût : modéré, chaque P&R sait lire une netlist Verilog. Il faut juste que les
  noms d'instances des SRAM (placement manuel) soient retrouvés dans les deux
  netlists.

### E4 : reproductibilité (VAL-21, VAL-24)

- Relancer 2 fois le même run (même fréquence, même flot) : résultats identiques ?
  Sinon, mesurer l'écart et s'en servir comme **barre d'erreur** : un écart entre
  flots plus petit que la variabilité d'un flot n'est pas significatif.
- Le binôme rejoue une campagne depuis un clone propre, sans aide.

### E5 : AMS 0.35 µm (Q5)

- Même méthode qu'E1, au moins côté licence. Côté open seulement si la licence du
  kit AMS l'autorise (hypothèse H3, décision D3).
- Le design sera probablement **réduit** (pas de macro SRAM AMS connue, décision D2) :
  Croc sans SRAM, ou un sous-bloc (domaine utilisateur, cœur seul).
- Fréquences à rescaler : une techno 0,35 µm est bien plus lente, on vise des
  dizaines de MHz.

### E6 : IHP130 vs AMS035 (Q5)

- **Règle d'or** : comparer le **même design** dans les deux technos. Si AMS035
  utilise un Croc réduit, on synthétise et place-route **aussi** ce Croc réduit en
  IHP130 pour la comparaison.
- On compare des technologies (et la façon dont chaque flot s'y adapte), pas des
  outils : tension (1,2 V vs 3,3 V), finesse, nombre de couches de métal changent tout.
- Métriques utiles : Fmax, surface, puissance à fréquence égale, et les **ratios**
  (ex. surface AMS / surface IHP) plutôt que les valeurs brutes.
- Question clé : **le classement open/licence d'E1 tient-il en AMS035 ?**

## 9. Ce que produira la campagne

Pour chaque techno :

1. un tableau de tous les runs (une ligne par flot × profil × fréquence), généré par
   `extract_metrics.py sweep` ;
2. des courbes : surface vs fréquence, WNS vs fréquence cible, puissance vs fréquence ;
3. la Fmax de chaque flot/profil, avec la barre d'erreur d'E4 ;
4. la matrice croisée E3 (à 1 ou 2 fréquences) ;
5. un tableau des métriques d'usage (temps, interventions, obstacles) ;
6. une section **Limites** reprenant le §10 ;
7. une conclusion qui répond explicitement à Q1 à Q5.

## 10. Limites (à écrire dans le rapport)

| Limite | Effet | Ce qu'on fait |
|---|---|---|
| Le flot open a été **réglé pour Croc** par ses développeurs (ETH, tape-outs) ; le flot licence part des réglages par défaut | biais en faveur du flot open en `iso` | le dire ; le profil `max` montre la marge de la licence |
| **Un seul design**, deux technos | les conclusions ne se généralisent pas à tout design | parler de « sur Croc », pas « en général » |
| Yosys **sans SDC** | la synthèse open ignore les contraintes réelles | verdict après routage seulement |
| **Pas de modèle RC IHP** côté Cadence, pas d'extraction côté open | timing natif des deux flots peu fiable en absolu | arbitre commun (§6) |
| **Pas de coin slow** dans le miroir public | setup vérifié en typique : Fmax optimistes pour un vrai tape-out | le dire ; coin ss en option si le PDK complet le permet |
| **Versions d'outils** différentes en âge (Genus 21.18 de 2021 vs Yosys/OpenROAD récents) | ne représente pas l'état de l'art Cadence | noter les versions dans chaque run (`run_info.txt`) |
| **Puissance** sans activité réelle | estimation grossière, potentiellement différente selon l'outil | même VCD/SAIF pour les deux, sinon puissance « indicative » |
| **Temps de calcul** dépendant de la charge des machines du CIME | bruit sur les temps | même machine, plusieurs mesures, ordre de grandeur seulement |
| Non-déterminisme possible | écarts aléatoires entre runs identiques | E4, barres d'erreur |
| Expertise inégale du binôme sur chaque outil | un flot mieux maîtrisé est mieux exploité | même budget de réglage, tout noter dans le journal |
| AMS035 : design probablement réduit, flot open peut-être interdit | E5/E6 partiels | règle d'or du §8 (E6), documenter les décisions D2/D3 |

### Ce qu'on pourra conclure

- « Sur Croc en IHP130, à contraintes égales et sans réglage fin, le flot licence
  atteint X MHz contre Y pour le flot open, pour une surface de … »
- « L'écart vient principalement de … (E3) »
- « Pousser le flot licence apporte … (E2) »
- « Le flot open demande … h de mise en place et … interventions par run »

### Ce qu'on ne pourra pas conclure

- « L'outil A est meilleur que l'outil B » en général.
- Une Fmax « garantie silicium » (pas de coin slow, pas de signoff complet de fonderie).
- Une comparaison de puissance fine sans activité commune.

## 11. Organisation

| Étape | Qui (WBS) | Quand |
|---|---|---|
| Rédiger et figer `benchmark_protocole.md` (VAL-19/20) | A + B | début lot 4 |
| Rendre la fréquence paramétrable côté open | A | avant E1 |
| Arbitre commun : DEF → OpenRCX → OpenSTA (VAL-11) | A + B | lot 4 (tâche 4.6) |
| Script unique de métriques (VAL-22) | fait : `cadence/scripts/extract_metrics.py` | à étendre au P&R |
| Campagnes E1, E2 | A (open), B (licence) | lot 4 |
| E3 matrice croisée, E4 reproductibilité | A + B | lot 4 |
| E5, E6 AMS035 | B (licence), A (open si D3) | lots 5-6 |
| Rapports L6, L8 | A + B | fin des lots 4 et 6 |

Ordre de réduction si le temps manque (cohérent avec le cahier des charges §8) :
moins de points de balayage, puis E3 réduit à une seule fréquence, puis E6
qualitatif.

**Nommage des runs** (plan de validation §5) : `[flot][techno][fréquence]_[date]`,
déjà appliqué côté licence (`licence-<profil>_<techno>_<f>MHz_<date>`). Chaque run
archive commit git, versions d'outils, configuration et logs.
