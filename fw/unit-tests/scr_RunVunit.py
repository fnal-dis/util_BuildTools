#!/usr/bin/env python3

from pathlib import Path
from vunit import VUnit
from subprocess import call
import re
import zipfile

this_path = Path(__file__).parent
src_path = this_path / "../../../fw/src"
#synth_path = this_path / "../../_project/intel/ip/"

VU = VUnit.from_argv()
#VU.add_vhdl_builtins()


lib_path = Path("/data/javierc/000_Resources/IP_Libraries/")
#VU.add_external_library("unisim", lib_path / "unisim/v08")
#VU.add_external_library("secureip", lib_path / "secureip/v08")

lib = VU.add_library("lib")
lib.add_source_files(src_path / "hdl/**/*.vhd")
lib.add_source_files(src_path / "bd/**/*.vhd", allow_empty=True)

ip_found = False
for f in Path(src_path / "ip").rglob("*.xcix"):
    ip_found = True
    zipfile.ZipFile(f).extractall(f.with_suffix('.tmp'))
if ip_found:
    lib.add_source_files(src_path / "ip/**/*stub.vhdl")
#lib.add_source_files(src_path/"tb/main_tb.vhd")

for f in VU.get_compile_order():
    print(f.name)
#import pdb; pdb.set_trace()

#VU.set_sim_option("ghdl.elab_flags", ["-P/data/Xilinx/Vivado/2024.1/data/vhdl/src"])
#VU.set_compile_option("ghdl.a_flags", [f"-P/data/Xilinx/Vivado/2024.1/data/vhdl/src"])
#VU.set_sim_option("ghdl.sim_flags", ["--wave=digitalbus.ghw"])
#VU.set_compile_option("enable_coverage", True)
#VU.set_sim_option("enable_coverage", True)


def post_run(results):
    results.merge_coverage(file_name='coverage_data')
    # Ellide paths from output reports
    r = re.compile(r"(.*@)|(:\(report note)\)")
    for path in this_path.rglob("output.txt"):
        text = path.read_text()
        new_text = r.sub("", text)
        path.write_text(new_text)

#VU.main(post_run=post_run)
VU.main(post_run=None)
