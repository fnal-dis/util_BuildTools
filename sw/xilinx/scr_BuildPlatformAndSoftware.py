#!/usr/bin/env python3
"""Build the Vitis platform and the application for this project.

Run through scr_BuildSoftware.sh, which publishes the ELF this run built.

For a MicroBlaze target, the linker script Vitis generates can place the vector
sections at absolute 0x0 while the CPU fetches its reset vector from
C_BASE_VECTORS. If nothing is mapped at 0x0 the application never starts, and
an ELF merged into the bitstream with scr_EmbedElf.sh initialises BRAM the CPU
never jumps to. This script relocates the vectors onto the memory region's
ORIGIN and refuses to build if that ORIGIN disagrees with C_BASE_VECTORS.
"""

import os
import re
import shutil
import zipfile
from datetime import datetime
from pathlib import Path

import vitis

root = (Path(__file__).parent / "../../..").resolve()

try:
    xsa_path = next(root.glob("_outputs/fw/latest/**/*.xsa"))
except StopIteration:
    raise Exception("Failed finding .xsa file. Fix fw flow first!")

# MicroBlaze vector offsets from C_BASE_VECTORS, fixed by the architecture.
VECTOR_OFFSETS = {
    ".vectors.reset": 0x00,
    ".vectors.sw_exception": 0x08,
    ".vectors.interrupt": 0x10,
    ".vectors.hw_exception": 0x20,
}
TEXT_OFFSET = 0x50


def base_vectors_from_xsa(path: Path):
    """C_BASE_VECTORS from the MicroBlaze .hwh inside the XSA, or None."""
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.endswith(".hwh") or "microblaze" not in name.lower():
                continue
            text = archive.read(name).decode("utf-8", "replace")
            match = re.search(r'C_BASE_VECTORS"\s+VALUE="(0x[0-9A-Fa-f]+)"', text)
            if match:
                return int(match.group(1), 16)
    return None


def relocate_vectors(script: Path, base_vectors: int) -> None:
    text = script.read_text()

    origins = re.findall(r"ORIGIN\s*=\s*(0x[0-9A-Fa-f]+)", text)
    if len(origins) != 1:
        raise Exception(f"{script}: expected exactly one MEMORY region, found {len(origins)}")
    origin = int(origins[0], 16)
    if origin != base_vectors:
        raise Exception(
            f"{script}: memory ORIGIN {origin:#x} does not match the XSA's "
            f"C_BASE_VECTORS {base_vectors:#x}. The CPU would fetch its reset "
            f"vector from an address the linker never fills."
        )

    for section, offset in VECTOR_OFFSETS.items():
        pattern = re.escape(section) + r"\s+0x[0-9A-Fa-f]+\s*:"
        replacement = f"{section} {origin + offset:#x} :"
        text, count = re.subn(pattern, replacement, text, count=1)
        if count != 1:
            raise Exception(f"{script}: could not place {section}")

    # The vector sections sit at explicit addresses outside the region's
    # allocator, so .text needs an explicit address too or it would be laid
    # down on top of them at ORIGIN.
    text, count = re.subn(
        r"^\.text\s*(0x[0-9A-Fa-f]+\s*)?:",
        f".text {origin + TEXT_OFFSET:#x} :",
        text,
        count=1,
        flags=re.M,
    )
    if count != 1:
        raise Exception(f"{script}: could not place .text after the vectors")

    script.write_text(text)
    print(f"Relocated vectors to C_BASE_VECTORS {origin:#x}, .text to {origin + TEXT_OFFSET:#x}")


project_name = os.getenv("PROJECT_NAME") or "NoName"
cpu_name = os.getenv("CPU_NAME")
if not cpu_name or cpu_name == "null":
    exc = Exception("Add the expected CPU name to your project.yaml")
    exc.add_note("E.g. psu_cortexa53_0 or microblaze_0_microblaze_0 (check your block design)")
    raise exc

base_vectors = None
if "microblaze" in cpu_name.lower():
    base_vectors = base_vectors_from_xsa(xsa_path)
    if base_vectors is None:
        raise Exception(f"C_BASE_VECTORS not found in any MicroBlaze .hwh inside {xsa_path}")
    print(f"XSA {xsa_path} reports C_BASE_VECTORS {base_vectors:#x}")

client = vitis.create_client()

# %H, not %I: a 12-hour hour sorts an afternoon workspace before a morning one.
date = datetime.now().strftime("%Y%m%d%H%M%S")
workspace = root / f"_build/sw/vitis_{date}/"
if os.path.isdir(workspace):
    shutil.rmtree(workspace)
client.set_workspace(workspace)

platform_name = f"plat_{project_name}"
print(f"Creating platform from {xsa_path}")
platform = client.create_platform_component(name=platform_name, hw_design=xsa_path)
platform.report()

domain_name = "standalone_a53_0"
domain = platform.add_domain(name=domain_name, cpu=cpu_name, os="standalone")
domain.report()

for d in platform.list_domains():
    print(d)

print("Building platform")
platform.build()

print("Creating app")
platform_xpfm = client.find_platform_in_repos(platform_name)
app_component = client.create_app_component(
    name=f"sw_{project_name}", platform=platform_xpfm, domain=domain_name
)
app_component.get_app_config()

src_dir = root / "sw" / "src"
files = [f.name for f in src_dir.glob("**/*.[ch]*")]
print(f"Importing files: {files}")
app_component.import_files(from_loc=src_dir, files=files, dest_dir_in_cmp="src")

linker = app_component.get_ld_script()
linker.regenerate()
if base_vectors is not None:
    relocate_vectors(workspace / f"sw_{project_name}" / "src" / "lscript.ld", base_vectors)

app_component.report()
print("Building app")
app_component.build()

# Tell scr_BuildSoftware.sh which workspace this run built, so it never has to
# guess among older ones.
(root / "_build/sw/latest_workspace").write_text(f"{workspace}\n")

vitis.dispose()
