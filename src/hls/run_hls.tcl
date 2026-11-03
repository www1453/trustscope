# run_hls.tcl -- Vitis HLS project driver for the TrustScope CNN kernel
#
# usage:  set HLS_MODE=csim   ; vitis_hls -f run_hls.tcl
#         set HLS_MODE=csynth ; vitis_hls -f run_hls.tcl
#
# WHY THIS SCRIPT WRITES ITS OWN TRACE FILE
# vitis_hls.bat pipes through the msys 'tee', which needs a named pipe. The DSH
# file sandbox does not provide named pipes, so every console line is lost --
# including error messages. On 2026-09-24 that turned a failed run into a silent
# one: no project directory, no sol1.log, exit code 0, nothing to read.
# So the script records its own progress and catches every error into
# hls_trace.txt. If hls_trace.txt stops mid-way, that is where it died.
#
# WHY AN ENVIRONMENT VARIABLE AND NOT $argv
# the first version read $argv, vitis_hls left something unexpected in it, and
# csynth ran when csim was intended.
#
# ASCII only.
# ============================================================================

set script_dir [file normalize [file dirname [info script]]]
cd $script_dir

set tr [open "hls_trace.txt" w]
proc T {m} {
    global tr
    puts $tr "\[[clock format [clock seconds] -format %H:%M:%S]\] $m"
    flush $tr
}

set part "xc7z020_clg400"
set top  "ts_cnn_top"
set work "hls_proj"

set mode "csim"
# NOTE: the variable is TS_HLS_MODE, not HLS_MODE. Vitis HLS has its OWN
# HLS_MODE variable (it read "tcl" on 2026-09-24), so the first version of this
# script silently took the wrong branch and ran csynth when csim was intended.
# Never reuse a tool's variable names.
if {[info exists ::env(TS_HLS_MODE)]} { set mode $::env(TS_HLS_MODE) }
T "start: mode=$mode top=$top cwd=[pwd]"

if {[catch {

    T "open_project -reset $work"
    open_project -reset $work
    T "  ok"

    T "set_top $top"
    set_top $top
    T "  ok"

    T "add_files src/ts_cnn.cpp"
    add_files src/ts_cnn.cpp
    T "  ok"

    T "add_files -tb tb/tb_cnn.cpp"
    add_files -tb tb/tb_cnn.cpp
    T "  ok"

    T "add_files -tb data/params.bin + vectors.bin"
    add_files -tb data/params.bin
    add_files -tb data/vectors.bin
    T "  ok"

    T "open_solution -reset sol1"
    open_solution -reset "sol1"
    T "  ok"

    T "set_part xc7z020clg400-2"
    set_part "xc7z020clg400-2"
    T "  ok"

    T "create_clock -period 6.67"
    create_clock -period 6.67 -name default
    T "  ok"

    if {$mode eq "csim"} {
        # WHY AN ABSOLUTE DATA PATH (added 2026-10-15, after a real failure)
        #   The compiled csim.exe runs with its CWD set to
        #   hls_proj/sol1/csim/build -- NOT to this script's directory.  The
        #   testbench resolves "<argv1>/params.bin" against that CWD, so passing
        #   the bare word "data" made it fail with
        #       cannot open data/params.bin
        #       @E Simulation failed: Function 'main' returns nonzero value '1'
        #   The compile had succeeded and the failure looked like a kernel bug;
        #   it was a path bug.  file normalize returns forward slashes on
        #   Windows, which is what the toolchain wants.
        #   (The testbench also writes a hard-coded relative "data/trace_c.bin",
        #   but only when argv[2] == "dump"; this script never passes that.)
        set data_abs [file normalize "$script_dir/data"]
        T "csim data dir (absolute): $data_abs"
        T "csim_design -argv $data_abs"
        csim_design -argv $data_abs
        T "csim_design RETURNED"
    } else {
        T "csynth_design"
        csynth_design
        T "csynth_design RETURNED"
    }

} err] } {
    T "*** ERROR ***"
    T "message: $err"
    if {[info exists ::errorInfo]} {
        foreach l [split $::errorInfo "\n"] { T "    $l" }
    }
}

T "done"
close $tr
exit
