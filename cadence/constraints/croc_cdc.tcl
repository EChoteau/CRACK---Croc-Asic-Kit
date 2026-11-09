# =============================================================================
# CRACK - Flot licence (Cadence)
# constraints/croc_cdc.tcl : contraintes CDC du DMI JTAG (équivalent de
#   openroad/src/instances.tcl + bloc "Cdcs and Syncs" de constraints.sdc)
#
# Flot open : set_max_delay 3.0 -ignore_clock_latency entre les bascules qui
# pilotent les nets async_* des cdc_2phase (requête/réponse DMI) et celles
# qui les reçoivent. Les noms y sont ceux de la netlist Yosys aplatie.
#
# Ici la hiérarchie des cdc*_src / cdc*_dst est conservée (keep_hier), on
# cible donc les ports async_* de ces sous-blocs avec des commandes SDC
# standard (all_fanin / all_fanout), utilisables par Genus ET Innovus.
#
# Best-effort : chaque contrainte est dans un catch et le nombre d'objets
# trouvés est affiché. 0 objet = contrainte NON appliquée -> à noter dans le
# journal des écarts (le chemin reste de toute façon coupé par
# set_clock_groups -asynchronous, comme dans le flot open).
# =============================================================================

proc crack_apply_croc_cdc {} {
    global CONSTR
    set jtag "i_croc_soc/i_croc/i_dmi_jtag/i_dmi_cdc"
    set n_ok 0

    # En MMMC, une commande SDC interactive doit viser un mode de contraintes
    # (sinon Genus : SDC-235). On cible tous les modes (ici : "func").
    if {[catch {set_interactive_constraint_modes [all_constraint_modes]} err]} {
        crack_warn "set_interactive_constraint_modes : $err"
    }

    foreach cdc {i_cdc_req i_cdc_resp} {
        set base "$jtag/$cdc"
        if {[catch {
            set pins [get_pins -hierarchical "$base/*/async*"]
            set npins [sizeof_collection $pins]
            if {$npins == 0} { error "aucun port async* sous $base" }
            set from [all_fanin  -to   $pins -startpoints_only -flat]
            set to   [all_fanout -from $pins -endpoints_only   -flat]
            if {[catch {set_max_delay $CONSTR(cdc_max_delay) -from $from -to $to -ignore_clock_latency} e1]} {
                # option non supportée par certaines versions : sans elle
                crack_warn "CDC $cdc : -ignore_clock_latency refusé ($e1), essai sans"
                set_max_delay $CONSTR(cdc_max_delay) -from $from -to $to
            }
            crack_info "CDC $cdc : $npins ports async, max_delay $CONSTR(cdc_max_delay) ns appliqué"
            incr n_ok
        } err]} {
            crack_warn "CDC $cdc : contrainte non appliquée ($err) -> journal des écarts"
        }
    }
    # Retour au mode normal (les commandes suivantes ne visent plus "func")
    catch {set_interactive_constraint_modes {}}
    return $n_ok
}
