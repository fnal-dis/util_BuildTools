#!/usr/bin/env sh

export PROJECT_NAME=`awk -F '"' '/project_name_short/ {print $2}' ../../../project.yaml`
export PART_NUMBER=`awk -F '"' '/part_number/ {print $2}' ../../../project.yaml`

export VIVADO_VERSION=2024.1
export VIVADO_DIR=/data/Xilinx/Vivado/${VIVADO_VERSION}

source ${VIVADO_DIR}/settings64.sh

vivado -mode batch -source ./scr_SynthNonProjectMode.tcl
