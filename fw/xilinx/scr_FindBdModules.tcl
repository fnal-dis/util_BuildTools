# scr_FindBdModules.tcl
# Scan block-design tcl files for list_check_mods entries,
# then locate the corresponding VHDL/Verilog sources under hdl/.

proc find_bd_module_files {files_bd src_directory} {
    # -- 1. Extract unique module names from list_check_mods in each .tcl file --
    array set seen {}
    foreach f $files_bd {
        set fh [open $f r]
        set content [read $fh]
        close $fh
        if {[regexp {set\s+list_check_mods\s+"([^"]+)"} $content -> mods_str]} {
            foreach mod [regexp -all -inline {\S+} $mods_str] {
                set mod [string trim $mod "\\"]
                if {$mod ne ""} {set seen($mod) 1}
            }
        }
    }
    set unique_mods [lsort [array names seen]]
    puts "INFO: Found [llength $unique_mods] unique modules: $unique_mods"

    # -- 2. Find HDL files matching each module name --
    set hdl_dir ${src_directory}/hdl
    set hdl_files {}
    foreach mod $unique_mods {
        set found {}
        foreach ext {.vhd .v .sv} {
            set found [concat $found [glob -nocomplain -directory $hdl_dir ${mod}${ext}] \
                                     [glob -nocomplain -directory $hdl_dir **/${mod}${ext}]]
        }
        if {[llength $found] == 0} {
            puts "WARNING: No HDL file found for module '$mod'"
        } else {
            foreach hit $found { lappend hdl_files $hit }
        }
    }
    set hdl_files [lsort -unique $hdl_files]
    puts "INFO: Resolved [llength $hdl_files] HDL files"
    return $hdl_files
}
