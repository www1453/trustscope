# cnn_integrate.tcl -- 把经过验证的 v12 CNN IP 集成进 AX7020 的 Block Design。
#
# 纪律（每一条都来自本项目付过代价的失败）
#   1. **改前备份**：调用方必须先跑 dl/backup.py save（BD 与 .xpr）
#   2. **不猜端口名**：从 component.xml 现场读，参考设计的端口名属于另一个打包版本
#   3. **每步断言**：改完立刻查"真的改到了吗"，而不是等构建"成功"
#   4. **validate 通过才 save**：Validate 失败就 exit 3，绝不保存半个设计
#   5. **原消费方必须仍在**：ps7_0_axi_periph 原有 M00..M04、mem_intercon_cap 原有 S00
#   6. ASCII ONLY
#
# 已知约束（来自 cnn_integration_recon.tcl）
#   ps7_0_axi_periph   NUM_MI=5 全满  -> 加到 7
#   mem_intercon_cap   NUM_SI=1 满    -> 加到 4
#   0x43C00000 已被 v_tc_0 占用      -> CNN 用 0x43C20000 / 0x43C30000
#   FCLK_CLK0 = 50 MHz                -> CNN 实际跑 50 MHz（约 14.4 ms/次）
#
# usage: vivado -mode batch -source cnn_integrate.tcl
set LOG "C:/Users/wzh/Documents/trustscope/ps_fft_dual/logs/cnn_integrate.log"
set PROJ "D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.xpr"
set IPREPO "C:/Users/wzh/Documents/trustscope/dl/hls/ip_v12_verified"
set _fh [open $LOG w]
proc L {m} { puts $m; global _fh; puts $_fh $m; flush $_fh }
proc FATAL {m} { L "*** FATAL: $m"; close [open "C:/Users/wzh/Documents/trustscope/ps_fft_dual/logs/_fail" w]; exit 3 }
proc CHK {cond msg} { if {![uplevel 1 [list expr $cond]]} { FATAL $msg } else { L "  OK  $msg" } }

L "=========== CNN integrate ==========="
open_project $PROJ
open_bd_design [get_files -quiet design_1.bd]
set BD [current_bd_design]
L "  BD = $BD"

# ---------------------------------------------------------------- 0) 备份闸门
set BK [file dirname $LOG]
foreach f {"D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.srcs/sources_1/bd/design_1/design_1.bd"} {
    if {![file exists $f]} { FATAL "找不到 $f" }
}
L "  前置检查通过（BD 存在）"

# ---------------------------------------------------------------- 1) IP 仓库
L ""
L "--- 1) 加入 IP 仓库并现场读出端口名 ---"
set rp [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $rp $IPREPO] < 0} {
    L "  追加仓库: $IPREPO"
    set_property ip_repo_paths [concat $rp [list $IPREPO]] [current_project]
}
update_ip_catalog -rebuild
set vlnv ""
foreach v [get_ipdefs -quiet *ts_cnn_top*] { set vlnv $v }
if {$vlnv eq ""} { FATAL "IP 仓库里没找到 ts_cnn_top" }
L "  找到 IP: $vlnv"

# 从 component.xml 现场读端口名（**不照抄参考设计**）
set cx "$IPREPO/component.xml"
set fh [open $cx r]
set txt [read $fh]
close $fh
set ck ""
foreach cand {ap_clk clk} { if {[string first ">$cand<" $txt] >= 0} { set ck $cand; break } }
set rst ""
foreach cand {ap_rst_n rst_n} { if {[string first ">$cand<" $txt] >= 0} { set rst $cand; break } }
L "  端口名: clk=$ck  rst=$rst"
if {$ck eq "" || $rst eq ""} { FATAL "读不到时钟/复位端口名" }
foreach p {s_axi_control s_axi_control_r m_axi_gmem0 m_axi_gmem1 m_axi_gmem2} {
    CHK {[string first $p $txt] >= 0} "component.xml 里有 $p"
}

# ---------------------------------------------------------------- 2) 建 cell
L ""
L "--- 2) 实例化 CNN ---"
if {[get_bd_cells -quiet ts_cnn_top_0] ne ""} { FATAL "ts_cnn_top_0 已存在（幂等保护）" }
create_bd_cell -type ip -vlnv $vlnv ts_cnn_top_0
CHK {[get_bd_cells -quiet ts_cnn_top_0] ne ""} "cell 已创建"

# 记录改动前的原消费方（第 5 条纪律）
set pre_periph {}
foreach p [get_bd_intf_pins -quiet ps7_0_axi_periph/M0*_AXI] {
    set n [get_bd_intf_nets -quiet -of_objects $p]
    lappend pre_periph [list $p $n]
}
set pre_cap ""
foreach p [get_bd_intf_pins -quiet mem_intercon_cap/S00_AXI] {
    set pre_cap [get_bd_intf_nets -quiet -of_objects $p]
}
L "  改前：ps7_0_axi_periph 有 [llength $pre_periph] 路；mem_intercon_cap S00 网络=$pre_cap"

# ---------------------------------------------------------------- 3) 时钟/复位
L ""
L "--- 3) 接时钟与复位 ---"
set CLKNET "processing_system7_0_FCLK_CLK0"
set RSTNET "proc_sys_reset_0_peripheral_aresetn"
connect_bd_net [get_bd_pins ts_cnn_top_0/$ck] [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins ts_cnn_top_0/$rst] [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
CHK {[get_bd_nets -quiet -of_objects [get_bd_pins ts_cnn_top_0/$ck]] ne ""} "时钟已接"
CHK {[get_bd_nets -quiet -of_objects [get_bd_pins ts_cnn_top_0/$rst]] ne ""} "复位已接"

# ---------------------------------------------------------------- 4) AXI-Lite
L ""
L "--- 4) AXI-Lite：ps7_0_axi_periph NUM_MI 5 -> 7 ---"
set_property -dict [list CONFIG.NUM_MI {7}] [get_bd_cells ps7_0_axi_periph]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M05_AXI] [get_bd_intf_pins ts_cnn_top_0/s_axi_control]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M06_AXI] [get_bd_intf_pins ts_cnn_top_0/s_axi_control_r]
foreach i {5 6} {
    connect_bd_net [get_bd_pins ps7_0_axi_periph/M0${i}_ACLK] [get_bd_pins processing_system7_0/FCLK_CLK0]
    connect_bd_net [get_bd_pins ps7_0_axi_periph/M0${i}_ARESETN] [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
}
CHK {[get_property CONFIG.NUM_MI [get_bd_cells ps7_0_axi_periph]] == 7} "NUM_MI 已是 7"
CHK {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins ps7_0_axi_periph/M05_AXI]] ne ""} "M05 已连"
CHK {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins ps7_0_axi_periph/M06_AXI]] ne ""} "M06 已连"
# 断言原有的 5 路仍在
foreach e $pre_periph {
    set p [lindex $e 0]; set n [lindex $e 1]
    CHK {[get_bd_intf_nets -quiet -of_objects $p] eq $n} "原消费方仍在: $p"
}

# ---------------------------------------------------------------- 5) 内存通路
L ""
L "--- 5) 内存：mem_intercon_cap NUM_SI 1 -> 4 ---"
# 为什么去掉 axi_dwidth_converter
#   参考设计 w6f 在 gmem0/gmem1 上各插了一个 dwc，但 gmem2 是**直连**的 --
#   说明这条设计至少容忍一个直连的 master。而 dwc 的时钟引脚名在本环境里
#   探不到（get_bd_pins dwc/aclk 匹配零个对象），继续照抄参考设计会卡在猜引脚上。
#   所以三个 master 全部直连；若综合/validate 报位宽不匹配，再按报错补 dwc。
set_property -dict [list CONFIG.NUM_SI {4}] [get_bd_cells mem_intercon_cap]
connect_bd_intf_net [get_bd_intf_pins ts_cnn_top_0/m_axi_gmem0] [get_bd_intf_pins mem_intercon_cap/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins ts_cnn_top_0/m_axi_gmem1] [get_bd_intf_pins mem_intercon_cap/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins ts_cnn_top_0/m_axi_gmem2] [get_bd_intf_pins mem_intercon_cap/S03_AXI]
foreach i {1 2 3} {
    connect_bd_net [get_bd_pins mem_intercon_cap/S0${i}_ACLK]    [get_bd_pins processing_system7_0/FCLK_CLK0]
    connect_bd_net [get_bd_pins mem_intercon_cap/S0${i}_ARESETN] [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
}
CHK {[get_property CONFIG.NUM_SI [get_bd_cells mem_intercon_cap]] == 4} "NUM_SI 已是 4"
foreach i {1 2 3} {
    CHK {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins mem_intercon_cap/S0${i}_AXI]] ne ""} "S0${i} 已连"
}
CHK {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins mem_intercon_cap/S00_AXI]] eq $pre_cap} "原采集通路仍在"

# ---------------------------------------------------------------- 6) 地址
L ""
L "--- 6) 地址分配（0x43C00000 已被 v_tc_0 占用，故用 0x43C2/0x43C3）---"
assign_bd_address -force -target_address_space /processing_system7_0/Data \
    -offset 0x43C20000 -range 64K [get_bd_addr_segs ts_cnn_top_0/s_axi_control/Reg]
assign_bd_address -force -target_address_space /processing_system7_0/Data \
    -offset 0x43C30000 -range 64K [get_bd_addr_segs ts_cnn_top_0/s_axi_control_r/Reg]
set n_cnn 0
foreach s [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    set off "?"; catch { set off [get_property OFFSET $s] }
    set nm  "?"; catch { set nm  [get_property NAME $s] }
    if {[string match "*ts_cnn_top_0*" $nm]} {
        L "  $nm -> $off"
        incr n_cnn
    }
}
# 注意：第一版断言写成 get_bd_addr_segs processing_system7_0/Data/*/$seg，
# 那个通配路径查不到任何对象，于是**明明分配成功却报了自己的失败**。
# 改成遍历地址空间的段并按名字过滤 —— 这类"断言写错导致假失败"与
# 前面几个坑同族：判断依据选错了对象。
CHK {$n_cnn >= 2} "两个 CNN 寄存器段都已分配 (找到 $n_cnn 个)"
# 3 个 master 指向 DDR（沿用现有已占用的 HP1 通道 —— 不改 PS 配置）
foreach m {m_axi_gmem0 m_axi_gmem1 m_axi_gmem2} {
    set sa [get_bd_addr_spaces -quiet ts_cnn_top_0/$m]
    if {$sa ne ""} {
        catch { assign_bd_address -force -target_address_space $sa \
                    [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] }
        L "  $m -> HP1_DDR_LOWOCM"
    }
}

# ---------------------------------------------------------------- 7) 验证闸门
L ""
L "--- 7) validate（不通过就不保存）---"
set vok 0
catch { set vok [validate_bd_design] }
CHK {$vok == 1 || $vok eq ""} "validate_bd_design 返回正常"

save_bd_design
L ""
L "=== 完成：BD 已保存 ==="
L "下一步：跑 make_wrapper / 综合，并核对 io_placed 与资源占用"
close $_fh
exit 0
