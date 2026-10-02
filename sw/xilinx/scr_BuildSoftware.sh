#!/usr/bin/env bash
set -euo pipefail

scrdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rootdir="$(cd "${scrdir}/../../.." && pwd)"
PROJECT_YAML=${rootdir}/project.yaml

export PROJECT_NAME=$(yq '.* | .project_name_short' ${PROJECT_YAML})
export PART_NUMBER=$(yq '.* | .part_number' ${PROJECT_YAML})
export CPU_NAME=$(yq '.* | .cpu_name' ${PROJECT_YAML})

export VITIS_VERSION=${VITIS_VERSION:-2024.1}
export VITIS_DIR=${VITIS_DIR:-/data/Xilinx/Vitis/${VITIS_VERSION}}

# shellcheck source=/dev/null
source ${VITIS_DIR}/settings64.sh

marker="${rootdir}/_build/sw/latest_workspace"
rm -f "${marker}"

vitis -s "${scrdir}/scr_BuildPlatformAndSoftware.py"

# Publish the ELF from the workspace this run built, and only that one. A glob
# over _build/sw/** would also match every older workspace, and a stale ELF
# could win.
[[ -f "${marker}" ]] || { echo "::error::Vitis build did not complete" >&2; exit 1; }
workspace="$(cat "${marker}")"
elf="${workspace}/sw_${PROJECT_NAME}/build/sw_${PROJECT_NAME}.elf"
[[ -f "${elf}" ]] || { echo "::error::build produced no ELF at ${elf}" >&2; exit 1; }

mkdir -p ${rootdir}/_outputs/sw
cp -p "${elf}" "${rootdir}/_outputs/sw/sw_${PROJECT_NAME}.elf"
printf 'ELF %s\nSHA256 %s\n' "${rootdir}/_outputs/sw/sw_${PROJECT_NAME}.elf" \
  "$(sha256sum "${elf}" | cut -d' ' -f1)"
