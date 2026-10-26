
# synth_generic.tcl
# Execute: tclsh synth_generic.tcl

set root [file dirname [file normalize [info script]]]
set rtl [file join $root rtl]
set build [file join $root build]

file mkdir $build

set rtl_files [list \
    host_if.sv \
    instruction_memory.sv \
    operand_buffer.sv \
    pe.sv \
    fabric.sv \
    sequencer.sv \
    tt_um_dataflow.sv \
]

set yosys_script [file join $build generic_synth.ys]
set log_file [file join $build generic_synth.log]
set netlist_file [file join $build generic_netlist.json]

set fd [open $yosys_script w]

# Load SystemVerilog modules
foreach filename $rtl_files {
    set path [file join $rtl $filename]

    if {![file exists $path]} {
        close $fd
        error "Missing RTL file: $path"
    }

    puts $fd "read_verilog -sv $path"
}

# Check design hierarchy
puts $fd "hierarchy -check -top tt_um_dataflow"

# Perform technology-independent synthesis
puts $fd "synth -top tt_um_dataflow"

# Check for structural problems
puts $fd "check"

# Print synthesis statistics
puts $fd "stat"

# Export synthesized netlist
puts $fd "write_json $netlist_file"

close $fd

puts "Running Yosys synthesis..."

if {[catch {
    exec yosys -s $yosys_script -l $log_file 2>@1
} result]} {
    puts stderr $result
    puts stderr "Synthesis failed. Check: $log_file"
    exit 1
}

puts "Synthesis completed."
puts "Log: $log_file"
puts "Netlist: $netlist_file"