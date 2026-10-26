
# run.tcl

set root [file dirname [file normalize [info script]]]

set rtl_dir [file join $root rtl]
set tb_dir [file join $root tb]
set build_dir [file join $root build]

file mkdir $build_dir

set rtl_files [list \
    [file join $rtl_dir host_if.sv] \
    [file join $rtl_dir instruction_memory.sv] \
    [file join $rtl_dir operand_buffer.sv] \
    [file join $rtl_dir pe.sv] \
    [file join $rtl_dir fabric.sv] \
    [file join $rtl_dir sequencer.sv] \
    [file join $rtl_dir tt_um_dataflow.sv] \
]

set tb_file [file join $tb_dir tb_smoke.sv]
set sim_file [file join $build_dir simv]

# Verify all source files exist
foreach f [concat $rtl_files [list $tb_file]] {
    if {![file exists $f]} {
        error "Missing file: $f"
    }
}

puts "Compiling RTL..."

set compile_cmd [concat \
    [list iverilog -g2012 -s tb_smoke -o $sim_file] \
    $rtl_files \
    [list $tb_file] \
]

if {[catch {exec {*}$compile_cmd 2>@1} result]} {
    puts stderr $result
    exit 1
}

if {$result ne ""} {
    puts $result
}

puts "Running simulation..."

set original_dir [pwd]
cd $build_dir

set failed [catch {exec vvp $sim_file 2>@1} result]

cd $original_dir

puts $result

if {$failed} {
    puts stderr "Simulation failed."
    exit 1
}

set expected "PASS: host upload/readback + four parallel MACs + sequencer"

if {[string first $expected $result] < 0} {
    puts stderr "ERROR: Expected PASS marker not found."
    exit 1
}

puts "SUCCESS: System smoke test passed."
puts "Waveform: [file join $build_dir smoke.vcd]"