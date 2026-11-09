# =============================================================================
# CRACK - Flot licence (Cadence)
# common/utils.tcl : fonctions utilitaires partagées par tous les outils
#                    (Genus, Innovus, ...). Pur Tcl, aucune commande outil.
# =============================================================================

# -----------------------------------------------------------------------------
# Lecture d'une variable d'environnement avec valeur par défaut
#   crack_env CRACK_CLK_SYS_NS 10.0
# -----------------------------------------------------------------------------
proc crack_env {name {default ""}} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default
}

# Variable d'environnement obligatoire (erreur explicite si absente)
proc crack_env_required {name} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        crack_error "Variable d'environnement $name non définie (lancer via run_implem.sh)"
    }
    return $::env($name)
}

# -----------------------------------------------------------------------------
# Messages homogènes dans les logs (faciles à filtrer avec grep "\[CRACK\]")
# -----------------------------------------------------------------------------
proc crack_info {msg} { puts "\[CRACK\]\[INFO\] $msg" }
proc crack_warn {msg} { puts "\[CRACK\]\[WARNING\] $msg" }
proc crack_error {msg} {
    puts "\[CRACK\]\[ERROR\] $msg"
    error $msg
}
proc crack_banner {msg} {
    puts "\[CRACK\] ==========================================================="
    puts "\[CRACK\] $msg"
    puts "\[CRACK\] ==========================================================="
}

# -----------------------------------------------------------------------------
# Vérifie que chaque fichier de la liste existe (erreur sinon)
# -----------------------------------------------------------------------------
proc crack_check_files {files {what "fichier"}} {
    set missing [list]
    foreach f $files {
        if {![file exists $f]} { lappend missing $f }
    }
    if {[llength $missing] > 0} {
        foreach f $missing { crack_warn "$what introuvable : $f" }
        crack_error "[llength $missing] $what manquant(s), voir ci-dessus"
    }
}

# -----------------------------------------------------------------------------
# Glob qui échoue proprement si rien ne correspond
# -----------------------------------------------------------------------------
proc crack_glob {dir pattern} {
    set res [lsort [glob -nocomplain -directory $dir $pattern]]
    if {[llength $res] == 0} {
        crack_error "Aucun fichier '$pattern' dans $dir"
    }
    return $res
}

# -----------------------------------------------------------------------------
# Lecture d'une file list au format Bender "flist-plus" (celle du flot open :
# yosys/src/croc.flist). On réutilise volontairement CE fichier pour garantir
# que les deux flots synthétisent exactement les mêmes sources, dans le même
# ordre, avec les mêmes defines.
#
#   +incdir+<dir>        -> répertoire d'include
#   +define+NAME[=VAL]   -> define
#   <fichier>            -> source HDL
#   chemins relatifs     -> résolus par rapport à base_dir
#
# Retourne un dict : files / incdirs / defines
# -----------------------------------------------------------------------------
proc crack_parse_flist {flist base_dir} {
    crack_check_files [list $flist] "file list"
    set fh [open $flist r]
    set lines [split [read $fh] "\n"]
    close $fh

    set files   [list]
    set incdirs [list]
    set defines [list]
    foreach raw $lines {
        set line [string trim $raw]
        if {$line eq "" || [string match "#*" $line] || [string match "//*" $line]} {
            continue
        }
        if {[string match "+incdir+*" $line]} {
            foreach d [split [string range $line 8 end] "+"] {
                if {$d ne ""} {
                    lappend incdirs [file normalize [file join $base_dir $d]]
                }
            }
        } elseif {[string match "+define+*" $line]} {
            foreach d [split [string range $line 8 end] "+"] {
                if {$d ne ""} { lappend defines $d }
            }
        } else {
            lappend files [file normalize [file join $base_dir $line]]
        }
    }
    crack_check_files $files "source HDL"
    return [dict create files $files incdirs $incdirs defines $defines]
}

# -----------------------------------------------------------------------------
# Fusionne deux listes de defines (NAME ou NAME=VAL) sans doublon de NAME.
# Les defines de "extra" remplacent ceux de "base" de même nom.
# -----------------------------------------------------------------------------
proc crack_merge_defines {base extra} {
    set order [list]
    array set val {}
    foreach d [concat $base $extra] {
        set name [lindex [split $d "="] 0]
        if {![info exists val($name)]} { lappend order $name }
        set val($name) $d
    }
    set res [list]
    foreach n $order { lappend res $val($n) }
    return $res
}

# -----------------------------------------------------------------------------
# Ecrit un fichier texte (crée le répertoire si besoin)
# -----------------------------------------------------------------------------
proc crack_write_file {path content} {
    file mkdir [file dirname $path]
    set fh [open $path w]
    puts -nonewline $fh $content
    close $fh
}

# -----------------------------------------------------------------------------
# Test "le nom de module correspond-il à un motif de la liste ?"
# Les noms de modules paramétrés sont suffixés par l'outil
# (ex. cdc_2phase -> cdc_2phase_T_logic...), on accepte donc "motif" et
# "motif_*", comme les motifs "t:<module>$*" du flot Yosys.
# -----------------------------------------------------------------------------
proc crack_name_matches {name patterns} {
    foreach p $patterns {
        if {[string match $p $name] || [string match "${p}_*" $name]} {
            return 1
        }
    }
    return 0
}
