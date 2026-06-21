#!/usr/bin/env sh

rootdir="../../.."
PROJECT_YAML=${rootdir}/project.yaml

export PROJECT_NAME=$(yq '.* | .project_name_short' ${PROJECT_YAML})
export PART_NUMBER=$(yq '.* | .part_number' ${PROJECT_YAML})
export CPU_NAME=$(yq '.* | .cpu_name' ${PROJECT_YAML})

export VITIS_VERSION=2024.1
export VITIS_DIR=/data/Xilinx/Vitis/${VITIS_VERSION}

source ${VITIS_DIR}/settings64.sh

vitis -s scr_BuildPlatformAndSoftware.py

mkdir -p ${rootdir}/_outputs/sw
shopt -s globstar
cp ${rootdir}/_build/sw/**/build/*.elf ${rootdir}/_outputs/sw
