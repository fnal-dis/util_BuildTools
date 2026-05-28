#!/usr/bin/env sh

PROJECT_YAML=../../../project.yaml

export PROJECT_NAME=$(yq '.* | .project_name_short' ${PROJECT_YAML})
export PART_NUMBER=$(yq '.* | .part_number' ${PROJECT_YAML})
export IP_REPOS=$(yq '.* | .ip_repos | join(";")' ${PROJECT_YAML})

export VIVADO_VERSION=2024.1
export VIVADO_DIR=/data/Xilinx/Vivado/${VIVADO_VERSION}

source ${VIVADO_DIR}/settings64.sh

vivado -mode batch -source ./scr_SynthNonProjectMode.tcl
