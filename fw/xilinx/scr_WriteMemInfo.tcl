# Emit the BRAM memory-map file (.mmi) that updatemem needs to merge an ELF
# into an existing bitstream.
#
# scr_SynthNonProjectMode.tcl writes the .mmi itself. This is the fallback for
# a bitstream built before it did: it opens the routed checkpoint and writes
# the .mmi from that. Nothing is re-implemented; the LMB BRAM placement is
# already fixed in the checkpoint, which is what makes the merge safe.
#
# Usage: vivado -mode batch -source scr_WriteMemInfo.tcl -tclargs POST_ROUTE_DCP OUT_MMI

proc fail {message} {
    puts stderr "ERROR: $message"
    exit 1
}

if {$argc != 2} { fail "usage: scr_WriteMemInfo.tcl POST_ROUTE_DCP OUT_MMI" }
lassign $argv dcp out_mmi

if {![file isfile $dcp]} { fail "checkpoint not found: $dcp" }
open_checkpoint $dcp
write_mem_info -force $out_mmi
close_design
puts "MMI $out_mmi"
