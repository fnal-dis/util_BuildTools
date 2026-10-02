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

set current_time [clock seconds]
set fmt_date [clock format [clock seconds] -format "%Y%m%d%I%M%S"]

set project_directory ${topdir}/_build/fw/vivado
set results_directory ${topdir}/_outputs/fw/${fmt_date}
set latest_directory ${topdir}/_outputs/fw/latest

file delete -force -- ${project_directory}

file mkdir ${results_directory}
file mkdir ${project_directory}

cd ${project_directory}

set files_vhd [fileutil::findByPattern ${src_directory}/hdl *.vhd]
set files_ver [concat \
               [fileutil::findByPattern ${src_directory}/hdl *.v] \
               [fileutil::findByPattern ${src_directory}/hdl *.sv] \
               ]
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

if {[llength ${ip_repos}] > 0} {
    set_property ip_repo_paths ${ip_repos} [current_fileset]
    update_ip_catalog
}

proc nonempty {var} {
    expr {[llength $var] > 0}
}

# Find and Read BD dependencies before mass HDL import
if {[nonempty ${files_bd}]} {
    # Collect unique module names referenced across all BD scripts
    source ${scrdir}/scr_FindBdModules.tcl
    foreach f [find_bd_module_files ${files_bd} ${src_directory}] {
        if {[string match *.vhd $f]} {read_vhdl $f} else {read_verilog $f}
    }
}

if {[file exists ${modules_directory}]} {
    set files_vhd [concat $files_vhd [fileutil::findByPattern ${modules_directory} *.vhd]]
    set files_ver [concat $files_ver [fileutil::findByPattern ${modules_directory} *.v]]
    set files_ver [concat $files_ver [fileutil::findByPattern ${modules_directory} *.sv]]
}


if {[nonempty ${files_vhd}]} {read_vhdl -vhdl2008 ${files_vhd}}
if {[nonempty ${files_ver}]} {read_verilog -sv ${files_ver}}
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
    #export_ip_user_files -of_objects [get_files -filter {NAME =~ *_project/**/*microblaze.bd}] -no_script -force -reset
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

#write_project_tcl -force -all_properties ${results_directory}/generate_project.tcl
write_hw_platform -fixed -force -file ${results_directory}/${project_name}.xsa

# The ELF is not built yet at this point -- it is compiled against the XSA
# written above -- so it is merged into the bitstream afterwards with
# updatemem, using the .mmi written below. See scr_EmbedElf.sh.

synth_design
opt_design
write_checkpoint -force ${results_directory}/synth.dcp

power_opt_design
place_design
write_checkpoint -force ${results_directory}/post_place.dcp

route_design
phys_opt_design
write_checkpoint -force ${results_directory}/post_route.dcp

report_timing

write_bitstream -force ${results_directory}/${project_name}.bit
write_debug_probes -force ${results_directory}/${project_name}.ltx

# BRAM memory map for scr_EmbedElf.sh. Written from the routed design, so the
# merge only re-initialises BRAM and never re-implements anything. A design
# with no processor has nothing to map; that is not a build failure.
if {[catch {write_mem_info -force ${results_directory}/${project_name}.mmi} err]} {
    puts "WARNING: write_mem_info failed, no .mmi written: $err"
}


file delete -force -- ${latest_directory}
file copy ${results_directory} ${latest_directory}
