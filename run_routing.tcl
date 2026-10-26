# run_routing.tcl — run from project root with: tclsh run_routing.tcl
set root [file dirname [file normalize [info script]]]
set rtl [file join $root rtl]
set tb [file join $root tb tb_routing.sv]
set build [file join $root build]
file mkdir $build
set sources [list \
    [file join $rtl host_if.sv] \
    [file join $rtl instruction_memory.sv] \
    [file join $rtl operand_buffer.sv] \
    [file join $rtl pe.sv] \
    [file join $rtl fabric.sv] \
    [file join $rtl sequencer.sv] \
    [file join $rtl tt_um_dataflow.sv] $tb]
foreach f $sources {if {![file exists $f]} {error "Missing file: $f"}}
set sim [file join $build routing_simv]
if {[catch {exec iverilog -g2012 -s tb_routing -o $sim {*}$sources 2>@1} msg]} {
    puts stderr $msg
    error "Compilation failed"
}
if {$msg ne ""} {puts $msg}
set original [pwd]
cd $build
set fail [catch {exec vvp $sim 2>@1} output]
cd $original
puts $output
if {$fail || [string first "PASS: two-cycle PE neighbor routed reduction" $output] < 0} {
    error "Routing test FAILED"
}
puts "SUCCESS: Routing test passed. Waveform: [file join $build routing.vcd]"
