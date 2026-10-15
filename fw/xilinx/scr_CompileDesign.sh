#!/usr/bin/env bash
set -euo pipefail

scrdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rootdir="$(cd "${scrdir}/../../.." && pwd)"
PROJECT_YAML=${rootdir}/project.yaml

PROJECT_NAME=$(yq '.* | .project_name_short' "${PROJECT_YAML}")
PART_NUMBER=$(yq '.* | .part_number' "${PROJECT_YAML}")
IP_REPOS=$(yq '.* | .ip_repos // [] | join(";")' "${PROJECT_YAML}")
# Top-level entity. Code-generated projects use `top` (the generated
# top_<project>.vhd); a hand-written design names its own top here.
TOP_ENTITY=$(yq '.* | .top_entity // "top"' "${PROJECT_YAML}")

# Debug build. project.yaml's `generics` are applied to the top entity in every
# build; with BUILD_DEBUG=1, `debug_generics` override them (e.g. to generate
# ILAs/VIOs), and block-design scripts see the Tcl variable ::build_debug = 1.
# The variant is recorded in the outputs as BUILD_VARIANT, so a debug
# bitstream is never mistaken for a release one.
BUILD_DEBUG=${BUILD_DEBUG:-0}
case "${BUILD_DEBUG}" in
  0|1) ;;
  *) echo "::error::BUILD_DEBUG must be 0 or 1, got '${BUILD_DEBUG}'" >&2; exit 1 ;;
esac
if [[ "${BUILD_DEBUG}" == 1 ]]; then
  generics_expr='(.generics // {}) * (.debug_generics // {})'
else
  generics_expr='.generics // {}'
fi
TOP_GENERICS=$(yq ".* | ${generics_expr} | to_entries | map(.key + \"=\" + (.value | tostring)) | join(\" \")" "${PROJECT_YAML}")
export PROJECT_NAME PART_NUMBER IP_REPOS TOP_ENTITY BUILD_DEBUG TOP_GENERICS

export VIVADO_VERSION=${VIVADO_VERSION:-2024.1}
export VIVADO_DIR=${VIVADO_DIR:-/data/Xilinx/Vivado/${VIVADO_VERSION}}

# shellcheck source=/dev/null
source ${VIVADO_DIR}/settings64.sh

cd "${scrdir}"
started="$(date +%s)"
vivado -mode batch -source ./scr_SynthNonProjectMode.tcl

# Do not trust the exit status alone: prove the run published a complete,
# fresh build. scr_SynthNonProjectMode.tcl writes BUILD_OK last.
latest="${rootdir}/_outputs/fw/latest"
[[ -f "${latest}/BUILD_OK" ]] || { echo "::error::Vivado exited but did not publish a complete build to ${latest}" >&2; exit 1; }
for want in bit xsa; do
  f="${latest}/${PROJECT_NAME}.${want}"
  [[ -f "${f}" ]] || { echo "::error::build produced no ${f}" >&2; exit 1; }
  [[ "$(stat -c %Y "${f}")" -ge "${started}" ]] || { echo "::error::${f} predates this build" >&2; exit 1; }
done
cat "${latest}/timing.txt"
cat "${latest}/BUILD_VARIANT"
