#!/usr/bin/env sh

export PROJECT_NAME=`awk -F '"' '/project_name_short/ {print $2}' ../../../project.yaml`
export PART_NUMBER=`awk -F '"' '/part_number/ {print $2}' ../../../project.yaml`

export VITIS_VERSION=2024.1
export VITIS_DIR=/data/Xilinx/Vitis/${VITIS_VERSION}

source ${VITIS_DIR}/settings64.sh

vitis -s scr_BuildPlatformAndSoftware.py
