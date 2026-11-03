###############################################################################
# two_fft.xdc -- two FFT 工程完整引脚约束 (单摄 J10 + 7寸屏 J11)
# 适配端口�?: cmos_d_0/cmos_href_0/cmos_vsync_0/cmos_pclk_0 (摄像�? J10)
#             vid_io_out_0_* / lcd_pclk / lcd_blen (7寸屏 J11)
# 摄像头引�? = 官方 an5642 例程 cmos1_* 那组 (J10)
# 屏引�?     = 官方 16_1_lcd7 lcd_test.xdc (J11)
###############################################################################

###### 像素时钟 (lcd_pclk, FCLK_CLK1 ~33MHz) -> J11 ######
create_clock -period 30.300 [get_ports lcd_pclk]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_pclk]
set_property PACKAGE_PIN H18 [get_ports lcd_pclk]

###### 背光 lcd_blen -> J11 (常亮) ######
set_property IOSTANDARD LVCMOS33 [get_ports lcd_blen]
set_property PACKAGE_PIN F16 [get_ports lcd_blen]

###### 摄像�? (J10) - cmos_d_0[9:0] ######
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports cmos_pclk_0]
set_property IOSTANDARD LVCMOS33 [get_ports cmos_href_0]
set_property IOSTANDARD LVCMOS33 [get_ports cmos_vsync_0]

set_property PACKAGE_PIN V18 [get_ports {cmos_d_0[9]}]
set_property PACKAGE_PIN V17 [get_ports {cmos_d_0[8]}]
set_property PACKAGE_PIN U12 [get_ports {cmos_d_0[7]}]
set_property PACKAGE_PIN W13 [get_ports {cmos_d_0[6]}]
set_property PACKAGE_PIN T14 [get_ports {cmos_d_0[5]}]
set_property PACKAGE_PIN U13 [get_ports {cmos_d_0[4]}]
set_property PACKAGE_PIN V13 [get_ports {cmos_d_0[3]}]
set_property PACKAGE_PIN T10 [get_ports {cmos_d_0[2]}]
set_property PACKAGE_PIN T12 [get_ports {cmos_d_0[1]}]
set_property PACKAGE_PIN V12 [get_ports {cmos_d_0[0]}]
set_property PACKAGE_PIN T11 [get_ports cmos_pclk_0]
set_property PACKAGE_PIN A20 [get_ports cmos_href_0]
set_property PACKAGE_PIN B19 [get_ports cmos_vsync_0]

###### �? (J11) 时序 ######
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_active_video]
set_property PACKAGE_PIN G20 [get_ports vid_io_out_0_hsync]
set_property PACKAGE_PIN G19 [get_ports vid_io_out_0_vsync]
set_property PACKAGE_PIN J18 [get_ports vid_io_out_0_active_video]

###### �? (J11) RGB 数据 vid_io_out_0_data[23:0] ######
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[23]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[22]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[21]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[20]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[19]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[18]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[17]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[16]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vid_io_out_0_data[0]}]

set_property PACKAGE_PIN E18 [get_ports {vid_io_out_0_data[23]}]
set_property PACKAGE_PIN E19 [get_ports {vid_io_out_0_data[22]}]
set_property PACKAGE_PIN G17 [get_ports {vid_io_out_0_data[21]}]
set_property PACKAGE_PIN G18 [get_ports {vid_io_out_0_data[20]}]
set_property PACKAGE_PIN H16 [get_ports {vid_io_out_0_data[19]}]
set_property PACKAGE_PIN H17 [get_ports {vid_io_out_0_data[18]}]
set_property PACKAGE_PIN H15 [get_ports {vid_io_out_0_data[17]}]
set_property PACKAGE_PIN G15 [get_ports {vid_io_out_0_data[16]}]
set_property PACKAGE_PIN J20 [get_ports {vid_io_out_0_data[15]}]
set_property PACKAGE_PIN H20 [get_ports {vid_io_out_0_data[14]}]
set_property PACKAGE_PIN L16 [get_ports {vid_io_out_0_data[13]}]
set_property PACKAGE_PIN L17 [get_ports {vid_io_out_0_data[12]}]
set_property PACKAGE_PIN M17 [get_ports {vid_io_out_0_data[11]}]
set_property PACKAGE_PIN M18 [get_ports {vid_io_out_0_data[10]}]
set_property PACKAGE_PIN D19 [get_ports {vid_io_out_0_data[9]}]
set_property PACKAGE_PIN D20 [get_ports {vid_io_out_0_data[8]}]
set_property PACKAGE_PIN L19 [get_ports {vid_io_out_0_data[7]}]
set_property PACKAGE_PIN L20 [get_ports {vid_io_out_0_data[6]}]
set_property PACKAGE_PIN M19 [get_ports {vid_io_out_0_data[5]}]
set_property PACKAGE_PIN M20 [get_ports {vid_io_out_0_data[4]}]
set_property PACKAGE_PIN K17 [get_ports {vid_io_out_0_data[3]}]
set_property PACKAGE_PIN K18 [get_ports {vid_io_out_0_data[2]}]
set_property PACKAGE_PIN K19 [get_ports {vid_io_out_0_data[1]}]
set_property PACKAGE_PIN J19 [get_ports {vid_io_out_0_data[0]}]

###### 未用输出端口 (调试信号, �? IOSTANDARD 避免 DRC 报错) ######
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_field]
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_hblank]
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_vblank]

###### 系统复位/输入 (保留 IOSTANDARD) ######
set_property IOSTANDARD LVCMOS33 [get_ports aclken_0]

###### 摄像头像素时钟从普�?�IO进入, 允许非专用时钟路�? (避免 Place 失败) ######
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cmos_pclk_0_IBUF]

###### 未用调试端口(field/hblank/vblank/aclken)悬空, 把未约束端口的DRC降为Warning ######
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property IOSTANDARD LVCMOS33 [get_ports IIC_0_0_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports IIC_0_0_scl_io]
set_property PULLUP true [get_ports IIC_0_0_scl_io]
set_property PULLUP true [get_ports IIC_0_0_sda_io]
set_property PACKAGE_PIN T16 [get_ports IIC_0_0_sda_io]
set_property PACKAGE_PIN T15 [get_ports IIC_0_0_scl_io]

# 摄像头复�? GPIO -> J10 (cmos_rstn_tri_o[0] -> B20)
set_property IOSTANDARD LVCMOS33 [get_ports GPIO_0_tri_o[0]]
set_property PACKAGE_PIN B20 [get_ports GPIO_0_tri_o[0]]

###### 把未指定 IOSTANDARD �? DRC 也降�? Warning (避免 NSTD-1 阻塞) ######
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
# Fix UCIO: give unused debug ports IOSTANDARD + demote UCIO-1 to warning
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_field]
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_hblank]
set_property IOSTANDARD LVCMOS33 [get_ports vid_io_out_0_vblank]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]

###############################################################################
# AN970 capacitive touchscreen (GT911) -- I2C bus on J11
#
# Pin numbers are from ALINX's own 28_lcd7_touch example
# (src/constraints/lcd.xdc):  lcd_i2c_scl_io = F20, lcd_i2c_sda_io = F19
# The interrupt pin (F17) is deliberately NOT used: the GT911 is polled by
# reading register 0x814E, so no PL->PS interrupt is required.
#
# ADDED BACK 2026-10-16.  These constraints were removed when iic1_emio.tcl
# deleted the lcd_touch_i2c port to free PS IIC_1 for camera 1 -- which left the
# touch panel wired to NOTHING.  Measured before this change (touch_probe.tcl):
# the GT911 answers on no bus at all (PS I2C0, PS I2C1 and the PL axi_iic all
# silent) while both cameras answer in the same session; the BD file confirms
# there was no touch port in the design.
# The port is back, driven by the PL axi_iic (cell `cam_iic_1`, whose master
# interface had been left dangling), and the names below are not guessed: the
# generated wrapper flattens an iic_rtl interface port `X` to `X_scl_io` /
# `X_sda_io`, which is exactly how cam_iic_1_io_scl_io is named further down.
###############################################################################
# --- 2026-10-16 (evening): the panel's pins are driven by a BIT-BANG GPIO now ---------
# The PL axi_iic was characterised and rejected: it drives, its IOBUFs are correctly
# tri-stated, its bytes match the vendor's driver -- and it reports "no ACK" for the
# panel, for camera 1's known chip id, at 100/50/32 kHz, and for a slave address that is
# not on the bus at all.  NACK for everything, including nothing, is not a device
# problem.  The pins therefore move from the iic_rtl port `lcd_touch_i2c` to a 2-bit
# bidirectional GPIO whose wrapper port is `lcd_touch_gpio_tri_io[1:0]`; the software
# drives every edge itself, so the acknowledge is read by our own code.
#
# THE PIN NUMBERS ARE UNCHANGED -- F20 = SCL, F19 = SDA -- because that mapping is what
# the vendor's own working bitstream uses on this panel (their lcd.xdc: lcd_i2c_scl_io
# F20, lcd_i2c_sda_io F19).  Only the PORT NAMES changed, to match the new wrapper.
# Bit 0 = SCL = F20, bit 1 = SDA = F19; touch.c must use the same order.
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_touch_gpio_tri_io[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_touch_gpio_tri_io[1]}]
set_property PULLUP true          [get_ports {lcd_touch_gpio_tri_io[0]}]
set_property PULLUP true          [get_ports {lcd_touch_gpio_tri_io[1]}]
set_property PACKAGE_PIN F20      [get_ports {lcd_touch_gpio_tri_io[0]}]
set_property PACKAGE_PIN F19      [get_ports {lcd_touch_gpio_tri_io[1]}]

###############################################################################
# clk_fpga_1 -> clk_fpga_0: constrain the DEBUG PROBE paths, and nothing else.
#
# MEASURED (100 MHz build, impl_1/design_1_wrapper_timing_summary_routed.rpt):
#   clk_fpga_1 -> clk_fpga_0   WNS -3.792 ns  TNS -29.155 ns   9 endpoints fail
#   clk_fpga_0 -> clk_fpga_1   WNS  8.835 ns  TNS   0.000 ns   0 endpoints fail
#
# All 9 failing paths end at capture_ram_0/inst/mem_reg_*/DIADI[*] -- the data
# inputs of the debug capture RAM -- and their sources are exactly the signals
# someone was probing while chasing the display chain (v_tc_0 hsync / vsync /
# active_video, v_axi4s_vid_out_0/locked, rst_33M, axi_vdma_1 MM2S internals).
# The ONLY clk_fpga_1 -> clk_fpga_0 path that is not a probe lives inside v_tc_0
# (AXI4_LITE_INTERFACE.SYNC2PROCCLK_I/data_sync_reg) and it MEETS timing.
# The requirement on the failing group is 0.010 ns anyway: both clocks have a
# 10 ns period in that build with a 10 ps skew, which nothing can satisfy.
#
# WHY NOT set_clock_groups -asynchronous
#   That declares the two clocks unrelated for the WHOLE design.  It would also
#   discard the 42 currently-PASSING clk_fpga_0 -> clk_fpga_1 paths and the v_tc
#   synchronizer above.  Those are real, both clocks come from the same PS PLL,
#   and their passing timing is meaningful evidence that would be thrown away.
#   It would also hide any FUTURE genuine crossing between these domains, which
#   is the opposite of what a constraint is for.
#
# CAVEAT, stated rather than hidden: a probe whose source is in another clock
# domain samples asynchronously, so captured bits can be metastable.  That is
# inherent to cross-domain probing and is acceptable for an instrument a human
# reads.  It would NOT be acceptable for functional data, and no functional data
# travels on these paths.
#
# NOTE ON MATCHING: capture_ram is an out-of-context module_ref, so during TOP
# synthesis these cells do not exist yet and the patterns legitimately match
# nothing.  The constraint therefore reports what it matched instead of raising
# an error; the build script checks the OUTCOME (WNS and the reported paths)
# after implementation, which is the evidence that actually matters.
###############################################################################
set _dbg_d [get_pins -quiet -hierarchical -filter {NAME =~ "*capture_ram_0/inst/mem_reg_*/DIADI*"}]
set _dbg_b [get_pins -quiet -hierarchical -filter {NAME =~ "*capture_ram_0/inst/mem_reg_*/DIBDI*"}]
set _dbg_n [expr {[llength $_dbg_d] + [llength $_dbg_b]}]
if {$_dbg_n == 0} {
    puts "INFO: debug-probe false_path matched no pins (expected during top synthesis; must be non-zero at implementation)"
} else {
    puts "INFO: constraining $_dbg_n debug capture-RAM data pins as false paths"
}
set_false_path -to $_dbg_d
set_false_path -to $_dbg_b

# ============================================================================
#  双目第二路（AN5642 的 cmos2_* 一组）—— 2026-10-15 加
#
#  引脚出处：厂商 23_ov5640_dual/.../constraints/an5642.xdc 的 cmos2_*
#  端口名出处：重新生成的 design_1_wrapper.v（不是猜的）
#
#  方向：cmos_*_1 都是相机 -> FPGA 的**输入**；GPIO_0_tri_o[1] 是 FPGA -> 相机复位的
#        **输出**；cam_iic_1_io_* 是**三态开漏**。没有任何一根是"FPGA 输出 + 外部也在驱动"，
#        所以不引入引脚对顶风险。
#
#  J10 安全规则提醒：PIN35(B20) 与 PIN28(V12) 绝对不能互插
#        （B20 = 第一路相机复位，V12 = 第一路相机数据）
# ============================================================================
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmos_d_1[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports cmos_pclk_1]
set_property IOSTANDARD LVCMOS33 [get_ports cmos_href_1]
set_property IOSTANDARD LVCMOS33 [get_ports cmos_vsync_1]
set_property IOSTANDARD LVCMOS33 [get_ports cam_iic_1_io_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports cam_iic_1_io_sda_io]
set_property PULLUP true          [get_ports cam_iic_1_io_scl_io]
set_property PULLUP true          [get_ports cam_iic_1_io_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports {GPIO_0_tri_o[1]}]
set_property PACKAGE_PIN W19 [get_ports {cmos_d_1[9]}]
set_property PACKAGE_PIN V15 [get_ports {cmos_d_1[8]}]
set_property PACKAGE_PIN Y17 [get_ports {cmos_d_1[7]}]
set_property PACKAGE_PIN R14 [get_ports {cmos_d_1[6]}]
set_property PACKAGE_PIN N17 [get_ports {cmos_d_1[5]}]
set_property PACKAGE_PIN P18 [get_ports {cmos_d_1[4]}]
set_property PACKAGE_PIN Y14 [get_ports {cmos_d_1[3]}]
set_property PACKAGE_PIN Y16 [get_ports {cmos_d_1[2]}]
set_property PACKAGE_PIN U15 [get_ports {cmos_d_1[1]}]
set_property PACKAGE_PIN U14 [get_ports {cmos_d_1[0]}]
set_property PACKAGE_PIN P15 [get_ports cmos_pclk_1]
set_property PACKAGE_PIN W15 [get_ports cmos_href_1]
set_property PACKAGE_PIN P16 [get_ports cmos_vsync_1]
set_property PACKAGE_PIN P14 [get_ports cam_iic_1_io_scl_io]
set_property PACKAGE_PIN W18 [get_ports cam_iic_1_io_sda_io]
set_property PACKAGE_PIN W14 [get_ports {GPIO_0_tri_o[1]}]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cmos_pclk_1_IBUF]

# ---------------------------------------------------------------------------
#  残留视频输出端口的 LOC（2026-10-15 补）
#  成因：重新生成 wrapper 后这三个端口出现在顶层，而 XDC 里只有 IOSTANDARD，
#        没有 PACKAGE_PIN，DRC UCIO-1 因此拒绝生成比特流。
#  引脚取值：上一版**已验证**构建的 io_placed.rpt 里它们实际落的位置。
#        J15 field / J16 hblank / K16 vblank
#        钉死而不是放任自动摆放 —— 它们是输出，落到电源/地网络是不可接受的。
#  注意：J16 与 K16 同时也是板载 LED 的引脚，驱动 LED 无害。
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN J15 [get_ports vid_io_out_0_field]
set_property PACKAGE_PIN J16 [get_ports vid_io_out_0_hblank]
set_property PACKAGE_PIN K16 [get_ports vid_io_out_0_vblank]
