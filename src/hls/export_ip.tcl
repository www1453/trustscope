# export_ip.tcl -- package the ALREADY SYNTHESISED ts_cnn_top as a Vivado IP core.
#
# WHY THIS EXISTS
# run_hls.tcl only ever called csynth_design. The solution type is "Vivado IP
# Flow Target", but csynth alone leaves sol1/impl with nothing but an RTL dump
# (verilog/, vhdl/, misc/) -- there is no component.xml and no _ip.zip, so the
# core cannot be added to a Block Design. On 2026-09-24 that was only discovered
# when W6 started, after four synthesis runs had each been assumed to produce
# a usable IP.
#
# THIS SCRIPT DOES NOT RE-SYNTHESISE. It opens the existing hls_proj/sol1 and
# runs export_design only, so it costs a minute, not ten. If the source has
# changed since the last csynth, the exported RTL would be stale -- the caller
# must therefore confirm that the RTL dump under sol1/impl/verilog is current
# (compare against the last csynth time in hls_trace.txt).
#
# usage: run_hls_nopipe.bat -f export_ip.tcl     (foreground, no tee)
# ASCII only.
# ============================================================================

set script_dir [file normalize [file dirname [info script]]]
cd $script_dir

set tr [open "hls_trace.txt" a]
proc T {m} {
    global tr
    puts $tr "\[[clock format [clock seconds] -format %H:%M:%S]\] $m"
    flush $tr
}

T "export_ip: opening existing hls_proj"
if {[catch {

    T "  open_project hls_proj (no reset)"
    open_project hls_proj
    T "  ok"

    T "  open_solution sol1 (no reset)"
    open_solution sol1
    T "  ok"

    T "  export_design -format ip_catalog"
    # NOTE: no -force here. Vitis HLS 2023.1 does not have it, and the failure
    # message is only "command 'export_design' returned error code" -- the real
    # reason ("Unknown option '-force'") is printed later in the console but NOT
    # in the Tcl error string. Always read the console, not just the catch text.
    export_design -format ip_catalog -rtl verilog
    T "  ok"

} err] } {
    T "*** ERROR ***"
    T "message: $err"
    if {[info exists ::errorInfo]} {
        foreach l [split $::errorInfo "\n"] { T "    $l" }
    }
}

# Explicitly report whether the artefact the next stage needs now exists.
set cxml "hls_proj/sol1/impl/ip/component.xml"
if {[file exists $cxml]} {
    T "RESULT: component.xml PRESENT -> $cxml"
} else {
    T "RESULT: component.xml MISSING -> export_design did not produce an IP"
}

T "done"
close $tr
exit
