
################################################################
# design_1_bd.tcl -- the TrustScope Block Design (design_1) as TEXT.
#
# PROVENANCE: produced by `write_bd_tcl` from the real project on 2026-10-19
#   project: two FFT.xpr (ALINX AX7020 dual-camera base + our additions)
#   recorded copy: submission/legacy/fpga_snapshot_20261019/board/design_1_bd.tcl
#   it contains: processing_system7_0, two alinx_ov5640 camera IPs, axi_vdma_0/1/2,
#   v_tc_0 + v_axi4s_vid_out_0, ps7_0_axi_periph, mem_intercon_cap/disp,
#   capture_ram_0 / analyzer_fe_0 / spi_gen_0 (module_ref), ts_cnn_top_0.
#   It does NOT contain the Vivado project, the module_ref .v sources or the
#   pin constraints (those are src/two_fft.xdc).  See ../README.md.
#
# HOW TO USE: in a fresh Vivado 2023.1 project create a Block Design, then
#   source this file, then run `regenerate_bd_layout; validate_bd_design;
#   save_bd_design`.  The module_ref cells need their .v files added to the
#   project first (create_bd_cell -type module -reference needs a known module).
#   Version mismatch with 2023.1 is reported and the script returns 1.
################################################################
# This is a generated script based on design: design_1
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2023.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source design_1_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# capture_ram, analyzer_fe, spi_gen

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z020clg400-2
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name design_1

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:processing_system7:5.5\
xilinx.com:ip:proc_sys_reset:5.0\
www.alinx.com.cn:user:alinx_ov5640:5.4\
xilinx.com:ip:axi_vdma:6.3\
xilinx.com:ip:axis_subset_converter:1.1\
xilinx.com:ip:v_axi4s_vid_out:4.0\
xilinx.com:ip:v_tc:6.2\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:util_vector_logic:2.0\
xilinx.com:ip:xlconcat:2.1\
xilinx.com:ip:c_counter_binary:12.0\
xilinx.com:ip:xlslice:1.0\
xilinx.com:hls:ts_cnn_top:1.0\
xilinx.com:ip:axi_dwidth_converter:2.1\
xilinx.com:ip:axis_switch:1.1\
xilinx.com:ip:axi_iic:2.1\
xilinx.com:ip:axis_register_slice:1.1\
xilinx.com:ip:ila:6.2\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
capture_ram\
analyzer_fe\
spi_gen\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]

  set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]

  set vid_io_out_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:vid_io_rtl:1.0 vid_io_out_0 ]

  set IIC_0_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 IIC_0_0 ]

  set GPIO_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 GPIO_0 ]

  set cam_iic_1_io [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 cam_iic_1_io ]

  set lcd_touch_gpio [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 lcd_touch_gpio ]


  # Create ports
  set cmos_d_0 [ create_bd_port -dir I -from 9 -to 0 cmos_d_0 ]
  set cmos_href_0 [ create_bd_port -dir I cmos_href_0 ]
  set cmos_pclk_0 [ create_bd_port -dir I cmos_pclk_0 ]
  set cmos_vsync_0 [ create_bd_port -dir I cmos_vsync_0 ]
  set lcd_pclk [ create_bd_port -dir O -from 0 -to 0 lcd_pclk ]
  set lcd_blen [ create_bd_port -dir O -from 0 -to 0 lcd_blen ]
  set cmos_d_1 [ create_bd_port -dir I -from 9 -to 0 cmos_d_1 ]
  set cmos_href_1 [ create_bd_port -dir I cmos_href_1 ]
  set cmos_pclk_1 [ create_bd_port -dir I cmos_pclk_1 ]
  set cmos_vsync_1 [ create_bd_port -dir I cmos_vsync_1 ]

  # Create instance: processing_system7_0, and set properties
  set processing_system7_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]
  set_property -dict [list \
    CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {666.666687} \
    CONFIG.PCW_ACT_CAN0_PERIPHERAL_FREQMHZ {23.8095} \
    CONFIG.PCW_ACT_CAN1_PERIPHERAL_FREQMHZ {23.8095} \
    CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.158730} \
    CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {32.727272} \
    CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_I2C_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_USB0_PERIPHERAL_FREQMHZ {60} \
    CONFIG.PCW_ACT_USB1_PERIPHERAL_FREQMHZ {60} \
    CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_APU_CLK_RATIO_ENABLE {6:2:1} \
    CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {666.666666} \
    CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC {External} \
    CONFIG.PCW_CAN0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_CAN1_PERIPHERAL_CLKSRC {External} \
    CONFIG.PCW_CAN1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_CAN_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_CAN_PERIPHERAL_VALID {0} \
    CONFIG.PCW_CLK0_FREQ {50000000} \
    CONFIG.PCW_CLK1_FREQ {32727272} \
    CONFIG.PCW_CLK2_FREQ {10000000} \
    CONFIG.PCW_CLK3_FREQ {10000000} \
    CONFIG.PCW_CPU_CPU_6X4X_MAX_RANGE {767} \
    CONFIG.PCW_CPU_PERIPHERAL_CLKSRC {ARM PLL} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_DCI_PERIPHERAL_CLKSRC {DDR PLL} \
    CONFIG.PCW_DCI_PERIPHERAL_FREQMHZ {10.159} \
    CONFIG.PCW_DDR_PERIPHERAL_CLKSRC {DDR PLL} \
    CONFIG.PCW_DDR_RAM_BASEADDR {0x00100000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF} \
    CONFIG.PCW_DM_WIDTH {4} \
    CONFIG.PCW_DQS_WIDTH {4} \
    CONFIG.PCW_DQ_WIDTH {32} \
    CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_ENET1_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_ENET1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_ENET_RESET_POLARITY {Active Low} \
    CONFIG.PCW_EN_4K_TIMER {0} \
    CONFIG.PCW_EN_CAN0 {0} \
    CONFIG.PCW_EN_CAN1 {0} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_EN_CLK2_PORT {0} \
    CONFIG.PCW_EN_CLK3_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG0_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG1_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG2_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG3_PORT {0} \
    CONFIG.PCW_EN_DDR {1} \
    CONFIG.PCW_EN_EMIO_CAN0 {0} \
    CONFIG.PCW_EN_EMIO_CAN1 {0} \
    CONFIG.PCW_EN_EMIO_CD_SDIO0 {0} \
    CONFIG.PCW_EN_EMIO_CD_SDIO1 {0} \
    CONFIG.PCW_EN_EMIO_ENET0 {0} \
    CONFIG.PCW_EN_EMIO_ENET1 {0} \
    CONFIG.PCW_EN_EMIO_GPIO {0} \
    CONFIG.PCW_EN_EMIO_I2C0 {1} \
    CONFIG.PCW_EN_EMIO_I2C1 {1} \
    CONFIG.PCW_EN_EMIO_MODEM_UART0 {0} \
    CONFIG.PCW_EN_EMIO_MODEM_UART1 {0} \
    CONFIG.PCW_EN_EMIO_PJTAG {0} \
    CONFIG.PCW_EN_EMIO_SDIO0 {0} \
    CONFIG.PCW_EN_EMIO_SDIO1 {0} \
    CONFIG.PCW_EN_EMIO_SPI0 {0} \
    CONFIG.PCW_EN_EMIO_SPI1 {0} \
    CONFIG.PCW_EN_EMIO_SRAM_INT {0} \
    CONFIG.PCW_EN_EMIO_TRACE {0} \
    CONFIG.PCW_EN_EMIO_TTC0 {0} \
    CONFIG.PCW_EN_EMIO_TTC1 {0} \
    CONFIG.PCW_EN_EMIO_UART0 {0} \
    CONFIG.PCW_EN_EMIO_UART1 {0} \
    CONFIG.PCW_EN_EMIO_WDT {0} \
    CONFIG.PCW_EN_EMIO_WP_SDIO0 {0} \
    CONFIG.PCW_EN_EMIO_WP_SDIO1 {0} \
    CONFIG.PCW_EN_ENET0 {0} \
    CONFIG.PCW_EN_ENET1 {0} \
    CONFIG.PCW_EN_GPIO {0} \
    CONFIG.PCW_EN_I2C0 {1} \
    CONFIG.PCW_EN_I2C1 {1} \
    CONFIG.PCW_EN_MODEM_UART0 {0} \
    CONFIG.PCW_EN_MODEM_UART1 {0} \
    CONFIG.PCW_EN_PJTAG {0} \
    CONFIG.PCW_EN_PTP_ENET0 {0} \
    CONFIG.PCW_EN_PTP_ENET1 {0} \
    CONFIG.PCW_EN_QSPI {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_EN_RST1_PORT {0} \
    CONFIG.PCW_EN_RST2_PORT {0} \
    CONFIG.PCW_EN_RST3_PORT {0} \
    CONFIG.PCW_EN_SDIO0 {0} \
    CONFIG.PCW_EN_SDIO1 {0} \
    CONFIG.PCW_EN_SMC {0} \
    CONFIG.PCW_EN_SPI0 {0} \
    CONFIG.PCW_EN_SPI1 {0} \
    CONFIG.PCW_EN_TRACE {0} \
    CONFIG.PCW_EN_TTC0 {0} \
    CONFIG.PCW_EN_TTC1 {0} \
    CONFIG.PCW_EN_UART0 {0} \
    CONFIG.PCW_EN_UART1 {1} \
    CONFIG.PCW_EN_USB0 {0} \
    CONFIG.PCW_EN_USB1 {0} \
    CONFIG.PCW_EN_WDT {0} \
    CONFIG.PCW_FCLK0_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK1_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK2_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK3_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK_CLK0_BUF {TRUE} \
    CONFIG.PCW_FCLK_CLK1_BUF {FALSE} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {33} \
    CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA3_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_FPGA_FCLK1_ENABLE {1} \
    CONFIG.PCW_GP0_EN_MODIFIABLE_TXN {1} \
    CONFIG.PCW_GP0_NUM_READ_THREADS {4} \
    CONFIG.PCW_GP0_NUM_WRITE_THREADS {4} \
    CONFIG.PCW_GP1_EN_MODIFIABLE_TXN {1} \
    CONFIG.PCW_GP1_NUM_READ_THREADS {4} \
    CONFIG.PCW_GP1_NUM_WRITE_THREADS {4} \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {0} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {0} \
    CONFIG.PCW_GPIO_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_I2C0_BASEADDR {0xE0004000} \
    CONFIG.PCW_I2C0_HIGHADDR {0xE0004FFF} \
    CONFIG.PCW_I2C0_I2C0_IO {EMIO} \
    CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_I2C1_BASEADDR {0xE0005000} \
    CONFIG.PCW_I2C1_HIGHADDR {0xE0005FFF} \
    CONFIG.PCW_I2C1_I2C1_IO {EMIO} \
    CONFIG.PCW_I2C1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_I2C_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_I2C_RESET_POLARITY {Active Low} \
    CONFIG.PCW_IMPORT_BOARD_PRESET {None} \
    CONFIG.PCW_INCLUDE_ACP_TRANS_CHECK {0} \
    CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_1_PULLUP {enabled} \
    CONFIG.PCW_MIO_1_SLEW {slow} \
    CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_2_SLEW {slow} \
    CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_3_SLEW {slow} \
    CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_48_PULLUP {enabled} \
    CONFIG.PCW_MIO_48_SLEW {slow} \
    CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_49_PULLUP {enabled} \
    CONFIG.PCW_MIO_49_SLEW {slow} \
    CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_4_SLEW {slow} \
    CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_5_SLEW {slow} \
    CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_6_SLEW {slow} \
    CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_8_SLEW {slow} \
    CONFIG.PCW_MIO_PRIMITIVE {54} \
    CONFIG.PCW_MIO_TREE_PERIPHERALS {unassigned#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#unassigned#Quad SPI Flash#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#UART\
1#UART 1#unassigned#unassigned#unassigned#unassigned} \
    CONFIG.PCW_MIO_TREE_SIGNALS {unassigned#qspi0_ss_b#qspi0_io[0]#qspi0_io[1]#qspi0_io[2]#qspi0_io[3]/HOLD_B#qspi0_sclk#unassigned#qspi_fbclk#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#tx#rx#unassigned#unassigned#unassigned#unassigned}\
\
    CONFIG.PCW_M_AXI_GP0_ENABLE_STATIC_REMAP {0} \
    CONFIG.PCW_M_AXI_GP0_ID_WIDTH {12} \
    CONFIG.PCW_M_AXI_GP0_SUPPORT_NARROW_BURST {0} \
    CONFIG.PCW_M_AXI_GP0_THREAD_ID_WIDTH {12} \
    CONFIG.PCW_NAND_CYCLES_T_AR {1} \
    CONFIG.PCW_NAND_CYCLES_T_CLR {1} \
    CONFIG.PCW_NAND_CYCLES_T_RC {11} \
    CONFIG.PCW_NAND_CYCLES_T_REA {1} \
    CONFIG.PCW_NAND_CYCLES_T_RR {1} \
    CONFIG.PCW_NAND_CYCLES_T_WC {11} \
    CONFIG.PCW_NAND_CYCLES_T_WP {1} \
    CONFIG.PCW_NOR_CS0_T_CEOE {1} \
    CONFIG.PCW_NOR_CS0_T_PC {1} \
    CONFIG.PCW_NOR_CS0_T_RC {11} \
    CONFIG.PCW_NOR_CS0_T_TR {1} \
    CONFIG.PCW_NOR_CS0_T_WC {11} \
    CONFIG.PCW_NOR_CS0_T_WP {1} \
    CONFIG.PCW_NOR_CS0_WE_TIME {0} \
    CONFIG.PCW_NOR_CS1_T_CEOE {1} \
    CONFIG.PCW_NOR_CS1_T_PC {1} \
    CONFIG.PCW_NOR_CS1_T_RC {11} \
    CONFIG.PCW_NOR_CS1_T_TR {1} \
    CONFIG.PCW_NOR_CS1_T_WC {11} \
    CONFIG.PCW_NOR_CS1_T_WP {1} \
    CONFIG.PCW_NOR_CS1_WE_TIME {0} \
    CONFIG.PCW_NOR_SRAM_CS0_T_CEOE {1} \
    CONFIG.PCW_NOR_SRAM_CS0_T_PC {1} \
    CONFIG.PCW_NOR_SRAM_CS0_T_RC {11} \
    CONFIG.PCW_NOR_SRAM_CS0_T_TR {1} \
    CONFIG.PCW_NOR_SRAM_CS0_T_WC {11} \
    CONFIG.PCW_NOR_SRAM_CS0_T_WP {1} \
    CONFIG.PCW_NOR_SRAM_CS0_WE_TIME {0} \
    CONFIG.PCW_NOR_SRAM_CS1_T_CEOE {1} \
    CONFIG.PCW_NOR_SRAM_CS1_T_PC {1} \
    CONFIG.PCW_NOR_SRAM_CS1_T_RC {11} \
    CONFIG.PCW_NOR_SRAM_CS1_T_TR {1} \
    CONFIG.PCW_NOR_SRAM_CS1_T_WC {11} \
    CONFIG.PCW_NOR_SRAM_CS1_T_WP {1} \
    CONFIG.PCW_NOR_SRAM_CS1_WE_TIME {0} \
    CONFIG.PCW_OVERRIDE_BASIC_CLOCK {0} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY0 {0.089} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY1 {0.075} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY2 {0.085} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY3 {0.092} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_0 {-0.025} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_1 {0.014} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_2 {-0.009} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_3 {-0.033} \
    CONFIG.PCW_PACKAGE_NAME {clg400} \
    CONFIG.PCW_PCAP_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_PCAP_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_PERIPHERAL_BOARD_PRESET {None} \
    CONFIG.PCW_PJTAG_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_PLL_BYPASSMODE_ENABLE {0} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_PS7_SI_REV {PRODUCTION} \
    CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_FBCLK_IO {MIO 8} \
    CONFIG.PCW_QSPI_GRP_IO1_ENABLE {0} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
    CONFIG.PCW_QSPI_GRP_SS1_ENABLE {0} \
    CONFIG.PCW_QSPI_INTERNAL_HIGHADDRESS {0xFCFFFFFF} \
    CONFIG.PCW_QSPI_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SD1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SDIO_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_SDIO_PERIPHERAL_VALID {0} \
    CONFIG.PCW_SINGLE_QSPI_DATA_MODE {x4} \
    CONFIG.PCW_SMC_CYCLE_T0 {NA} \
    CONFIG.PCW_SMC_CYCLE_T1 {NA} \
    CONFIG.PCW_SMC_CYCLE_T2 {NA} \
    CONFIG.PCW_SMC_CYCLE_T3 {NA} \
    CONFIG.PCW_SMC_CYCLE_T4 {NA} \
    CONFIG.PCW_SMC_CYCLE_T5 {NA} \
    CONFIG.PCW_SMC_CYCLE_T6 {NA} \
    CONFIG.PCW_SMC_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_SMC_PERIPHERAL_VALID {0} \
    CONFIG.PCW_SPI0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SPI1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SPI_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_SPI_PERIPHERAL_VALID {0} \
    CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
    CONFIG.PCW_S_AXI_HP0_ID_WIDTH {6} \
    CONFIG.PCW_S_AXI_HP1_DATA_WIDTH {64} \
    CONFIG.PCW_S_AXI_HP1_ID_WIDTH {6} \
    CONFIG.PCW_TPIU_PERIPHERAL_CLKSRC {External} \
    CONFIG.PCW_TRACE_INTERNAL_WIDTH {2} \
    CONFIG.PCW_TRACE_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_TTC0_CLK0_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC0_CLK0_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC0_CLK1_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC0_CLK1_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC0_CLK2_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC0_CLK2_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_TTC1_CLK0_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC1_CLK0_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC1_CLK1_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC1_CLK1_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC1_CLK2_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC1_CLK2_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_UART1_BASEADDR {0xE0001000} \
    CONFIG.PCW_UART1_BAUD_RATE {115200} \
    CONFIG.PCW_UART1_GRP_FULL_ENABLE {0} \
    CONFIG.PCW_UART1_HIGHADDR {0xE0001FFF} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_UART_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
    CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
    CONFIG.PCW_UIPARAM_DDR_ADV_ENABLE {0} \
    CONFIG.PCW_UIPARAM_DDR_AL {0} \
    CONFIG.PCW_UIPARAM_DDR_BL {8} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_STOP_EN {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_PACKAGE_LENGTH {105.056} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_PACKAGE_LENGTH {66.904} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_PACKAGE_LENGTH {89.1715} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_PACKAGE_LENGTH {113.63} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_PACKAGE_LENGTH {98.503} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_PACKAGE_LENGTH {68.5855} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_PACKAGE_LENGTH {90.295} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_PACKAGE_LENGTH {103.977} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
    CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {0} \
    CONFIG.PCW_UIPARAM_GENERATE_SUMMARY {NA} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_USB1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_USB_RESET_POLARITY {Active Low} \
    CONFIG.PCW_USE_AXI_FABRIC_IDLE {0} \
    CONFIG.PCW_USE_AXI_NONSECURE {0} \
    CONFIG.PCW_USE_CORESIGHT {0} \
    CONFIG.PCW_USE_CROSS_TRIGGER {0} \
    CONFIG.PCW_USE_CR_FABRIC {1} \
    CONFIG.PCW_USE_DDR_BYPASS {0} \
    CONFIG.PCW_USE_DEBUG {0} \
    CONFIG.PCW_USE_DMA0 {0} \
    CONFIG.PCW_USE_DMA1 {0} \
    CONFIG.PCW_USE_DMA2 {0} \
    CONFIG.PCW_USE_DMA3 {0} \
    CONFIG.PCW_USE_EXPANDED_IOP {0} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
    CONFIG.PCW_USE_HIGH_OCM {0} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_M_AXI_GP1 {0} \
    CONFIG.PCW_USE_PROC_EVENT_BUS {0} \
    CONFIG.PCW_USE_PS_SLCR_REGISTERS {0} \
    CONFIG.PCW_USE_S_AXI_ACP {0} \
    CONFIG.PCW_USE_S_AXI_GP0 {0} \
    CONFIG.PCW_USE_S_AXI_GP1 {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_USE_S_AXI_HP2 {0} \
    CONFIG.PCW_USE_S_AXI_HP3 {0} \
    CONFIG.PCW_USE_TRACE {0} \
    CONFIG.PCW_VALUE_SILVERSION {3} \
    CONFIG.PCW_WDT_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_WDT_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_WDT_PERIPHERAL_ENABLE {0} \
    CONFIG.preset {None} \
  ] $processing_system7_0


  # Create instance: proc_sys_reset_0, and set properties
  set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]

  # Create instance: alinx_ov5640_0, and set properties
  set alinx_ov5640_0 [ create_bd_cell -type ip -vlnv www.alinx.com.cn:user:alinx_ov5640:5.4 alinx_ov5640_0 ]

  # Create instance: axi_vdma_0, and set properties
  set axi_vdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0 ]
  set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm_dre {1} \
    CONFIG.c_num_fstores {4} \
    CONFIG.c_s2mm_genlock_mode {0} \
    CONFIG.c_s2mm_linebuffer_depth {4096} \
  ] $axi_vdma_0


  # Create instance: ps7_0_axi_periph, and set properties
  set ps7_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps7_0_axi_periph ]
  set_property CONFIG.NUM_MI {10} $ps7_0_axi_periph


  # Create instance: axis_subset_converter_0, and set properties
  set axis_subset_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 axis_subset_converter_0 ]
  set_property -dict [list \
    CONFIG.M_HAS_TLAST {1} \
    CONFIG.M_TDATA_NUM_BYTES {3} \
    CONFIG.M_TUSER_WIDTH {1} \
    CONFIG.S_HAS_TLAST {1} \
    CONFIG.S_TDATA_NUM_BYTES {2} \
    CONFIG.S_TUSER_WIDTH {1} \
    CONFIG.TDATA_REMAP {tdata[4:0],3'b000,tdata[10:5],2'b00,tdata[15:11],3'b000} \
    CONFIG.TUSER_REMAP {tuser[0:0]} \
  ] $axis_subset_converter_0


  # Create instance: axi_vdma_1, and set properties
  set axi_vdma_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_1 ]
  set_property -dict [list \
    CONFIG.c_include_mm2s_dre {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_m_axis_mm2s_tdata_width {24} \
    CONFIG.c_mm2s_genlock_mode {0} \
    CONFIG.c_mm2s_max_burst_length {128} \
    CONFIG.c_num_fstores {2} \
  ] $axi_vdma_1


  # Create instance: v_axi4s_vid_out_0, and set properties
  set v_axi4s_vid_out_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 v_axi4s_vid_out_0 ]
  set_property -dict [list \
    CONFIG.C_ADDR_WIDTH {12} \
    CONFIG.C_VTG_MASTER_SLAVE {1} \
  ] $v_axi4s_vid_out_0


  # Create instance: v_tc_0, and set properties
  set v_tc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.2 v_tc_0 ]
  set_property -dict [list \
    CONFIG.GEN_F0_VFRAME_SIZE {525} \
    CONFIG.GEN_F0_VSYNC_VEND {493} \
    CONFIG.GEN_F0_VSYNC_VSTART {490} \
    CONFIG.GEN_HACTIVE_SIZE {800} \
    CONFIG.GEN_HFRAME_SIZE {1056} \
    CONFIG.GEN_HSYNC_END {968} \
    CONFIG.GEN_HSYNC_START {840} \
    CONFIG.GEN_VACTIVE_SIZE {480} \
    CONFIG.VIDEO_MODE {Custom} \
    CONFIG.enable_detection {false} \
  ] $v_tc_0


  # Create instance: xlconstant_0, and set properties
  set xlconstant_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {1} \
    CONFIG.CONST_WIDTH {1} \
  ] $xlconstant_0


  # Create instance: axi_gpio_0, and set properties
  set axi_gpio_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0 ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO2_WIDTH {9} \
    CONFIG.C_GPIO_WIDTH {20} \
    CONFIG.C_IS_DUAL {1} \
  ] $axi_gpio_0


  # Create instance: xlconstant_1, and set properties
  set xlconstant_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_1 ]

  # Create instance: xlconstant_2, and set properties
  set xlconstant_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_2 ]

  # Create instance: xlconstant_3, and set properties
  set xlconstant_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_3 ]

  # Create instance: xlconstant_4, and set properties
  set xlconstant_4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_4 ]

  # Create instance: rst_33M, and set properties
  set rst_33M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_33M ]

  # Create instance: inv_lcd_pclk, and set properties
  set inv_lcd_pclk [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 inv_lcd_pclk ]
  set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
  ] $inv_lcd_pclk


  # Create instance: mem_intercon_disp, and set properties
  set mem_intercon_disp [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 mem_intercon_disp ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $mem_intercon_disp


  # Create instance: mem_intercon_cap, and set properties
  set mem_intercon_cap [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 mem_intercon_cap ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {5} \
  ] $mem_intercon_cap


  # Create instance: vtc_probe_concat, and set properties
  set vtc_probe_concat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 vtc_probe_concat ]
  set_property CONFIG.NUM_PORTS {10} $vtc_probe_concat


  # Create instance: clk_probe_cnt, and set properties
  set clk_probe_cnt [ create_bd_cell -type ip -vlnv xilinx.com:ip:c_counter_binary:12.0 clk_probe_cnt ]
  set_property -dict [list \
    CONFIG.CE {false} \
    CONFIG.Output_Width {17} \
  ] $clk_probe_cnt


  # Create instance: clk_probe_slice, and set properties
  set clk_probe_slice [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 clk_probe_slice ]
  set_property -dict [list \
    CONFIG.DIN_FROM {16} \
    CONFIG.DIN_TO {16} \
    CONFIG.DIN_WIDTH {17} \
  ] $clk_probe_slice


  # Create instance: cam_pclk_cnt, and set properties
  set cam_pclk_cnt [ create_bd_cell -type ip -vlnv xilinx.com:ip:c_counter_binary:12.0 cam_pclk_cnt ]
  set_property -dict [list \
    CONFIG.CE {false} \
    CONFIG.Output_Width {18} \
  ] $cam_pclk_cnt


  # Create instance: cam_pclk_slice, and set properties
  set cam_pclk_slice [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 cam_pclk_slice ]
  set_property -dict [list \
    CONFIG.DIN_FROM {17} \
    CONFIG.DIN_TO {17} \
    CONFIG.DIN_WIDTH {18} \
  ] $cam_pclk_slice


  # Create instance: axi_gpio_1, and set properties
  set axi_gpio_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1 ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS {0} \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_IS_DUAL {1} \
  ] $axi_gpio_1


  # Create instance: capture_ram_0, and set properties
  set block_name capture_ram
  set block_cell_name capture_ram_0
  if { [catch {set capture_ram_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $capture_ram_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: analyzer_fe_0, and set properties
  set block_name analyzer_fe
  set block_cell_name analyzer_fe_0
  if { [catch {set analyzer_fe_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $analyzer_fe_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: xlconstant_ctrl, and set properties
  set xlconstant_ctrl [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_ctrl ]
  set_property -dict [list \
    CONFIG.CONST_VAL {3} \
    CONFIG.CONST_WIDTH {32} \
  ] $xlconstant_ctrl


  # Create instance: xlconstant_tkeep, and set properties
  set xlconstant_tkeep [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_tkeep ]
  set_property -dict [list \
    CONFIG.CONST_VAL {7} \
    CONFIG.CONST_WIDTH {3} \
  ] $xlconstant_tkeep


  # Create instance: xlconstant_tuser, and set properties
  set xlconstant_tuser [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_tuser ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {1} \
  ] $xlconstant_tuser


  # Create instance: xlslice_cam, and set properties
  set xlslice_cam [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_cam ]
  set_property -dict [list \
    CONFIG.DIN_FROM {0} \
    CONFIG.DIN_TO {0} \
    CONFIG.DIN_WIDTH {10} \
    CONFIG.DOUT_WIDTH {1} \
  ] $xlslice_cam


  # Create instance: spi_gen_0, and set properties
  set block_name spi_gen
  set block_cell_name spi_gen_0
  if { [catch {set spi_gen_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $spi_gen_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: xlslice_cam_hi, and set properties
  set xlslice_cam_hi [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_cam_hi ]
  set_property -dict [list \
    CONFIG.DIN_FROM {6} \
    CONFIG.DIN_TO {4} \
    CONFIG.DIN_WIDTH {10} \
    CONFIG.DOUT_WIDTH {3} \
  ] $xlslice_cam_hi


  # Create instance: xlconcat_probe, and set properties
  set xlconcat_probe [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_probe ]
  set_property CONFIG.NUM_PORTS {7} $xlconcat_probe


  # Create instance: dcat, and set properties
  set dcat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 dcat ]
  set_property CONFIG.NUM_PORTS {9} $dcat


  # Create instance: frmptr_slice, and set properties
  set frmptr_slice [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 frmptr_slice ]
  set_property -dict [list \
    CONFIG.DIN_FROM {0} \
    CONFIG.DIN_TO {0} \
    CONFIG.DIN_WIDTH {5} \
  ] $frmptr_slice


  # Create instance: ts_cnn_top_0, and set properties
  set ts_cnn_top_0 [ create_bd_cell -type ip -vlnv xilinx.com:hls:ts_cnn_top:1.0 ts_cnn_top_0 ]

  # Create instance: dwc_gmem0, and set properties
  set dwc_gmem0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dwidth_converter:2.1 dwc_gmem0 ]

  # Create instance: dwc_gmem1, and set properties
  set dwc_gmem1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dwidth_converter:2.1 dwc_gmem1 ]

  # Create instance: alinx_ov5640_1, and set properties
  set alinx_ov5640_1 [ create_bd_cell -type ip -vlnv www.alinx.com.cn:user:alinx_ov5640:5.4 alinx_ov5640_1 ]

  # Create instance: cam_switch, and set properties
  set cam_switch [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_switch:1.1 cam_switch ]
  set_property -dict [list \
    CONFIG.M00_S01_CONNECTIVITY {0} \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {2} \
  ] $cam_switch


  # Create instance: cam_iic_1, and set properties
  set cam_iic_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 cam_iic_1 ]

  # Create instance: rs_slice0, and set properties
  set rs_slice0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 rs_slice0 ]

  # Create instance: rs_slice1, and set properties
  set rs_slice1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 rs_slice1 ]

  # Create instance: sl_gpio, and set properties
  set sl_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 sl_gpio ]
  set_property -dict [list \
    CONFIG.DIN_FROM {1} \
    CONFIG.DIN_TO {0} \
    CONFIG.DIN_WIDTH {4} \
    CONFIG.DOUT_WIDTH {2} \
  ] $sl_gpio


  # Create instance: sl_sel, and set properties
  set sl_sel [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 sl_sel ]
  set_property -dict [list \
    CONFIG.DIN_FROM {3} \
    CONFIG.DIN_TO {3} \
    CONFIG.DIN_WIDTH {4} \
    CONFIG.DOUT_WIDTH {1} \
  ] $sl_sel


  # Create instance: inv_sel, and set properties
  set inv_sel [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 inv_sel ]
  set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
  ] $inv_sel


  # Create instance: cc_sup, and set properties
  set cc_sup [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 cc_sup ]
  set_property CONFIG.NUM_PORTS {2} $cc_sup


  # Create instance: axis_subset_converter_1, and set properties
  set axis_subset_converter_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 axis_subset_converter_1 ]
  set_property -dict [list \
    CONFIG.HAS_ACLKEN {0} \
    CONFIG.M_HAS_TKEEP {1} \
    CONFIG.M_HAS_TLAST {1} \
    CONFIG.M_HAS_TREADY {1} \
    CONFIG.M_HAS_TSTRB {0} \
    CONFIG.M_TDATA_NUM_BYTES {3} \
    CONFIG.M_TDEST_WIDTH {0} \
    CONFIG.M_TID_WIDTH {0} \
    CONFIG.M_TUSER_WIDTH {1} \
    CONFIG.S_HAS_TKEEP {1} \
    CONFIG.S_HAS_TLAST {1} \
    CONFIG.S_HAS_TREADY {1} \
    CONFIG.S_HAS_TSTRB {0} \
    CONFIG.S_TDATA_NUM_BYTES {2} \
    CONFIG.S_TDEST_WIDTH {0} \
    CONFIG.S_TID_WIDTH {0} \
    CONFIG.S_TUSER_WIDTH {1} \
    CONFIG.TDATA_REMAP {tdata[4:0],3'b000,tdata[10:5],2'b00,tdata[15:11],3'b000} \
    CONFIG.TDEST_REMAP {1'b0} \
    CONFIG.TID_REMAP {1'b0} \
    CONFIG.TKEEP_REMAP {1'b1,tkeep[1:0]} \
    CONFIG.TLAST_REMAP {tlast[0]} \
    CONFIG.TSTRB_REMAP {1'b0} \
    CONFIG.TUSER_REMAP {tuser[0:0]} \
  ] $axis_subset_converter_1


  # Create instance: axi_vdma_2, and set properties
  set axi_vdma_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_2 ]
  set_property -dict [list \
    CONFIG.C_FAMILY {zynq} \
    CONFIG.C_SELECT_XPM {0} \
    CONFIG.c_addr_width {32} \
    CONFIG.c_dlytmr_resolution {125} \
    CONFIG.c_dynamic_resolution {1} \
    CONFIG.c_enable_all {0} \
    CONFIG.c_enable_mm2s_buf_empty {0} \
    CONFIG.c_enable_mm2s_delay_counter {1} \
    CONFIG.c_enable_mm2s_frm_counter {1} \
    CONFIG.c_enable_mm2s_frmstr_reg {0} \
    CONFIG.c_enable_mm2s_fsync_out {0} \
    CONFIG.c_enable_mm2s_param_updt {0} \
    CONFIG.c_enable_mm2s_rst_out {0} \
    CONFIG.c_enable_s2mm_buf_full {0} \
    CONFIG.c_enable_s2mm_delay_counter {1} \
    CONFIG.c_enable_s2mm_frm_counter {1} \
    CONFIG.c_enable_s2mm_frmstr_reg {0} \
    CONFIG.c_enable_s2mm_fsync_out {0} \
    CONFIG.c_enable_s2mm_param_updt {0} \
    CONFIG.c_enable_s2mm_rst_out {0} \
    CONFIG.c_enable_s2mm_sts_reg {0} \
    CONFIG.c_enable_tstvec {0} \
    CONFIG.c_enable_vert_flip {0} \
    CONFIG.c_enable_vidprmtr_reads {1} \
    CONFIG.c_flush_on_fsync {1} \
    CONFIG.c_include_internal_genlock {1} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_mm2s_sf {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_s2mm_dre {1} \
    CONFIG.c_include_s2mm_sf {1} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_mm2s_genlock_repeat_en {0} \
    CONFIG.c_mm2s_linebuffer_thresh {4} \
    CONFIG.c_mm2s_sof_enable {1} \
    CONFIG.c_num_fstores {4} \
    CONFIG.c_s2mm_genlock_mode {0} \
    CONFIG.c_s2mm_genlock_repeat_en {1} \
    CONFIG.c_s2mm_linebuffer_depth {4096} \
    CONFIG.c_s2mm_linebuffer_thresh {4} \
    CONFIG.c_s2mm_max_burst_length {8} \
    CONFIG.c_s2mm_sof_enable {1} \
    CONFIG.c_use_fsync {1} \
    CONFIG.c_use_s2mm_fsync {2} \
  ] $axi_vdma_2


  # Create instance: touch_gpio, and set properties
  set touch_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 touch_gpio ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS {0} \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS {0} \
    CONFIG.C_GPIO2_WIDTH {1} \
    CONFIG.C_GPIO_WIDTH {2} \
    CONFIG.C_INTERRUPT_PRESENT {0} \
    CONFIG.C_IS_DUAL {1} \
  ] $touch_gpio


  # Create instance: u_ila_vid, and set properties
  set u_ila_vid [ create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 u_ila_vid ]
  set_property -dict [list \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_OF_PROBES {9} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_TRIGIN_EN {false} \
  ] $u_ila_vid


  # Create interface connections
  connect_bd_intf_net -intf_net alinx_ov5640_0_m_axis_video [get_bd_intf_pins alinx_ov5640_0/m_axis_video] [get_bd_intf_pins rs_slice0/S_AXIS]
  connect_bd_intf_net -intf_net alinx_ov5640_1_m_axis_video [get_bd_intf_pins alinx_ov5640_1/m_axis_video] [get_bd_intf_pins rs_slice1/S_AXIS]
  connect_bd_intf_net -intf_net axi_gpio_0_GPIO [get_bd_intf_ports GPIO_0] [get_bd_intf_pins axi_gpio_0/GPIO]
  connect_bd_intf_net -intf_net axi_vdma_0_M_AXI_S2MM [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins mem_intercon_cap/S00_AXI]
  connect_bd_intf_net -intf_net axi_vdma_1_M_AXIS_MM2S [get_bd_intf_pins axi_vdma_1/M_AXIS_MM2S] [get_bd_intf_pins v_axi4s_vid_out_0/video_in]
  connect_bd_intf_net -intf_net axi_vdma_1_M_AXI_MM2S [get_bd_intf_pins axi_vdma_1/M_AXI_MM2S] [get_bd_intf_pins mem_intercon_disp/S00_AXI]
  connect_bd_intf_net -intf_net axi_vdma_2_M_AXI_S2MM [get_bd_intf_pins axi_vdma_2/M_AXI_S2MM] [get_bd_intf_pins mem_intercon_cap/S04_AXI]
  connect_bd_intf_net -intf_net axis_subset_converter_0_M_AXIS [get_bd_intf_pins axis_subset_converter_0/M_AXIS] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net axis_subset_converter_1_M_AXIS [get_bd_intf_pins axis_subset_converter_1/M_AXIS] [get_bd_intf_pins axi_vdma_2/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net cam_switch_M00_AXIS [get_bd_intf_pins cam_switch/M00_AXIS] [get_bd_intf_pins axis_subset_converter_0/S_AXIS]
  connect_bd_intf_net -intf_net dwc_gmem0_M_AXI [get_bd_intf_pins dwc_gmem0/M_AXI] [get_bd_intf_pins mem_intercon_cap/S01_AXI]
  connect_bd_intf_net -intf_net dwc_gmem1_M_AXI [get_bd_intf_pins dwc_gmem1/M_AXI] [get_bd_intf_pins mem_intercon_cap/S02_AXI]
  connect_bd_intf_net -intf_net mem_intercon_cap_M00_AXI [get_bd_intf_pins mem_intercon_cap/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP1]
  connect_bd_intf_net -intf_net mem_intercon_disp_M00_AXI [get_bd_intf_pins mem_intercon_disp/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
  connect_bd_intf_net -intf_net processing_system7_0_DDR [get_bd_intf_ports DDR] [get_bd_intf_pins processing_system7_0/DDR]
  connect_bd_intf_net -intf_net processing_system7_0_FIXED_IO [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins processing_system7_0/FIXED_IO]
  connect_bd_intf_net -intf_net processing_system7_0_IIC_0 [get_bd_intf_ports IIC_0_0] [get_bd_intf_pins processing_system7_0/IIC_0]
  connect_bd_intf_net -intf_net processing_system7_0_IIC_1 [get_bd_intf_pins processing_system7_0/IIC_1] [get_bd_intf_ports cam_iic_1_io]
  connect_bd_intf_net -intf_net processing_system7_0_M_AXI_GP0 [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins ps7_0_axi_periph/S00_AXI]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M00_AXI [get_bd_intf_pins ps7_0_axi_periph/M00_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M01_AXI [get_bd_intf_pins ps7_0_axi_periph/M01_AXI] [get_bd_intf_pins axi_vdma_1/S_AXI_LITE]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M02_AXI [get_bd_intf_pins ps7_0_axi_periph/M02_AXI] [get_bd_intf_pins v_tc_0/ctrl]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M03_AXI [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M04_AXI [get_bd_intf_pins ps7_0_axi_periph/M04_AXI] [get_bd_intf_pins axi_gpio_1/S_AXI]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M05_AXI [get_bd_intf_pins ps7_0_axi_periph/M05_AXI] [get_bd_intf_pins ts_cnn_top_0/s_axi_control]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M06_AXI [get_bd_intf_pins ps7_0_axi_periph/M06_AXI] [get_bd_intf_pins ts_cnn_top_0/s_axi_control_r]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M07_AXI [get_bd_intf_pins ps7_0_axi_periph/M07_AXI] [get_bd_intf_pins cam_iic_1/S_AXI]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M08_AXI [get_bd_intf_pins ps7_0_axi_periph/M08_AXI] [get_bd_intf_pins axi_vdma_2/S_AXI_LITE]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M09_AXI [get_bd_intf_pins ps7_0_axi_periph/M09_AXI] [get_bd_intf_pins touch_gpio/S_AXI]
  connect_bd_intf_net -intf_net rs_slice0_M_AXIS [get_bd_intf_pins rs_slice0/M_AXIS] [get_bd_intf_pins cam_switch/S00_AXIS]
  connect_bd_intf_net -intf_net rs_slice1_M_AXIS [get_bd_intf_pins rs_slice1/M_AXIS] [get_bd_intf_pins axis_subset_converter_1/S_AXIS]
  connect_bd_intf_net -intf_net touch_gpio_GPIO [get_bd_intf_pins touch_gpio/GPIO] [get_bd_intf_ports lcd_touch_gpio]
  connect_bd_intf_net -intf_net ts_cnn_top_0_m_axi_gmem0 [get_bd_intf_pins ts_cnn_top_0/m_axi_gmem0] [get_bd_intf_pins dwc_gmem0/S_AXI]
  connect_bd_intf_net -intf_net ts_cnn_top_0_m_axi_gmem1 [get_bd_intf_pins ts_cnn_top_0/m_axi_gmem1] [get_bd_intf_pins dwc_gmem1/S_AXI]
  connect_bd_intf_net -intf_net ts_cnn_top_0_m_axi_gmem2 [get_bd_intf_pins ts_cnn_top_0/m_axi_gmem2] [get_bd_intf_pins mem_intercon_cap/S03_AXI]
  connect_bd_intf_net -intf_net v_axi4s_vid_out_0_vid_io_out [get_bd_intf_ports vid_io_out_0] [get_bd_intf_pins v_axi4s_vid_out_0/vid_io_out]
  connect_bd_intf_net -intf_net v_tc_0_vtiming_out [get_bd_intf_pins v_tc_0/vtiming_out] [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in]

  # Create port connections
  connect_bd_net -net Net [get_bd_pins axi_vdma_1/m_axis_mm2s_tvalid] [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tvalid] [get_bd_pins dcat/In2] [get_bd_pins u_ila_vid/probe7]
  connect_bd_net -net Net1 [get_bd_pins axi_vdma_1/m_axis_mm2s_tlast] [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tlast] [get_bd_pins dcat/In4]
  connect_bd_net -net alinx_ov5640_0_m_axis_video_tdata [get_bd_pins alinx_ov5640_0/m_axis_video_tdata] [get_bd_pins axis_subset_converter_0/s_axis_tdata]
  connect_bd_net -net alinx_ov5640_0_m_axis_video_tlast [get_bd_pins alinx_ov5640_0/m_axis_video_tlast] [get_bd_pins axis_subset_converter_0/s_axis_tlast]
  connect_bd_net -net alinx_ov5640_0_m_axis_video_tuser [get_bd_pins alinx_ov5640_0/m_axis_video_tuser] [get_bd_pins axis_subset_converter_0/s_axis_tuser]
  connect_bd_net -net alinx_ov5640_0_m_axis_video_tvalid [get_bd_pins alinx_ov5640_0/m_axis_video_tvalid] [get_bd_pins axis_subset_converter_0/s_axis_tvalid] [get_bd_pins vtc_probe_concat/In5]
  connect_bd_net -net analyzer_fe_0_m_axis_tdata [get_bd_pins analyzer_fe_0/m_axis_tdata]
  connect_bd_net -net analyzer_fe_0_m_axis_tlast [get_bd_pins analyzer_fe_0/m_axis_tlast]
  connect_bd_net -net analyzer_fe_0_m_axis_tvalid [get_bd_pins analyzer_fe_0/m_axis_tvalid]
  connect_bd_net -net axi_gpio_0_gpio_io_o [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_pins sl_gpio/Din] [get_bd_pins sl_sel/Din]
  connect_bd_net -net axi_gpio_1_gpio_io_o [get_bd_pins axi_gpio_1/gpio_io_o] [get_bd_pins capture_ram_0/ctrl_i] [get_bd_pins spi_gen_0/ctrl_i]
  connect_bd_net -net axi_vdma_0_s2mm_frame_ptr_out [get_bd_pins axi_vdma_0/s2mm_frame_ptr_out] [get_bd_pins frmptr_slice/Din]
  connect_bd_net -net axi_vdma_0_s_axis_s2mm_tready [get_bd_pins axi_vdma_0/s_axis_s2mm_tready] [get_bd_pins axis_subset_converter_0/m_axis_tready]
  connect_bd_net -net axi_vdma_2_s2mm_frame_ptr_out [get_bd_pins axi_vdma_2/s2mm_frame_ptr_out] [get_bd_pins touch_gpio/gpio2_io_i] [get_bd_pins vtc_probe_concat/In9]
  connect_bd_net -net axis_subset_converter_0_m_axis_tdata [get_bd_pins axis_subset_converter_0/m_axis_tdata] [get_bd_pins axi_vdma_0/s_axis_s2mm_tdata]
  connect_bd_net -net axis_subset_converter_0_m_axis_tlast [get_bd_pins axis_subset_converter_0/m_axis_tlast] [get_bd_pins vtc_probe_concat/In7] [get_bd_pins axi_vdma_0/s_axis_s2mm_tlast]
  connect_bd_net -net axis_subset_converter_0_m_axis_tuser [get_bd_pins axis_subset_converter_0/m_axis_tuser] [get_bd_pins axi_vdma_0/s_axis_s2mm_tuser]
  connect_bd_net -net axis_subset_converter_0_m_axis_tvalid [get_bd_pins axis_subset_converter_0/m_axis_tvalid] [get_bd_pins axi_vdma_0/s_axis_s2mm_tvalid]
  connect_bd_net -net axis_subset_converter_0_s_axis_tready [get_bd_pins axis_subset_converter_0/s_axis_tready] [get_bd_pins alinx_ov5640_0/m_axis_video_tready]
  connect_bd_net -net cam_pclk_cnt_Q [get_bd_pins cam_pclk_cnt/Q] [get_bd_pins cam_pclk_slice/Din]
  connect_bd_net -net cam_pclk_slice_Dout [get_bd_pins cam_pclk_slice/Dout] [get_bd_pins vtc_probe_concat/In8]
  connect_bd_net -net capture_ram_0_data_o [get_bd_pins capture_ram_0/data_o] [get_bd_pins axi_gpio_1/gpio2_io_i]
  connect_bd_net -net cc_sup_dout [get_bd_pins cc_sup/dout] [get_bd_pins cam_switch/s_req_suppress]
  connect_bd_net -net clk_probe_cnt_Q [get_bd_pins clk_probe_cnt/Q] [get_bd_pins clk_probe_slice/Din]
  connect_bd_net -net clk_probe_slice_Dout [get_bd_pins clk_probe_slice/Dout]
  connect_bd_net -net cmos_d_0_1 [get_bd_ports cmos_d_0] [get_bd_pins alinx_ov5640_0/cmos_d] [get_bd_pins analyzer_fe_0/ch_i] [get_bd_pins xlslice_cam/Din] [get_bd_pins xlslice_cam_hi/Din]
  connect_bd_net -net cmos_d_1_1 [get_bd_ports cmos_d_1] [get_bd_pins alinx_ov5640_1/cmos_d]
  connect_bd_net -net cmos_href_0_1 [get_bd_ports cmos_href_0] [get_bd_pins alinx_ov5640_0/cmos_href]
  connect_bd_net -net cmos_href_1_1 [get_bd_ports cmos_href_1] [get_bd_pins alinx_ov5640_1/cmos_href]
  connect_bd_net -net cmos_pclk_0_1 [get_bd_ports cmos_pclk_0] [get_bd_pins alinx_ov5640_0/cmos_pclk] [get_bd_pins cam_pclk_cnt/CLK]
  connect_bd_net -net cmos_pclk_1_1 [get_bd_ports cmos_pclk_1] [get_bd_pins alinx_ov5640_1/cmos_pclk]
  connect_bd_net -net cmos_vsync_0_1 [get_bd_ports cmos_vsync_0] [get_bd_pins alinx_ov5640_0/cmos_vsync] [get_bd_pins vtc_probe_concat/In6]
  connect_bd_net -net cmos_vsync_1_1 [get_bd_ports cmos_vsync_1] [get_bd_pins alinx_ov5640_1/cmos_vsync]
  connect_bd_net -net dcat_dout1 [get_bd_pins dcat/dout] [get_bd_pins capture_ram_0/probe_i]
  connect_bd_net -net frmptr_slice_Dout [get_bd_pins frmptr_slice/Dout] [get_bd_pins vtc_probe_concat/In4]
  connect_bd_net -net inv_lcd_pclk_Res [get_bd_pins inv_lcd_pclk/Res] [get_bd_ports lcd_pclk]
  connect_bd_net -net inv_sel_Res [get_bd_pins inv_sel/Res] [get_bd_pins cc_sup/In1]
  connect_bd_net -net proc_sys_reset_0_interconnect_aresetn [get_bd_pins proc_sys_reset_0/interconnect_aresetn] [get_bd_pins mem_intercon_disp/ARESETN] [get_bd_pins mem_intercon_cap/ARESETN]
  connect_bd_net -net proc_sys_reset_0_peripheral_aresetn [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins alinx_ov5640_0/m_axis_video_aresetn] [get_bd_pins ps7_0_axi_periph/S00_ARESETN] [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins ps7_0_axi_periph/M00_ARESETN] [get_bd_pins ps7_0_axi_periph/ARESETN] [get_bd_pins axis_subset_converter_0/aresetn] [get_bd_pins axi_vdma_1/axi_resetn] [get_bd_pins ps7_0_axi_periph/M01_ARESETN] [get_bd_pins v_tc_0/s_axi_aresetn] [get_bd_pins ps7_0_axi_periph/M02_ARESETN] [get_bd_pins axi_gpio_0/s_axi_aresetn] [get_bd_pins ps7_0_axi_periph/M03_ARESETN] [get_bd_pins mem_intercon_disp/S00_ARESETN] [get_bd_pins mem_intercon_disp/M00_ARESETN] [get_bd_pins mem_intercon_cap/S00_ARESETN] [get_bd_pins mem_intercon_cap/M00_ARESETN] [get_bd_pins ps7_0_axi_periph/M04_ARESETN] [get_bd_pins axi_gpio_1/s_axi_aresetn] [get_bd_pins capture_ram_0/aresetn] [get_bd_pins analyzer_fe_0/aresetn] [get_bd_pins spi_gen_0/aresetn] [get_bd_pins ts_cnn_top_0/ap_rst_n] [get_bd_pins ps7_0_axi_periph/M05_ARESETN] [get_bd_pins ps7_0_axi_periph/M06_ARESETN] [get_bd_pins mem_intercon_cap/S01_ARESETN] [get_bd_pins mem_intercon_cap/S02_ARESETN] [get_bd_pins mem_intercon_cap/S03_ARESETN] [get_bd_pins dwc_gmem0/s_axi_aresetn] [get_bd_pins dwc_gmem1/s_axi_aresetn] [get_bd_pins cam_switch/aresetn] [get_bd_pins alinx_ov5640_1/m_axis_video_aresetn] [get_bd_pins cam_iic_1/s_axi_aresetn] [get_bd_pins ps7_0_axi_periph/M07_ARESETN] [get_bd_pins rs_slice0/aresetn] [get_bd_pins rs_slice1/aresetn] [get_bd_pins axis_subset_converter_1/aresetn] [get_bd_pins axi_vdma_2/axi_resetn] [get_bd_pins mem_intercon_cap/S04_ARESETN] [get_bd_pins ps7_0_axi_periph/M08_ARESETN] [get_bd_pins touch_gpio/s_axi_aresetn]
  connect_bd_net -net processing_system7_0_FCLK_CLK0 [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] [get_bd_pins processing_system7_0/S_AXI_HP1_ACLK] [get_bd_pins axi_vdma_1/m_axi_mm2s_aclk] [get_bd_pins axi_vdma_0/m_axi_s2mm_aclk] [get_bd_pins axi_vdma_0/s_axi_lite_aclk] [get_bd_pins ps7_0_axi_periph/M00_ACLK] [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins axis_subset_converter_0/aclk] [get_bd_pins axi_vdma_1/s_axi_lite_aclk] [get_bd_pins ps7_0_axi_periph/M01_ACLK] [get_bd_pins proc_sys_reset_0/slowest_sync_clk] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] [get_bd_pins ps7_0_axi_periph/S00_ACLK] [get_bd_pins ps7_0_axi_periph/ACLK] [get_bd_pins ps7_0_axi_periph/M02_ACLK] [get_bd_pins v_tc_0/s_axi_aclk] [get_bd_pins alinx_ov5640_0/m_axis_video_aclk] [get_bd_pins axi_gpio_0/s_axi_aclk] [get_bd_pins ps7_0_axi_periph/M03_ACLK] [get_bd_pins mem_intercon_disp/ACLK] [get_bd_pins mem_intercon_disp/S00_ACLK] [get_bd_pins mem_intercon_disp/M00_ACLK] [get_bd_pins mem_intercon_cap/ACLK] [get_bd_pins mem_intercon_cap/S00_ACLK] [get_bd_pins mem_intercon_cap/M00_ACLK] [get_bd_pins ps7_0_axi_periph/M04_ACLK] [get_bd_pins axi_gpio_1/s_axi_aclk] [get_bd_pins capture_ram_0/aclk] [get_bd_pins analyzer_fe_0/aclk] [get_bd_pins spi_gen_0/aclk] [get_bd_pins ts_cnn_top_0/ap_clk] [get_bd_pins ps7_0_axi_periph/M05_ACLK] [get_bd_pins ps7_0_axi_periph/M06_ACLK] [get_bd_pins mem_intercon_cap/S01_ACLK] [get_bd_pins mem_intercon_cap/S02_ACLK] [get_bd_pins mem_intercon_cap/S03_ACLK] [get_bd_pins dwc_gmem0/s_axi_aclk] [get_bd_pins dwc_gmem1/s_axi_aclk] [get_bd_pins cam_switch/aclk] [get_bd_pins alinx_ov5640_1/m_axis_video_aclk] [get_bd_pins cam_iic_1/s_axi_aclk] [get_bd_pins ps7_0_axi_periph/M07_ACLK] [get_bd_pins rs_slice0/aclk] [get_bd_pins rs_slice1/aclk] [get_bd_pins axis_subset_converter_1/aclk] [get_bd_pins axi_vdma_2/m_axi_s2mm_aclk] [get_bd_pins axi_vdma_2/s_axi_lite_aclk] [get_bd_pins axi_vdma_2/s_axis_s2mm_aclk] [get_bd_pins mem_intercon_cap/S04_ACLK] [get_bd_pins ps7_0_axi_periph/M08_ACLK] [get_bd_pins touch_gpio/s_axi_aclk] [get_bd_pins ps7_0_axi_periph/M09_ACLK]
  connect_bd_net -net processing_system7_0_FCLK_CLK1 [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins v_axi4s_vid_out_0/aclk] [get_bd_pins v_tc_0/clk] [get_bd_pins axi_vdma_1/m_axis_mm2s_aclk] [get_bd_pins rst_33M/slowest_sync_clk] [get_bd_pins inv_lcd_pclk/Op1] [get_bd_pins clk_probe_cnt/CLK] [get_bd_pins u_ila_vid/clk]
  connect_bd_net -net processing_system7_0_FCLK_RESET0_N [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins proc_sys_reset_0/ext_reset_in] [get_bd_pins rst_33M/ext_reset_in]
  connect_bd_net -net rst_33M_peripheral_aresetn [get_bd_pins rst_33M/peripheral_aresetn] [get_bd_pins v_tc_0/resetn] [get_bd_pins v_axi4s_vid_out_0/aresetn] [get_bd_pins vtc_probe_concat/In3] [get_bd_pins dcat/In8]
  connect_bd_net -net sl_gpio_Dout [get_bd_pins sl_gpio/Dout] [get_bd_ports GPIO_0_tri_o]
  connect_bd_net -net sl_sel_Dout [get_bd_pins sl_sel/Dout] [get_bd_pins inv_sel/Op1] [get_bd_pins cc_sup/In0]
  connect_bd_net -net spi_gen_0_cs_n [get_bd_pins spi_gen_0/cs_n] [get_bd_pins xlconcat_probe/In3]
  connect_bd_net -net spi_gen_0_mosi [get_bd_pins spi_gen_0/mosi] [get_bd_pins xlconcat_probe/In2]
  connect_bd_net -net spi_gen_0_sck [get_bd_pins spi_gen_0/sck] [get_bd_pins xlconcat_probe/In1]
  connect_bd_net -net v_axi4s_vid_out_0_locked [get_bd_pins v_axi4s_vid_out_0/locked] [get_bd_pins dcat/In0] [get_bd_pins u_ila_vid/probe5]
  connect_bd_net -net v_axi4s_vid_out_0_overflow [get_bd_pins v_axi4s_vid_out_0/overflow] [get_bd_pins dcat/In1] [get_bd_pins u_ila_vid/probe6]
  connect_bd_net -net v_axi4s_vid_out_0_s_axis_video_tready [get_bd_pins v_axi4s_vid_out_0/s_axis_video_tready] [get_bd_pins axi_vdma_1/m_axis_mm2s_tready] [get_bd_pins dcat/In3] [get_bd_pins u_ila_vid/probe8]
  connect_bd_net -net v_tc_0_active_video_out [get_bd_pins v_tc_0/active_video_out] [get_bd_pins v_axi4s_vid_out_0/vtg_active_video] [get_bd_pins vtc_probe_concat/In0] [get_bd_pins dcat/In5] [get_bd_pins u_ila_vid/probe0]
  connect_bd_net -net v_tc_0_hblank_out [get_bd_pins v_tc_0/hblank_out] [get_bd_pins v_axi4s_vid_out_0/vtg_hblank] [get_bd_pins u_ila_vid/probe3]
  connect_bd_net -net v_tc_0_hsync_out [get_bd_pins v_tc_0/hsync_out] [get_bd_pins v_axi4s_vid_out_0/vtg_hsync] [get_bd_pins vtc_probe_concat/In1] [get_bd_pins dcat/In6] [get_bd_pins u_ila_vid/probe1]
  connect_bd_net -net v_tc_0_vblank_out [get_bd_pins v_tc_0/vblank_out] [get_bd_pins v_axi4s_vid_out_0/vtg_vblank] [get_bd_pins u_ila_vid/probe4]
  connect_bd_net -net v_tc_0_vsync_out [get_bd_pins v_tc_0/vsync_out] [get_bd_pins v_axi4s_vid_out_0/vtg_vsync] [get_bd_pins vtc_probe_concat/In2] [get_bd_pins dcat/In7] [get_bd_pins u_ila_vid/probe2]
  connect_bd_net -net vtc_probe_concat_dout [get_bd_pins vtc_probe_concat/dout] [get_bd_pins axi_gpio_0/gpio2_io_i]
  connect_bd_net -net xlconcat_probe_dout [get_bd_pins xlconcat_probe/dout]
  connect_bd_net -net xlconstant_0_dout [get_bd_pins xlconstant_0/dout] [get_bd_ports lcd_blen] [get_bd_pins rst_33M/dcm_locked]
  connect_bd_net -net xlconstant_1_dout [get_bd_pins xlconstant_1/dout] [get_bd_pins v_axi4s_vid_out_0/aclken]
  connect_bd_net -net xlconstant_2_dout [get_bd_pins xlconstant_2/dout] [get_bd_pins v_axi4s_vid_out_0/vid_io_out_ce]
  connect_bd_net -net xlconstant_3_dout [get_bd_pins xlconstant_3/dout] [get_bd_pins v_tc_0/gen_clken]
  connect_bd_net -net xlconstant_4_dout [get_bd_pins xlconstant_4/dout]
  connect_bd_net -net xlconstant_ctrl_dout [get_bd_pins xlconstant_ctrl/dout] [get_bd_pins analyzer_fe_0/ctrl]
  connect_bd_net -net xlconstant_tkeep_dout [get_bd_pins xlconstant_tkeep/dout] [get_bd_pins axi_vdma_0/s_axis_s2mm_tkeep]
  connect_bd_net -net xlconstant_tuser_dout [get_bd_pins xlconstant_tuser/dout]
  connect_bd_net -net xlslice_cam_Dout [get_bd_pins xlslice_cam/Dout] [get_bd_pins xlconcat_probe/In0]
  connect_bd_net -net xlslice_cam_hi_Dout [get_bd_pins xlslice_cam_hi/Dout] [get_bd_pins xlconcat_probe/In4]

  # Create address segments
  assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x41210000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_gpio_1/S_AXI/Reg] -force
  assign_bd_address -offset 0x43000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_vdma_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x43010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_vdma_1/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x44A00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_vdma_2/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x40800000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs cam_iic_1/S_AXI/Reg] -force
  assign_bd_address -offset 0x41220000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs touch_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0x43C20000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs ts_cnn_top_0/s_axi_control/Reg] -force
  assign_bd_address -offset 0x43C30000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs ts_cnn_top_0/s_axi_control_r/Reg] -force
  assign_bd_address -offset 0x43C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs v_tc_0/ctrl/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces axi_vdma_0/Data_S2MM] [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces axi_vdma_1/Data_MM2S] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces ts_cnn_top_0/Data_m_axi_gmem0] [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces ts_cnn_top_0/Data_m_axi_gmem1] [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces ts_cnn_top_0/Data_m_axi_gmem2] [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces axi_vdma_2/Data_S2MM] [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


