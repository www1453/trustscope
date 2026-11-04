# ============================================================================
# batch_build.tcl -- regenerate BD outputs, synth, impl, bitstream, export XSA
#   usage: vivado -mode batch -source src/build/batch_build.tcl
#
# INPUTS THIS REPOSITORY DOES *NOT* CONTAIN
#   This repo ships text sources, not a Vivado project. Three inputs are
#   therefore absent and must be supplied before this script can run:
#     *.xpr  the Vivado project file. Not distributed: it embeds the ALINX
#            vendor board files and the generated IP products, and it points
#            at a machine-local IP cache. Supply it with TRUSTSCOPE_XPR.
#            It can be recreated: src/build/bd/design_1_bd.tcl rebuilds the
#            Block Design in a fresh project, and src/two_fft.xdc carries the
#            pin constraints.
#     *.v    the module_ref RTL the BD points at (capture_ram.v, analyzer_fe.v,
#            spi_gen.v, alinx_ov5640.v ...). Not distributed either. Set
#            TRUSTSCOPE_RTL to the directory that holds them.
#     *.xsa  FFT.xsa is an OUTPUT of this script. It is only an input to the
#            Vitis side, never a hard requirement here.
#   Every path below is derived from this file's own location, so a clone at
#   any directory works. Override with the env vars named next to the defaults.
# ============================================================================
#
# WHY EVERY RUN IS RESET
# ----------------------
# Every HDL module_ref in the BD gets its own OUT-OF-CONTEXT synthesis run.
# capture_ram_0 is a module_ref with SYNTHESISFLOW=OOC_HIERARCHICAL: it is
# synthesized on its own into
#     two FFT.runs/design_1_capture_ram_0_0_synth_1/design_1_capture_ram_0_0.dcp
# and the top level only LINKS that checkpoint.
#
# The previous version of this script reset only synth_1 and impl_1. On
# 2026-09-18 that left the capture_ram DCP dated 09-17 13:44 while
# rtl/capture_ram.v had been edited at 09-18 14:55 -- so a full day of RTL
# fixes (including the capture trigger rewrite) were SILENTLY NOT IN THE
# BITSTREAM, while every build still reported "write_bitstream Complete!".
#
# Resetting all runs costs a full rebuild and removes that whole failure mode.
# The assertions near the end make the build state out loud whether the RTL
# actually made it in, so a stale link can never pass unnoticed again.
#
# ASCII ONLY -- Vivado on a Chinese Windows console reads .tcl as GBK and
# non-ASCII bytes can eat quotes/braces and cause unrelated syntax errors.
# ============================================================================

# --- path policy: script location first, environment variable second -------
set ROOT [file normalize [file join [file dirname [info script]] .. ..]]

proc ENV {name def} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $def
}
proc RESOLVE {p base} {
    if {[file pathtype $p] eq "absolute"} { return $p }
    return [file join $base $p]
}

# TRUSTSCOPE_LOG  default <root>/build_logs/build.log
set LOGFILE [RESOLVE [ENV TRUSTSCOPE_LOG [file join $ROOT build_logs build.log]] $ROOT]
file mkdir [file dirname $LOGFILE]
set _lfh [open $LOGFILE w]
proc L {msg} {
    puts $msg
    global _lfh
    if {[info exists _lfh]} { puts $_lfh $msg; flush $_lfh }
}

# TRUSTSCOPE_XPR  default <root>/hw/two_fft/two FFT.xpr   (NOT distributed)
set XPR  [RESOLVE [ENV TRUSTSCOPE_XPR [file join $ROOT hw two_fft "two FFT.xpr"]] $ROOT]
# TRUSTSCOPE_XSA  default <root>/src/build/FFT.xsa        (output of this script)
set XSA  [RESOLVE [ENV TRUSTSCOPE_XSA [file join $ROOT src build FFT.xsa]] $ROOT]
# TRUSTSCOPE_RUNS default: runs dir of the project opened above
set RUNS [RESOLVE [ENV TRUSTSCOPE_RUNS [file rootname $XPR].runs] $ROOT]
# TRUSTSCOPE_RTL  default <root>/src/rtl                   (NOT distributed)
set SRCD [RESOLVE [ENV TRUSTSCOPE_RTL [file join $ROOT src rtl]] $ROOT]

file mkdir [file dirname $XSA]
L "root      = $ROOT"
if {[file exists $XPR]}    { set nxpr "  (present)" } else { set nxpr "  (MISSING)" }
if {[file isdirectory $SRCD]} { set nrtl "" } else { set nrtl "  (MISSING)" }
L "project   = $XPR$nxpr"
L "xsa       = $XSA"
L "runs      = $RUNS"
L "rtl       = $SRCD$nrtl"

proc MTIME {f} {
    if {![file exists $f]} { return -1 }
    return [file mtime $f]
}
proc STAMP {t} {
    if {$t < 0} { return "MISSING" }
    return [clock format $t -format {%Y-%m-%d %H:%M:%S}]
}

L "=========== batch_build ==========="

if {![file exists $XPR]} {
    L "*** FATAL: no Vivado project at: $XPR"
    L "*** The .xpr is NOT part of this repository (vendor board files and"
    L "*** generated IP products are not distributed). Either set TRUSTSCOPE_XPR"
    L "*** to an existing project, or rebuild the block design from"
    L "*** src/build/bd/design_1_bd.tcl -- see src/build/README.md."
    close $_lfh
    exit 1
}

if {[catch {

    open_project $XPR
    L "project opened"

    set bdfile [lindex [get_files -quiet *.bd] 0]
    L "bd file: $bdfile"

    # ---- 1. regenerate BD output products (includes the hwh) ----
    L "--- generate_target all ---"
    generate_target all $bdfile
    L "generate_target done"

    # ---- 2. regenerate the wrapper ----
    L "--- make_wrapper ---"
    make_wrapper -files $bdfile -top
    L "make_wrapper done"

    # ---- 3. reset EVERY run, not just the top two ----
    L "--- reset runs (all, including OOC module_ref runs) ---"
    set allruns [get_runs -quiet]
    L "run count: [llength $allruns]"
    foreach r $allruns {
        if {[catch { reset_run $r } e]} {
            L "  reset_run $r : FAILED: $e"
        } else {
            L "  reset_run $r : ok"
        }
    }

    # ---- 4. launch ----
    # NOTE 2026-09-22: -jobs was 12. The first run today (2026-09-22 12:27)
    # died with an EMPTY hs_err_pid*.dmp right here, inside launch_runs, with
    # no error message at all -- the JVM was killed, most likely on memory
    # (12 parallel vivado processes). Lowered to 4 to make the build complete;
    # it only costs wall-clock time. Raise it again only with free RAM to spare.
    L "--- launch_runs impl_1 -to_step write_bitstream (jobs=4) ---"
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    L "runs launched, waiting..."

    if {[catch { wait_on_run impl_1 } e]} {
        L "wait_on_run error: $e"
    }

    # ---- 5. status ----
    set st   [get_property STATUS   [get_runs impl_1]]
    set prog [get_property PROGRESS [get_runs impl_1]]
    L "impl_1 STATUS   = $st"
    L "impl_1 PROGRESS = $prog"

    if {[string match "*Complete*" $st] == 0} {
        L "*** impl_1 did not complete successfully ***"
    }

    # ---- 6. ASSERT the RTL actually made it in (no silent staleness) ----
    L "--- freshness assertions ---"
    foreach {nm dcp src} [list \
        capture_ram  "$RUNS/design_1_capture_ram_0_0_synth_1/design_1_capture_ram_0_0.dcp" "$SRCD/capture_ram.v" \
        cam_pclk_cnt "$RUNS/design_1_cam_pclk_cnt_0_synth_1/design_1_cam_pclk_cnt_0.dcp"  "" \
        clk_probe_cnt "$RUNS/design_1_clk_probe_cnt_0_synth_1/design_1_clk_probe_cnt_0.dcp" "" ] {

        set td [MTIME $dcp]
        if {$src ne ""} {
            set ts [MTIME $src]
            L "  $nm: dcp [STAMP $td]   source [STAMP $ts]"
            if {$td < 0} {
                L "    *** FAIL: OOC dcp does not exist ***"
            } elseif {$td < $ts} {
                L "    *** FAIL: dcp is OLDER than the source -- RTL edit NOT linked in ***"
            } else {
                L "    OK: dcp is newer than the source"
            }
        } else {
            L "  $nm: dcp [STAMP $td]"
        }
    }

    set tbit [MTIME "$RUNS/impl_1/design_1_wrapper.bit"]
    set tcm  [MTIME "$SRCD/capture_ram.v"]
    L "  bitstream  [STAMP $tbit]"
    L "  capture_ram.v [STAMP $tcm]"
    if {$tbit < 0} {
        L "    *** FAIL: bitstream missing ***"
    } elseif {$tbit < $tcm} {
        L "    *** FAIL: bitstream OLDER than capture_ram.v ***"
    } else {
        L "    OK: bitstream is newer than capture_ram.v"
    }

    # ---- 7. export XSA ----
    L "--- write_hw_platform ---"
    catch { file delete -force $XSA }
    write_hw_platform -fixed -include_bit -force -file $XSA
    L "XSA written: $XSA"

    L "=== BUILD DONE ==="

} err] } {
    L "*** ERROR CAUGHT ***"
    L "message: $err"
    global errorInfo
    if {[info exists errorInfo]} { foreach l [split $errorInfo "\n"] { L "    $l" } }
}

L "log: $LOGFILE"
close $_lfh
