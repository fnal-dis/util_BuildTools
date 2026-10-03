#!/usr/bin/env bash
# Merge the processor ELF into the bitstream, so that programming the FPGA is
# by itself enough to bring the board up: no JTAG download of the software, no
# debugger attached, and the same behaviour after a power cycle from flash.
#
# Inputs, relative to the project root:
#   _outputs/fw/latest/${PROJECT_NAME}.bit   from scr_CompileDesign.sh
#   _outputs/fw/latest/${PROJECT_NAME}.mmi   from scr_CompileDesign.sh, or
#   _outputs/fw/latest/post_route.dcp        to regenerate the .mmi from
#   _outputs/sw/sw_${PROJECT_NAME}.elf       from scr_BuildSoftware.sh
#
# Output: _outputs/fw/latest_with_elf/${PROJECT_NAME}.{bit,ltx}
#
# The merge runs updatemem against the routed design's BRAM map. Nothing is
# re-implemented, so the merged bitstream is the same design with different
# BRAM initialisation. The unmerged bitstream is left in place.
#
# Environment:
#   EMBED_ELF_SKIP_AGE_CHECK=1  skip the "ELF newer than bitstream" guard. CI
#                               sets this: artifacts copied between jobs do not
#                               keep their timestamps, and the job graph already
#                               ties the ELF to the XSA of the same run.
set -euo pipefail

scrdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rootdir="$(cd "${scrdir}/../../.." && pwd)"
PROJECT_YAML="${rootdir}/project.yaml"

PROJECT_NAME="$(yq '.* | .project_name_short' "${PROJECT_YAML}")"
CPU_NAME="$(yq '.* | .cpu_name' "${PROJECT_YAML}")"

# Only a soft processor boots from BRAM initialised in the bitstream. A Zynq or
# Versal PS boots from its own boot image, so there is nothing to merge.
if [[ "${CPU_NAME,,}" != *microblaze* ]]; then
  echo "::notice::cpu_name '${CPU_NAME}' is not a MicroBlaze; no ELF to embed in the bitstream"
  exit 0
fi

VIVADO_VERSION="${VIVADO_VERSION:-2024.1}"
VIVADO_DIR="${VIVADO_DIR:-/data/Xilinx/Vivado/${VIVADO_VERSION}}"
if ! command -v updatemem >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${VIVADO_DIR}/settings64.sh"
fi

latest="${rootdir}/_outputs/fw/latest"
work="${rootdir}/_build/fw/embed_elf"
merged_dir="${rootdir}/_outputs/fw/latest_with_elf"

bit="${latest}/${PROJECT_NAME}.bit"
ltx="${latest}/${PROJECT_NAME}.ltx"
mmi="${latest}/${PROJECT_NAME}.mmi"
dcp="${latest}/post_route.dcp"
elf="${rootdir}/_outputs/sw/sw_${PROJECT_NAME}.elf"
out="${merged_dir}/${PROJECT_NAME}.bit"

for required in "${bit}" "${elf}"; do
  [[ -f "${required}" ]] || { echo "::error::missing ${required}" >&2; exit 1; }
done

# An ELF older than the bitstream was built against a different XSA.
if [[ "${EMBED_ELF_SKIP_AGE_CHECK:-0}" != "1" && "${elf}" -ot "${bit}" ]]; then
  echo "::error::ELF ${elf} is older than ${bit}; rebuild the software first" >&2
  exit 1
fi

mkdir -p "${work}" "${merged_dir}"

if [[ ! -f "${mmi}" ]]; then
  [[ -f "${dcp}" ]] || { echo "::error::no ${mmi} and no ${dcp} to generate it from" >&2; exit 1; }
  echo "no ${mmi}; generating it from ${dcp}"
  mmi="${work}/${PROJECT_NAME}.mmi"
  ( cd "${work}" && vivado -mode batch -nojournal -nolog \
      -source "${scrdir}/scr_WriteMemInfo.tcl" -tclargs "${dcp}" "${mmi}" )
  [[ -f "${mmi}" ]] || { echo "::error::write_mem_info produced no ${mmi}" >&2; exit 1; }
fi

# updatemem needs the processor's hierarchical instance path. The .mmi names
# it, so read it back rather than hard-coding a path that moves whenever the
# block design is re-hierarchised.
proc_path="$(sed -n 's/.*<Processor[^>]*InstPath="\([^"]*\)".*/\1/p' "${mmi}" | head -1)"
[[ -n "${proc_path}" ]] || { echo "::error::no Processor InstPath in ${mmi}" >&2; exit 1; }
echo "processor ${proc_path}"

# updatemem drops a journal in the current directory.
( cd "${work}" && updatemem -force -meminfo "${mmi}" -data "${elf}" \
    -bit "${bit}" -proc "${proc_path}" -out "${out}" )
[[ -f "${out}" ]] || { echo "::error::updatemem produced no ${out}" >&2; exit 1; }

# The probe file travels with the bitstream it describes.
if [[ -f "${ltx}" ]]; then
  cp -p "${ltx}" "${merged_dir}/${PROJECT_NAME}.ltx"
fi

printf 'BIT %s\nSHA256 %s\nELF %s\nELF_SHA256 %s\n' \
  "${out}" "$(sha256sum "${out}" | cut -d' ' -f1)" \
  "${elf}" "$(sha256sum "${elf}" | cut -d' ' -f1)"
