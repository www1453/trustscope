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

# --- input discovery: same directory layout as this clone -------------------
# The repository ships src/hls/ts_cnn.cpp and src/hls/tb_cnn.cpp FLAT (no src/
# or tb/ subdirectory), and it does NOT ship the test vectors
# data/params.bin + data/vectors.bin. Both layouts are accepted so the script
# works from a clone and from the original working tree.
proc FIRST {cands} {
    foreach c $cands { if {[file exists $c]} { return $c } }
    return ""
}
set SRC  [FIRST [list [file join $script_dir src ts_cnn.cpp] [file join $script_dir ts_cnn.cpp]]]
set TB   [FIRST [list [file join $script_dir tb tb_cnn.cpp] [file join $script_dir tb_cnn.cpp]]]
set PDIR [FIRST [list [file join $script_dir data] [file join $script_dir .. .. data] "data"]]
set POK 0
if {$PDIR ne ""} {
    if {[file exists [file join $PDIR params.bin]] && [file exists [file join $PDIR vectors.bin]]} { set POK 1 }
}
T "src=$SRC tb=$TB data=$PDIR vectors_ok=$POK"

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

    if {$SRC eq ""} { T "FATAL ts_cnn.cpp not found next to this script"; exit 1 }
    T "add_files $SRC"
    add_files $SRC
    T "  ok"

    if {$TB ne ""} {
        T "add_files -tb $TB"
        add_files -tb $TB
        T "  ok"
    } else {
        T "WARN tb_cnn.cpp not found -- csim will be unavailable"
    }

    if {$POK} {
        T "add_files -tb $PDIR/params.bin + vectors.bin"
        add_files -tb [file join $PDIR params.bin]
        add_files -tb [file join $PDIR vectors.bin]
        T "  ok"
    } else {
        T "NOTE test vectors (params.bin / vectors.bin) are NOT distributed"
        T "     csynth/export_ip work; csim cannot run without them"
    }

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
        set data_abs [file normalize $PDIR]
        if {!$POK} {
            T "FATAL csim needs data/params.bin + data/vectors.bin, which this"
            T "      repository does not distribute. Run with TS_HLS_MODE=csynth."
            close $tr
            exit 2
        }
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
