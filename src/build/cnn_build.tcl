# cnn_build.tcl -- 集成后的构建：wrapper -> 综合 -> 实现 -> 比特流。
#
# 本仓库不含 Vivado 工程（.xpr）：厂商板级文件与生成的 IP 产物没有随包分发。
# 脚本不再写死任何绝对路径，全部由本文件位置推导，可用环境变量覆盖：
#   TRUSTSCOPE_XPR  工程 .xpr，默认 <root>/hw/two_fft/two FFT.xpr（包内不存在）
#   TRUSTSCOPE_XSA  XSA，默认 <root>/src/build/FFT.xsa
#   TRUSTSCOPE_LOG  日志目录，默认 <root>/build_logs
#   TRUSTSCOPE_RTL  module_ref 的 .v 源目录，默认 <root>/src/rtl（包内不存在）
# 说明见同目录 README.md。
#
# 纪律
#   * 每一步等 run 真正结束再继续（launch_runs 是异步的，wait_on_run 必须调）
#   * PROGRESS 不是 100% 就判失败，**不把"没跑完"当成"跑过了"**
#   * 报告资源与违反路径数，供事后核对
#   * ASCII ONLY
#
# usage: vivado -mode batch -source src/build/cnn_build.tcl
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

set LOGDIR [RESOLVE [ENV TRUSTSCOPE_LOG [file join $ROOT build_logs]] $ROOT]
set LOG    [file join $LOGDIR cnn_build.log]
set PROJ   [RESOLVE [ENV TRUSTSCOPE_XPR [file join $ROOT hw two_fft "two FFT.xpr"]] $ROOT]
set RUNS   [RESOLVE [ENV TRUSTSCOPE_RUNS [file rootname $PROJ].runs] $ROOT]
file mkdir $LOGDIR
set _fh [open $LOG w]
proc L {m} { puts $m; global _fh; puts $_fh $m; flush $_fh }

L "root = $ROOT"
L "proj = $PROJ"
if {![file exists $PROJ]} {
    L "*** FATAL: no Vivado project at $PROJ"
    L "*** the .xpr is not distributed -- set TRUSTSCOPE_XPR or rebuild the BD"
    L "*** from src/build/bd/design_1_bd.tcl (see README.md)"
    close $_fh
    exit 1
}

L "=========== CNN build ==========="
open_project $PROJ
set bd [get_files -quiet design_1.bd]
if {$bd eq ""} { L "FATAL 找不到 design_1.bd"; exit 3 }

L "--- wrapper ---"
# TRAP (cost one build on 2026-10-15)
#   make_wrapper RETURNS a path string.  This project's path contains a SPACE
#   ("two FFT.gen"), and `foreach w $wrap` splits a Tcl string on whitespace --
#   so the iteration produced the bogus entry
#       FFT.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v
#   and add_files failed with
#       ERROR: [Vivado 12-172] File or Directory 'FFT.gen/...' does not exist
#   A Block Design's wrapper is auto-managed and regenerated during synthesis,
#   so we do NOT use the return value as a list: we ask the project for the
#   wrapper file (get_files returns a proper list, spaces safe).
set wrapf [get_files -quiet *design_1_wrapper.v]
if {[llength $wrapf] == 0} {
    make_wrapper -files $bd -top -force
    set wrapf [get_files -quiet *design_1_wrapper.v]
}
L "  wrapper = $wrapf"
foreach w $wrapf {
    if {[lsearch -exact [get_files -quiet] $w] < 0} { add_files -norecurse $w }
}
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1
L "  顶层 = [get_property top [current_fileset]]"

L "--- synthesis ---"
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set sp [get_property PROGRESS [get_runs synth_1]]
set ss [get_property STATUS   [get_runs synth_1]]
L "  synth PROGRESS=$sp STATUS=$ss"
if {$sp ne "100%"} { L "FATAL 综合未完成"; exit 3 }

L "--- implementation + bitstream ---"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set ip_ [get_property PROGRESS [get_runs impl_1]]
set is_ [get_property STATUS   [get_runs impl_1]]
L "  impl PROGRESS=$ip_ STATUS=$is_"
if {$ip_ ne "100%"} { L "FATAL 实现未完成"; exit 3 }

L "--- reports ---"
open_run impl_1
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
L "  WNS = $wns ns"
L "  WHS = $whs ns"
set viol [get_msg_config -count -severity {CRITICAL WARNING}]
L "  CRITICAL WARNING 计数 = $viol"

set rpt [file join $LOGDIR cnn_util.rpt]
file mkdir [file dirname $rpt]
report_utilization -file $rpt
L "  资源报告 -> $rpt"

set bit [file join $RUNS impl_1 design_1_wrapper.bit]
if {[file exists $bit]} {
    L "  比特流: $bit  ([file size $bit] bytes)"
} else {
    L "  *** 没找到比特流文件"
}
L "=== DONE ==="
close $_fh
exit 0
