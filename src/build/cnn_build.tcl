# cnn_build.tcl -- 集成后的构建：wrapper -> 综合 -> 实现 -> 比特流。
#
# 纪律
#   * 每一步等 run 真正结束再继续（launch_runs 是异步的，wait_on_run 必须调）
#   * PROGRESS 不是 100% 就判失败，**不把"没跑完"当成"跑过了"**
#   * 报告资源与违反路径数，供事后核对
#   * ASCII ONLY
#
# usage: vivado -mode batch -source cnn_build.tcl
set LOG "C:/Users/wzh/Documents/trustscope/ps_fft_dual/logs/cnn_build.log"
set PROJ "D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.xpr"
set _fh [open $LOG w]
proc L {m} { puts $m; global _fh; puts $_fh $m; flush $_fh }

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

set rpt "C:/Users/wzh/Documents/trustscope/ps_fft_dual/logs/cnn_util.rpt"
report_utilization -file $rpt
L "  资源报告 -> $rpt"

set bit "D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.runs/impl_1/design_1_wrapper.bit"
if {[file exists $bit]} {
    L "  比特流: $bit  ([file size $bit] bytes)"
} else {
    L "  *** 没找到比特流文件"
}
L "=== DONE ==="
close $_fh
exit 0
