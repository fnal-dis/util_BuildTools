set project_name $::env(PROJECT_NAME)
set part_number $::env(PART_NUMBER)
set ip_repos [split $::env(IP_REPOS) ";"]

# # # # # # # # # # # # # # # # # # # #
# Find files and populate directories #
# # # # # # # # # # # # # # # # # # # #

package require fileutil;

set scrdir [file normalize .]
set topdir [file normalize ../../../]

set src_directory ${topdir}/fw/src
set modules_directory ${topdir}/fw/modules

# %H, not %I: a 12-hour hour sorts an afternoon build before a morning one.
set fmt_date [clock format [clock seconds] -format "%Y%m%d%H%M%S"]

set project_directory ${topdir}/_build/fw/vivado
set results_directory ${topdir}/_outputs/fw/${fmt_date}
set latest_directory ${topdir}/_outputs/fw/latest

# Remove the previous build's outputs up front, so a failed build can never
# leave an older bitstream in latest/ for a later step to pick up.
file delete -force -- ${project_directory}
file delete -force -- ${latest_directory}

file mkdir ${results_directory}
file mkdir ${project_directory}

cd ${project_directory}

proc fail {message} {
    puts stderr "ERROR: $message"
    exit 1
}

proc nonempty {var} {
    expr {[llength $var] > 0}
}

# # # # # # # # # # # # # # # # # # # #
# Project hooks                       #
# # # # # # # # # # # # # # # # # # # #
#
# A project can add design-specific checks without forking this script by
# providing fw/scripts/build_hooks.tcl. Every proc in it is optional:
#
#   hook_post_bd        {results_directory xsa}  after the block designs and XSA
#   hook_post_opt       {results_directory}      after opt_design
#   hook_post_route     {results_directory}      after route_design/phys_opt_design
#   hook_post_bitstream {results_directory}      after the bitstream is written
#
# A hook fails the build by raising an error, with `error "..."`. Hooks run with
# the design open, from ${project_directory}; ${topdir} is the project root.
set hooks_file ${topdir}/fw/scripts/build_hooks.tcl
if {[file exists ${hooks_file}]} {
    puts "INFO: sourcing project hooks ${hooks_file}"
    source ${hooks_file}
}

proc run_hook {name args} {
    if {[llength [info procs ${name}]] == 0} { return }
    puts "INFO: running project hook ${name}"
    if {[catch {${name} {*}$args} err]} {
        fail "project hook ${name} failed: $err"
    }
}

# # # # # # # # # # # # # # # # # # # #
# Sources                             #
# # # # # # # # # # # # # # # # # # # #

# SystemVerilog is read in its own read_verilog -sv call, not in the same call
# as plain Verilog. A .sv file that opens with `default_nettype none would
# otherwise share a compilation unit with Xilinx-generated Verilog wrappers that
# rely on implicit nets, and those wrappers would stop elaborating.
set files_vhd [fileutil::findByPattern ${src_directory}/hdl *.vhd]
set files_v   [fileutil::findByPattern ${src_directory}/hdl *.v]
set files_sv  [fileutil::findByPattern ${src_directory}/hdl *.sv]
set files_xdc [fileutil::findByPattern ${src_directory}/constraints *.xdc]
set files_xcix [fileutil::findByPattern ${src_directory}/ip *.xcix]
set files_bd [fileutil::findByPattern ${src_directory}/bd *.tcl]

# # # # # # # # # # # # # # # # # # # #
# Begin Xilinx build commands         #
# # # # # # # # # # # # # # # # # # # #

set_part ${part_number}
set_property TARGET_LANGUAGE VHDL [current_project]
set_property PLATFORM.DESIGN_INTENT.EMBEDDED true [current_project]
set_property source_mgmt_mode all [current_project]

if {[nonempty ${ip_repos}]} {
    foreach repo ${ip_repos} {
        if {![file isdirectory ${repo}]} { fail "ip_repos entry not found on this machine: ${repo}" }
    }
    set_property ip_repo_paths ${ip_repos} [current_fileset]
    update_ip_catalog
}

# Find and Read BD dependencies before mass HDL import
if {[nonempty ${files_bd}]} {
    # Collect unique module names referenced across all BD scripts
    source ${scrdir}/scr_FindBdModules.tcl
    foreach f [find_bd_module_files ${files_bd} ${src_directory}] {
        if {[string match *.vhd $f]} {
            read_vhdl $f
        } elseif {[string match *.sv $f]} {
            read_verilog -sv $f
        } else {
            read_verilog $f
        }
    }
}

if {[file exists ${modules_directory}]} {
    set files_vhd [concat $files_vhd [fileutil::findByPattern ${modules_directory} *.vhd]]
    set files_v   [concat $files_v   [fileutil::findByPattern ${modules_directory} *.v]]
    set files_sv  [concat $files_sv  [fileutil::findByPattern ${modules_directory} *.sv]]
}

if {[nonempty ${files_vhd}]} {read_vhdl -vhdl2008 ${files_vhd}}
if {[nonempty ${files_v}]}   {read_verilog ${files_v}}
if {[nonempty ${files_sv}]}  {read_verilog -sv ${files_sv}}
if {[nonempty ${files_xdc}]} {read_xdc ${files_xdc}}

if {[nonempty ${files_xcix}]} {
    add_files -scan_for_includes ${files_xcix}
    get_ips
    upgrade_ip [get_ips]
    generate_target all [get_ips]
    export_ip_user_files -of_objects [get_ips] -no_script -force -reset

    # Read IP VHDL stubs into work so `entity work.<ip>` instantiations resolve
    foreach ip [get_ips] {
        set stubs [get_files -quiet -of_objects $ip -filter {FILE_TYPE == "VHDL" && USED_IN =~ "*synthesis*" && NAME =~ "*stub.vhdl"}]
        if {$stubs ne ""} {
            read_vhdl -vhdl2008 $stubs
        }
    }
}


set_property top top [get_filesets sources_1]
update_compile_order -fileset sources_1

proc generate_bd_files {bd_name} {
    set bd [get_files -filter "NAME =~ *${bd_name}.bd"]
    make_wrapper -top -import -files ${bd}

    update_compile_order -fileset sources_1
    set_property synth_checkpoint_mode None ${bd}
    generate_target all ${bd}
    export_ip_user_files -of_objects ${bd} -no_script -force -reset
}

# Read and generate block designs (order is alphabetic)
foreach bd_file ${files_bd} {
    source $bd_file
    set bd_name [file rootname [file tail $bd_file]]
    generate_bd_files $bd_name
}

set ips [get_ips]
if {[nonempty ${ips}]} {upgrade_ip [get_ips]}

set xsa ${results_directory}/${project_name}.xsa
write_hw_platform -fixed -force -file ${xsa}
if {![file isfile ${xsa}]} { fail "write_hw_platform produced no ${xsa}" }

# Block-design and address-map checks belong here, minutes into the build,
# rather than after implementation.
run_hook hook_post_bd ${results_directory} ${xsa}

# The ELF is not built yet at this point -- it is compiled against the XSA
# written above -- so it is merged into the bitstream afterwards with
# updatemem, using the .mmi written below. See scr_EmbedElf.sh.

synth_design

opt_design
run_hook hook_post_opt ${results_directory}
write_checkpoint -force ${results_directory}/synth.dcp

power_opt_design
place_design
write_checkpoint -force ${results_directory}/post_place.dcp

route_design
phys_opt_design
write_checkpoint -force ${results_directory}/post_route.dcp

report_timing_summary -max_paths 20 -file ${results_directory}/timing_summary.rpt
report_utilization -file ${results_directory}/utilization.rpt
report_drc -file ${results_directory}/drc.rpt
report_methodology -file ${results_directory}/methodology.rpt
report_clock_interaction -file ${results_directory}/clock_interaction.rpt
report_cdc -file ${results_directory}/cdc.rpt

run_hook hook_post_route ${results_directory}

# Judge the run on slack, not on Vivado's exit status. A bitstream that misses
# timing programs and half works, which is worse than no bitstream.
# ALLOW_TIMING_FAILURE=1 writes the bitstream anyway, for debugging only.
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fh [open ${results_directory}/timing.txt w]
puts $fh "WNS ${wns}\nWHS ${whs}"
close $fh
puts "TIMING WNS ${wns} ns  WHS ${whs} ns"
if {${wns} eq "" || ${whs} eq ""} {
    fail "no timing paths found; is the design constrained?"
}
if {${wns} < 0 || ${whs} < 0} {
    set message "implementation missed timing: WNS ${wns} ns, WHS ${whs} ns. See timing_summary.rpt"
    if {[info exists ::env(ALLOW_TIMING_FAILURE)] && $::env(ALLOW_TIMING_FAILURE) eq "1"} {
        puts "CRITICAL WARNING: ${message} (ALLOW_TIMING_FAILURE=1, continuing)"
    } else {
        fail ${message}
    }
}

write_bitstream -force ${results_directory}/${project_name}.bit
write_debug_probes -force ${results_directory}/${project_name}.ltx

# BRAM memory map for scr_EmbedElf.sh. Written from the routed design, so the
# merge only re-initialises BRAM and never re-implements anything. A design
# with no processor has nothing to map; that is not a build failure.
if {[catch {write_mem_info -force ${results_directory}/${project_name}.mmi} err]} {
    puts "WARNING: write_mem_info failed, no .mmi written: $err"
}

run_hook hook_post_bitstream ${results_directory}

# Publish only a complete build. scr_CompileDesign.sh checks for this marker.
file copy ${results_directory} ${latest_directory}
set fh [open ${latest_directory}/BUILD_OK w]
puts $fh ${results_directory}
close $fh
puts "BUILD_OK ${results_directory}"
