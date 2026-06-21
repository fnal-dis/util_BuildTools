#!/usr/bin/env python3
import vitis
import shutil
import os
from datetime import datetime
from pathlib import Path
import platform as os_platform

root = (Path(__file__).parent / "../../..").resolve()

try:
    xsa_path = next(root.glob("_outputs/fw/latest/*.xsa"))
except StopIteration:
    raise Exception("Failed finding .xsa file. Fix fw flow first!")


client = vitis.create_client()

# Configure workspace
date = datetime.now().strftime("%Y%m%d%I%M%S")
workspace = root / f"_build/sw/vitis_{date}/"

if os.path.isdir(workspace):
    shutil.rmtree(workspace)

client.set_workspace(workspace)

# Configure platform
project_name = os.getenv("PROJECT_NAME")
if project_name == "":
    project_name = "NoName"

platform_name = f"plat_{project_name}"
print("Creating platform")
print(xsa_path)
platform = client.create_platform_component(name=platform_name, hw_design=xsa_path)
platform.report()

print("Creating domain")
domain_name = "standalone_a53_0"
cpu_name = os.getenv("CPU_NAME")
if cpu_name == "":
    exc = Exception("Add the expected CPU name to your project.yaml")
    exc.add_note(
        "E.g. psu_cortexa53_0 or microblaze_0_microblaze_0 (check your block design)"
    )
    raise exc
standalone_a53_0 = platform.add_domain(name=domain_name, cpu=cpu_name, os="standalone")
standalone_a53_0.report()

# Check that domain was created
for domain in platform.list_domains():
    print(domain)

print("Building platform")
platform.build()

# Create application component
print("Creating app")
platform_xpfm = client.find_platform_in_repos(platform_name)
app_component = client.create_app_component(
    name=f"sw_{project_name}", platform=platform_xpfm, domain=domain_name
)

app_component.get_app_config()

src_dir = root / "sw" / "src"
files = [f.name for f in src_dir.glob("**/*.[ch]*")]
print("Importing files")
print(files)
app_component.import_files(from_loc=src_dir, files=files, dest_dir_in_cmp="src")


print("Building app")
linker = app_component.get_ld_script()
linker.regenerate()

app_component.report()
app_component.build()

vitis.dispose()
