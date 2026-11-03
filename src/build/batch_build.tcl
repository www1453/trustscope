# ============================================================================
# batch_build.tcl -- regenerate BD outputs, synth, impl, bitstream, export XSA
#   usage: vivado -mode batch -source batch_build.tcl
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

set LOGFILE "C:/Users/wzh/Documents/trustscope/ps_fft_dual/logs/build.log"
file mkdir [file dirname $LOGFILE]
set _lfh [open $LOGFILE w]
proc L {msg} {
    puts $msg
    global _lfh
    if {[info exists _lfh]} { puts $_lfh $msg; flush $_lfh }
}

set XPR  "D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.xpr"
set XSA  "C:/Users/wzh/Documents/vitis/xsa/FFT.xsa"
set RUNS "D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.runs"
set SRCD "C:/Users/wzh/Documents/trustscope/ps_fft_dual/rtl"

proc MTIME {f} {
    if {![file exists $f]} { return -1 }
    return [file mtime $f]
}
proc STAMP {t} {
    if {$t < 0} { return "MISSING" }
    return [clock format $t -format {%Y-%m-%d %H:%M:%S}]
}

L "=========== batch_build ==========="

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
