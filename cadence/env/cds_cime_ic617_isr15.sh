#!/bin/bash
# =============================================================================
# CRACK - Environnement Cadence / Mentor / Synopsys du CIME (machines cimeld*)
#
# Copie versionnée de ~/ams_cds_isr/.bashrc_cdsic617_823_isr15 pour que tout
# le monde ait le même environnement en clonant le dépôt.
#
# Modifications par rapport à l'original (tout le reste est identique) :
#   1. Les deux lignes csh (setenv / set path=(...)) sont converties en bash.
#      En bash, "set path=(...)" est une erreur de syntaxe qui arrête le
#      source : les licences et le reste du fichier n'étaient jamais appliqués.
#   2. $INNOVUS (non défini, ligne commentée) n'est plus mis dans le PATH :
#      Innovus vient maintenant de CDS_DDI 25.11 avec Genus.
#   3. CDS_DDI surchargeable (export CDS_DDI=... avant le source).
# =============================================================================

#
# CADENCE CDS IC 6.1.7 823 / IUS 15.20 / DDI 25.11 (Genus, Innovus, ...)
#

unset CDS_INST_DIR

#export CDS_INST_DIR=/softslin/cdsic616_500_140
export CDS_INST_DIR=/softslin/cdsic617_823
#export CDS_INST_DIR=/softslin/cdsic617_707
export CDSDIR=${CDS_INST_DIR}

export LDVDIR=/softslin/cdsincisiv15_20_035
export IUSDIR=${LDVDIR}
export QRC_HOME=/softslin/cdsext18_21_000
#export QRC_HOME=/softslin/cdsext15_26_s603
#export ASSURAHOME=/softslin/cdsassura4_13_102_615
export ASSURAHOME=/softslin/cdsassura4_15_111_617
#export INNOVUS=/softslin/cdsinnovus17_11_000_isr1
export PVS_INST_DIR=/softslin/cdspve12_11_228
export PVSHOME=${PVS_INST_DIR}

# Digital Design & Implementation 25.11 : Genus, Innovus, Tempus...
# (original csh : setenv CDS_DDI ... / set path=($path $CDS_DDI/bin ...))
export CDS_DDI="${CDS_DDI:-/softl1/cdsddi25_11_000}"
export PATH="${PATH}:${CDS_DDI}/bin:${CDS_DDI}/tools/bin"

export MMSIMHOME=/softslin/cdsspectre18_10_235
#export MMSIMHOME=/softslin/cdsmmsim14_10_921_isr17

export CDS_AUTO_64BIT=ALL

export LANG=C
export LC_COLLATE=C
export LC_CTYPE=C
export LC_MESSAGES=C
export LC_MONETARY=C
export LC_NUMERIC=C
export LC_TIME=C

export PATH="$LDVDIR/tools/bin:$MMSIMHOME/tools/bin:$MMSIMHOME/bin:${CDSDIR}/bin:${CDSDIR}/tools/dfII/bin:${CDSDIR}/tools/bin:$QRC_HOME/tools/bin:$ASSURAHOME/tools/bin:$ASSURAHOME/tools/assura/bin:${PATH}"

export LM_LICENSE_FILE=5287@cimeldap:5280@cimekey1
export CDS_LIC_FILE="${LM_LICENSE_FILE}"

##########################################################
# Synopsys Hspice path.
##########################################################
export HSP_HOME=/softslin/hspicevK2015_06_sp2_2/hspice
#source $HSP_HOME/bin/cshrc.meta
export PATH="${PATH}:${HSP_HOME}/bin"
##########################################################
# Synopsys Design Compiler path.
##########################################################
export SYNOPSYS=/softslin/synthesisvJ2014_09_sp2_64b
export PATH="${PATH}:${SYNOPSYS}/bin"
##########################################################
# Synopsys License.
##########################################################
export LM_LICENSE_FILE=${LM_LICENSE_FILE}:1721@cimekey1

######## Environnement pour Calibre ############
export MGC_HOME=/softslin/calibre2018_4_34_26/ixl_cal_2018.4_34.26
#export MGC_HOME=/softslin/calibre2015_1_38_27/ixl_cal_2015.1_38.27
export PATH="${PATH}:${MGC_HOME}/bin"

export LM_LICENSE_FILE=${LM_LICENSE_FILE}:1718@cimekey1
export USE_CALIBRE_VCO=ixl
###### End Environnement pour Calibre ###########

######## Environnement pour AMS 4.10 ISR15 ############
export AMS_DIR=/softslin/AMS_410_ISR15
export PATH="${PATH}:${AMS_DIR}/programs/bin:${AMS_DIR}/cds/bin"
export DD_DONT_DO_OS_LOCKS=set

alias amsc35b4='ams_cds -tech c35b4 -mode fb & '
alias amsc35b3='ams_cds -tech c35b3 -mode fb & '
alias amss35d4='ams_cds -tech s35d4 -mode fb & '
alias c35b4m3='ams_cds -tech s35d4 -mode fb &'
alias rmtran='find . -name "tran.tran" -exec /bin/rm {} \; '
alias rmlck='find . -name "cdslck" -exec /bin/rm {} \; '
