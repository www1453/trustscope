TrustScope 可信成像质检系统
技术文档（Zynq-7020 双目采集 · PS 渲染质检 · 触摸面板 · 网页质检台）
版本：2026-10-28（第 14 章的表换成 41 块板的授权扫描——构建 TSC1 7C54944F、参考 909、工作点 6——并新增第十六章：出货比特流的资源、时序与实测延迟，第十七章：两次 AI 尝试以及它们为什么输，以及第十八章：外部复核的十一条发现与四项已修；第十六章另增 16.11 的两处更正（平均采样的上限、class 的构成）；其余各章与前一次版本逐字一致）
硬件：Zynq-7020 开发板 + AN5642 双目相机模块（两颗 OV5640）+ AN970 7 英寸电容触摸屏（800×480）
说明：本文所有量化结论均标注来源文件与章节；凡在仓库内找不到可核对来源的数字，一律写成「未验证」并说明原因，不以合理推测补齐。

## 阅读约定与溯源说明
来源标记形如（来源：dl/HANDOVER_20261016.md §19.1），§ 指该文件的小节或行区间；ps_ui/main.c 等源码以行号或宏名定位。
「实测」= 仓库内有脚本输出或日志可直接核对的读数；「设计值」= Block Design / XDC / 源码里写死的意图值，两者不同处本文分别列出。
「未验证」= 该数字在仓库内找不到来源，或来源本身被后续记录推翻。本文不把「未验证」写成结论。
本文只描述既有事实，不修改任何工程文件；文中出现的「下一步」均引自交接文件，不是本文给出的新结论。
全文不含任何人员、单位或编号身份信息；这是提交的硬性要求，已在交付前逐字复查。

# 一、系统概述与架构

## 1.1 系统组成

## 1.2 数据通路
采集通路（PL → DDR）：
相机0: cmos_d_0 -> rs_slice0 -> cam_switch(S00 静态) -> subset_conv_0 -> axi_vdma_0 -> mem_intercon/S00 -> HP1
相机1: cmos_d_1 -> rs_slice1 -> subset_conv_1 -> axi_vdma_2 -> mem_intercon/S04 -> HP1
（来源：dl/STEREO_SUCCESS_ROOTCAUSE.md「现在的双目架构」）
渲染与质检通路（PS）：
DDR 采集帧存 0x10000000/0x10400000（相机0）、0x11200000/0x11600000（相机1）
-> PS draw_camera()：2x2 箱式降采样 1280x720 -> 640x360，双曝光融合，色调映射，同时统计裁剪
-> PS measure()：质量度量（当前发布的是饱和/裁剪门限这一条）
-> PS draw_panel()：状态面板；draw_camera1_view()：相机1 视图
-> PS 写显示帧存 0x10800000/0x10A00000
-> 显示通道 axi_vdma_1(MM2S) 0x43010000 -> v_axi4s_vid_out -> AN970 面板（时序由 v_tc 产生）
遥测：PS -> 邮箱 0x10F00000 -> （JTAG，无板上网络通路）-> 主机 status_feed.py -> 网页质检台
（来源：dl/HANDOVER_20261016.md §四①、§14.2、§22.3；ps_ui/main.c 地址宏区；submission/dashboard/README.md 第二节）
关键数据量：采集帧 1280×720、stride 3840、每帧 2.76 MB；显示帧 800×480、stride 2400、每帧 1.15 MB；通道总数 MB_CHANTOT = 640×360×3 = 691200（每帧逐通道统计）。（来源：ps_ui/main.c 的 CAM_BUF/UI_FRAME/MB_CHANTOT 宏；ps_fft_dual/logs/ps_run.log 第 106 行）

## 1.3 PL 与 PS 的职责划分
（来源：dl/HANDOVER_20261016.md §19.2、§21.2、§22.3；dl/STEREO_SUCCESS_ROOTCAUSE.md；ps_ui/mmu.c；ps_ui/main.c）

## 1.4 地址与缓冲布局（PS 视角）

# 二、硬件与时钟

## 2.1 FCLK_CLK0：设计值 50 MHz，实测 16.67 MHz
为什么会不同：本项目自己的 ps7_init_cdcfix_50m.tcl 从不写 0xF8000140；而 rst -system 与断电都会把时钟单元复位回默认值（÷60 → 16.67 MHz），于是「不写」等于放任。厂商那份 ps7_init 是写的（0x00100801 ⇒ 125 MHz），所以触摸调查中跑厂商 ps7_init 的那次 FCLK0 一度是 125 MHz，之后的复位又把它打回 16.67 MHz。（来源：dl/HANDOVER_20261016.md §19.1）
FCLK_CLK0 挂着什么（逐 consumer 查得）：ps7_0_axi_periph 全部 M00–M08、三个 VDMA 的 m_axi_*_aclk 与 s_axi_lite_aclk、两个 DDR HP 端口、v_tc_0/s_axi_aclk、axi_gpio_0/1、两个 alinx_ov5640 的 m_axis_video_aclk、ts_cnn_top_0/ap_clk、cam_iic_1/s_axi_aclk、mem_intercon_cap/disp、capture_ram_0、proc_sys_reset_0。FCLK_CLK1 独自承担 v_axi4s_vid_out/aclk、v_tc_0/clk、显示 VDMA 的 MM2S aclk、rst_33M、inv_lcd_pclk、clk_probe_cnt —— 即 LCD 时序只挂这一条，所以把 FCLK0 恢复成 50 MHz 不碰 LCD 时序。（来源：dl/HANDOVER_20261016.md §19.2）
如何修正并断言：引导脚本在 ps7_init 之后写 FPGA0_CLK_CTRL = 0x00001401（÷20 → 50 MHz），随后回读并断言分频位，不满足就 FATAL 退出：
L "--- FCLK_CLK0 (the PL AXI clock) ---"
set f0old [RD 0xF8000140]
WR 0xF8000140 0x00001401
set f0new [RD 0xF8000140]
if {[expr {$f0new & 0x3F00}] != 0x1400} { FATAL "FCLK_CLK0 did not take the 50 MHz setting" }
（来源：ps_fft_dual/stereo_bringup_byname.tcl 第 225–247 行；dl/HANDOVER_20261016.md §21.2）
单变量实验的实际结果（重要，且结论与设计意图不一致）：ps_fclk0_test.tcl 按「先存原值 → 量 BEFORE → 写 → 回读 → 量 AFTER」的流程跑过一次，预测写在脚本头部（采集率↑、循环率↑、LCD 画面不变）。实测：
（来源：ps_fft_dual/logs/ps_fclk0_test.log 全文；原值保存在 ps_fft_dual/logs/fclk0_original.txt = 00003C01）
判读：这次实验是在一次不健康的板态上跑的（VDMA0 停、VDMA2 读回 0xFFFFFFFF、循环率只有 1.8 fps），所以 1.72→1.86 fps 这个读数不能用来支持或否定「FCLK0 提高 3 倍会让整条 AXI 通路变快」的预测。50 MHz 这一条被固化进引导脚本并带回读断言，属于「把设计意图恢复成事实」，但「FCLK0 修正带来的性能增益」本身在仓库内未验证（没有一次健康上电下的 FCLK0 前后对照）。（来源：同上日志的 VDMA 读回值；dl/HANDOVER_20261016.md §20.3、§21.2）

## 2.2 DDR
来源分歧（如实记录）：dl/HANDOVER_20261016.md §20.3 写「Zynq 的 DDR 只在上电时由 boot ROM 训练，ps7_init 不训练」；而同一仓库的提交记录 ac14e68 写「设计无法在未跑 ps7_init 的冷态运行（DDR 由 ps7_init 初始化）」。两句话对「谁初始化 DDR」的说法不一致，本文并列出，不替其中一方下结论。（来源：dl/HANDOVER_20261016.md §20.3；git 提交 ac14e68 信息）

## 2.3 MMU 与 D-Cache 的当前状态
当前是打开的：板上实测 SCTLR = 0x08C5107D，MMU / D-cache / I-cache 全开（ps_run.log 第 49 行；dl/HANDOVER_20261016.md §18.2）。打开 MMU + D-cache 让 PS 侧渲染从 2.87 fps 提升到 19.60 fps（6.8×）。（来源：submission/README.md「当前状态」节；ps_ui/mmu.c 文件头）
页表与属性（ARMv7-A 短描述符 1 MB 段；ps_ui/mmu.c mmu_init()）：
未映射的地址保持「翻译故障」而不是静默读垃圾：mmu.c 注释明确写出这是有意为之，故障处理程序记录 DFAR，使失败能报出地址。0x11000000 那一段在 2026-10-16 之前是缺失的，缺失本身就是画中画那一轮失败的根因（faultcode 0x11111104、DFAR = 0x11200000），而不是显示代码的问题。（来源：ps_ui/mmu.c 第 126–164 行；dl/HANDOVER_20261016.md §四①、§九）
缓存一致性契约（当前状态的直接后果）：
采集帧存（相机0/相机1）：CPU 只读，PL 只写 → 读前必须 dcache_invalidate（作废，无需写回）。
显示帧存：CPU 写、PL 读 → 翻转前必须 dcache_clean，否则面板停在上两帧。
邮箱：非缓存映射，不做缓存维护。
相机1 帧存是 WBWA：读前必须 dcache_invalidate(CAM1_BUF, CAM_BYTES)。忘记的后果是画面冻结而不报错，所以这条契约写在映射处与读者处各一遍。
为什么只需要 L1 维护：先读了 L2C-310 的寄存器再看结论 —— Cache ID = 0x410000C8（存在），Control = 0x00000000，即 L2 是关的，只有 L1 打开，DCIMVAC/DCCMVAC 就能到达内存；若 L2 打开，同样操作不完整，还需编程 L2C-310。（来源：ps_ui/mmu.c 第 10–15 行；skill/pitfalls/zynq-cache-dma-traps.md 坑 3）
一条过时注释的代价：main.c 头部曾长期写着「MMU AND D-CACHE ARE OFF ON PURPOSE」，而缓存早已打开。上一轮正是据这句过时注释去推断 0x11200000 可达性，导致板上跑飞。该注释已在 §9.1 一并改掉。（来源：dl/HANDOVER_20261016.md §9.1、§四①）

## 2.4 上电状态的随机性（同一套文件，快慢两种状态）
已逐条排除的编辑项：本项目的代码、比特流、ps7_init 内容、PS 时钟、MMU/cache、看门狗、FCLK0、PL 流量、等帧、曝光、显示读带宽。仍有两个未分开的假说：上电时的 DDR/PS 初始化本身，或其间跑过厂商 ps7_init 留下的、按键复位清不掉的差异。判决实验（两次上电，冷态 vs 跑过我们 ps7_init 之后）已写进交接文件，需要板子。（来源：dl/HANDOVER_20261016.md §20.3、§20.5）

## 2.5 约束文件集与「构建成功」的可复现性（2026-10-22 至 10-23）
2026-10-22 21:50 起，place_design 一直失败：ERROR: [Place 30-99] Placer failed with error: 「failed to commit all instances」，同时 53 条 Critical Warning、36 条 Terminal X cannot be placed on <pad> because the pad is already occupied by terminal Y。判据在 placer 报错，根因却不在 placer。
根因在工程的约束文件集 constrs_1：里面有四个 XDC，而不是两个。
two_fft_j11.xdc 是另一套完整且互斥的引脚方案：它把 LCD 输出映射到 J10/J11 的相机焊盘上（例如 vid_io_out_0_data[2] = T14，而本工程在该脚上是 cmos_d_0[5]）。它独有端口数 = 0，即不提供任何其余三份文件未约束的端口，因此移除它不会留下未约束的引脚——这一点是删之前按引脚聚合机械核对过的，不是估计。
顺带消除的隐患：该文件把 V12 指派为 lcd_blen（输出），而 V12 在工程自己的表里是 cmos_d_0[0]（相机输入），正是硬件安全手册里「J10 PIN35(B20) ↔ PIN28(V12) 跳线必须不插」的那个脚。两套方案同时生效时，该脚会同时被要求当输出和当输入。
一个值得记下的操作教训：当天 09:14 已经有一次同目的的脚本删除了该文件，却没有保存工程。Vivado 的工程编辑只在内存里，而 save_project 命令并不存在——写 .xpr 的动作是 close_project。所以那次删除没有持久化，下一次构建原样失败；脚本还打印了「删了 1 个」。这次的判据因此改成：删除 → close_project → 重新 open_project 并读回 constrs_1（应为 3 个文件）→ 才允许启动构建。
修复后的构建（ps_fft_dual/xdcfix_build_20261023.tcl，ASCII only）：place_design completed successfully、already occupied 告警 36 → 0、impl_1 STATUS = write_bitstream Complete!、WNS = 2.594 / WHS = 0.032、All user specified timing constraints are met；比特流 4,045,676 B，SHA256 5CEF5D86…3113701，且与 10-20 那份不同（BD 改动确实进了 PL）。归档为 safe_bitstreams/BIT_20261023_xdcfixed.bit，哈希与源一致。
构建后按安全手册复核引脚方向（runs/impl_1/design_1_wrapper_io_placed.rpt）：26 个 cmos_* 端口全部 INPUT；IIC_0_0_* 与 cam_iic_1_* 全部 BIDIR；GPIO_0_tri_o[0](B20) / [1](W14) 为 OUTPUT；没有任何 OUTPUT 端口落在相机焊盘上。这一节与 8.2（10）末条是同一件事的两面：构建成功不等于设计正确，所以必须回去核验引脚表。
（来源：dl/REPORT_UPDATE_DRAFT_20261023.md §F；dl/STATUS_20261023_XDC_AND_PROBE.md §一、§二；ps_fft_dual/xdcfix_build_20261023.tcl 与其构建日志）

# 三、质检算法与判据

## 3.1 一帧的相位与各段职责
PS 主循环按相位计时并发布（MB_T_*，word 70–79；健康上电实测，来源 ps_fft_dual/logs/ps_verify_display.log）：

## 3.2 饱和/裁剪门限：按通道计，门限由主机给
统计口径：以通道为单位（不是像素）。一个像素只要有一个通道到达裁剪点就计入丢失，因为信息就是在那里丢的。逐帧检查通道数 MB_CHANTOT = 691200。（来源：ps_ui/main.c 第 1045–1055 行）
门限 MB_CLIP_LIM（word 67 / byte 268）由主机写入，单位是千分之一通道数（per-mille），0 表示用内置默认值；PS 实际采用的值另发布为 MB_CLIP_LIME（word 68 / byte 272），这样「主机要求多少、板子用了多少」同时可见。
（来源：ps_ui/main.c 第 474–492 行、第 1041–1080 行）
判据公式（ps_ui/main.c 第 1055–1066 行）：
g_clip_pm  = g_chan_total ? (g_clip_long * 1000 / g_chan_total) : 0;
lim        = MB_CLIP_LIM；if (lim == 0 || lim > 1000) lim = 10;   /* 默认 10‰ = 1% 通道 */
g_clip_gate= (g_clip_pm > lim) ? 1 : 0;
一次 fail-open 事故及其修复（必须写在判据里）：第一版只替换「恰好等于 0」的情形。板上主机尚未播撒这个字时，该字读到 DDR 垃圾值 0x91C8D0B2，被钳到 1000，于是闸门在 4.4% 裁剪率下保持打开——一个由未初始化字段造成的「放行型仪表」。修法是把「0 或 >1000」都回落到默认值。写在源码里的规则是：测量装置必须往「我无法判定」的方向失败，绝不能往「看起来没问题」的方向失败。（来源：ps_ui/main.c 第 1058–1065 行）
另一个「不会触发的判据」：本项目早前用 min(B,G,R) ≥ 251 判定饱和，在该采集链路上永远不可能成立——min(B,G,R) 最高只到 248。源码里的结论是：一个不可能触发的判决不是保守判决，而是不存在的判决。（来源：ps_ui/main.c 第 1046–1051 行）
健康读数示例（ps_fft_dual/logs/ps_run.log 第 85–91 行）：裁剪通道 6‰ = 0.60%；用通道字（word 216）= 4411 做交叉核对同样得 6‰ = 0.60%，两次读落在同一帧上；饱和区域 x 76..475 / y 38..181；门限使用 10‰（主机要求 10）→ GATE = 0。另一次运行（同一日志的融合统计段，第 105–114 行）记录 691200 通道中被检查、长曝裁剪 4191 = 0.61%、短曝恢复 0（0.00%）——即双曝光融合在该场景是空转，任何「白点裁剪被降低」的说法都指向另一条流水线。
来源分歧（时间相关，非矛盾）：git 提交 cd69a75 记录当时「当前 NG 并非来自饱和门限（实测仅 0.2%）」，而 ps_run.log 记的是 0.60%。两者是不同时刻/场景的读数，本文并列出，不取其一。

## 3.3 局部闸门与主机判定的区别
（来源：ps_ui/main.c 第 1057–1069 行；submission/dashboard/README.md 第二节、第八节）

## 3.4 面板如何把两者不一致显式呈现出来
面板（draw_panel 的 NG/OK 分支）现在同时打印三样东西：
CLIP xx.x PCT LIM yy.y      <- 证据本身：实测值与它所比较的门限
GATE OK/NG   HOST OK/NG/--  <- 局部闸门的答案 与 主机判定的答案
!LOCALOK                    <- 当 HOST=NG 而 GATE=OK 时追加的显式不一致标记
（随后是相对门限的百分比条、RUN 00H00M04S、LOT --、CAL RMS 0.137 PX、CNN ARG REGS BAD（g_cnn_ok = 0，本构建 WANT_CNN 0））
设计理由（源码注释原文要点）：闸门是本地从像素算出来的，判定是从邮箱来的，两者是不同的东西；在这行出现之前面板只显示主机那一个字，于是「主机判 NG」与「裁剪占比 0.2% 对门限 1.0%」并排放在一起，看起来像系统自相矛盾。一个隐藏这件事的质检显示，比一个把它显示出来的更糟。（来源：ps_ui/main.c 第 1848–1931 行，含第 1881–1897 行的 GATE/HOST/!LOCALOK 逻辑）
判定与显示无关：measure() 与裁剪切点统计直接遍历 DDR 帧，切视图不改变判定；可以在源码注释里读到「VERDICT IS UNAFFECTED either way；no display layout can change what the instrument decides」。（来源：ps_ui/main.c 第 1600–1604 行；dl/HANDOVER_20261016.md §13.1）
合格率口径：板上面板用 (total − ng − unsure) / total（无法判定不算合格），与网页第七节的第二种口径 ok/total 并列出。（来源：ps_ui/main.c 第 1938 行；submission/dashboard/README.md 第七节第 6 条）

## 3.5 面板当前发布的关键结论行

# 四、触摸屏（GT911）

## 4.1 问题陈述
面板的触摸控制器 GT911 在项目自有的 PL axi_iic 通路上始终不应答。本节按时间顺序记录「如何把问题从器件身上移回自己的设计上」，以及最终方案。每一步都带判据。
（来源：dl/HANDOVER_20261016.md §13.2、§14.4、§15.1、§16、§22）

## 4.2 厂商比特流证明 GT911 存活
决定性实验：烧厂商自己的比特流 + 从它 XSA 里提取的 ps7_init（其触摸走 PS I2C0 → EMIO → F20/F19），再从 JTAG 读。脚本 ps_fft_dual/vendor_touch_test.tcl；断电重启后未做 rst -system，直接停核即可读到 OCM，DAP 正常。
结论（范围限 2026-10-16）：面板、GT911、F20/F19 接线、以及本项目所用的协议与地址（与厂商驱动同源：地址 0x5D、产品 ID 寄存器 0x8140、配置表同源）全部正确；当时坏的是「让 PL 的 axi_iic 当 I2C 主机」这条路。2026-10-22 更正：这条结论只覆盖 axi_iic，不能读成「触摸现在可用」。改用 GPIO 位翻转之后，2026-10-16 19:18 还能读到真实产品 ID（0x39313100、ERR=0、0 次永久读失败）；2026-10-16 21:09 那次把 touch_gpio 改成双通道的 BD 改动之后，连 ID 也读不到了（MB_TOUCH_OK=0、PID=0xCCCC0000、ST=0）。即项目在选定的替代路径上又遇到第二个故障，当前状态与判据见 4.6。（来源：dl/HANDOVER_20261016.md §16.1；ps_fft_dual/logs/ps_touch_check.log；ps_fft_dual/bd_cam1_frmptr.tcl；dl/TOUCH_FIX_20261022.md §7）

## 4.3 axi_iic 被逐项否证的过程
（来源：dl/HANDOVER_20261016.md §16.3、§22.2；ps_ui/touch.c 文件头注释）

## 4.4 判据：「对所有地址都 NACK」
把上表收敛成一条判据：
对「存在的」和「不存在的」都给出 NACK  ⇒  是它的应答检测坏了，不是器件不答。
这条判据的价值在于它是可归零的：判据里包含一个已知应当无人应答的地址（负对照）。如果只测 GT911 一个对象，得到 NACK 时既可能是器件问题，也可能是主机问题，无法区分；加上「不存在的地址同样 NACK」这一路，就把可能性收敛到主机侧。源码里的结论是这不在 IP 外面能修。（来源：dl/HANDOVER_20261016.md §22.2 原文引用；ps_ui/touch.h 文件头注释）
交换实验（把「不能用的主机」换成「验证过的器件」，看是不是主机的问题）：把触摸接回 PS I2C1（厂商验证过的控制器家族）、相机1 改挂 axi_iic，重建后在 50 MHz + 中止/复位 + 8 次重试下问相机1 的已知 ID：
RESULT: 0x300A correct in 0/8 attempts, 0x300B correct in 0/8
即 axi_iic 连一个已知答案的器件都读不到。两个独立器件、两条总线、同一个结论 → 交换被否证。代价核算：相机1 必须能配（303 条寄存器，每次上电一次），保留交换等于「用能用的触摸换掉能用的双目」，不划算，已用 bd_swap_touch_back.tcl 回退并重建。（来源：dl/HANDOVER_20261016.md §16.2、§21.2）

## 4.5 最终方案：GPIO 软件位翻转
为什么选位翻转：axi_iic 的控制路径已被逐项否证，而位翻转让每一次边沿、每一个 ACK 都成为我们自己的代码，最不依赖 IP 怪癖。（来源：dl/HANDOVER_20261016.md §22.2、§21.3 第 3 条）

## 4.6 未验证项与语义提醒
一根手指：面板当前是不通的。2026-10-16 19:18 的记录（ps_fft_dual/logs/ps_touch_check.log）里 GT911 还回过真实产品 ID：OK=1、PID=0x39313100、STATUS=0x00、ERR=0，0 次永久读失败；但同一次记录里 EVENTS=0、TAPS=0，即那次也没有观测到触摸事件。2026-10-16 21:09 的 BD 改动（ps_fft_dual/bd_cam1_frmptr.tcl）把 touch_gpio 从单通道改成双通道、把 axi_vdma_2 的帧指针接进通道 2，此后所有测量都是 MB_TOUCH_OK=0、PID=0。2026-10-22 实测：MB_TOUCH_OK=0、MB_TOUCH_PID=0xCCCC0000（诊断标记，不是产品 ID）、MB_TOUCH_ST=0；同轮 MB_FPSX10=190，说明主链路未受影响。固件确实进入 touch_start()、把 GPIO_TRI 写 0x3 释放两条线，而 GPIO_DATA 仍读回 0,0、GPIO_TRI 回读 0 —— 即失败点在第一个 I2C 位之前，线释放后没有回到高电平。根因尚未确定：曾提出的「BD 里 touch_gpio 丢了 C_TRI_ENABLE」已被实测推翻并撤回（axi_gpio v2.0 没有这个参数，双向由 C_ALL_INPUTS=0 且 C_ALL_OUTPUTS=0 决定），目前只把「gpio:1.0 与 gpio_rtl:1.0 的接口绑定使 IOBUF 的 T 悬空」当作待验证假设，不写成结论。视图切换逻辑本身已用主机路径验证（ps_view_dump.tcl 1 + 逐像素 100%，两者修改同一个 g_view），但「手指按下 → 切换视图」仍未验证。（来源：ps_fft_dual/logs/ps_touch_check.log；ps_fft_dual/bd_cam1_frmptr.tcl；dl/TOUCH_FIX_20261022.md §7.1–§7.3；ps_ui/main.c 第 4090–4105 行）
MB_TOUCH_* 的语义是分开的，不能混成「触摸坏了」：MB_TOUCH_OK=1 才是「面板报出了 id 911」；PID=0xEEEEEEEE 是「传输失败」；PID=0 是「传了但读到 0」。（来源：dl/HANDOVER_20261016.md §13.2 末段）

## 4.7 触屏寄存器的地址失配（2026-10-23 定位并修复）
现象：MB_TOUCH_OK = 0、MB_TOUCH_PID = 0，但 PL 里触屏 GPIO 的寄存器读回正常值。真因是地址不一致，不是触屏硬件：
实测：0x41220000 读回 NO ANSWER（AXI 无从设备应答），0x41230000 读回 0x00000003。而 10-20 那份位流里触屏能读出 PID「911.」，说明当时 touch_gpio 位于 0x41220000；10-22 的 BD 改动把它移到了 0x41230000，固件没有跟着改。ps_ui/touch.c:65 自己就写着注释 /* verify against the address editor after the build */。
这条把「触屏坏了」改写为「软件与硬件地址约定失配」，也解释了为什么之前所有查 I2C、查 GT911 上电时序的努力都不收敛：那些都作用在一个 CPU 访问不到的地址上。
修复（2026-10-23 10:51 已实施）：把 ps_ui/main.c:1474 与 ps_ui/touch.c:65 的 TOUCH_GPIO_BASE / TOUCH_GPIO 从 0x41220000 改为 0x41230000，用 ps_ui/build.ps1 重建 ELF。实测 MB_TOUCH_OK = 1、MB_TOUCH_PID = 0x39313100（字节「911.」）、FWID = 30344445。
兼容性提醒：该修改只对 touch_gpio 位于 0x41230000 的位流成立；10-20 那份位流里该 IP 在旧地址上，二者不能共用同一个 ELF。这条与 4.6 的「一根手指」未验证项是两件事：4.6 讲的是「手指按下 → 切换视图」还没人验过，本节讲的是那之前的面板通信本身曾经根本不通。
（来源：dl/REPORT_UPDATE_DRAFT_20261023.md §H；dl/STATUS_20261023_XDC_AND_PROBE.md §三·补；dl/HANDOVER_20261023.md 开头的「触屏也已修好」节（同日 10:51）；ps_ui/touch.c:65、ps_ui/main.c:1474）

# 五、显示质量：闪烁、帧率、撕裂

## 5.1 三条症状的改前/改后（健康上电实测）
配套读数：自由跑 21.02 fps / 撕裂 75%，渲染起点对齐采集翻转后 18.24 fps / 撕裂 5.1% —— 对齐是用帧率换撕裂。健康基线：DDR 跨行 128 ns、PL 读 398 ns、SAME 17.9 ns、OCM 38.6 ns；CHANTOT 始终 691200（内层改动没有破坏统计语义）。（来源：dl/HANDOVER_20261016.md §21.1）

## 5.2 频闪的根因与修法
根因（代码级可定位）：draw_panel 的 NG 分支是 if (g_alarm_blink & 1) { 画红底 }，而 g_alarm_blink 每帧 +1；当前渲染率 ~15 fps → 红底以 ~7.5 Hz 闪烁；而当时场景判定就是「不合格」（GATE=1，饱和告警），所以操作员看到的是持续频闪。修法：把闪烁改成按时间基（由全局定时器导出）约 1 Hz，并发布为 MB_BLINK。（来源：dl/HANDOVER_20261016.md §17.1、§18.1）
验收自己踩过一次：第一版验收脚本 1 秒采一次 1 Hz 方波 —— 混叠，读数无意义。改成 300 ms × 14 次后才有上表 1.07 Hz 的结论。（来源：dl/HANDOVER_20261016.md §21.1 表内判据栏）

## 5.3 帧率：相位分解与两次优化
注：53 → 21 ms 与 36.9 ms 是不同场合的读数（前者是单次优化后的相位，后者是健康上电上 A/B 的相位），量级一致但不等于同一条件，本文并列出。另：cam 相位在坏上电上曾读到 391–565 ms，与 53/120/391 三个互相矛盾的读数同属一节量具教训（见第八节）。（来源：dl/HANDOVER_20261016.md §17.2、§18.1、§19.3、§21.1）
双曝光融合当前是空转：recovered under full scale = 0（0.00%），因为 6.5× 的短曝采样对每个过曝通道仍过曝，钳位后与长曝一致；且 g_bracket_on == 0（单曝光）时融合本来就无意义却仍在跑。这是帧率的候选优化方向之一，但收益需要实测确认（§17.2 已注明「需要实测确认收益」）。（来源：dl/HANDOVER_20261016.md §17.2；ps_fft_dual/logs/ps_run.log 第 105–114 行）

## 5.4 撕裂：完整因果链
本节讲的是相机1 整幅视图的撕裂（相机0 的 MB_TEAR 结果见 5.1）。链条的每一环都有实测：
未验证的数字：任务上下文给出的「等待交接后 0.36%」在仓库内查不到来源。已检索 *.md、*.c、ps_fft_dual/logs/*.log、ps_ui/*、git log 全文（含备份目录），撕裂相关的可核对值只有：13–20%（原）、1.09%（3/274，交接等待后）、0.00%（守卫后，提交信息）、9.76%（4/41，交接等待前）、以及相机0 的 75.1% → 5.1%。0.36% 本文按未验证处理，不写入结论。
期间被推翻的一版修复（记录在案，不是悄悄删掉）：第一版用「读帧存首字两次看是否在变」来判断哪块正在被写。它不可能可靠 —— 探针只能说明某块现在空闲，永远说不出它的写是从什么时候开始的，因此剩余安全时间未知；实测得到 16.5% 的包裹率，每一次都是穿过画面中部的接缝。随后接入相机1 自己的帧指针（axi_vdma_2/s2mm_frame_ptr_out 原本悬空，2026-10-16 接到 touch_gpio gpio2_io_i，立即可读、DATA2 以 ~18 Hz 在 0/1 间翻转），直接问「哪块正在被填」；但极性/位选择未归零：INVERT=0 时包裹 45%、INVERT=1 时 28%。真正的剩余问题是拷贝起点在相机1 帧内是任意的 —— 这就是 5.4 表中「等待交接」要解决的。（来源：ps_ui/main.c 第 1644–1651 行；git 提交 2c59e1c、d3c57d6、5565ca1）
撕裂带宽的量化与「不改 BD」的决定（画中画时代，结论对整幅视图仍然有效）：窗口读时间 × 采集行速率 = 撕裂带。ps_capture_rate.tcl 用帧指针探针位实测采集行速率 18.24 帧/秒、54.8 ms/帧、13.13 源行/ms。
仅在「读与写重叠」的帧里出现（约一半），且当时场景静止，放大快照看不到接缝。决定：不改 BD（代价是改图 + 重新综合约半小时，且有 B17 那类风险，收益是消除一条 ≤4 行、静止场景看不见的带子）。根治方法已写明：把 axi_vdma_2/s2mm_frame_ptr_out 引到一个空闲探针位。（来源：dl/HANDOVER_20261016.md §12.2、§12.3；ps_fft_dual/logs/ps_capture_rate.log）

## 5.5 被取代的读数（画中画时代，仅供溯源，勿与现状混用）

## 5.6 黑屏、颜色与其它显示事实
屏幕全黑的真因：重烧 PL 会把 v_tc 复位成关闭，而引导脚本从没配 v_tc → 没有时序输出 → 没人消费显示 VDMA 的流 → 通道报「运行中」而整帧永不完成 → 面板全黑。而 DDR 里的画面一直完全正确，所以那几张截图看起来完美。判据：显示通道 SR 的 IOC(bit12) 修前 6 次读全 0，修后 8/8 置位；v_tc CTRL 由 0 变为 0x03F7EF06；HORIZ/VB = 0x420 / 0x01F901F9（写入已核验）。教训：截图是 DDR 的转储，它证明不了面板收到任何像素。（来源：dl/HANDOVER_20261016.md §14.1）
显示双缓冲第一次真正生效：DIS CR 的 bit8 不存储，所以原来的「翻转」是空操作，通道一直停在帧存 0（撕裂 + 一半工作从没显示）。改用 park 模式 + PARK_PTR（实测每帧翻转 84 次 / 4.36 s，与 19.5 fps 同步）。（来源：submission/README.md「当前状态」节）
颜色：根因是 AN970 的 40 针接插件上 LCD 数据位成对颠倒（B6,B7,B4,B5,B2,B3,B0,B1），而 XDC（与厂商 lcd_test.xdc 逐脚相同）按顺序分配。修法是只改约束：把 vid_io_out_0_data[2k] 与 [2k+1] 的 PACKAGE_PIN 成对对调（12 对 / 24 条），不动 RTL / BD。（来源：submission/README.md「当前状态」节）
已知限制：采集链路仍是 RGB565（5:6:5，65536 色），而 AN970 是 24 位面板；瓶颈在本项目自己的 cmos_8_16bit.v 与子集转换器。（来源：submission/README.md「已知限制」节）
一块「纯色」区域出现四色等量，就是 32 位字写进了 3 字节像素：实测面板背景曾出现 16992/16392/16386/16318 四色近似等量，根因是 gcd(3,4)=1 → 每个字比上一个多走一个字节相位。修法是 12 字节（4 像素 = 3 字）图案重复。（来源：ps_ui/main.c 第 1089–1109 行）

## 5.7 帧率与画面质量的基线（2026-10-20 实测，2026-10-22 复核 19.0–20.0 fps）
本节补入 10-20 的三组对照，全部在健康上电（断电重启后一次引导）上取得，脚本为 ps_fft_dual/measure_fps.tcl（帧计数差分）与 ps_fft_dual/phases.tcl（MB_T_* 相位和 ÷ 次数）。 2026-10-22 复核：主链路仍为 19.0–20.0 fps（DDR 邮箱 MB_FPSX10 = 190，即 19.0 fps），显示配置 CR=0x00010003、HSIZE=2400、DLYS=2400、VSIZE=480，自动曝光已收敛（state=1、exp=2666、mean=160、clip=0）；当轮 WANT_DIFF=1。下表 18.00 fps 是 10-20 关掉双曝光融合时的读数，两者配置不同，不可互换。
① 双曝光融合是帧率的唯一瓶颈，不是带宽也不是渲染。关闭融合（g_bracket_on = 0）与打开时，同一套比特流、同一场景、同一曝光设定，测得：
判读：两行的非 sync 相位几乎相同（差 0.3 ms 以内），全部差值落在 sync 上——即每帧等多一次交接。这与此前记录的“融合 19 fps → 8 fps”方向一致，本次给出了相位分解证据，不再只是帧率读数。
② 曝光与增益是“画面暗、看着糊”的两个独立量。板端实测（同一场景、同一工作距离，以全帧平均亮度与平均梯度 |dL/dx| 为判据）：
判读：增益从 27 提到 64 使亮度翻倍、梯度接近翻倍；对焦再贡献 40%。三者中任何一个缺失，画面都会被认为是“糊”，而三者的修法完全不同（改寄存器 / 改寄存器 / 动物理镜头）——这是本次把主观“糊”拆成可测量的过程。
③ 一条被撤回的假设（记录在案，不悄悄删掉）：10-20 曾判断“固件写的曝光从未生效，因为多字节 I2C 写污染了相邻寄存器”。当晚把 0x3500/0x3501/0x3502 直接读回，得到 00 / 0B / B8，即 0x0BB8 = 3000，与请求值逐位一致 —— 写入一直是正确的，该假设撤回。真正的原因是增益停留在模式表的 0x1B，以及镜头没有在当前工作距离上对焦。
④ 一条操作结论：普通室内照明下，曝光 3000 + 增益 0x40 即可得到可用的质检画面，不再需要暗箱；但强光直射下的表现未测，不写入结论。
（来源：ps_fft_dual/measure_fps.tcl 与 phases.tcl 的当次输出；git 提交 ccbe7f9、801e3db、688c0f3 的提交信息；ps_ui/cam_i2c.c 的 cam_set_gain_bus()；ps_ui/main.c 的 CAM_LONG_L/CAM_LONG_R/CAM_GAIN 宏）

## 5.8 显示通道的模式位：Circular_Park（2026-10-21 发现，2026-10-23 三条证据确认）
现象（操作者描述，人眼判定）：屏上有完整 UI，但画面静止、并且持续频闪。10-21 与 10-23 两轮排查指向同一个根因，本节把两轮证据合在一起写，因为它们是同一个缺陷的两个侧面，分成两节只会让读者以为出现了两次。
根因是显示通道 AXI VDMA 的工作模式位。MM2S_VDMACR 的 bit1 是 Circular_Park：0 = Park，1 = Circular（PG020），而该链路脚本的源码注释与写入值（0x00010003）都按「1 = Park」处理。于是显示端在两块帧存之间按扫描率循环扫描；而两块帧存里是两帧不同的画面（实测 UI_A = 0x10800000 与 UI_B = 0x10A00000 的前 8 个字完全不同），二者按帧率交替出现，人眼看到的就是「静止 + 频闪」。
2026-10-21 的判定（当时固件里加了一条主机命令）：MB_CMD = 8 把即将翻转的缓冲整帧涂成一种颜色（A 蓝、B 红），命令不清零所以图案保持。同一图案下：循环模式时面板呈现两色按扫描率混合的紫色闪烁；把 bit1 改为 0 后，变成每次渲染换一次颜色（可数）。据此把 CR 改为 0x00010001（RS = 1、Park、帧计数使能），并同步修正 ps_run.tcl。复核（可重放）：xsdb ps_fft_dual\disp_vdma_regs.tcl 读到 CR = 0x00010001、ADDR1 = 0x10800000、ADDR2 = 0x10A00000、PARK_PTR 的 bit0 跟随渲染目标。
2026-10-23 的三条独立证据（缺一不可）：
① 配置面：脚本写 0x00010003，即 bit1 = 1 = Circular；
② 内容面：两块帧存内容显著不同，交替显示必然产生闪烁而不是撕裂；
③ 因果面：把显示 CR 改成 0x00010001（RS = 1、Park）后，回读确认 bit0 = 1 且 bit1 = 0，操作者确认「不再频闪，只剩一张静止画面」。
这一条的价值在方法上：频闪既可能是时序/像素时钟问题，也可能是扫描模式问题，二者在屏上看起来很像。用寄存器回读（模式位）+ 帧存内容比对（是否两块不同）把二者分开，比换时序参数快得多。
两条就地更正（2026-10-23）：5.6 记的「改用 park 模式 + PARK_PTR」是按错误的位定义解释的读数——那时写进去的是 Circular（bit1 = 1），PARK_PTR 的翻转因此不能当作「停在选定帧存上」的证据，真正的 Park 是 0x00010001；5.7 的 10-22 复核记下 CR = 0x00010003，那是修复前的值，不是正确配置。5.2 记的是另一种频闪（NG 分支按渲染帧率闪红底，已改成时间基约 1 Hz），与本条不是同一个成因，修法也完全不同。
（来源：dl/REPORT_UPDATE_DRAFT_20261021.md §A；dl/REPORT_UPDATE_DRAFT_20261023.md §G；dl/HANDOVER_20261023.md §一；ps_fft_dual/disp_finish_20261023.tcl（写 0x00010001 并回读两种状态）；ps_fft_dual/disp_vdma_regs.tcl（只读复核））

## 5.9 自动曝光闭环：量具与算术缺陷（2026-10-21 修复）
自动曝光在 2026-10-21 之前「不收敛」的原因不在控制律，在量具，两个独立缺陷：
① 发布字全部撞号。控制器先后把状态/曝光/亮度发布到邮箱 132–134 和 137–139，而这六个字号分别属于 MB_ARM_EXP / MB_ARM_PHASE / MB_LASTDONE 与 MB_PAIR_N / MB_MEAN_RENDER / MB_LONG_EXP。于是「亮度 34–45‰」读到的是整块面板的渲染均值，「状态 0」读到的是融合关闭时的配对计数，而控制器自己的均值被写进了主机的模式字 MB_LONG_EXP——cam_bracket_arm() 会把它当长曝光行数读回去。
② 均值 32 位溢出。(g_mean_acc * 1000) / (g_mean_n * 255) 的分子是 230,400 个样本的和（约 1.57e7），乘 1000 会在 32 位上绕三圈，商恒落在 40–70，与光照无关。
修正后（AEC 自有字 144/145/149/151–153，先除再乘）同一场景 12 s 采样：状态恒为 1（已收敛）、曝光恒为 1871、亮度均值 215–254‰、裁切门未触发。
控制律另修两处算术缺陷：加亮 ×9/8 配压暗 ×7/8 一个来回乘出 63/64（每轮掉 1.6%，只会走不会停），改为 ×8/9；裁切千分比在相邻两次评估之间会 4↔11 跳（高光斑），12.5% 步长下这点噪声足以驱动极限环，因此换向要连问两次（同向不延迟），决策码发布在 154–156 供事后核对。
死区下界取 150‰ 而非 200‰：实测曝光 1478 时均值 192‰ / 裁切 4‰，曝光 1871 时均值 231‰ / 裁切 6–11‰、门已被触发——200‰ 正好是开始裁切的亮度，「够亮」与「不裁切」在该带内不能同时成立。
（来源：dl/REPORT_UPDATE_DRAFT_20261021.md §B；ps_ui/main.c 的 AEC 字定义（144/145/149/151–156）与 aec_control() 的算术；当次 12 s 采样的邮箱读数。5.7 的 10-22 复核记 exp = 2666 / mean = 160 / clip = 0，那是另一个场景、另一套死区设定下的收敛点，两处数值不可互换）

## 5.10 触摸放大通路的取样错误（2026-10-21 修复）
触摸放大此前并非 1:1。放大分支沿用 wstep = 3（每次消耗 4 个源像素），却仍读 6 个字（8 个源像素）并套用概览的 2×2 盒式平均，于是输出像素 n 读的是源像素 n + (n mod 4)：水平 2:1 挤压、每 4 像素重复一次、并带 2 抽头模糊。右相机裁剪从 x = 640 起，末块还会读到下一行前 4 个像素；融合的短曝光在两种模式下都按 k*6 取样，与长帧相差 2 倍坐标。
修正后：放大按 3 字 = 4 像素单行直通复制，短曝光同坐标。
复核（主机侧，可重放）：放大模式下 corr(UI 第 200 行, 相机第 380 行 x = 0..639)= 0.980（1:1 模型）对 0.949（旧锯齿模型），与 source[2x] 的相关系数为 −0.16。ps_ui/check_layout.py 现在对两种映射建模，wstep 一改即构建失败。
（来源：dl/REPORT_UPDATE_DRAFT_20261021.md §C；ps_ui/main.c 的放大分支；ps_ui/check_layout.py）

# 六、标定

## 6.1 结果

## 6.2 方法
采集：stereo_calib_capture.tcl 抓取 20 对左右 raw 帧（每帧 1280×720 RGB888 = 2764800 字节），存于 calib/。（来源：dl/stereo_calibrate.py 文件头；dl/HANDOVER_20261016.md §三）
角点：用 cv2.findChessboardCornersSB（9×6 内角点，EXHAUSTIVE | ACCURACY | NORMALIZE_IMAGE）+ cornerSubPix 精修。
求解：calibrateCamera 各求内参+畸变 → stereoCalibrate 求 R/T（固定内参）→ stereoRectify → remap → StereoSGBM 在校正后的图上求视差。
验证纪律（脚本文件头写明「不重复 M25 那个错」）：把成功的图对分成标定集与留出集，标定集求内参/外参，留出集只用来量极线垂直残差，看校正是否真的成立；只报留出集数字，标定集数字只作参考。
棋盘格尺寸：在手机屏幕上显示、物理尺寸未知，方格边长取 1.0。脚本注明这不影响内参与校正，只影响 T 的绝对尺度，而本项目不需要绝对距离。
（来源：dl/stereo_calibrate.py 第 1–44 行）

## 6.3 一次被修正的失败（为什么换检测器）
老的 findChessboardCorners 对棋盘格在画面里的朝向（转 90/180 度）会让返回的角点起始位置变化，于是与固定的物体点一一对应不上，标定被污染。实测症状：左相机标出 cy = −77（图像中心的 y 不可能为负）、立体标定 RMS 7.1 px、校正后垂直残差 8e6 px —— 完全崩。改用方向鲁棒且自带亚像素精度的 SB 版本后，才得到 0.137 px。（来源：dl/stereo_calibrate.py 第 58–63 行）

## 6.4 局限（如实列出）
0.137 px 是留出集上量到的重投影/极线残差，它证明的是「标定与校正的几何链条一致」，不等于「两个视角已经可以逐像素对齐做稠密立体」。
校正后两图仍未对齐、视差搜索饱和在 255 —— 需继续调 alpha、视差搜索范围与匹配代价参数；这部分工作未完成。（来源：dl/HANDOVER_20261016.md §四②）
该数值在板上是常量（不是实时测量）：main.c 里没有任何标定字，面板与网页都把它当作「记住的结果」打印；网页侧 calibration.from_board = false，source 标注为交接文件。（来源：ps_ui/main.c 第 1921–1928 行；submission/dashboard/README.md 第二节、第七节第 4 条）
方格边长取 1.0（任意单位）意味着 T 只有相对尺度；任何需要绝对基线长度的量都不可由此得出。

# 七、与网页质检台的数据契约

## 7.1 链路与文件
板载 PS -> 邮箱 0x10F00000 -> ps_status_read.tcl（只读 mrd，不写任何一个字）
-> dl/status_feed.py -> status.json / status.js / status_trend.json -> index.html（页面 1.5 s 轮询）
（来源：submission/dashboard/README.md 第一节、第四节）

## 7.2 状态 JSON 模式
schema             "trustscope.dashboard.status/1"   版本号，页面据此判断能不能读
generated_at(_epoch)  本次读取的墙钟时间（主机记录）
source             kind/transport/mailbox_base/xsdb/reader_tcl/timeout_s/read_ok/
severity/error/magic_expected/magic_read/magic_ok/words_read
stale              true = 不要相信里面的任何数字
stale_reason_code  stale_no_link | stale_partial | stale_magic | stale_magic_err |
stale_frozen | stale_no_board_forced
stale_reason       上面那条的中文说明（页面直接显示）
board_time         恒为 null；board_time_note 说明原因
verdict            code(0/1/2/9/null) / label / known / reason_code / reason / reason_source / checks[]
production         total/ok/ng/unsure/pass_rate_pct/ok_rate_pct/alarm_last_12/
inspection_rate_per_s/definitions
quality            clip_pm / clip_limit_used_pm / gate_tripped / clipped_channels /
channels_total / saturated_bbox_px …
classifier         engine_score(MB_SCORE) / cnn_status("unavailable") / cnn_logits(null) / cnn_note
calibration        stereo_rms_px 0.137 / mono_rms_px / from_board=false / source
system             ps_frames / progress / mmu_sctlr / camera_id / i2c_* / timer_ok / tear* / thumb_n
snapshots          note（是快照不是视频流）+ 每个文件的 mtime / age_s / bytes
trend[]            本脚本自己累积的采样点（只认真读板子时的数据）
（来源：submission/dashboard/README.md 第三节；submission/dashboard/status.json 实例）

## 7.3 陈旧时必须不显示数字（核心契约）
一条贯穿全表的规则：stale=true 时，verdict 之外的所有数值字段一律是 null，不是 0。0 是一个合法的测量值，「读不到」必须与「读到 0」区分开。（来源：submission/dashboard/README.md 第三节末段、第五节）
magic 不匹配的含义：0x10F00000 那块内存里没有本程序发布的遥测 —— 板子没在跑、主机侧没在推送、或者读错了地址；magic 不对时里面的每个字都可能是别人的数据，所以一个数字都不显示。（来源：submission/dashboard/README.md 第五节）
status.json 的实例状态（本轮交付、未连板）：stale=true、stale_reason_code=stale_no_board_forced、source.read_ok=false、words_read=0，verdict 与 production/quality/system 全为 null —— 这正是契约在起作用。（来源：submission/dashboard/status.json）

## 7.4 已核实 / 未核实的划分
（来源：submission/dashboard/README.md 第六节）

## 7.5 main.c 里找不到的字段（页面写「不可用」而不是编一个）
CNN 分类器输出（logits/类别）：没有。ts_cnn_top 把两个 logits 写到 CNN_ARG_LOGITS（0x43C30000 + 0x4C，见 ps_ui/cnn_drv.h），main.c 没有把结果搬进邮箱，也没有任何 MB_* 字承载它。MB_SCORE 是主机侧的面积×对比度分数，不是 CNN 输出。
工件条码 / 工单号：没有。邮箱里没有件号、没有序列号。
板载时间戳：没有。main.c 不发布任何日历时间，邮箱里唯一的时间相关计数是 MB_PS_FRAMES；页面的 generated_at 是本次 JTAG 读取的墙钟时间（由主机记录），board_time 恒为 null。
不合格的其它原因：邮箱只发布饱和这一条质量门限；缺陷分数/阈值只存在于主机侧。当 MB_VERDICT=1 而门限没置位时，页面明说「能确定不合格，但板上给不出原因」，不编一个。
逐件历史：没有。邮箱只有累计计数，趋势图是本脚本自己采样出来的序列。
MB_PS_FPSX10：声明了但不是一个独立字段 —— 它与 MB_PROGRESS 都是 word 11（byte 44），PS 每帧往那里写阶段号 1..7，所以读出来不是帧率。该字已移到 word 122，主机写入点改为字节 488；页面不显示它，status_feed.py 把它当 progress 记录。
快照不是视频流：板子到 PC 没有网络通路，1.15 MB 走调试线。实测 dump+转换约 2.1 秒/次（首次 7.7 秒含 xsdb 启动），页面 5 秒轮询是宽松的；判断这张图多新要看跑 live_view.py 的终端，页面计数器只说明浏览器在轮询。缩略图方案：PS 自己生成两张 160×90 缩略图写在 0x10C00000 / 0x10C10000 连续两槽，主机一次 128 KB 传输把两张一起取回；交接用 .done 标记文件（内含 PS 自己的缩略图计数器），所以不会读到写了一半的图，也能看出「流还在不在」。
（来源：submission/dashboard/README.md 第八节、第七节、第二节；dl/HANDOVER_20261016.md §14.2、§15.3）

# 八、验证方法学与真实故障记录
本节是全文的重点。它回答一个问题：这个项目是如何学会「不轻信测量」的。所有案例都有真实代价记录，不是预防性罗列。案例编号（T=工具与构建、M=测量与证据、B=Block Design 与 Tcl）对应 skill/pitfalls/ 下的案例集。

## 8.1 判据必须具备的形态

## 8.2 真实故障记录

### （1）B17：删网络删掉了全局时钟
事故：清理 axis_switch 时写了 `foreach p [get_bd_pins cam_switch/*] { foreach n [get_bd_nets -of_objects $p] { delete_bd_objs $n } }`。`get_bd_nets -of_objects <pin>` 返回的是「这条引脚所在的那一条网络」，而 cam_switch/aclk 连的是 processing_system7_0_FCLK_CLK0 全局时钟网络 —— 于是整条时钟分配网络被删掉，45 个引脚全部悬空。发现方式：验证时报 ERROR [BD 41-758]，列出 /processing_system7_0/M_AXI_GP0_ACLK、S_AXI_HP0_ACLK、/proc_sys_reset_0/slowest_sync_clk、/axi_vdma_0/s_axi_lite_aclk 等一片时钟引脚没有有效源。恢复：靠 backups/20261015_212453__before-2vdma 里的 BD 文件。
纪律：删 cell 之前先想清楚它的引脚上挂的是什么网络；时钟/复位这类全局网络绝不能靠「删引脚上的网络」来断。断某一处连接用 disconnect_bd_net，或直接删 cell 让工具处理它独占的网络；删之前先打印「这条网络挂载了几个引脚」，挂载引脚数 > 1 就绝对不能直接删。BD 改动永不删 cell；断线前先断言那条网只有 2 个端点；每步后断言全局时钟网引脚数只增不减。（来源：skill/pitfalls/block-design-traps.md B17；dl/HANDOVER_20261016.md §五；§22.3 记录「删除旧接口端口时时钟网 51 未掉」；§21.2 记录「全程断言时钟网引脚数(51→51)」）

### （2）B18：验证闸门看返回值，等于没有闸门
事故：把「validate 通过才保存」写成 `set vok 0; catch { set vok [validate_bd_design] }; L "validate 返回 $vok"; save_bd_design`，保存是无条件的；更「严谨」的一版写成 `CHK {$vok == 1 || $vok eq ""}`，而 validate_bd_design 在成功和失败时都可能返回空串 ⇒ 条件恒为真。闸门形同虚设，把删掉全局时钟的设计保存了。
正确做法：查验证产生的 ERROR 消息数量，不看返回值：
reset_msg_config -severity {ERROR} -quiet
set before [get_msg_config -count -severity {ERROR}]
catch { validate_bd_design }
set after  [get_msg_config -count -severity {ERROR}]
if {$after > 0} { error "验证产生 $after 条 ERROR，拒绝保存" }
save_bd_design
三条教训：闸门必须真的能拦住（恒为真的条件不是闸门，是装饰）；判断依据要选对对象（判断验证是否通过要看它报了什么错，而不是看它返回了什么）；闸门要能自证有效（故意造一个错误设计跑一次，确认它真的拦住）。（来源：skill/pitfalls/block-design-traps.md B18；dl/HANDOVER_20261016.md §三①②、§五）

### （3）B19：备份工具在含空格的路径上静默失效
事故：恢复 BD 时执行 python dl/backup.py restore <备份名>，输出「* 源不存在，跳过: ...\trustscope\D_/BaiduNetdiskDownload/Vivado/two」然后照样打印「完成」；文件的 MD5 一点没变 —— 什么都没恢复。根因：MANIFEST 的格式是 <路径> <字节数> <sha256>，路径在最前面，而路径里有空格（本项目的 BD 就在 `two FFT.gen` 下），解析时 line.split() 把路径切成好几段，取 parts[0] 只得到前半段，拼出来的源文件当然不存在。更坏的地方：restore 对「源文件不存在」只打印一行提示就继续，最后照样说「完成」。
修法（两处）：格式改成 <sha256> <字节数> <路径> 并用 split(None, 2) 解析；回写后立刻校验哈希并把结果打出来。教训：「完成」这个词必须被证据支撑 —— 工具打印「完成」之前，要确认它真的做成了它该做的事（这里是文件真的被回写了）。这条与 B16/B18 同族：一个环节「没报错」，于是上游以为它成功了。（来源：skill/pitfalls/block-design-traps.md B19；dl/HANDOVER_20261016.md §二）

### （4）M25：没有对照组的「对比测试」不成立
事故：判断「第二路相机有没有数据」时，dump 两块内存、间隔 1.5 秒、比较内容，得到「两帧相同」，于是下结论：第二路没有数据。那个结论是不可信的，因为：那次 dump 用的是 `targets -set 2`，而该编号当时指向正在运行的 CPU 核；在运行中的核上 mrd 会失败；读失败返回 0xFFFFFFFF；两次都失败 → 两次都得到同样的 0xFFFFFFFF → 「相同」。
修正后的做法（带对照组）：先用已知答案证明读通路有效（CAP SR 应等于已知好值 0x00015810）；再同时采「已知在变的」与「待判定的」：相机0 帧存（对照）与相机1 帧存（待判）。实测：
读通路自检 = 有效
相机0 帧存: 24/32 个字不同      <- 对照组成立
相机1 帧存:  0/32 个字不同
这次结论才成立。教训：任何「A 和 B 不同/相同」的结论，都必须先有一个「已知应该不同」的对照组通过，否则你测的是「你的方法有没有在工作」，而不是「被测量的对象」；「两次都失败」在数值上表现为「两次都相同」，判据里必须包含「这次读到的是不是一个有效值」，而不只是「两次是否一致」；交付话术上，说「X 没有变化」之前，先说出你凭什么相信这次读到了 X。
（来源：skill/pitfalls/measurement-traps.md M25；dl/HANDOVER_20261016.md §四1、§五）
同一纪律在别处救了一次：画中画逐像素校验最初得到 `4936/25560 精确相同，平均差 13`，而错位一像素的错误映射是 4278 —— 区分度太弱。当时并没有据此宣布「窗口不是相机1」；查明原因是判据设计错了：dump 与「渲染那一刻」相差若干帧，静止场景也有传感器噪声。正确顺序是「先冻采集 → 让 PS 再画一帧 → 再停核」，此时参考帧与窗口必然逐字节相同；改顺序后 25560/25560 = 100.00%（错位映射 18.90%）。同一教训在视图1 上重演一次：顺序反了只能到 ~19%，看着像「显示了错误的相机」。（来源：dl/HANDOVER_20261016.md §10.3、§11.1、§13.1）

### （5）把静态残留当成实时状态
案例一（M1）：用 ILA 观察信号时看到一段非常干净、稳定、完全符合预期的波形 —— 干净到不像真的。根因是 ILA 显示的是该触发位置最近一次捕获到的数据，新配置生效之前就触发过一次，屏幕上一直是旧数据，它不会因为你改了设计就自动刷新。排查办法是主动改变被测信号再重新触发，看波形跟不跟着变：跟着变是实时数据，纹丝不动极可能是残留。本案例直接催生了本作品的核心功能之一（可信度警告：「未检测到新数据，可能是残留」）。相关的还有 M15（读了滚动窗口的错误一端，把一秒前的文本当成实时状态）与 M16（分项之和对不上总数，是识别「残留数据」的唯一线索）。（来源：skill/pitfalls/measurement-traps.md M1、M15、M16）
案例二（本项目自己的脚本）：ps_run.tcl 的「是否已停」判据是反的。AXI VDMA CR 的 bit0 = RS：1 = 运行、0 = 停（本项目自己的脚本用 0x00010003 启动、0x00000000 停止），而脚本写的是 `if {$cr & 1} { 重新武装 }` —— 在跑的时候才重新武装，停着的时候什么都不做；随后又无条件打印 `capture running`（一句永远不会为假的「检查」）。后果：stereo_both.tcl 结尾会停掉两路采集（它要静止帧来 dump 立体图对），自那以后每一次 ps_run.tcl 的运行都没把采集重新打开，PS 一直在渲染一帧静止画面 —— 而日志写着 capture running。
是 1c 段的对照检查把它揪出来的：对照（相机0）采样 0/32 在变 → 测量判为 VOID，没有据此得出「相机1 坏了」的结论（这正是 M25 想防的事）。修好之后：capture before: CR=0x00010000（停的）→ 重新武装 → CR=0x00010003 / SR bit0=0；1c 段「对照 22/32、相机1 20/32」都在变。新增的是断言而不是说明文字：武装后必须 CR bit0=1 且 SR bit0=0，否则整轮判失败。（来源：dl/HANDOVER_20261016.md §10.2）
案例三（自本次上电累计的计数器）：MB_TEAR 是自本次上电累计的，一次读到的 92% 是旧上电里包含 cam1 实验时段的历史值，曾被当成当前现象；另一个同类错误是脚本把 MB_VIEW 的字索引（86）当成字节偏移（344），于是所有用 mwr 设 view 的验证都无效，已全部改正并用变量 g_view 交叉验证 override 本来是好的。同一夜里还给新增的邮箱字 320..340 做了清零，理由正是「防静态残留被当成结果」。（来源：git 提交 2c59e1c；dl/HANDOVER_20261016.md §9.1）
案例四（活着的寄存器会给出撕裂值）：PARK_PTR 在 0x00000001 与 0x00010001 之间交替（bit16 跟着 bit0），而第一版 ps_view_dump.tcl 拿整字去比 0/1 ⇒ 报出 PARK_PTR=65537 is neither store，看起来像硬件故障，其实是判据太严；已改为掩码 & 0x1F。同一节的第二条：脚本在 dump 前 FATAL 时旧文件会被当成结果 —— 那次 verify_view.py 报 6.09% 与 5.94%，是它读了上一轮的 ui_view.bin。判据要能区分「这次真的转储了」：转储脚本的 `dumped N bytes` 行必须出现，否则结论无效。（来源：dl/HANDOVER_20261016.md §22.5）

### （6）仪器先说真话，再用它
这一族是本项目最贵的一课，共六例：
① 先校量具，再谈异常。项目曾把 1675 ns 这个 25 倍的异常直接当地基去推硬件，而没有先校正量具。补做之后结论是「量具没问题、异常是真的」，但流程本身当时是错的。补做的内容：加已知答案对照 —— SAME（反复读同一个字，首次后必在 L1）16.4 ns、OCM（片上 SRAM）61.7 ns ⇒ 量具能分辨「命中」；而 DDR 1743 ns、PL 3713 ns 仍然慢 ⇒ 慢是真的，不是我读错。（来源：dl/HANDOVER_20261016.md §20.1 第 2 条、§20.2）
② 用 tick 计时的量测不出「CPU 自己变慢」。global timer = CPU/2，tick 是 CPU 派生的，所以任何 tick 计时的量都测不出「CPU 自己变慢」 —— 若 CPU 实际只有 83 MHz，DDR = 1743 ns 会看起来不变。因此新增 MB_CMD = 3：2 亿次纯寄存器迭代，由主机墙钟计时（独立参照），给出真实 MIPS；并给出 host/timer 比值作为「定时器被静默重配」的判据。
而这台新量具的第一版本身是坏的：编译器把 2 亿次循环当死代码删掉了（BUSY_TICKS=3，于是报出不可能的 1379 M/s）。修法是把 bench_dummy 改成 volatile，并把基准改成 4 个独立累加器（单链是串行依赖，54 M/s 描述的是链延迟不是核心）；实测 182.8M iter/s ⇒ CPU 就是 666 MHz。
另一条同族修正：tick→ns 必须按活着的 ARM_PLL FBDIV 现算。上电时 FBDIV=26（定时器 216.7 MHz），我们 ps7_init 之后才是 40（334.8 MHz）；用固定值会在 A/B 之间制造出 1.5 倍的假效应。（来源：dl/HANDOVER_20261016.md §20.1 第 3、4 条；git 提交 ebdaf1a、ab3aed5）
③ 读正在运行的核：mrd 会间歇失败并返回 -1。把 -1 当值读，就会看到「帧计数 185 → 14」、`frames: -1 -> 44 -> -1`，于是得出「程序在自我重启」的结论 —— 它根本没重启。所有在跑的板上读数必须重试，并且把重试/失败次数打印出来（ps_phase_measure.tcl 与 ps_ab_lr.tcl 现在都这么做，输出里的 READ HEALTH 就是它）。（来源：dl/HANDOVER_20261016.md §18.4 第 1 条）
④ 采样率不够就是混叠。ps_capture_rate.tcl 自己写着「必须远慢于 7/s，否则是混叠」，而它正是在 3 Hz 上用了 7 Hz 采样。要么提高采样率（PS 紧循环，MB_CMD=1），要么承认这个数不可用 —— 不要在它上面建结论。同类：第一版闪烁验收脚本 1 秒采一次 1 Hz 方波，同样混叠。（来源：dl/HANDOVER_20261016.md §18.4 第 3 条、§21.1）
⑤ 窗口和必须除以同一窗口的次数。MB_T_* 是「每 32 次循环的窗口和」，把窗口和当累加和、或把两个时刻的值相除，会得出 53/120/391 ms 三个互相矛盾的「cam 相位」。ps_phase_measure.tcl 现在先读 N、读和、再读 N，两次一致才采纳。（来源：dl/HANDOVER_20261016.md §18.4 第 2 条）
⑥ 诊断通道够不到目标时不要放弃，也不要外推。JTAG 能读 0x11200000，但 JTAG 不走 MMU，PS 走 —— 把「JTAG 能读」外推成「PS 能读」是错的，我因此在板上跑飞（faultcode = 0x11111104，DFAR = 0x11200000，prog = 3、frames = 0）。修法是先只改 MMU，再单独验证。（来源：dl/HANDOVER_20261016.md §四①、§9.1；ps_ui/mmu.c 第 141–149 行）

### （7）CPU 停机 ≠ 采集停机
判据设计上的一个结构性事实：停掉 CPU 并不会停掉 PL 的采集。因此「停机后读帧存再逐像素比对」这类判据不成立 —— 停机只是冻结了 CPU，帧存仍在被采集改写。已记录在提交 e28b81b 里。两个脚本因此各有单向能力，不能互相替代：
（来源：dl/HANDOVER_20261016.md §12.2、§13.1；git 提交 e28b81b；ps_fft_dual/ps_live_snap.tcl 文件头）
同一族的另一条（B 系列）：CPU 停机本身也有判据 —— 停机后「逐帧存比对」不可用时，项目用「端到端相干性判据」（停机后读 STORE 再转储对应帧存逐像素比对）替代。（来源：git 提交 5565ca1 信息）

### （8）缓存假设过时
事故形状：main.c 头部长期写着「MMU AND D-CACHE ARE OFF ON PURPOSE」，而 MMU 与 D-cache 早已打开（板上 SCTLR = 0x08C5107D）。上一轮正是据这句过时注释去推断 0x11200000 的可达性，导致板上跑飞。该注释已在 §9.1 与负对照实验一并改掉。教训：代码注释也是一种「测量结论」，同样会过时，同样会误导；判断缓存状态要看活着的寄存器，不要看注释。（来源：dl/HANDOVER_20261016.md §9.1；ps_fft_dual/logs/ps_run.log 第 49 行）
配套的缓存/DMA 纪律（每一条都对应一次有代价的失败）：
L2 开不开决定要不要额外编程 L2C-310：先去读它的 Control 寄存器，本队读出 0x00000000 ⇒ L2 是关的，所以只有 L1，DCIMVAC/DCCMVAC 就够了。（坑 3，代价是「避免了多写一段无效代码」）
dow -data + con 不会复位 CPU：上一版留下的脏行会写回、盖在新下载的镜像上，I-cache 里还留着上一版镜像的指令，于是「刚下载的代码」和「CPU 正在执行的代码」不是一回事（症状：随机位置的数据中止、寄存器里出现反汇编上不可能的值）。所以 startup.S 的 _start 第一件事就是关缓存、按 set/way 作废整个 D-cache（丢弃脏行而不是写回）、作废 I-cache/TLB、关 MMU —— 之后反复下载运行才可靠。（坑 1）
主写、PL 读要 clean；PL 写、主读要 invalidate。搞反了不报错但不生效：接收 buffer 读到恒定不变的旧值，尤其第一次运行是对的、之后一直是同一份 → 先怀疑只 flush 没 invalidate。（坑 2，代价：显示帧存翻转前忘写回 → 画面停在上两帧）
主机（JTAG）写、CPU 读的那块内存必须映射为不可缓存（本项目把 4096 段中的 1 段设为 Normal Non-cacheable），否则主机写了、CPU 反复读到旧值，而主机读回来是对的。缓存维护对它无效这件事也就不再是坑。（坑 4）
逐字段读取一组计数器会读到撕裂值：本项目一度得到「相位占比加起来 136.8%」这种物理上不可能的结论，根源是读的每个字来自不同帧。正确做法是一次一致快照（序号包裹：先读序号→读数据→再读序号，两次相同才算有效）或让 PL 提供原子锁存脉冲。识别线索：各分量加起来不等于总数。（坑 5；与 M16 同源）
不要为了回避一致性问题而关缓存：打开 MMU + D-cache 让 PS 侧渲染从 2.87 fps 提升到 19.60 fps（6.8×）；关缓存等于用 6.8 倍的性能损失去换一个本来可以正确处理的义务。（坑 6）
（来源：skill/pitfalls/zynq-cache-dma-traps.md 坑 1–6 与「一页速查」；submission/README.md「开缓存之后必须知道的一件事」节）

### （9）归因越界：把「我的查询失败」读成「那个东西不存在」
事故：项目曾用两条「独立证据」（I2C 无 ACK、DVP 无输出）得出「第二颗传感器不响应 / 可能坏了」。归因是错的：真相是 PL 的 axi_iic 那条 I2C 通路读不到器件，传感器一直是好的。改成厂商原设计的做法（把两个 IIC 都设置成 EMIO 输出，即 PS I2C0 → 相机0、PS I2C1 → 相机1）后立刻读到 ID（0x56 / 0x5640，两张配置表各 303/303 条写入成功，两路 VDMA 状态相同，帧存在更新且带对照）。
教训：证据只支持「从我们这侧够不到」时，结论就只写「够不到」；两者现象一样，原因完全不同。尤其当还有另一条未验证的通路存在时，不能升级成「它坏了」。这与案例集 T20/B16 同族。（来源：dl/STEREO_SUCCESS_ROOTCAUSE.md；dl/HANDOVER_20261016.md §六；AGENTS.md 第四节第 2 条）

### （10）工具与链路的真实形状（都被代价证明过）
`rst -system` 是本板 DAP 的触发者：两次 APB AP transaction error（DAP status 0x30000021 / 0xF0000021）都紧跟在它后面，且只能靠断电清除；断电重启后不需要 reset，停核即可 ps7_init。（来源：dl/HANDOVER_20261016.md §15.2、§16.5）
把调试链路弄卡的那个形状：在 CPU 正在运行程序时执行 fpga -file（重配 PL）。引导脚本一直是 halt → fpga → ps7_init → dow → con，从未出问题；把 fpga 放在停核之前，两次都把 PS 的 APB 访问打成 0xFFFFFFFF（只能断电恢复）。规则：烧 PL 之前必须先停核；停不住核就地放弃，不要重试（重试是第二次卡死的直接动作）。（来源：dl/HANDOVER_20261016.md §20.4）
容器不是核：走 `targets -set 1`（APU 容器）读 OCM/DDR/PL 全是 0xFFFFFFFF，而同一个会话里按名字选中 A9 读同样这些地址是正确的（OCM 0x00000000 = EA000006 即 PS 程序入口字，DDR 两路实时帧，PL DIS CR / VDMA2 CR 都是 0x00010003）。历史上 APU 容器这条路能读，它现在不一定能 —— 同一块板子、同一天，前后两个会话行为不同。修法：先按名字选中 A9（targets -set -filter {name =~ "*Cortex-A9*#0"}）再做任何读写，选不中就 FATAL，不再 catch 成一句 WARN。（来源：dl/HANDOVER_20261016.md §11.2、§11.4）
T22 的极端形态：`targets -set N` 的编号会漂移。断电重启后链路正常（1=APU, 2=A9#0, 3=A9#1, 4=PL）；而 rst -system 之后 DAP 进入错误态，新会话里只有 1=DAP（带该错误）和 2=xc7z020，A9 只在「发出 reset 的那个会话」里出现且编号变成 3/4 —— 此时项目里所有 targets -set 1/2/4 全部指错对象（2 是 PL 而不是 CPU）。对策：一律按名字选目标；必要时先做一次恢复 reset。（来源：dl/HANDOVER_20261016.md §11.3；skill/pitfalls/tool-and-build-traps.md T22）
I2C 只能在 rst -system + ps7_init + ps7_post_config 的同一会话里访问。缺 ps7_post_config 或换个会话，ISR 会读到 ARB_LOST（0x01）、读值全 -1。（来源：dl/HANDOVER_20261016.md §五；dl/STEREO_SUCCESS_ROOTCAUSE.md 末节）
`mrd -bin -file` 的长度参数按「字」（32 位）计，不是字节。（来源：AGENTS.md 第三节③）
xsdb.bat 不传递 Tcl 里的 `exit N` 退出码：脚本内 exit 4 之后 $LASTEXITCODE 仍是 0。判据必须看日志文本，不能看退出码。这条今天犯了两次，脚本现已按此实现（按日志文本判成败）。（来源：dl/HANDOVER_20261016.md §9.3 第 2 条、§11.5、§11.4）
xsdb 的 Tcl 不替换 [0x20] 这种十六进制字面量括号（[expr 1+1]→2，[zzz]→invalid command name，但 "word[0x20]" 原样输出；ps_run.tcl 一直依赖这个行为）。tcl_lint.py 会就此告警 —— 在这个解释器下是假警报。（来源：dl/HANDOVER_20261016.md §9.3 第 1 条）
脚本只用 ASCII：中文 Windows 下 Vivado 的 Tcl 控制台按 GBK 读脚本，UTF-8 中文字节被误解码时可能吃掉引号或括号，产生与中文看似无关的语法错误。同类事故还有：用 PowerShell 的 Get-Content -Raw + Set-Content 改 UTF-8 的 Python 文件，中文串被按 GBK 解码后写成乱码（已恢复并用编辑工具重做）。（来源：dl/HANDOVER_20261016.md §16.5、§15.3；ps_fft_dual/skill_add_tools.md 第 147–148 行）
「构建成功」在这里不等于「设计正确」：本工程的 XDC 把 DRC UCIO-1 与 NSTD-1 降级成了警告（two_fft.xdc 第 136–137 行），而那正是本该拦住「标量网接到接口的 _i 子引脚、把接口拆开、多出 4 个未约束顶层端口」的两条安全网。它照样生成了比特流；唯一说明问题的是 io_placed 报告里的 V6/W6/V10/W11 与 12-584 No ports matched 'lcd_touch_i2c_scl_io'。所以构建后必须核验引脚表。（来源：dl/HANDOVER_20261016.md §14.3）

### （11）D6：读失败被兜底成一个合法的寄存器值
事故：读寄存器的辅助函数写成 set v 0; catch {set v [mrd ...]}，读失败时返回 0。而 CR = 0 恰好是「通道停止」的合法编码，于是「读失败」被读成了「通道被停」，并据此写下了关于通道状态的结论。
纪律：兜底值必须是不可能出现的值（如 −1）并单独标注；一个合法取值不能同时当「没有读到」的哨兵。这条与（4）M25 同族：判据里必须包含「这次读到的是不是一个有效值」，而不只是「两次是否一致」。
（来源：dl/REPORT_UPDATE_DRAFT_20261023.md §J；dl/STATUS_20261023_XDC_AND_PROBE.md §三·补2；dl/HANDOVER_20261023.md §三）

### （12）D7：一位判据分不清「我要的状态」和「更坏的状态」
事故：判断「已进入 Park 模式」只查了 bit1 == 0，而 CR = 0（通道停止）同样满足 bit1 == 0，判据因此通过了一个错误的状态，并据此宣布了成功。正确判据是 bit0(RS) == 1 且 bit1 == 0 两条同时成立。
纪律：一个状态若能被两种不同的编码满足，判据就必须把两者同时写出来；「我想要的」与「更坏的」在同一位置上重合时，一位判据永远分不开。这与 5.8 是同一类错误的两个侧面：那里是位定义读反了，这里是把「停止」当成了「停住」。
（来源：dl/REPORT_UPDATE_DRAFT_20261023.md §J；dl/STATUS_20261023_XDC_AND_PROBE.md §三·补2）

### （13）T48：应用运行时不要从主机 poke PL 寄存器
事故：交接文档里早已写明「应用运行时主机写 PL 地址被 MMU 挡」，仍然直接在应用运行时 mwr 0x43010000，结果是把显示通道停掉、并且之后主机对该寄存器的读写全部失败（READ-FAILED / write_error = 1），只能断电恢复。
正确做法：改脚本里的常量、从冷启动重跑，而不是热改。这条与（7）同族——「能写」和「写入生效了」是两件事。
（来源：dl/REPORT_UPDATE_DRAFT_20261023.md §J；dl/HANDOVER_20261023.md 的可重放流程一节（disp_fix 必须在装应用之前跑）；dl/STATUS_20261023_XDC_AND_PROBE.md §三·补2）
三条合起来是一句话：「我能写这个寄存器」和「这个写入生效了」是两件事；而「我读到了 0」和「它是 0」也是两件事。

## 8.3 这些纪律落在哪里（不是写在文档里的口号）

# 九、未完成项与风险

## 9.1 CNN 未接入质检回路
事实：HLS 卷积核 ts_cnn_top 在 PL 内（逐位一致的比对是在早期独立验证比特流上做的，见 dl/HANDOVER_20261016.md §三）。但它在这个交付固件里处于关闭状态：ps_ui/main.c 用 #define WANT_CNN 0 把它编译掉，g_cnn_ok 恒为 0，上电自检不运行，面板上那一行因此是「CNN ARG REGS BAD」而不是运行结果。原因与判据见本节最后一段。
数据面后果：ts_cnn_top 把两个 logits 写到 CNN_ARG_LOGITS（0x43C30000 + 0x4C），main.c 没有把结果搬进邮箱，也没有任何 MB_* 字承载它；网页侧 classifier.cnn_status = "unavailable"、cnn_logits = null。
2026-10-22 更正：上段与 10-21 的写法都已被推翻。CNN 的硬件确实在片内，但在本次交付的固件里它是关闭的：ps_ui/main.c 第 2373 行 #define WANT_CNN 0，因此 cnn_init() 从不执行、g_cnn_ok 发布为 0（MB_CNN_OK = 0）、cnn_selftest_run() 上电不运行（它只在主机发 MB_CMD=7 时被调用）。关闭的原因是实测出来的：2026-10-22 用 0xF1/0xF2 两个信标测得，对 0x43C30000 的前四次写（+0x14/+0x20/+0x2C/+0x38）都通过且 0xF2 已发布，之后程序再也到不了下一句 —— 即它死在 0x43C30000+0x44 / +0x50 这两次写或 cnn_init() 内部。一个不应答的 fabric 模块不能把整台机器带走，而质检通路并不用它，所以在这里关掉，并把这件事写进邮箱；等寄存器映射与已构建的设计核对一致后再打开。（来源：ps_ui/main.c 第 2373、3551–3565、4039–4054、4593 行；dl/HANDOVER_20261022_EVENING.md §三、§七）
未区分项（不得写成已定位）：是加速器算错，还是第一次 cnn_run() 就没能正确搬运数据，现有读数分不开这两者。区分实验需要一次带 ILA 或 DMA 回读的比对，已列入待办。这条与本节原结论一致：文档与演示必须如实标注，不能把 CNN 当作已交付功能。
风险：评委若把「CNN 硬件加速」当作已交付功能，会在演示中落空。文档与演示必须如实标注（网页 README 第八节与面板那行就是这个处理方式）。
（来源：dl/HANDOVER_20261016.md §三；dl/HANDOVER_20261022_EVENING.md §三、§七；ps_ui/main.c 第 2373、3286–3295、4039–4054 行；submission/dashboard/README.md 第八节）
来源分歧（如实记录）：较早的 submission/report/handoff.md（2026-09-24）记载了一条 PS 定点 + NEON 的推理路径（40.1 ms/帧、与参考逐位一致）与「触摸三视图已实现」，并把 CNN 的 PL 加速器列为唯一未完成大项；而 2026-10-16 的交接文件记载触摸刚刚才做通（GPIO 位翻转）、且面板的 CNN 一行当时显示 CNN NOT RUN（该字符串在本构建里已不存在，现在按 g_cnn_ok 显示 CNN ARG REGS BAD，见 9.1）。两份文件描述的是不同阶段，必须以 2026-10-16 交接为准；CNN 与触摸的现状已按 2026-10-22 的源码与实测数据更正（见 9.1、4.6），其余涉及 CNN、触摸、帧率的历史结论取自 10-16 交接与实时源码。

## 9.2 批号（LOT）待主机提供
面板上没有键盘，批号必须由主机写入；当前面板显示 LOT --。邮箱里没有件号、没有序列号，网页也不能显示「这一件是哪一件」。
已有替代：RUN hh:mm:ss 是本会话运行时长（由全局定时器导出），是本地唯一「从何时起」的真实信息。
（来源：ps_ui/main.c 第 1909–1918 行；submission/dashboard/README.md 第八节）

## 9.3 残余撕裂
相机1 在 2026-10-16 之前没有可读帧指针（vdma2_frmptr_probe.tcl 测过 S2MM 块 0x38/0x3C/0x40/0x44/0x48/0x4C，没有一个寄存器跟着帧存变，对照位在跳所以测量有效）；当天把 axi_vdma_2/s2mm_frame_ptr_out 接到 touch_gpio gpio2_io_i 后立即可读。
残余量：交接等待把撕裂从 13–20% 降到 1.09%（3 wraps / 274 copies，60 s）；随后加的「所选帧存探针字必须稳定」守卫在提交信息里记为实测 0.00%。但两者都是在静止场景下量的。
风险：演示若有明显运动，残余撕裂会重新可见；且「等待交接」把拷贝钉到采集率上是有代价的。根治方法已写明：把 axi_vdma_2/s2mm_frame_ptr_out 引到一个空闲探针位并改 BD + 重新综合（约半小时，但有 B17 那类风险）。当前决定是不改。
（来源：dl/HANDOVER_20261016.md §10.3、§11.5、§12.2、§22.3；git 提交 d3c57d6、e28b81b、0eaf675；ps_ui/main.c 第 1624–1651 行）

## 9.4 板子上电状态的随机性（最大的工程风险）
同一套文件、同一天，不同上电给出 15.15 fps 与 1.79 fps 两种状态；病态上电同时伴随 DDR 访问慢 10–14 倍（1043→128 ns 级别），而两个对照（SAME/OCM）不变 ⇒ 内存结论两侧验证过。
已逐条排除可编辑项，仍剩下两个未分开的假说；判决实验已写好但需要板子。这种状态上一次出现两次，都只有断电重启能清。
对交付的影响：屏幕/网页两条线已可用且可验收；交付物（文档、视频、RAR、GitHub）完全不需要板子。
（来源：dl/HANDOVER_20261016.md §20.3、§21.1、§21.4）

## 9.5 四项交付物状态

## 9.6 仍然生效的硬件红线（操作前必读）
J10 PIN35(B20) ↔ PIN28(V12) 之间的跳线必须保持不插：B20 与 V12 在设计中都是信号脚，一旦插上就把两个输出短路。这是唯一需要动手检查的红线。
相机数据脚（cmos_d_*、pclk、href、vsync）在设计里全部是 INPUT，从不驱动 —— 对相机零风险；GPIO_0_tri_o[0](B20)/[1](W14) 是两颗相机的复位，为 OUTPUT。
XDC 里的引脚号不许凭记忆改；本仓库的 two_fft.xdc 是被验证过的，16 个第二路相机引脚与厂商 an5642.xdc 逐一对应。
绝不修改冻结的 HLS 交付物与金标准数据；工程必须保持 Tcl 可复现。
改任何文件前先备份：python dl/backup.py save <名字> <文件路径>；恢复后它会自动校验哈希（「拷过去了」不等于「文件对了」）。
（来源：AGENTS.md 第一节；dl/HARDWARE_SAFETY.md 第一节至第四节；submission/board/RESTORE.md）

## 9.7 采集通路的负结果与它的撤回（2026-10-23）
用 10-23 新构建的比特流跑「完整版启动序列」（ps_fft_dual/run_newbit_20261023.tcl，与 run_complete.tcl 仅 2 行差异）后：
同一序列曾有一次性 SR = 0x00010000（halted = 0、无错误）的读数，但不可复现。因此不能把「通道干净」当作稳定状态来描述。
另一次对照：把同一个探针换回 10-20 那份比特流，SR 与 store 变化逐位相同。这一条排除了「10-22 的 BD 改动弄坏了采集通路」这个假设（对应 8.2（4）：没有对照组的对比测试不成立——这次两侧都有读数，且相同）。但因为两次运行的固件不同（ps_ui.elf 于 10-23 08:30 重建），「新位流是否比 10-20 差」这个问题没有被分离，不能下结论。
撤回（2026-10-23 10:50）：用 10-21 那条验证过的完整脚本 ps_fft_dual/stereo_bringup_byname.tcl 跑今天新构建的位流，一次就得到 camera0 CONTROL = 30/32 words、camera1 = 32/32 words，即 both captures are live。当天那条自写脚本漏了四件事，每一件都足以单独导致「通道干净但没数据」：
结论：safe_bitstreams/BIT_20261023_xdcfixed.bit 是好的，两路采集、显示、AEC、差分质检全通；上面那张负结果表里的读数没有错，错的是当时把它归因给了位流。判据因此改成：脚本必须与已验证的那条逐行相同（除 BIT 一行），而不是「我自己这条跑起来没报错」。
（来源：dl/REPORT_UPDATE_DRAFT_20261023.md §I；dl/HANDOVER_20261023.md 开头的「已解决（2026-10-23 10:50）：采集不通是脚本的问题，不是位流」节与其遗漏项表；dl/STATUS_20261023_XDC_AND_PROBE.md §三、§三·补）

## 9.8 右相机帧存与撕裂（负结果，2026-10-21）
相机 1 的两个采集帧存都在被写（2 s 内各 55% 的字节变化），而显示端固定读 store A，因此存在读到正被覆盖的缓冲的可能。尝试过三种选帧存策略，各 412 次渲染下测得的撕裂比例如下：
三种策略的差别落在噪声里：原因是渲染读一帧（约 40 ms）与采集写一帧（约 40 ms）同量级，选哪一块都躲不开重叠窗口。真正的修法需要第三块缓冲做快照，涉及内存映射调整，因此列为已知限制，不在本轮实施。
口径提醒：9.3 的 1.09%（3 wraps / 274 copies，60 s）是 2026-10-16 那一轮「等待交接」之后的拷贝包裹率，本节是 2026-10-21 在四块帧存的环上按 412 次渲染统计的撕裂比例。两次的条件与统计口径不同，不可互换。
（来源：dl/REPORT_UPDATE_DRAFT_20261021.md §E；dl/HANDOVER_20261016.md §10.3、§12.2；ps_ui/main.c 的帧存选择逻辑）

# 十、附录

## 附录 A：命令速查（一页）
通用前置纪律：
I2C 只能在 rst -system + ps7_init + ps7_post_config 的同一会话里访问（缺 ps7_post_config 则 ISR 读 ARB_LOST、值全 -1）
烧 PL 之前必须先停核（CPU 运行时 fpga -file 会把 PS 的 APB 访问打成 0xFFFFFFFF，只能断电恢复）
脚本只用 ASCII；mrd -bin -file 的长度按「字」计；xsdb 不传递 exit N ⇒ 判据看日志文本，找 === DONE ===
选目标一律按名字：targets -set -filter {name =~ "*Cortex-A9*#0"}（编号会漂移，容器不是核）
引导与运行：
验收与测量：

## 附录 B：邮箱（mailbox）字表
基址 0x10F00000；字节偏移 = 字索引 × 4；MB_VALID = 0x54534331（"TSC1"）。来源：ps_ui/main.c 的 #define 区；submission/dashboard/README.md 第二节。

## 附录 C：关键寄存器与地址表

## 附录 D：溯源与「未验证」清单
本文引用的主要来源（按使用频度）：
本文明确按「未验证」处理的项（不写入结论）：

## 附录 E：交付物可重建性检查
事故：交付的 ps_ui.elf 曾被证明由另一份 main.c 编译——反汇编里 movw ..., #10000 出现 3 次、#3000 出现 0 次，而包内新旧两份源码正是 10000 与 3000 的差别。此后加了三道机制：
① 构建时由 dl/build_id.py 对 13 个源文件取哈希，写入镜像（TSC1 + 8 位十六进制），运行期发布到邮箱 168–171；
② dl/check_package.py 校验三项——「每个生成副本等于其源」「交付镜像带当前哈希」「MANIFEST 与磁盘一致」；
③ 实测：板上读回 TSC1 + 哈希与源一致；从包内单独重建得到的 ps_ui.bin 与交付件逐字节相同。
这一条与 5.7 ③（一条被撤回的假设）是同一种纪律：「我以为我交付的是这份源码」和「交付件真的是这份源码编译出来的」是两件事，差别只能用哈希证明。
（来源：dl/REPORT_UPDATE_DRAFT_20261021.md §D；dl/build_id.py；dl/check_package.py）

# 十一、全分辨率（5 MP）实验与结论（2026-10-19 至 10-20）
本章回答一个具体问题：这套硬件能不能采到 2592×1944（5.04 MP）的完整一帧。结论是不能，并给出排除过程。之所以把失败写成一章，是因为评委与后来者最需要的不是“我们试过”，而是“哪几条路已经被证据堵死”。本章每条排除都有脚本与读数。

## 11.1 完整一帧的判据
判据不是“能看到图像”，而是“采集帧存的写入范围覆盖到最后一行的最后一个字节”：2592×1944×3 = 15,116,544 字节。做法是逐 64 KB 偏移采样帧存，两次读数不同即判定该偏移在被写，取最后一个在变的偏移除以 stride 得到实际行数（脚本 ps_fft_dual/fine_scan.tcl、scan_extent.tcl）。健康读数应当是 1944 行；实测只有约 1087 至 1255 行，且不同次运行不一致。

## 11.2 已排除的 14 项
下表每一行都是“改了 → 复测 → 边界没变或更差”。判据同上：最后一个在变的偏移。

## 11.3 ILA 的直接证据：问题在相机侧，不在下游
相机 IP 自带一个探针在 AXI-Stream 输出上（探针名 s_axis_tvalid / tvalid / tuser / tready），用 Vivado 硬件管理器直接抓取，无需改动 BD。读数（1024 个时钟的窗口）：
判读：AXI 侧的数据供给是稀疏的，说明相机 IP 的 FIFO 大部分时间是空的，即传感器侧的真实像素率远低于 AXI 时钟。据此可以排除“VDMA 写不快”这一整类解释。

## 11.4 2592×1080 可用，但镜头解析力不够
把高度降到 1080（DVPVO = 0x0438、VTS 4000）可以完整采满 1080 行（实测 1070/1080，8.3 MB / 8.4 MB）。但同一场景下与 1280×720 对比每像素梯度，得到：
判读：传感器像素间距 1.4 µm，奈奎斯特约 357 lp/mm，而常用 M12 镜头中心约 80–120 lp/mm。两者差三倍，多出来的像素采到的是同一份模糊。因此 2592 并不能换来更多细节，只换来更宽的视野与更慢的帧率（约 3 fps）。这是本项目的检出下限由光学而非传感器决定的原因。

## 11.5 结论与可复现步骤
结论：在 DVP 并口 + 现有镜头这一组合上，2592×1944 无法稳定完整采集；2592×1080 可采但无解析力收益。项目因此保持 1280×720，并在第五章给出它在该距离下的像素当量与最小可检尺寸。
复现方式（不修改任何工程文件也可复核）：ps_fft_dual/scan_extent.tcl 扫写入范围；ps_fft_dual/count_lines.tcl 按 stride 折算行数；ps_fft_dual/fine_scan.tcl 逐 64 KB 细化；ps_fft_dual/read_vdma2.tcl 读 S2MM 的 0x30/0x34/0xA0/0xA4/0xA8；相机探针的抓取命令见 dl/cap_multi.tcl 与 dl/an3.py。
一条方法学教训（与第八章同族）：本章三次“完全相同的读数”后来证明是同一个被占用的转储文件，不是两次独立测量。判据必须是“新文件、时间戳前进、且转储脚本打印了 dumped 行”，而不是“读到了数字”。

# 十二、缺陷检测链路的实测能力与已知限制（2026-10-23）
本章记录 2026-10-23 一天里对「稳定闸门 → 配准 → 比较单元」三个环节的定位与修复，以及由此得到的实测能力边界。写法沿用前几章：每处都给出改前/改后的对照（尽量用同一批帧），并把「没有验证」的部分单独列出。本章的结论只覆盖板上邮箱读数与离线回放，不覆盖「拿真实缺陷样件跑产线」这件事。

## 12.1 稳定闸门：被当成运动的滚动快门条带
症状：MB_READY 恒为 0（20/20 次采样），而 MB_SETTLE_MS 会从 12548 复位到 773 再重新增长。g_settle_t0 只在 ready == 1 时复位，所以闸门不是被一个永久条件卡死——它开过，然后又被反复打断。
先排除曝光：MB_AEC_EVAL 在 7.2 s 内从 2519 涨到 2531（12 次评估）、MB_AEC_STEPS 在 2531 次评估里恒为 0、MB_AEC_STATE 20/20 次为 1、EVCLIP / EVMEAN = 0 / 443、MB_AEC_EXP 恒为 2369 —— 控制器在评估，但一次都没有调整。插桩构建（FWID TSC16167E148）在 20 s 内 12 次采样，把「哪一半判据在失败」分开了：
结论：闸门被「运动」判据关住，不是被曝光关住。那么「运动」判据在量什么？用相干快照（读数前后停核；直方图之和恰好 2176，这就是快照相干的自证）看到两类循环：
标准差为 0 的那些循环，是环把 store 2 连续递给了闸门两次：store 3 与相机 1 共用，需要换一块时被 store 2 替代，而 store 2 正是下一轮本来就要读的那块。于是闸门把「没有在测量」发布成了「完美的静止」。
其余循环里是一个逐行均匀、周期性的亮度调制：±10 counts，周期约 8–14 个网格行（160–280 个源行），逐行均值的一个实例是 −7, −9, −10, −8, −5, 0, +4, +7, +9, +9, +7, +4, −1, −4, −7, −9 …，形状在不同采样之间重复而相位不同。READY_CELL_DIFF 是 10 counts，这个门限正好落在这个分布的身体里，于是没人碰的场景上格数在 45 与 820 之间移动。在帧的行速率下，244 行的周期正好是 50 Hz 市电纹波在滚动快门下的空间周期。
修法两条，每一条都在同一批帧上做了对照：
① settle_gate() 改为减每一行自己的均值，而不是减一个整帧均值。滚动快门条带按构造在一行内是常数，因此被精确移除；而零件移动不会逐行均匀，因此被保留。
② 共用帧存的那条替换路径改为读 store 1（完整、不共用、且不是上一轮读过的那块），这样每一轮都在比较两帧真正不同的画面。
对照（同一批帧、两个统计量并列：MB_SETTLE_MOTION 是逐行的新规则，MB_SETTLE_MOTG 是同一份数据走旧的整帧规则）：
改后一个循环的直方图（和为 2176）是 0:423 1:784 2:546 3:254 4:110 5:37 6–7:21 8–9:1 10–12:0 —— 10 counts 的门限从约 1.7σ 移到了约 5σ。
验收（静态场景，22 s 内 22 次采样，FWID TSC1E7E06F81）：MB_READY 在 22/22 次采样里为 1（改前是 20/20 次为 0）；MB_SETTLE_MOTION 在全部 22 次里为 0（旧规则在同一批帧上读到 2..81）；MB_READY_STILL 从 199 涨到 512，即闸门是保持住了，不只是碰了一下；差分判定的结果不再有任何一次是「无法判定」。
未验证与这个数字的含义（必须一起读）：
① 这条统计量的正对照还没有跑——「真实的运动会把闸门关上」在这个构建上尚未演示，它与 12.2 的移板实验一起排期。如果逐行减均值减得过头，问题会在这里暴露。
② 条带的物理来源没有确立。已经量到的是：它逐行均匀、±10 counts、周期约 160–280 个源行、相位每次都在变。它是在每一帧之内（对滚动快门的闪烁）还是只存在于差分里（采集时序与场景纹理的相互作用）仍然开放：单帧的行剖面（MB_GRID_ROWM）只有 ±2 counts 的起伏，比差分里看到的 ±10 小。把前一块网格的行剖面也发布出来可以定这件事。
③ 条带被移除后，差分判定在没人碰的场景上给出的是 NG（24..52 格，限 8）。这是 diff_frame() 里本就存在的假阳性来源，此前被闸门挡着没暴露；逐行处理同样适用于它，属 12.3 的工作。
附一条被否决的仪器：mrd -bin -file <帧存> 691200 是既定的「看画面」方法，但它不是原子快照——同一个帧存相隔 6.9 s 的两次 dump 差 501 个格、带同样的 ±15 counts 行图案；实测一次 dump 耗时 6,696 ms，而环每约 240 ms 重写该帧存，即一次 dump 把约 28 帧拼在一起。结论：JTAG dump 不能用于帧间结构，但可以用于大尺度几何（零件的 bbox）与看画面——12.2 正是这样用的。
（来源：dl/STAGE1_20261023_gate.md（含其预注册的假设表、预测表与「被否决的仪器」节）；ps_ui/main.c 的 settle_gate()、MB_GATE_* 与 MB_SETTLE_* 字；ps_ui/st1_gate_replay.py）

## 12.2 配准：从整帧统计改为零件区域
缺陷：reg_search() 在每一个格点上最小化匹配误差。这台台面上皮带、地面与墙约占格点的 79%，于是它最小化的量被那些从不移动的东西主导：它报「场景没有动」，而零件动了。实测：板在帧里的 bbox 在 y 上移动了 +4 px，而搜索报 dy = 0.38 px、并且没有做任何补偿。
改动（搜索结构不动：粗翻译、试尺度、细化、抛物线拟合全部保留）：
① part_green()：绿色优势 score = G − max(R,B)，每个 8×8 块内取 +2、+5 两处 2×2 采样，阈值 12。板上实测：板 +17.0、皮带 −15.7、地面 −51.9。
② part_masks()：在格点上建掩模，并腐蚀一个格点步（3×3 取最小，24 个源像素的边距），这样没有格骑在掩模边界上——在那里一个像素的定位误差会变成一个很大的分数。
③ reg_score()：只有当活帧的掩模说这个格点是零件、且基线掩模说它映射到的格点也是零件时才计分。
④ 发布 MB_PART_PTS / MB_PART_REF / MB_PART_USED（366/367/368），给出掩模面积与获胜配准真正用到的支撑点。
⑤ 任一侧掩模低于 PART_MIN_PTS = 400 个格点（= 2.8% 的帧）时 reg_search() 拒绝（g_reg_ok = 2）；diff_frame() 已会把它变成 MB_DIFF_OK = 5、diff_verdict() 变成「无法判定」，永不 PASS。
⑥ 粗搜索范围从 48 个半分辨率像素放宽到 128（步长 8→16，中段 ±8→±12）：原范围只差一次手工摆放就会饱和，而带掩模的搜索反而更便宜（289 个偏移 × 约 92 点，对 169 × 900）。
板上实测：MB_PART_PTS / MB_PART_REF = 1,486 / 1,529 个格点（约 9.5% 的帧，95,000 px）；MB_PART_USED = 931 点；静止场景 dx = 0.00 px、dy = 0.00 px、scale 255、匹配误差 5.1 levels、状态 1；搜索代价 39–43 ms（13–14 M ticks），每 16 帧跑一次。
掩模算术用独立实现验证过，不是自己验自己：ps_ui/st2_mask_check.py 从半分辨率描述复现 part_masks()，在一块 dump 帧上返回 1,256 点，而板上发布 1,386–1,534（腐蚀前原始绿色 3,379 点 = 23.5%）；掩模内得分 +29.0、掩模外 −16.3；st2_mask_overlay.png 显示掩模落在 PCB 上。
已知答案验证（这一步才是缺陷与修法的分界）：ps_ui/st2_track_test.py 取一帧真实画面，把带掩模的零件整体移动一个已知的源像素数，腾出的区域用该行自己的中位数填上，其余像素逐字节不变——即零件在动、背景不动。同一对图上两个统计量并列：
即：旧统计量对三个不同的真实位移都报「没有位移」，带掩模的那个把每一个都精确恢复。它不是固件自己的搜索在一块被物理移动的板上跑出来的结果，不能这样写。把它与固件绑起来的证据是上面两条：掩模点数的一致（独立实现 1,256 对板上 1,386–1,534）与静止场景的结果（dx = dy = 0.00 px，而真值是 0）。
同一组测试顺带找出的一个静默拒绝：点数下限原本有一个绝对钳位 48。在 923 点的掩模下，stride 4 只能看到约 57 点，钳位却要求其中 84%，于是 176 像素的零件移动在粗搜索被判「没有测到」，而同一指标刚刚精确定位了 96 像素的移动——真实的答案被静默拒绝，只因为这个测试有已知答案才被发现。钳位改为 16（真正保护统计量的是相对下限 mask_pts / (2 × stride²)，而 PART_MIN_PTS 已经拒绝过小的掩模）。
未验证：物理移板没有做（本次会话无法让操作者移动那块板）。要在板上验 dx/dy，步骤已写明：用 MB_CMD = 9 取基线，mrd dump 活帧存，把板滑动 1–2 cm，再读 MB_ALIGN_DX/DY（226/227，单位 1/16 源像素、带符号），与两次 dump 之间绿色掩模质心的位移比对。拒绝路径（PART_MIN_PTS）也没有在板上被触发过：本次会话里没有任何东西能把零件移出视野。
（来源：dl/STAGE2_20261023_part_registration.md；ps_ui/st2_track_test.py、ps_ui/st2_mask_check.py、ps_ui/st2_mask_overlay.png；ps_ui/main.c 的 part_green() / part_masks() / reg_score() / reg_search()）

## 12.3 比较单元与旋转容差：为什么是 16×16 + 5×5 盒均值
先记改了什么：
cell_mean4() 与 ref_cell() 是唯一的取样器；下游（3×3 blob 规则、持续性、bbox 字）一律不变。
为什么是这两个数——量出来的，不是挑出来的。ps_ui/st3_blur_sweep.py 取一帧真实画面，绕帧中心按已知角度旋转（边缘钳位双线性），套用比较自己的算术加上固件自己的 3×3 blob 规则，统计存活格数（限 8）：
再加一个未补偿的 2 像素垂直残差（仍在 0°）：8×8 4 点 812、8×8 盒 283、16×16 4 点 215、16×16 盒 37、整格均值 17。
读法：模糊本身几乎没用（8×8 从 41 只降到 36），因为 8 个像素的格没法对 2 个像素的位移取平均；格尺寸做了大部分工作（41 → 4），盒再做掉剩下的一点（4 → 3）。整格均值更好，但每次比较要扫一遍全帧；四个 5×5 盒是每格 100 次读。
在这一切可信之前必须先移除的两个假象：PIL 的 rotate(fillcolor=0) 会填一个黑色楔形，它单独就能读出约 150 格；np.roll 会绕行。两者都修好之后，直线图像在每一种方案下都读 0 格——这是「台架没有在制造信号」的对照。
板上：此刻板子不发布格数，因为零件掩模是空的（见 12.6 的自动白平衡）。在板上被验证的是拒绝路径，也正是任务在「找不到零件」时要求的行为：MB_PART_PTS = 39（需要 400）、MB_PART_REF = 0、MB_REG_STATE = 2（无法判定，未尝试配准）、MB_DIFF_OK = 5、MB_DIFF_VERDICT = 2（无法判定，永不 PASS）。
顺带查出并修掉一个被抹掉的拒绝：调用点是 diff_frame(CAM_BUF); …; MB_DIFF_OK = 1;（无条件）。diff_frame() 自己在拒绝路径上会置 4 或 5，这一行把它的结果覆盖掉了。修前在空掩模的那一帧上读到 diff_ok = 1、reg_state = 2、cells = 0xFFFFFFFF、verdict = NG——「这一帧无法配准」以「对着一个不可能的格数判 NG」的形式到达主机。diff_frame() 现在只在比较真的发生过时返回 1，调用点也只在此时发布 MB_DIFF_OK = 1；修后同一帧读到 diff_ok = 5、verdict = 2。
（来源：dl/STAGE3_20261023_blur_and_cell.md；ps_ui/st3_blur_sweep.py；ps_ui/main.c 的 cell_mean4() / ref_cell() / diff_frame() / diff_verdict()）

## 12.4 帧存极性：已知答案注入
结论：「置位 = 采集正在填第二块，已写完的是第一块」成立。相机 0 与相机 1 的选帧逻辑都是对的。这条从「继承自相机 0 的约定、未实测」升级为已实测。
方法（不是统计比较）：往相机 1 的两块帧存（0x11200000 与 0x11600000）的第 719 行各写一个不同的魔数——A = 0xA5A5A5A5、B = 0x5A5A5A5A——立刻读回，看哪一块的魔数先被相机数据冲掉；被冲掉的就是正在被写的那块，它与帧指针位的对应关系就是极性的定义。选第 719 行的理由：measure_pass 只采样偶数行对 (0,1)、(16,17)…，719 不在其中，所以注入不会污染任何被发布的统计量。
结果：12 次试次里有 8 次两块同状态（同时存活 (1,1) 或同时被冲 (0,0)），这些不含信息；剩下 4 次是判据：
两个可能的方向都出现了、各自配着对应的位值：4/4 自洽、0 个反例。
前两次为什么测不出来（记录以免重犯）：两次都是「比较两种极性下的统计量散布」，两个原因同时成立——静止画面下两块帧存的内容几乎相同，读错了也没有差别；运动画面下运动本身的方差远大于极性造成的方差（同一配置重复测得 4 / 20 / 16 三个值，噪声底 12 比效应 16 还大）。教训：「没测出差别」不等于「没有差别」；当效应小于噪声底时，正确的做法是换一个不需要统计的判据（已知答案注入），而不是加大样本量或换统计量。
遗留：主机调试位 MB_FP_INVERT（邮箱 word 219）保留在固件里供将来快速对照，已恢复为 0，正常运行时不使用。
（来源：dl/POLARITY_MEASURED_20261023.md；ps_ui/main.c 的 CAP_WRBT / 选帧逻辑与 MB_FP_INVERT）

## 12.5 双路判定与采集环的四块帧存
采集环由四块帧存组成：两路各两块，A/B 按帧交替。其中 store 3 与相机 1 共用，闸门要「换一块上一轮没读过的」时，它会被 store 2 替代，而 store 2 正是下一轮本来就要读的那块——12.1 里「四分之一在拿一个帧存和自己比」就是这个共用关系造成的。
相机 1 的帧指针原先落在 GPIO 捕获范围之外：拼接输出是 15 位 [14:0]，而 axi_gpio_0 的通道 2 是 C_GPIO2_WIDTH = 9，即 [8:0]——相机 1 的帧指针落在 bits [14:9]，全在捕获范围之外被丢弃，所以信号一直在 fabric 里，只是软件够不到（main.c 里「相机 1 的帧指针 goes nowhere」那条注释把「读不到」当成了「没接」）。把 C_GPIO2_WIDTH 从 9 改成 15（与拼接总线等宽；gpio2_io_i 是内部总线、不是封装引脚，因此不涉及 XDC、不影响引脚方向红线）之后，CAP_FRPTR（0x41200008）的 bits [14:9] 就是相机 1 的帧指针，其 bit0（即 bit9）是 store 选择位，语义与相机 0 的 CAP_WRBT 相同。实测 0x41200008 从恒 0x00000000 变成 0x00000E29；400 次采样统计到相机 0 帧指针 7 次跳变、相机 1（bits 9–14）14 次跳变。
双路参与判定（2026-10-23 13:30 实现并上板验证）：固件改动只在 ps_ui/main.c（+509/−17 行），新增邮箱字 204–218，ps_ui/check_layout.py 报 168 个字、0 撞号。合并规则：任一路判 NG → NG；任一路无法判定 → 无法判定；否则 PASS。同一场景、两路各看一处，实测：
两处自审发现的问题已修：① cam1_verdict 原本永远不返回 NG（只会 0 或 2），即相机 1 只能否决、不能判坏；改为相机 1 自己的 AEC 收敛（state = 1）之后，过曝超限同样判 NG，未收敛则判「无法判定」。② aec_control()（相机 0）原本仍吃绘制循环的 g_mean_acc / g_clip_pm，而那是跟着 g_cam 走的，于是 view = 1 时相机 0 的曝光会被相机 1 的图像驱动；改为吃解耦后的 g_cam0_mean_pm / g_cam0_clip_pm（measure_pass 在 draw_camera() 之前跑，本帧有效）。
相机 0 的曝光跳变（同日 13:47 已修）：根因是 measure_pass 读的 g_long_buf 在单曝光模式下只在启动时赋值一次（main.c 第 4267 行），而采集 VDMA 在 A/B 两块之间按帧轮转，于是一半的测量读着正在被覆盖的帧，均值忽高忽低，AEC 追着撕裂帧跑。改成按 CAP_FRPTR 的 CAP_WRBT 选「刚写完的那块」（与相机 1 对称）。实测：曝光 5 步收敛到 6078 后连续 8 秒不动、状态恒为 1；修之前它是逐秒来回跳的。
未验证与新增风险（必须一起读）：
① 相机 1 的判定在纸一动时于 0/1/2 之间逐秒跳变。对质检这是硬伤——同一件产品会得到互相矛盾的结论。判定需要时间稳定化（连续 N 帧一致才发布，或对 clip/mean 做过窗平均），否则「两路参与判定」只会带来噪声。
② 相机 1 的 NG 分支已经在半遮 + 摆动时第一次触发（clip = 13、AEC 状态 = 1 → v1 = 1），但次数极少。
③ 传感器是否真的响应曝光：未证。半遮 + 摆动的两轮数据里，同一个曝光值（约 5460）既能对应均值 364 也能对应 19，均值摆动由纸张主导，行为法测不出，需要寄存器回读 0x3500/0x3501/0x3502。不要再重复「遮/晃纸」这一类行为测试：它们把「我改变了曝光」和「我改变了场景」绑在一起。
（来源：dl/HANDOVER_20261023.md 的开头各节（采集已解决、显示几何、相机 1 帧指针、两路参与判定、13:4x 逐项实测、13:47 相机 0 曝光修复）；dl/POLARITY_MEASURED_20261023.md；ps_ui/main.c 的邮箱 204–218 与 measure_pass()）

## 12.6 已知限制与实测能力
这一节只有两个实测输入，其余全部是除法，所以每一步都把算式写出来，读者可以自己复核。输入一：工件在当前取景下的外接框（bbox）556 像素宽 × 276 像素高，从一个 dump 帧用绿色优势分割测出——这是本章唯一的像素测量。输入二：板卡的实际尺寸100 mm × 70 mm，操作者提供的实测尺寸（仓库内没有任何文件记录它，这是本章唯一的口头来源，故在此写明出处）。
由这两个量得到的分辨率（除法的结果，不是又一次测量）：
两个分辨率不一样，这本身就是一条测量结果。板卡真实长宽比是 100 : 70 = 1.43，而它在画面里是 556 : 276 = 2.01，两者之比 1.43 ÷ 2.01 = 0.71，正好是 cos 45° = 0.71。也就是说，相机视线与板面大约成 45°，纵向被透视压缩：每像素覆盖的毫米数从 0.18 涨到 0.25（×1.41，多出约四成），纵向的分辨能力只有横向的约 0.71 倍。这不是镜头或算法的问题，是取景角度的问题。
一条建议（本轮没有做）：把相机摆到与板面约 15–20°，cos 15° = 0.97、cos 20° = 0.94，各向异性会降到 1.03–1.07 倍，像素接近方形，纵向那部分损失基本收回来。要改就改视角，不要指望换镜头或加算法。
因此可以宣布的与不能宣布的：可以宣布「在当前取景（约 45° 斜视）、带机械装夹、缺陷可见且不小于约 4 mm 的条件下，比较格数能稳定区分合格与不合格」；不能宣布「能检 0.1 mm 级划痕」「能免装夹」「能测小于 4 mm 的特征」。「约 4 mm」是由纵向 4.1 mm 的单元尺寸推出来的，横向单元只有 2.9 mm——限制来自斜视，而不是像素总量。
旋转容差是这一轮最贵的约束。0.16° 的旋转在离线量具上已经把存活格数从 0 推到 3 格（限 8），0.5° 推到 52 格，必然判 NG。板上这一项没有测成（当时设备不可用），板上可对照的读数是静止板的 309–403 格（限 8）——比限值高出两个数量级，说明板上另有尚未收敛的假阳性，容差的实际留量比离线数字更小。结论不变：「板子放歪一点」不是可以靠算法吃掉的问题，必须由装夹解决，而且要紧到远小于 0.2°。
把镜头拉近也不能解决各向异性。让工件占满画面宽度的约 60%（1280 × 0.60 = 768 像素），横向当量变成 100 ÷ 768 = 0.13 mm/像素；同一台相机、同一个 45° 视角下纵向按同一放大比例变细：70 ÷ (276 × 768 ÷ 556) = 0.18 mm/像素，两者之比仍是 1.4 倍。拉近只是把两条轴一起变细，各向异性只由视角决定，不由距离决定——要两条轴一起变方，只能改角度。
自动白平衡是当前已知未解决项，它让绝对阈值这条路在会话中途失效。三帧的实测（同一台设备、同一天）：
20:47 那一帧里，帧内任何 16×16 块的绿色优势均值都不超过 +2，于是没有任何绝对阈值能找到这块板：掩模是空的，配准正确地拒绝，固件就一直回答「无法判定」。固件做的是安全的事，失效的是掩模的前提——一个程序并不掌控的色彩平衡。两条独立检查说这是场景而不是代码：板上发布 0–39 个掩模点，而 ps_ui/st2_mask_check.py（与它不共享任何一行代码）在同一帧上返回 1 个原始点。本程序不写任何白平衡寄存器，OV5640 默认跑自己的 AWB 环。
一条备选方案（未采用）：相对规则 score > median + 12 本可以活过这次漂移——三帧的帧中位数都停在 −20，而板的最好块在 20:38 高出它 +71、在 20:47 高出它 +22——但它改动的是一个被任务规定为绝对的阈值，需要自己的标定，而一个失败的阶段不是开始做这件事的地方。
本章仍未验证的项（汇总，不写成结论）：① 12.1 的正对照（真实运动时闸门会关）没跑；② 12.2 的物理移板没做；③ 掩模拒绝路径没在板上触发过；④ 板上格数在本次会话里取不到（掩模为空）；⑤ 12.5 的相机 1 判定抖动没有稳定化；⑥ 传感器是否响应曝光没有寄存器级证据。
（来源：dl/STAGE1_20261023_gate.md、dl/STAGE2_20261023_part_registration.md、dl/STAGE3_20261023_blur_and_cell.md、dl/POLARITY_MEASURED_20261023.md、dl/HANDOVER_20261023.md；工件外接框 556 × 276 像素为当前取景下从 dump 帧用绿色优势分割测得；板卡实测尺寸 100 mm × 70 mm 由操作者提供（仓库内无记录，故无文件可引）；本节所有毫米数都由这两个量按上面写出的算式导出，没有第三个来源）

# 十三、缺陷检测链路的收敛与三处「测量口径」错误（2026-10-25）
本章记录 2026-10-25 一天在这块板上的工作：曝光闭环与帧长、比较单元的 ROI 与面积判据、零件掩模从「绿色优势」改为「不是背景」、空皮带背景采样器的一个单位错误、配准的评分结构与精度，以及在合格品总体上学习的逐格容差图。当天每一次加载都只换固件（ps_fft_dual/strict_load_cores.tcl：不动比特流、不断电、不 poke 运行中的 VDMA）。文中引用的构建号依次是 06C4E921、627926F0、DE379078、EBF0919B、DE833091、58648B95，其后 stage H 与 stage I 的两次构建文档没有给构建号。每次上电前 J10 的 PIN35(B20)↔PIN28(V12) 跳线必须在外面——这是人做的检查，软件看不到，本章的每一次实测都以它为前提。
本章的「缺陷」有两种，文中各自标出、不混用：参考图里由 MB_CMD = 15 注入的合成印章（已知答案，用来标定判据的分离度），以及操作者确认的污染板（真实缺陷，用来看判据在真实缺陷上的读数）。两者都不构成产线精度：本章不声明任何产线准确率，这也是前几章一贯的口径。
写法沿用前几章：实测与推导分开标注，每个数字都带产生它的方法，撤回写成撤回，每一节都以「未验证」结尾。最后三节（13.11–13.13）是方法层面的内容——三处「代码量的不是它报的量」、三处撤回、仍未验证的清单——它们比任何单个数字都更重要，理由写在 13.11 的开头。

## 13.1 曝光闭环：一个「非零但越界」的字堵死每一步，而锁存没有出口
症状（实测，冷启动后第一次采样）：MB_AEC_STATE 3、MB_AEC_EXP 8698（= 2 × MB_LINE10 4349）、MB_AEC_GAIN 16、MB_AEC_MEAN 545..549、MB_AEC_EVCLIP 14..21、MB_CLIP_LIME 10、MB_AEC_LAST 7（卡住、保持）、MB_READY 0、MB_DIFF_OK 3（比较根本不跑）、MB_DIFF_VERDICT 2（无法判定）、MB_PART_PTS 1200 / MB_PART_REF 1071。其中 MB_EXP_LOCK 读 1495970783——非零，且在有效范围 16..60000 之外，是 DDR 里的残留。
这一次的原因不是范围太窄：帧在过曝（绿色通道 17‰，限 10‰），而控制器 dim 不下去，因为曝光被钉死了。根因（读源 + 受控对照）：k 步的守卫写的是 host_lock == 0u，而上面三个街区之外的有效性判据是 16..60000。于是一个「非零但越界」的字会挡住每一步曝光，同时什么也没有钉住；控制器只剩增益，增益到轨，就锁进 STUCK。而每一次冷启动都会留下这样一个字（0xFFFFFFFF，或者 DDR 残留）——这不是偶发条件，是每次上电的初始条件。
受控对照（同一场景、同一幅画面，只改一个字）：
锁存没有出口，这是第二个缺陷。MB_AEC_STATE 3 的状态体不改任何东西，于是画面不会变得可用，于是锁存永远清不掉。直接测出口：把 MB_EXP_LOCK 写成 4349（k = 1，一帧不过曝的画面），下一次评估就清掉了——state 3 → 1、dec 8、MB_AEC_EXP 8698 → 4349、mean 549 → 352、clip 17 → 0，随后判定开始跑。那就是固件原本没有的出口。
追踪还暴露了两个同类缺陷：① 控制器作用在一个还没测出来的过曝份额上——冷启动的第一次评估从一次刚开始的测量里读到 g_cam0_clip_pm = 10560‰，并据此把增益 64 → 40 → 16 连降三级；② 帧被拒绝时掩模从来没有被测过——掩模由 diff_frame() 建，而闸门在 g_aec_state == 3 时跳过 diff_frame()，于是在最需要掩模的那个状态里，MB_PART_PTS 是上一次的陈旧值。
改动（ps_ui/main.c:7310-7500 一带，另加 mask_sample_refused()）：以 pinned 取代 host_lock == 0u；每一个状态都先跑「亮度带 + 过曝 + 掩模」这一支，所以任何锁存都过不去它；掩模进控制回路（MB_AEC_MASK 157、MB_AEC_FLAGS 159 发布决策用了哪个掩模、为什么）；有界的恢复搜索（AEC_STUCK_TRIES 12 步后保持但继续重测）；被拒绝的帧上也要测掩模，并把调用点放在拒绝分支上（main.c:11038）；掩模项要求 g_part_pts > 0，所以「还没测过」不会被读成「太短」。
出口的界（实测）：锁存在第一幅可用画面的评估上清除——判据是评估的第一支、对每个状态都成立，所以没有东西能被锁过它。实测：从 state 3 且曝光被钉在不可用的值上，放开钉子后 state 2 → 下一次评估就到 state 1（1 × 250 ms 轮询，evals 110 → 111）。
验收（敌意初值 0xFFFFFFFF 下的启动）：
MB_READY 1、MB_AVG_CNT 6..8；此后取一次新参考（MB_CMD = 9）得到 MB_DIFF_CELLS 0、MB_DIFF_FCELLS 0、MB_DIFF_FVALID 625、MB_DIFF_VERDICT 0 = PASS、MB_REG_STATE 1。也就是说 con 之后 3.2 s 收敛、比较真的在跑——这正是改动之前这块板完全做不到的事。
变暗与变亮是用主机钉子模拟的，写清楚：台灯没有动。用 MB_EXP_LOCK 把传感器放在一个让画面比工作点更暗或更亮的位置，控制器看到的就是同一个信号。变暗：钉在 1000 单位（0.23 个周期，约 4.3 倍少光），画面落到 mean 329、clip 0，控制器把增益抬到 64（16 → 40 → 64），报 state 1、dec 13（追掩模），比较在跑并通过，没有 STUCK。变亮：钉在 k=2（8698），画面过曝 19‰（限 10‰），控制器想去 dim 却做不到（主机钉着），报 state 3、dec 7——它没有假装画面是好的；放开后回到 state 1、k=1、mean 352、clip 0。宽范围买到的是什么、没买到什么：它把暗端往下延（需要更多光的场景现在可以用 30 和 40 ms），对亮端没有帮助——亮端的下限仍是一个周期 × 1 倍增益，更亮的场景仍会锁存，那个问题的解是锁存现在能自己恢复，不是这个改动。
未验证（这一节）：① 掩模项真的把一个过短的掩模救回来这件事没有端到端看到——今天每个可用曝光给出的掩模都是 509..642，代码路径被走到了（dec 13、flags bit1、变暗模拟里 tries 3），但结果没有。实验（不需要操作者，约 2 分钟）：把 MB_EXP_LOCK 钉到约 2800 单位，让 mean 留在带内而掩模低于 400，看 MB_AEC_MASK、MB_AEC_FLAGS 的 bit1、MB_AEC_LAST 10/11，以及掩模是否越过 448。② 一个真正更暗的场景让 k 从 1 爬到 2/3/4 没看到：阶梯是用算术和钳位验证的（见 13.2），不是看控制器爬上去的。③ 参考之后零件被拿走的情况没有测（掩模项以「参考里有零件」为门控）。

## 13.2 帧长 740 → 1200：k = 1..4，以及推导窗从 224 ms 到 597 ms
VTS 740 时一帧最多装下两个 10 ms 周期，所以抗闪烁锁定只给得出三个曝光。VTS 改到 1200 之后：MB_SEN_SIZE 511 读回 0x04B00764（VTS 1200、HTS 1892，经 I2C 读回）、MB_SEN_VTS 165 = 1200、MB_FRAME_TICKS 503 = 14,781,254 个334.8 MHz 的 tick = 44.152 ms（22.65 fps）、MB_LINE_PS 504 = 36,790 ps = 36.79 us、MB_LINE10 509 = 4349（16 × 10 ms / 行 = 4348.8）。行时间没有变（HTS 和 PLL 都没有动），而且这是重新推导、不是按比例缩放：line = frame_ticks / VTS = 14,781,254 / 1200 = 12,317.7 tick，16 × 3,348,000 / 12,318 = 4349；帧周期独立地对上：1200 × 36.79 us = 44.15 ms，实测 44.15 ms。
k 的范围是钳出来的，不是断言的：把 MB_EXP_LOCK 钉到远高于帧钳位，60000 → MB_AEC_EXP 17396 = 4 × 4349，所以 k_max = 4（固件把钉子钳到 g_kmax × LINE10）。背后的算术：(1200 − 4) × 16 / 4349 = 4.40 → 4 个整周期；第 4 个周期需要 1087.3 行，钳位在 1196 行，余量 109 行（10%）。任务提到的 VTS ~1100 也有同样的 k 范围，但余量只有 8.7 行（0.8%）——行时间差 1% 就会让请求越钳，而被钳的曝光不是一个整周期。这就是选 1200 的理由，也是最容易被忽略的一条：范围够不够不只看「装不装得下」，要看余量。
整周期的已知答案，一行一个 k（MB_EXP_LOCK = k × 4349，读回 MB_AEC_EXP）：
推导窗必须变大，而这件事是板子自己抓到的。这一改动的第一次烧写上来以后，MB_LINE10 读 4349，但 MB_AEC_K = 0，即 g_line10 == 0：推导失败，AEC 掉回未锁定的法则，把曝光走到 1871——不是一个整周期，抗闪烁锁定静默地关掉了，而其它每一个被发布的字看起来都正常（它们是上一轮的陈旧值，读起来完全合理）。原因：窗固定 224 ms，而 n >= 3 的守卫数的是奇偶跳变（每两个帧存一次）；44.1 ms/帧时窗里只装得下约 5 个帧存，n 落在 2..3。窗现在是 597 ms（约 13 个帧存，n ~ 6，与 27 ms 帧当年的余量相同）。MB_AEC_K 就是为这件事才发布的：它把「推导失败」与「推导成功」分开，而其它字不能。
撕裂没有回归（帧时序变了，所以重新查了一遍）：MB_TEAR_SEL 0 / 942、MB_TEAR_ROW 0 / 943、MB_TEAR_BIG 0、MB_TEAR_WIN/NOFLIP 0 / 0。方向是安全的那一侧：一个帧存每 4 个帧周期被重写一次，而周期刚从 27.2 ms 长到 44.15 ms，所以一次渲染对它读的那个帧存的余量变大了，不是变小了。
静止场景的验收（一次 165 s 的跑，每行一个被判定过的比较，共 120 个比较）：粗格 120 / 0 / 0、细格 120 / 0 / 0（0 格 / 1..7 格 / ≥ 8 格）、判定不是 PASS 的 0 行、细格 ≥ 8 还判 PASS 的 0 行；MB_READY 1、MB_AVG_CNT 6..8；MB_PART_PTS 509..642 对 MB_PART_REF 612；同一跑的 MB_TEAR_ROW 5 / 4224（0.12%），5 次全都计为 WIN（渲染期间发生了交接），NOFLIP 0、MB_TEAR_BIG 0——改动前同一口径是 1 / 409（0.24%），即比率降了、没有升。另一次较短的跑（67 个比较）结论相同。顺带记一条：MB_VERDICT（word 2）是主机写的，PS 只读它；这次没有任何东西写过它，所以它仍是 DDR 残留 0xDFF59D7E。固件自己算的判定是 MB_DIFF_VERDICT，上面每一个被判定过的行都是 0 = PASS。
未验证（这一节）：① k = 3、k = 4 的光学零点没有测——曝光是整周期是算术（四个 k 的 exp mod LINE10 都是 0），但光学零点在 2026-10-24 只测到 k = 2；若照明仍是 100 Hz，k = 3/4 也应当归零，验证要用 stage B 的方法（每个曝光两次单帧参考 dump，ps_ui/stB_pair.py --period 271.8），这次没做，因为要 dump REF_BASE 而判定正在用那份参考。② 「100 Hz」这个前提仍压在每一个整周期结论下面（见 stage B 的 7.4）。③ 相机 1 仍跑自己的控制器、仍会把自己的画面带出条带，与 stage B 一样没有动。

## 13.3 比较单元的 ROI 与「振幅 × 面积」判据：两个数都是从直方图里选的
先纠一个数：任务书写「掩模约占画面的 40%、零件约 30%」。在那两帧从板上 dump 下来的画面上实测（.tmp/stD/cur/live.raw，2026-10-25 10:12）：出厂规则腐蚀后的零件掩模是 588 格 = 160×90 格点的 4.08%，PCB 自己在画面里的框（x 400..960、y 380..600 源像素）是画面的 13.4%，掩模有 198/588 格（34%）落在这个框外面。10-23 的近景取景下同一规则是 2,599 格 = 18.0%。也就是说关系是对的（掩模比零件的框小，因为它是丝印与元件之间的绿色阻焊层，不是板的轮廓），绝对值是任务书那个数的四分之一。本节所有数字都用实测单位。
改动一：ROI 取「零件自己的簇」。出厂的掩模不是一个物体：活帧上有 30 个连通分量（10-24 的失败帧上 45 个），丝印和元件把阻焊层切成 30..45 块。于是「保留最大的一块」这种写法在这块台面上不可用——实测：
字面规则失败的原因不是参数没调好，是零件的掩模本来就是碎片：「只留最大的岛」会留下 PCB 的一小块、把其余全扔掉，掩模随即落到配准要求的 400 点下限之下，也就是这块板会拒绝每一次比较。在 10-23 的近景取景下同一规则几乎是空操作（2,599 → 2,596 格），因为那里零件就是一个连通分量。采用的写法是：在膨胀 2 个格点（16 源像素）后的掩模上取最大连通分量、再与原掩模求交（main.c:3421 / 3484 / 3512）——一格都不加，结果是腐蚀后掩模的子集，所以「去掉的边距」不是零件边缘的一条带，而是断开的碎片：活帧上丢掉 13 个分量 / 78 格（画面的 1.08%），全在背景上；参考帧上 19 个 / 66 格。代价写在源里（main.c:3415-3428）：离零件主体 16 源像素以外、落在掩模碎片上的缺陷不再被判。取簇前的格数作为 MB_PART_RAW（word 21）发布，所以这个代价在运行时可查。
被判定的 ROI 现在是「活掩模与基线掩模一致」（ref_part_ok()，main.c:5723 / 6450）：一个细格只有同时满足「活掩模说是零件」和「它的中心按同一个变换（同一组 Q12 系数、同一移位）映射到基线的零件格」才被判。在这之前，被判的格里有三分之一是「零件对非零件」——搜索自己把那个比例发布成 MB_PART_USED / MB_PART_PTS = 345/517。改动后的账：MB_DIFF_FVALID 468..509 = PART_PTS 的 88..94%（改动前正好 100%，因为它判每一个掩模内的格），判定面积又少了 6..12%；掩模本身小了 8..12%（MB_PART_PTS 517..573 → 466..556，MB_PART_REF 603 → 521..543），两边合起来判定面积少了大约五分之一。这是「一致性」的价钱，而且它每个比较都会发布出来。
改动二：判定改读「振幅 × 面积」。旧判据是「超过 14 灰的格数」；量出来的问题是：3 像素残差下它读到 17（3×3 规则之后），而限是 8 —— 一个放歪的好零件会被判 NG。新判据是「超过 30 灰的最大连通组的面积」（MB_DIFF_DAREA 23 是权威，MB_DIFF_FCELLS 保留发布以便对照）。两个数不是挑的，是从三组总体的直方图里选的（52 个被判格，|d| 以灰为单位，只统计被判的格）：
四个手挑的位移什么也界不住，所以整格的 (dy,dx) 在 0..3 px 全扫了一遍（18 个摆位，另加 0.5/1.5/2.5 px 的行）：整个扫描的最坏情况是振幅 > 30 时最大连通组 2 格（> 25 时 2 格，> 35 时 1 格），而旧计数在 3 像素残差下就达到 17（超过 8 的限）——这就是任务书说的重叠，被复现并被量化了：旧统计量在 3 px 上就会把一个好零件判坏。
选定的数：DEFECT_AMP = 30 灰（main.c:2247）、DEFECT_AREA = 8 格（= DIFF_LIM_DEFAULT，main.c:2248，按构造相同，这样主机字 MB_DIFF_LIM 的单位和覆盖功能都保持不变，变的只是被比较的那个量现在是连通组的面积）。理由逐条从表里来：30 是静止场景峰值（6）的 5 倍、是 14 灰门限的 15 倍；30 灰下最坏的位移摆位只产生 2 格的组，所以面积下限 8 在它下面有 4 倍余量；40×40 +60 的印章产生 19 格，对 8 有 2.4 倍余量。MB_DIFF_DAREAMIN（31）与 MB_DIFF_DAMPTHR（30）把这两个数发布出去。
代价，在板上量的、不是推的（把缺陷注入参考图）：
也就是说：+22 灰、4.2 × 6.0 mm 的一步在 23 个比较上全部读 PASS，而那 23 个比较里有 21 个旧计数在限 8 之上——旧构建会判 NG。振幅阈值以下没有东西能救它：差必须比 30 灰更深、或者比 8 格更宽。今天最小的可检出缺陷是 3×3 个比较单元（4.2 × 6.0 mm）的 +60 灰斑。这个取舍是本章最重要的一条产品性格：判据变严的是「面积」，变松的是「低对比」。
验收（构建 627926F0，全部按名字读）：① 好板放在一个故意不同的位置读 PASS——23 个比较里 20 个被判定 + 1 个 settle 槽（OK=5 → 无法判定，正确），原始细格数在 20/20 上都是 16..20（全部 ≥ 旧限 8），而 DAREA 在 20/20 上是 0（采用期间有一次读到 1），判定 PASS 20/20。② 已知缺陷印章仍然 NG：40×40 px、+60 灰、注入格 (67,73)，23 个比较 0 拒绝、DN 25、DAREA 25、DAMP 68..69、DBOX (67,73)-(71,77) 正好是印章的 5×5 块——这是「面积是几何、不是噪声」的独立几何检查；取新参考后 DAREA 0、PASS。③ 低对比缺陷如实报成漏检（上表）。④ 154 个静止比较没有回归：0 拒绝、原始 FCELLS 在 154/154 上为 0、DAREA 在 154/154 上为 0、「原始计数 ≥ 8 还判 PASS」0 行、「DAREA ≥ 8 还判 PASS」0 行；配准保持恒等（dx16 −2、dy16 0、angle100 +3、scale 256）。
当天在这条改动里自己找出的四个缺陷，两个是板子抓到的：① DBOX 发布错误——dbx1/dby1 用 0xFFFFFFFF 当「未设置」，于是 fx > dbx1 永远不成立，板上第一跑读到 DBOX=67,73,−1,−1；改成「为空时才发布 0xFFFFFFFF」，重测得 DBOX=67,73,71,77。② 洪水填充的错误在板子看到之前就被抓到：第一版 cc_largest() 用 a[idx] > thr 判、又把已访问格标成 2，thr = 0 时被标记的格通过自己的判据，填充不终止；改成严格 == 1 的网格契约。③ 独立拟合里的符号约定错误，用测量而不是争论改正：第一次按教科书的旋转符号打分，报「改动更糟」（14.36 → 15.37）；同一变换在同一区域上两种符号各打一次分，才定下固件的符号与教科书相反（reg_coeffs() 给 (c·vx + s·vy, −s·vx + c·vy)），改后是 12.15 灰。④ 任务书建议的「字面最大连通分量」在这块台面上不可用（上表），实测否决、换成闭运算变体。
未验证（这一节）：① 真实零件上的真实缺陷没有测——这里所有缺陷都是参考图里的合成印章；要测就得用操作者那批约 40 块故意损坏的板，逐块取参考、记录 MB_DIFF_DAREA / DAMP / DBOX / FCELLS / VERDICT 与操作者的描述；在它存在之前，这条规则不声明任何准确率，只声明三组总体之间的分离度。② +20..30 灰的缺陷按构造不可见（上表量到的，不是藏的）：若产品需要那点灵敏度，杠杆在假阳性那一侧（接受放歪时的 NG，或者加一条「两种摆位各比一次取较好的」的路径），那比这次改动大。③ 配准的冷启动不确定性没有变、又被看到一次：同一份注入参考的两次冷采用给出 dx16 842 与 896、angle100 80 与 107——两者都比旧构建的热保持更接近独立拟合，但它们不是同一个答案，一次冷采用不能当成「配准精度」来引用。④ 只有一种取景（零件约占画面 13%、掩模约 4%）；10-23 的近景下取簇规则是空操作，一致性检查在那边没有测。

## 13.4 掩模从「绿色优势」改为「不是背景」，以及它引起的配准回归
失败是先在板上复现的，不是先在纸上推的（10:48，污染板在皮带上，我还没有动任何东西）：MB_PART_RAW 21 读 283..340、MB_PART_PTS 366 读 123..271、PART_MIN_PTS 400、MB_PART_REF 503、MB_BG_STATE 230 读 0（这块板上根本不存在背景图）、MB_DIFF_OK 3（比较被拒绝：AEC 已宣布自己卡住）。两个独立的阻断被复现：掩模在它自己的下限之下，而且 stage C 的掩模项因此锁进了 state 3。掩模一恢复，AEC 的锁存自己就清了（实测 MB_AEC_STATE 3 → 1）。
为什么绿色优势恰好在缺陷板上失败，这是本节最值得记的一条：判据是 score = G − max(R,B)，阈值取帧自己的中位数 + 12。缺陷板的表面变了，变了色的表面就不再是「绿色占优」。实测（.tmp/stE/cur/live.raw，10:47）：绿色掩模腐蚀后 309 格 = 2.15%，取簇之后 121 格 = 0.84%，在 400 的下限之下，判定是无法判定——每一次比较都是。板上同一瞬间读到 RAW 283..340、PTS 123..271，与离线一致。也就是说：掩模的判据不是「这块是不是零件」，而是「这块是不是绿色占优」，而后者在这块板被污染之后不再成立。
新规则：一个格是零件，当它和空皮带的背景的差超过 BG_MASK_THR = 20 灰，亮度用两张 8×8 网格中位数之比补偿，然后 3×3 腐蚀，再走 stage D 的取簇规则（main.c:3690 / 3075 / 3614）。对零件的颜色不做任何假设。同一帧上实测：MB_PART_RAW 974（300 s 内 848..1,009）、MB_PART_PTS 974（865..1,009）、MB_PART_REF 985；旧规则的同一帧是 268..361 / 110..280。旧规则仍然每个比较都算、都发布（MB_PART_GREEN 33 正是旧构建发布成 MB_PART_RAW 的那个数，MB_PART_GCLU 34 是旧构建的 MB_PART_PTS），所以这次改动可以对每一份历史分布审计。
为什么补偿用中位数之比而不是均值之比（main.c:3614）：均值之比会被零件自己在画面里的份额带偏。实测（把帧里的零件区域用皮带重建）：两张网格的均值是 92.67 与 98.21（比 271/256 = 1.059），而中位数是 71 与 73（263/256 = 1.027）；真实光比是 1.000，因为两帧是同一个场景。在 152 counts 的皮带上，均值估计器加进去 +9 counts 的纯算术误差，几乎是 20 counts 阈值的一半。所以掩模用中位数之比；存在检测器保留它的均值（那不是这次改动的），两者都发布。
陈旧背景有三道检查、两个方向都安全（main.c:3690，失败就退回旧规则并发布原因 MB_PART_BGWHY：1 没有背景、2 光比出带、3 面积不可信）：① 本次上电没有采到或采纳过背景；② 中位亮度比在 0.5..2.0 之外；③ 原始掩模超过 BG_AREA_MAX = 画面的 50%（「这个背景不是在描述这个场景」）——这个界是在这块板实际有过的两份错背景上量的：0x127A8C00 上的 DDR 残留读 84%、10-23 的 dump（ps_ui/bg_grid.bin）读 77%，而零件自己的框是 13.4%。失败的两个方向都对：带着零件采的背景给出空掩模（低于下限、拒绝）；一份多了皮带格的陈旧背景加进来的格在两帧里都是皮带，细差约 0。明确的限制：皮带上局部的变化（一道新影子、放上去一个东西）会作为一个假的零件区进掩模；它被 50% 的检查和基线一致性界住，但今天量不了。
必须写清楚的一件事：这块台面上没有真空皮带背景，而且没有操作者就造不出来。所以第 3 节之后板上每一个数都是用标定过的合成背景测的：零件的脚印（x 512..1104、y 370..660）按行、按通道用框外皮带列的线性插值换掉，同一个操作在同类可见皮带上标定（1,275 格）：8×8 格的误差均值 2.74 counts、p95 12、最大 45，对着 20 的阈值。这是替代品，不是细节：它量不了皮带自己的假阳性率（脚印外的皮带是从被分割的那一帧里抄的，按构造完全相同），操作者的真实采集必须同时确认阈值和皮带那一侧。
配准回归（实测，本节未解决项）：同一个仪器 ps_ui/stD_reg_fit.py，加了可选的搜索框（--dx/--dy/--th/--sc，默认值不变，所以 stage D 的每个数仍然可复现）。造三对真值已知的参考（零件移动一个选定的量、皮带不动，.tmp/stE/stE_part_shift.py），先用独立拟合确认真值，再比固件发布了什么：
对照：stage D 那一对是真物理位移，发布 +842 对拟合 +840，即 0.13 px。机制（读码 + 与每一行都一致）：扩宽的冷搜索只在出厂冷搜索拒绝时进入（REG_COLD_FAIL，main.c:3900-3920；g_reg_widen）。新的掩模大一倍、宽松得多，于是保持的答案永远可打分，搜索从不拒绝、也从不升级，最后发布一个偏离 2.6..30 px 的局部答案，残差是真值的十倍（MB_REG_MODE 2/5、MB_REG_RULE 0）。
哪些是硬的、哪些不是：硬的是——在三对独立拟合能精确（0.5 px / 0.00°）恢复真值的图上，固件的答案偏 2.6..30 px、残差十倍；而同一个答案在 stage D 的那对上是 0.13 px。不硬的是——这三对是重建的（零件用双线性重采样移动、下面的皮带被插值），而 stage D 那对是真实的物理位移，所以这不是掩模的单变量 A/B；而且掩模在其中的作用是从升级条件推出来的，不是直接测的，因为旧构建在这块场景上根本跑不起来（它的掩模是 121 < 400，即它拒绝）。
未验证（这一节）：① 这个配准回归本身（13.6/13.7/13.8 是它的后续：低置信度升级、结构评分、粗阶段亚像素采样；到 13.8 时同类已知真值的误差从 5.1/2.8/3.1 降到 1.0/0.2/0.1 源像素，但本节的这三对没有被原样重跑）。② 一份真实的空皮带背景：阈值 20 与皮带的假阳性率都是对着重建的皮带标定的；需要一次真实采集，然后读 MB_BG_MEDD（预期 0..8）与掩模面积（预期 3..15%）。③ 三块好板的 DAREA 0..2、PASS：污染板上的静止场景已经到 DAREA 3，即任务书的界下面没有余量。④ 污染板对着好参考被判 NG——被配准挡住，不是被掩模挡住。

## 13.5 空皮带背景的采样节拍：8×8 的格被 16×16 的取样器填，7,200/14,400 格越过采集存储
任务书说：有了真实的空皮带背景之后，MB_BG_CELLS 读 10,414，裸皮带上 MB_PART_RAW 419..466 / MB_PART_PTS 365..408，即皮带被分成「不是背景」；并指出 BG_MASK_THR 20 低于皮带实测的 8×8 残差（均值 2.74 / p95 12 / 最大 45）。这些在这里都复现了。但阈值不是唯一的原因，也不是最大的那个。先把板子自己的 dump 拿来量（.tmp/stF/now1，11:45，构建 DE379078）：
周期 80、相关 1.000 的复制不是皮带的性质，它是「16 像素节拍的取样器被当成 8 像素网格来索引」的签名：gx ≥ 80 时基列 gx×16 落到 (gx−80)×16（下一源行），gy ≥ 45 时基行越过第 720 行，即越过存储。原因在源里：bg_take() 用 cell_mean4(src, gx, gy) 填 160×90 的 8×8 格网格——那是比较单元的 16×16 格、5×5 盒取样器（DIFF_CELL 16、DIFF_W/H 80×45），而 GRID_W/GRID_H 是 160×90，而且这份网格的每一个读者（bg_bbox()/bg_align()、掩模用的 bg_scale_median()+bg_diff_fill()、以及 MB_CMD = 18 由主机采纳的网格）用的都是 bg_cell_mean8()——每个 8×8 格里 +0/+4 处的四个绿像素，正好是 latt_point()。git blame 把这一行定到 f0a34602，2026-10-23，所以空皮带网格从来就不是掩模从它里面减去的那个量。这和比较单元自己那条注释记的是同一个失败：「一个差的两侧必须用同一种方式采样，否则一个没人碰过的场景会读出一个掩模。」它一直没被抓到，是因为今天之前每一个被量过的掩模用的都是主机写进去的背景（stage E 那张标定过的合成网格），那份是对的。
修法是一行调用（main.c:5768，bg_take）：cell_mean4 → bg_cell_mean8，并把上面的测量写在调用点。烧写后的后果，全部在板上量：裸皮带上 MB_BG_CELLS 从 8,494..10,393 变成 0（24 s / 17 个比较内 0..15）、MB_BG_MEDD 1..2 灰、MB_PART_BGWHY 0（背景规则就是答案）、MB_PART_RULE 1、MB_PART_RAW/PTS 0 / 0。同一帧上旧规则读 309/121、新规则读 974/974。也就是说存在字和零件掩模在空皮带上都读「空」，这正是验收要的，而且背景规则现在真的在跑。
阈值是在真实采集上扫出来的，不是从上一次估计里抄的。输入：固件自己在空皮带上平均出来的活格点（LATT_BASE）、固件自己的空皮带网格，以及四帧有 PCB 的真实零件画面（11:27 那份参考与三份已知变换参考），全部在修好后的 8×8 节拍上。空皮带残差在 14,400 格上的分布：均值 10.74、p50 6、p90 22、p95 22、p99 23、最大 25 灰（stage E 标定的合成背景读 2.74 / 12 / 45：真的那份身体更胖、尾巴更短）。
为什么是 24：它是裸皮带掩模第一次为零的阈值（阈值 20 时皮带自己就越过了 PART_MIN_PTS 400，即一条空皮带可以被注册成一个零件），也是空皮带p99 + 1，所以测到的噪声没有一个格能过它。它还留下最大的零件余量：四帧真实零件画面都仍然越过 400 的下限（最小 471 = 1.18 倍，中位 648 = 1.62 倍）。到 30 时最差的真实零件读 405，即 1.01 倍下限——再暗一点就会被拒绝。板上在 24 下验证：裸皮带 MB_PART_RAW 0 / PTS 0；随后把 11:27 的 PCB 参考注入（MB_CMD = 17）→ MB_PART_REF 667、MB_PART_RRULE 1（1.67 倍下限）。再往后（第二个缺陷的构建）对视野里的真实污染板取新参考读到 764 / 764（1.91 倍），MB_PART_RULE 1、MB_PART_RRULE 1、MB_PART_BGWHY 0。
未验证（这一节）：① 采集的那一瞬间视野里有真实零件这件事没有测——采空皮带背景时板子不在皮带上，所以零件那一侧的 667 是经固件的参考路径（MB_CMD = 17）测的，而 EBF0919B 的活路径零件掩模要等板子回来才能测；后来在 DE833091 上读 764，两条路径都被测到了，但不在同一个比较里。② 好板的余量：1.18 倍是四帧重建画面的最差值，当时皮带上没有好板。③ 光阑相位：活掩模的输入是 8 帧的均值，而测到的帧在两个相差约 1.5 倍的曝光之间交替，背景却是单帧——空皮带残差（最大 25）里含这个失配，这也是阈值落在 24而不是 12 的原因；用 8 帧均值采背景会把它压低，是下一步。④ MB_CMD = 18 可能拒绝一份好背景一次（同一组缓冲上实测两次：第一次 MB_BG_STATE 5、第二次 4，因为采纳的检查只跑一帧，它的曝光相位可以落在光阑的任一侧）；重试是绕法，把检查做成相位容忍是后续，不是这个缺陷的一部分。⑤ MB_BG_CELLS 在裸皮带上是 0..15 而不是正好 0：存在检测器不再把皮带当零件，但也没有瞎掉；BG_MIN_CELLS 32 没变，空皮带仍在它下面。

## 13.6 配准（一）：低置信度就升级，而目标函数自己的极小值在 4 源像素之外
13.4 的回归先在板上重被复现（EBF0919B，污染板在皮带上，三对已知真值的图用 stE_part_shift.py / stE_shift_ref.py 从当时的摆位造出、经 MB_CMD = 17 注入，真值由 ps_ui/stD_reg_fit.py 给）：误差 5.25/1.1 px、0.43°；1.25/4.0 px、0.48°；1.88/36.25 px、5.52°，每一行都是 MB_REG_MODE 2（HOLD，候选输给了保持的答案）或 5（RE-AIM）、MB_REG_RULE 0——出厂的双重规则，即扩宽搜索从未被进入。
能回答「这个对齐对不对」的量不是 REG_ERR_LIM（480 = 30 灰，它回答的是「这帧是不是这个零件」），而是 reg_score()——搜索最小化的同一个算术，发布在 MB_REG_INCERR。它是五个缓冲的纯函数，所以在 Python 里重放（ps_ui/stF_reg_score.py）。重放是对着板校过的、不是假定的：对板在 11:26 保持的那个变换（dx16 −544、dy16 −104、angle100 737、scale256 257）它返回 405，而板发布 MB_REG_INCERR 403（同一次比较，577/578 个被打分的点）；另外两个已知答案检查：参考对着自己时恒等是它自己曲面的极小值；参考正好平移一个格点时极小值正好在那个平移上。总体（1/16 灰）：「正确的答案」（三对真值 + 静止场景的恒等）读 96、149、152、129 = 6.0..9.5 灰；「旧构建发布的错答案」读 225、303、309 = 14.1..19.3 灰。REG_CONF_LIM = 192（12.0 灰）落在量到的空隙里最靠中间的那个整数：比最差的正确答案高 1.26 倍、比最好的错答案低 1.17 倍。
改动（ps_ui/main.c 四处）：① 4934——can_widen 不只在保持的答案不可打分时置位，得分高于 REG_CONF_LIM 时也置位（可打分但不可信的答案也可以扩宽）；② 4947/4955——热/保持的捷径现在要求保持的答案是自信的（e_inc ≤ 192），否则落到完整的冷搜索，而不是重新发布；③ 5324——高于 192 的冷答案走 REG_COLD_FAIL（出厂规则下升级到扩宽规则，扩宽规则下拒绝），这是让「错答案不再被发布」成为事实而不是希望的那一条；④ 5349/5355——冷路径第 0 级的「更好」与「保持的答案仍合适」改用 REG_CONF_LIM，取代 REG_ERR_LIM 与旧的 15 灰 REG_HOLD_LIM（后者被删掉）。REG_ERR_LIM、各个边距、热窗、re-aim 界、冷搜索的几何、掩模规则与比较都没有动，所以一个自信的答案走的是与从前完全相同的路。
改善得最明显的是最坏那一对：dy 误差 36.25 → 1.38 px、角度 5.52 → 0.35°、拟合残差 39.09 → 15.39 灰（2.5 倍）；第一对残差 25.43 → 17.06；每一个发布的答案现在都落在与真值同一个盆里，而不是随机的另一个盆；静止场景仍然把恒等保持到 0.25 px / 0.13°。没有改善的：第二对（16.89 → 16.78 灰，x 上 4.0 px），而且没有任何一对到 1 px / 0.3°。新答案的 MB_REG_INCERR 读 71..109，全部在置信界之下——也就是说在这块场景上这个修法对它们根本不触发，只对严重失败触发。原因在下一段，而且是量出来的。
为什么这个改动做不到 1 px——测出来的上限。reg_score() 采样的是活格点：每个 8×8 格四个绿像素、在 4 像素的格上，与半分辨率基线的一个最近邻比，在零件掩模上平均。这是个粗糙、有混叠的量；在 13.5 的掩模下它是约 700 个格的平均，其中白丝印与皮带相像，所以错答案在这个量上得分低。在第二对的 dump 上重放它，它的极小值在 (−968, +356)，而独立拟合把真值放在 (−904, +296)——距 2 个半分辨率像素 = 4 个源像素，就在搜索随后发布的那个盆里。所以剩下的误差是目标函数的采样，不是升级策略：一个最小化 reg_score() 的搜索不可能比那个函数的极小值更好。这也解释了验收的仪器（每个格采 16 个位置、全分辨率）为什么能把真值 3.6 灰与发布答案的 15..17 灰分开，而固件自己的字对两者都读 71..109（4.4..6.8 灰）。下一个杠杆（已经写明但没有在这次改动里拿走，因为它改的是测量而不是控制流）：用细取样器（ref_cell8 的每格 16 个位置、全分辨率绿）来给搜索打分，和/或把被打分的格限制在有局部对比度的地方，让搜索最小化的那个函数的极小值落在比较需要的那条对齐上。在那之前，这个构建的配准是「从不严重错、有时偏几个像素」，不是「0.13 px」。
未验证（这一节）：① 好板取参考、再让污染板对着它——这是唯一不能从当时的台面上做出来的验收：当天唯一取过的参考就是污染板自己，而自己跟自己比正确地读 PASS（DAREA 0）。② 好参考之后的配准精度：这里每一对都是从污染板自己的帧造的；4 像素的目标函数偏置是帧与掩模的性质、不是板好坏的性质，但只在这一块上量过。③ 扩宽搜索在大的真实摆位上的行为：第三对进入了扩宽（残差减半以上），但场景的摆位很小，stage D 的大摆位实验没有重跑。④ REG_CONF_LIM 的上侧：一块好零件在另一种光下可能读在 192 与 480 之间、在无处可退时被拒绝；那个方向是无法判定，永不 PASS，三个正确答案有 26% 的余量。

## 13.7 配准（二）：评分的是结构（梯度幅值），而 rank 是被一次搜索测量否决的
先抓现场，再改一个字。12:31 板上跑着 DE833091，正好是任务书说的那个状态：MB_PART_REF 482（一份好参考）、MB_PART_PTS 761 > PART_MIN_PTS 400、规则 1/1、MB_REG_STATE 2、MB_REG_MODE 0、MB_REG_INCERR −1、verdict 2、DAREA −1。只读地 dump 了 grey_base.raw（好参考的 640×360 半分辨率灰）、ref.raw、live.raw + live2.raw（污染板的两帧）、latt.raw、两张掩模、mb_all.bin。用之前两个检查：① grey_base.raw 与按 grey_capture() 的方式转换 grey(ref.raw) 得到的逐字节相同（230,400 字节，0 处不同）——所以 dump 就是固件打分的那个基线，不是相似物；② 活格点不是单帧（与 latt(live.raw) 有 12,222/14,400 字节不同、两帧活画面之间均值 |d| 2.7 灰）：latt.raw 是 avg_take() 产生的 8 帧均值，也就是 reg_score() 打分的那个量。
失败的是两个机制。（a）置信闸门量的是亮度：在独立结构真值处重放出厂 reg_score()，均值绝对差 13.11 灰 = 闸门单位里的 210，高于 REG_CONF_LIM 192；同一块板对着它自己的参考读 2.36 灰 = 38。于是一个对齐正确的污染板被拒绝，理由是它的表面不同、不是它的几何不同。（b）点数下限可以要求比参考掩模拥有的更多点：floor_pts = g_part_pts / (stride² × 2) 用的是活掩模的格数。在这一对上活掩模是 761..1072 个格点，而参考掩模是 482；一个点只有在两张掩模都同意时才被打分，所以没有任何偏移、任何 stride 能达到 1072/2 = 536 个点——12:31 的读数正是 PART_PTS 1072、PART_REF 482、INCERR −1、PART_USED 远低于 536。下限改为 min(g_part_pts, g_part_ref) / (stride² × 2)，即两张掩模的交集实际能到的数；两张掩模一样大时（静止场景 755/737）它就是原来的那个数。
决定性的测量：强度 对 census/rank 对 梯度。先建一个独立的真值仪器：把两张半分辨率梯度幅值图在 (Dx, Dy, θ, scale) 上做归一化相关的稠密对齐，带已知答案检查（把一个人造变换施加到参考上能被恢复到 0.5 px / 0.2°）。在真实那一对上它把真值放在 D = (14.5, 3.0) 半分辨率像素、+0.10°、scale 0.994；而出厂强度目标函数自己的极小值在 (14.5, 2.5)——只差 0.5 px。也就是说对齐从来不是问题。在同一个真值处、用固件的采样几何与掩模规则打分（被打分点上的均值绝对差；强度以灰计、rank 以 8 个 rank 步计、梯度以 gm 计）：
对活帧做单调变换（0.8·live + 18，结构不变）：强度 13.11 → 11.75（它动了），梯度 9.59 → 9.59（带增益比），rank 1.77 → 1.89。这正是任务书要的性质，而且在真实帧上量的。
为什么是梯度，而不是分数更好的 rank。rank 的代价曲面对它太平。在零件掩模下，粗阶段在 stride 4 上采约 20 个点；rank 度量的「对/错」差别与那个采样的散布是同一个量级。在这一对上实测：289 个候选的粗冠军离真值 16..20 个半分辨率像素；扩宽路径上并集规则的极小值落在 ±128 窗口的边缘（(−48,+128)，分数 29，对着真值的 29 但后者用了 30 倍多的点）。从那里起步的搜索到不了那个盆——完整重放在细阶段被拒绝（ps_ui/stG_rank_replay.py）。梯度保留了搜索需要的锐度：静止场景上 +2 个半分辨率像素的代价是 2.2 → 19.5 灰。这是一次搜索测量，不是一个分数：rank 的不变性分数更好（1.77 对梯度的 3.85），它被否决的理由是它的代价曲面喂不动这个搜索。
改动（ps_ui/main.c）：① 1866——BASE_GM / LIVE_GM 两块 DDR 缓冲，0x11FA3000（GREY_BASE 的 640×360 uint8 梯度幅值，230,400 B，止于 0x11FDC900）与 0x11FE0000（活格点的 160×90 uint8 梯度，14,400 B）；② 3087 gm_base_fill() ——在 ref_take() 里一次扫过 GREY_BASE（230,400 像素 × 4 次读，一次性），与 grey_capture() 相邻调用；③ 3109 gm_latt_fill()——每个比较从源帧算一次，每个格点取 9 个半分辨率灰值（与 grey_capture() 相同的 2×2 绿盒）再算同一个算子，每个点 36 次源读，单帧就够（算子只依赖局部），所以多帧平均没有被改动；④ 4338 reg_score()——被打分的值换成两块梯度幅值，增益比仍施加、改从梯度格点算；搜索结构、阶段、窗、抛物线、双线性细化、边距与置信闸门都没有变；⑤ 4408 下限改为 min(活, 基线)；⑥ 5218 粗阶段在 stride 2 而不是 4 上打分（stride 4 时冠军离真值 16..20 px，stride 2 时是 (16,0) 对真值 (14.5,3.0)），代价发布为 MB_REG_TICKS；⑦ 5267 第 1b 级（角度之前先细化平移）现在出厂路径也跑、而且在双重掩模规则上跑（不放宽）——它在 10-24 被加进扩宽路径正是为了这种耦合；在已知真值的 p2 上实测，16 px 的粗网格把冠军留在 6..7 px 外、随后角度扫描挑到 −2.0°，而真值是 −0.4°；加上 1b 之后同一次重放发布 1.75 个半分辨率像素 / 0.20°（p2）与 1.0 / 0.10°（真实那一对）；⑧ 置信闸门没有动（091ce9a）：同一机制、同一代码路径、REG_CONF_LIM 192，没有为了让它过而放宽。
板上验收 1（达成）：污染板对着好参考，21 个连续的、被判定的比较（MB_DIFF_N 80..108），全部在同一个保持的变换上：判定 21/21 NG；MB_DIFF_DAREA 9, 10, 9, 10, 10, 9, 10 … 11, 10，每一个都 ≥ 8（下限）；MB_DIFF_DAMP 58..74；MB_REG_STATE 1（已稳定）在每一个上，0 拒绝、0 无法判定；MB_REG_MODE 2（HOLD）在每一个上——答案没有游走；MB_REG_INCERR 108..112 对 REG_CONF_LIM 192（1.7 倍余量）；保持的变换 dx16 +4、dy16 +132、angle100 +2、scale 256；MB_PART_PTS / REF = 823..891 / 482；MB_REG_TICKS 6.15..6.19 M tick = 18.4..18.5 ms。一个表面与参考不同、却能对齐、能稳定（state 1、HOLD、分数 108）而不是拒绝的板，这就是任务书要的机制，也是上一版做不到的验收。
板上验收 3（同一对上，实测的负结果）：固件保持的那个变换不是真实摆位。独立稠密结构拟合（ps_ui/stG_align.py，已知答案校到 0.5 px / 0.3°）把真值放在 (14.5, 3.5) 半分辨率像素、+0.30°、scale 0.996（dx16 +464、dy16 +112、angle100 +30），与 12:31 dump 的 (14.5, 3.0, +0.10) 是同一个真值；而固件发布 (+0.125, +4.125, +0.02°)——x 上错了 14.4 个半分辨率像素 = 28.8 个源像素。机制，量出来的：ref_take() 之后保持的答案是恒等，它在这一帧上的分数是 108..121——在置信闸门之下，于是热窗把它当成一个可信的答案；冷搜索必须按 REG_WARM_MARGIN 赢过它而赢不了，于是恒等被重新发布（mode 2，HOLD）。同一份固件、同一对图，在参考掩模还是绿色规则的（534 点、采纳背景之前）时候发布过 (+14.5, +1.0, +0.05°)——离真值 2.5 个半分辨率像素。两个状态之间唯一的差别是参考掩模的形状，于是当时把这一点写成「目标函数的极小值在这对上是掩模塑形的」。这条判断在 13.12 被撤回：stage H 随后用六种掩模变体量到细代价的极小值根本不移动；真正被掩模塑形的是粗阶段的最近邻采样（以及「保持的答案落在置信界哪一侧」这件事），见 13.8。
这一节的两条负结果要一起读：① 上面 21 个 NG 行是真的（这块板与参考的差别远大于对齐误差），但 DAREA 9..11 是在一个错了 28 像素的变换上跑出来的，所以这些 NG 还不构成「缺陷被量在正确的位置上」的证据；这就是为什么这一节把它记成验收 3 的负结果，尽管验收 1 达成了。② 在这一对上，梯度分数分不开严重错的对齐（偏 2..8 个半分辨率像素时读 70..102，一个偏 128 px 的并集候选读 72）与正确的那个（62），所以置信闸门在表面变过的对上载不动搜索，界住它的是掩模重叠下限。这一点写在 REG_CONF_LIM 的注释里。
未验证（这一节）：① 验收 2（两块不同的好板）与验收 4（好板上 100+ 个比较的静止场景）——当时没有好板，不算达成、也不声明。② 换一种光的好板（192 的闸门在两个正确答案上有 3.1 倍余量）。③ 13.4 那三对重建的图没有被原样重跑，所以「回归被修好了」这句话只对新造的已知真值对成立。

## 13.8 配准精度：粗阶段改为亚像素采样 + 联合细化，以及「离散度没有变窄」
任务是把配准的代价做成与掩模形状无关、并把发布的变换拉进已知真值图的 2–3 源像素 / 0.3°，同时不放宽置信闸门（REG_CONF_LIM 192）与扩宽升级（091ce9a）。头一句就要把前提拆成两半、并量出假的那一半：细代价的极小值不是掩模塑形的，而上一轮推荐的两条「与掩模无关」的疗法都被量过、都被否决。真正被掩模塑形的是粗阶段的采样——一个约 65 点、最近邻采样、stride 2 的曲面，它的极小值离真值 20+ 个半分辨率像素；这一点在 main.c 里被修好，而一个从参考的恒等先验起步的联合细化能走到细极小值。
仪器与它的可用性检查。ps_ui/stH_reg_points.py 是 Python 里的 reg_score()：同一张 Q15 正弦表、同一个 Q12 映射、同一组双线性权重、同一套掩模规则与下限、同一个 1/16 gm 输出；BASE_GM 用 gm_base_fill() 的算子从 grey_base.raw 建，LIVE_GM 用 gm_latt_fill() 的从 dump 的源帧建。对着板自己的字做已知答案检查（.tmp/stG/accept1，好参考 / 坏活帧那一对）：在保持的恒等处重放返回 122（325 个点），板发布 MB_REG_INCERR 110（MB_PART_USED 302）——同一处、同一量级；差别来自活帧是比板那次比较更晚的采集（活梯度是单帧）与掩模移动（865 对 854 个点）。一个复制不出那个数的移植不会被用来选任何东西。
掩模塑形的是什么、不是什么——决定性的测量。同一对图，把基线掩模膨胀一格、腐蚀一格、在 x 或 y 上平移一格、或者换成结构阈值（下表六种），stride 1 的亚像素极小值停在同一个地方：
所以掩模改变的是分数的水平（恒等处 112..135），从来不是细极小值的位置。水平的作用是决定置信闸门要不要升级、以及某个边距是否满足——把参考掩模从绿色规则的 534 点换成背景规则的 482 点之所以改变了发布的答案，机制在这里，不是「目标函数是掩模塑形的」。
被搞错的是粗曲面。stride 2 上双重规则打约 65 个点；289 个候选的 ±128 网格、最近邻采样：它的冠军是 (32,0) 得 87，而真值那个盆读约 100；289 个候选里只有 14 个可打分。搜索就顺着进那个盆：完整阶段序列在重放上发布 (34,0) = 离真值 35 个源像素，而细曲面自己的极小值离它只有 3 个源像素。在同一个固定变换 (40,8) 上，最近邻与双线性读 79 对 101——纯粹由采样引入的 22 单位误差，那个假的 79 就是粗冠军。而且 stride 2 上这个曲面是奇偶伪迹：在 (32,−1) 处偶-偶子集读 77、奇-奇子集读 123；在真值那个盆 (16,3) 两者读 79 与 74。那个「极小值」属于被采样的子集，不属于对齐。
上一轮推荐的两条疗法，都被量过、都被否决。① 结构门控的点（按活梯度强度 gm ≥ 2/3/4/5/6 在活掩模里选点、不做基线掩模检查）：真值处的分数从 88 涨到 125..178（多出来的点是好参考没有的污染边缘——基线掩模在做的是野值剔除，不只是划一块区域）；粗曲面变平（整个 ±128 网格上 187..245），完整搜索发布 88..97 个源像素之外（六个阈值全都比出厂的差）。② 截尾 SAD（把每点差里最坏的 q 截掉）：在粗级别 q = 0.2/0.3/0.4/0.5 把冠军放在 (64,32)/(48,32)/(64,32)/(16,32)，离真值最近的候选排在第 3..8 位；而且它把分数除以约 4（恒等处 122 → 38），固定的 REG_CONF_LIM 192 会因此不再有分辨力。两条理由都足以否决。
改动（ps_ui/main.c）：① 第 1、1b、2、5、6 级改成亚像素打分（reg_score(dx,dy,2u,1u)，在此之前是最近邻）。这是精度的那一条：在三对同表面的已知真值图上，阶段序列发布的误差从 5.1 / 2.8 / 3.1 降到 1.0 / 0.2 / 0.1 个源像素（ps_ui/stH_search_sim.py --pairs）。② g_reg_phase / reg_score_phase_pair()——上一段那个两奇偶平均，只被联合细化的宽扫用；代价是两个 stride 2 的分数而不是一个（每候选约 130 点而不是约 65）。③ reg_joint_refine()——对 (dx,dy,angle,scale) 做一次联合细化：±20 个半分辨率像素、4 px 步（两奇偶），然后角度 ±1.00°、0.20° 步，然后 scale ±4/256、1 步，然后平移 ±2、1 px 步在完整 stride 1 网格上，最后收尾用冷搜索同样的两条抛物线与同样的 stride-1 3×3。每一遍都包含自己的种子，所以它只能降低分数。离线实测，在失败那一对的恒等先验上起：它返回 (15.06, 4.00) 半分辨率像素、误差 61，对着独立真值 (14.5,3.5) 与先验的 110（ps_ui/stH_seedref.py）。④ g_reg_seeded——ref_take() 用恒等给保持的答案做种子，因为参考帧本来就是一幅活帧。这个先验不能再靠默认赢：在它还没被测量时 HOLD 捷径被跳过、联合细化从它起跑、结果必须用同一套远近边距挣到这个移动、并留在同一个 REG_CONF_LIM 192 之下。在 dump 的那一对上，先验自己的分数是 110，即在闸门之下、却偏了 14.5 个半分辨率像素——这正是上一版把它保持了 21 个比较的原因。⑤ 置信闸门与扩宽升级没有动：同一机制、同一路径、REG_CONF_LIM 192、REG_ERR_LIM、热/跳边距、re-aim 界与持续性窗都不变。
代价：.text 109,948（比 108,244 多 1,704）、.bss 11,532、镜像止于 0x1DAF4（121,588）、OCM 余 9,484 B，没有新缓冲、没有新邮箱字、没有比特流。稳态搜索 MB_REG_TICKS 5.7 M = 17 ms（原 18.4 ms）；取参考之后的第一个比较（联合细化 + 可能的冷解）实测 68.4 M = 204 ms 一次——这是这一节唯一一处成本回归，如实报告、没有藏。
板上：静止场景（验收 4）。参考单元（#1）单独两次跑，每行一个被判定的比较：195 行、MB_DIFF_N 72..381；判定 PASS 195/195；拒绝 / 无法判定 0 / 0（每行 REG_STATE 1、DIFF_OK 1）；MB_DIFF_DAREA 0 × 108、1 × 71、2 × 15、4 × 1（最大 4、均值 0.54），没有 DAREA ≥ 8 还判 PASS 的行；MB_REG_INCERR 32..44（闸门 192）；MB_REG_MODE 2（HOLD）在每一个被判定的行上；保持的变换在参考附近的几个源像素内（(0,0,0,256) → (36,6,+0.12,258) → (4,0,−0.17,255)）；MB_REG_TICKS 5.7 M = 17 ms。
板上：已知真值的图（验收 1，部分达成）。真值按构造精确：把一份参考帧平移整数个源像素、用 MB_CMD = 17 注入，所以真实变换是 dx16 = −16·Sx、dy16 = −16·Sy、0.000°、scale 256（符号约定由 h1 的结果检查：发布 −512 对真值 −496，若约定相反它会是 +496）：
所以 4 对里有 2 对在 2–3 个源像素、0.3° 之内；h3 输在角度，h3/h4 的位置差约 0.5–1 个源像素。机制在数字里看得见：h1/h2 是联合细化够得到、解得开的摆位（它们的真值在 (15.5,4.5) 与 (28.5,9) 个半分辨率像素，细化的 stride-1 局部级能解到约 1 个源像素）；h4 是一个 2 个半分辨率像素的摆位，单帧梯度代价在那里的对比度与帧间项（第 0 级的注释量到最多 80 单位）一样大，所以细化看不见它：它发布约 0 而不是 −4 个源像素。那是目标函数的分辨率下限，不是搜索的盆。
四个合格单元（验收 3）。操作者把参考单元与另外三块好板一块一块放上去，对着单元 #1 上取的那一份参考（从未重取），整轮只读邮箱：
四块里三块在限（8）之下并有余量；单元 #3 不在，它的 4 个 NG 行是对一块操作者说是好的板的误拒。改动之前同一批总体读 DAREA 0 / 6..8 / 3 / 混合（5 PASS + 3 无法判定）。改动之后的分布 {0..4, 1..3, 4..8, 2..5} 并没有收窄：在这个总体上，离散度不是对齐主导的。
说这句话的那个测量。单元 #3 曾是最像「对齐解释」的候选，所以把比较自己的细格量（cell_mean8 对 ref_cell8，在发布的变换上，ps_ui/stH_celldiff.py）在 dump 的那一对待选变换上算了一遍：
而在固件自己的平移上对这个同一个比较量做角度扫描，它的极小值在 −1.75°（4.90、5 个格超 30），固件是 −1.52°（5.23、9 个格超 30）：固件离比较自己的最优只差 0.23°，而在那里这一对仍有约 5 个格在振幅阈值之上——单元 #3 的 DAREA 不可能被对齐掉。一个按全分辨率拟合的残差打分的角度细化会把它挪到 +0.6..+2.0°，而在那里同一个比较量差 4–8 倍（37–42 个格超 30）。那个改动没有做，理由就是这次测量（撤回记录见 13.12）。结论照实说：剩下的离散是单元间差异，不是对齐；配准在 #1/#2/#4 上的精度是好的（它们的 DAREA 1..5 与「两块物理上不同的板」的残差相符），而 #3 与参考单元的表面差别足以在任何对齐下越过限——没有任何配准改动能修它。
阈值问题，数据自己给出的结论：四个合格单元的 DAREA 最大值是 4、3、8、5；失败的限是 DIFF_LIM 8（0..7 过、8 及以上不过）。单元 #3 正好在限上，所以任何能放它过的生产阈值至少是 9。而上一轮用好参考量到的污染板总体是 DAREA 9..11——即它的最小值是 9。于是不存在一个阈值既能放过单元 #3、又能有余量地拒掉污染板：好的最大值（8）与坏的最小值（9）是相邻的。把限抬到 9 会放过 #3，也会放过污染板最低的那些读数；把限留在 8，则在 23 行里拒掉 #3 四次（那一块上 17% 的假 NG，占四块好板里的一块）。这是比较的振幅/面积规则的性质，这一轮被要求不要动它——所以它被报告，没有被改。
未验证（这一节）：① 联合细化在「零件离先验超过约 3 mm」时的行为（它的窗口是 ±20 个半分辨率像素 = ±40 个源像素 = ±3 mm）；超出之后仍然是冷阶段序列在发布，与从前一样。② 收工时视野里那块干净板是不是要求的那块污染板（见 13.9 的说明：当时请求了两次，最终看到的是一块干净的 ME-42A，无法从图像上分辨）。③ 粗阶段亚像素采样带来的「每候选两倍点」在更慢的板/更大的场景上的时间预算：这次只测了 17 ms 的稳态与 204 ms 的首次比较。

## 13.9 逐格容差图：在合格品总体上学习（工程结果，账要一笔一笔算）
问题，先量出来。四块合格单元对着一份参考、一个固定的振幅阈值（|live − ref| > 30 灰；一个缺陷是 ≥ 8 个这样的格组成的连通组）：DAREA 最大 4、3、8、5。限是 8（8 及以上就算 NG），所以四块里有一块（#3）正好到限，而污染板读 9..11。用比较自己的最好变换（由它的细格算术选，ps_ui/stH_celldiff.py）选之后，#3 仍然带着约 9 个格在 30 灰之上——这个重叠不是对齐造成的（13.8 的 celldiff 表）。
同一个问题在一块不同的好板上又被量到一次（本会话，这个构建，图还没有生效——学到的合格单元少于 3 个）：单元 #2，28 行（= 23 个不同的比较，见本节后面的行/比较说明），DAREA 分布 4×4、5×12、6×7、11×4、12×1 → 5 个 NG 行 / 28 行（18%）。问题在一块第二块好板上复现了，不只是 #3。
改动：
DEFECT_AMP 保留为这张图的地板，所以从没被任何合格单元超过的格，行为与这个构建出厂时完全一致，一张空图是空操作。图存在哪、活得过什么：FINE_TOL 0x126FC000、14,400 B；TOL_HDR 0x126FF840、20 B。两者都活得过一次固件加载，都活不过断电；而一次烧写仍然要重新学一遍，这是设计、不是疏漏：g_ref_ok 在 RAM 里，所以固件在每次加载后 64 个循环就取一份新参考（main.c:12596），而一份新参考会清空这张图。因此头里带 magic、样本数、图的世代、地板，以及 REF_BASE 的一个稀疏 FNV-1a 指纹；tol_boot() 在 magic 与指纹都对上之前清空这张图，并在读入的路上把每个字节钳到地板之上，所以一个损坏的字节永远不可能比出厂的规则更严。
为什么按基线格而不是活格——量出来的。用两块好单元对同一份参考回放（.tmp/stH/unit3 在 dx16 −96、.tmp/stH/def3 在 dx16 +516，即相距 38 px = 4.8 个格），重新生成比较自己的逐格场（ps_ui/stI_replay.py，对着同一份 dump 的 MB_DIFF_FVALID / DN / DAREA / FMAXD 校过：482/483、9/11、3/3、66/66）：
按活格建的图学到的是「板当时恰好摆在哪儿」。
图自己的数：从四块不同的合格单元学来，每块一个比较，按基线格索引：样本 MB_TOL_N 4；高于 30 灰地板被放宽的格 75 / 14,400 = 0.52%；最坏那个格的容差 MB_TOL_MAX 142 灰（位置：基线格 gx 109、gy 57，键 9229）；地板上分布：52 个格在 31..45 灰、7 个在 46..70、5 个在 71..100、11 个在 100 以上；运行时的作用：在单元 #3 上救回 49% 的深格观察、在 #3 的一次重新摆位上是 62%、在参考单元上是 11%。那 11 个 100 灰以上的格是这张图最弱的一点，本节不藏它：那些格是「某一块合格单元曾经在这里差过 100 灰以上」，更可能是镜面高光或边缘格，而不是板与板之间的自然差异。生产用的 AOI 图会给包络加上限；这张没有，而下面的缺陷测量正是说它在这块台面上要紧不要紧。
验收（一行一次摆位；除非「图的大小」一列另说，其余都带图）。下面的 NG 按固件自己的计法：一个被测量的比较，其 DAREA 在限 8 之上。
行不是比较，表里两个都给。一行是主机侧的一批 44 个 mrd 操作（约 0.7 s），而比较是每约 1.7 s 一次，所以一行可能落在同一个比较上两次；NG 一列数的是不同的比较，那是诚实的分母。单元 #2 的固定阈值那一跑正是让这件事要紧的例子：5 个 NG 行 / 28 行 = 3 个 NG 比较 / 23 个比较。
这张表里必须写出来的两处更正，因为它们是账，不是措辞。
① 181 个比较这个总数是对的，但它只覆盖三块不同的单元。104 + 27 + 22 + 28 = 181 个比较、0 个 NG、最坏 DAREA 6（参考单元，余量 +2）——但它们分别是单元 #1 的两次摆位（104 + 27）、单元 #3 的 22 与单元 #4 的 28。单元 #2 在完整图下的那一行没有测：它的两次跑是一次固定阈值（图未生效，3 个 NG 比较 / 23；5 个 NG 行 / 28；DAREA 最大 12）与一次图大小 3（2 个 NG 比较 / 22；25 行；最大 10）。stage I 的文档把 27 个比较那一跑同时列成「#2，图大小 4」与「#1，第二次摆位」，两次是同一次跑（计数与 DAREA 分布完全相同），而它自己的归属说明确认那是单元 #1 的第二次摆位（dx16 −122 对长跑的 256）。因此「四块好板都在完整图下通过」这句话不能引用；能说的是：四块单元、五次测量，其中三次在完整图下（#1 两次、#3、#4）读 0 NG、最坏 6，#2 的完整图那次尚未测。这次缺测可以补：把 #2 放回原处、读一次参考、跑 20+ 个比较，约两分钟板时；补上之后这一节可以升级成「四块都好板都在完整图下读过 0 NG」。
② 「4 块里有 1 块在固定阈值下失败」是白天的数，晚上被同一块板推到了 2 块。stage H 在白天的总体里量到 1 / 4（单元 #3，4 个 NG 行 / 23 行）；同一天晚上对单元 #2 用同一个固定规则重测，得到 5 个 NG 行 / 28 行 = 3 个 NG 比较 / 23 个比较，DAREA 最大 12——于是这个数被进一步的测量往上改成 2 / 4。这不是两条互相矛盾的结论，是一个被更多测量修正过的数；而且它正好是容差图被引入要对付的那件事：固定阈值在合格品总体上会假 NG。
归属警告，因为它真的发生过。现在存成 u1_seat2.csv 的那个文件，先被记成单元 #2、又被转发记成单元 #4，之后操作者才确认它是单元 #1 的第二次摆位（dx16 −122 对长跑的 256）。DAREA 的数不受这次改标签影响，变的只是它们被归到哪块单元上。而总体计数本身（MB_TOL_N = 4）只建立在操作者的摆位记录上、不建立在邮箱里任何东西上：实测，把同一块单元重复采一次贡献了 12 个新放宽的格，而一块真正新的板贡献 11..12 个——所以 MB_TOL_JUMP 管不住这个分母，MB_TOL_EPOCH 数的是图的世代（每一次参考、每一次清空），不是单元数。
参考单元上的 100+ 个比较，仍是静止场景。单元 #1，121 行覆盖 104 个不同的比较、195 s、图在生效、变换整跑恒定（dx16 256、dy16 524、角度 0）：MB_DIFF_OK = 1 在全部 121 行上（没有任何一种拒绝，所以没有一次能归到这次改动）；119 PASS、0 NG、2 次无法判定——两次都是 MB_READY = 0（P1 的就绪闸门扣住了判定；.tmp/stI/u1_long.csv 的第 115 与 119 行），不是图、也不是拒绝；没有 DAREA 在限之上还判 PASS 的行，整跑最大 6。
污染板仍然读 NG——是的，而且是决定性的。那块被污染的单元（固定阈值下读 NG 21/21、DAREA 9..12、DAMP 70..89 的那块），在四块单元学来的图生效、且图处在它最宽松的设置（MB_TOL_SCALE 256，也就是学习它时用的那个值）下：
这里的 DAREA（14..17）比固定阈值下的 9..12 大，但两跑不能直接比：不同的参考（14:50 取的，由背景规则建的）与不同的摆位（dx16 −254、dy16 −74）。可以比的是：两个规则在每一个比较上都把它放在限上或限之上。
让一行成为证据的两条不变量（每一行都算、都由 ps_ui/stI_rows.py 报）：① MB_DIFF_DVAR + MB_DIFF_DRESQ == MB_DIFF_DN——超过 30 灰的格必须恰好分成「仍在自己容差之上」与「图认为它是自然的」；不满足的行是一次撕裂快照（这些字跨过了一个比较的边界被读到），报告出来、不当证据用。② 没有任何DAREA ≥ 8 的行可以读 PASS；每一次跑里 0 行违反。撕裂的行：每跑 25..121 行里 2..8 行（一行是 44 个 mrd 的批，约 0.7 s，对着每约 1.7 s 一次的比较）。它们被数出来，没有被藏起来。
未验证（这一节）：① 单元 #2 在完整图下的那一跑（上面 ①，约两分钟板时）。② 图对一块不在总体里的合格单元的泛化——见 13.10，留一重放说它不泛化。③ 图的 11 个 100 灰以上的格没有被封顶；缺陷测量说明它们在这里不要紧（3.1%），但另一个缺陷可能落上去。④ MB_TOL_SCALE 的 128/64/0 走法没有在板上跑过，因为不需要——「它会收紧」是读码，不是测量；今天有分量的声明是在 scale 256 上量到的那一个。

## 13.10 这个方法自己的上限：容差图能吸收一个真缺陷，量到的答案是「几乎没有」
容差图放宽了 75 个格 / 14,400（0.52%）。污染板的 2468 个深格观察里，图救回了 76 个 = 3.1%，最坏那一行是 79 个里的 2 个。也就是说：放宽的集合与缺陷所在的格实际上不相交，而且是带余量的不相交——这不是「我们希望它们不相交」，是量出来的比例。当时不需要收紧，所以 MB_TOL_SCALE 留在 256、128/64/0 的走法没有跑：缺陷是在学到的图能有的最宽松设置下被测的，这是这个结果能有的最强形式。
这条结果的含义要说准：容差图有能力吸收一个真缺陷——它逐格放宽，而一个静态缺陷如果正好落在被放宽的格上，就会读成自然。今天它没有，因为 0.52% 与 3.1% 的交集在测量上近乎空。但「0.52% 的格 × 某个缺陷」这件事不是一个概率声明：缺陷落点与放宽格之间是否独立没有测过。所以在另一块产品上要信任这张图，需要的测试是明确的、也是便宜的：学第五块、测第六块——不是「学第五块、测第五块」。
留一重放给出的答案是「不泛化」。只用另一块单元建图，单元 #3 保持 DAREA 3（9 个深格里救回 1 个），def3 保持 DAREA 2。所以在这块台面上，这张图最接近四块采样板的记忆包络；一块没见过的第五块好板，预期会读得像上表「图大小 2」那一列。这是这个方法按实测的性质，不是实现缺陷，而它决定了这句话怎么写：四块（实测三块）单元在这张图下通过，不是「任何好板都能通过」，后者不能被引用。
还有一条不对称的风险：图只能让判据变松、不能变严（每个字节都被钳到地板之上），所以它的失效方向是吸收真缺陷，而不是制造假 NG。今天量到的边界是3.1%；如果以后某块产品的缺陷正好落在被放宽的 0.52% 上，正确的修法是给包络封顶（那 11 个 100 灰以上的格），而不是把整张图扔掉。
未验证（这一节）：① 第五块/第六块的实验（上面写的那个）。② 缺陷落点与放宽格独立的假设。③ 包络封顶之后的结果（没有实现）。④ 一张图在两个不同产品之间迁移（同一台设备换产品必须重新学，这一点是设计，但代价没有量过：一次重新学 = 一次新参考 + 四块板的摆位时间）。

## 13.11 测量口径：三次「代码量的不是它报的量」
这一节是本章方法上最要紧的材料，所以放在数字之后单独写。当天有三个互不相干的故障，形状完全相同：数字被读对了，但它不是标签所声称的那个量。这不是逻辑错误，是测量口径（measurement spec）错误——代码、注释、脚本各自都自洽，错在它们描述的不是同一件事。三个都要写出来，因为它们的检查方法可以复用。
① 采样节拍：一个 8×8 的格被一个 16×16 的取样器填（13.5）。bg_take() 用比较单元的 cell_mean4 去填背景的 8×8 网格，而每一个读者都用 bg_cell_mean8。于是那个叫「空皮带背景」的字，量的是半张错位的网格：右半与左半相关 1.000、7,200/14,400 个格越过采集存储的末尾。它活了两天（git blame 到 f0a34602，2026-10-23），因为在这之前每一个被量过的掩模都用主机写进去的背景——正确的那一份。抓到它的不是「再读一遍代码」，是两个独立的检查：周期 80、相关 1.000 的复制（皮带不会有这种性质），以及越界格计数。教训：一个差的两侧必须用同一种方式采样；这条在比较单元自己的注释里已经写过一次（cell_mean4 那条），只是没有人把它套到背景上。
② 字号：一个注释里的字号是主张，不是权威（stage C 第 1 节）。我把 MB_AEC_TRIES / MB_SEN_VTS 编在 160/161，而 160..163 这四个字是给端到端时延计数器用的、按字面偏移写的（MAILBOX + n×4）；于是 MB_SEN_VTS 读回 63,374,337，而期望是 1200。数没读错，是贴在它上面的名字错了。现在它们在 164/165，而且 check_layout.py 除了 #define 的编号，还会收集每一个字面偏移、在两者抢同一个字时让构建失败。这条检查立刻找到了一处先前就存在的：字号 131 是 MB_ARM_DT（支架臂的间隔），而 CNN 面板按字面偏移把它读成自己的「自检超时」标志（main.c:9588）——于是一个恰好等于 5 的臂间隔会在面板上打印 CNN SELFTEST TIMEOUT。它被列在检查里、连原因一起，没有被改（显示层不在这一轮的范围），但对任何新的冲突构建会失败。同一个课上还有一条：上一轮的主机脚本读 366/368/494/496 得到垃圾（17826237），当时以为是「编号过期」，实测那些编号全是对的——垃圾是一份没有被发布的邮箱返回的东西。而且 MB_MAGIC（字 0）是主机写的，PS 用它的存在来门控 MB_VERDICT（main.c:9421），所以一块刚启动的板上的判定看起来可以是垃圾。这三件事都是同一个错：把「我读到的」当成「它量到的」。
③ 单位：一个测试装置自己把 4 倍放大了（13.12 的第一条）。测「固件的位移单位错了 4 倍」的那个合成真值，用的是 dx_i = 2·d 个半分辨率像素去表示 d 个源像素的位移，而正确的换算是 d/2（灰图是 1280×720 的 640×360，所以一个源像素是半个半分辨率像素）。两个 4 倍错误互相抵消，于是那个「已知答案」测试在两次都错的情况下读出一个漂亮的 534 格，而固件是对的。教训：已知答案测试的「已知」也要被独立验证；这里的独立权威是移植过来的搜索本身（它给 dx_i = 4，而发布的那条链路把它变成正好 8.00 个源像素）。
这三条合起来是一条可以操作的纪律：任何一次比较，都要问「这个差的两侧是同一个量吗」——同一个采样节拍（①）、同一个字（②）、同一个单位（③）。而最便宜的检查不是「再读一遍」，是用一个独立算出来的已知答案去对：背景对 cell_mean8 的复制测试、字号对 #define 的生成表、单位对移植搜索的输出。三次故障都是在同一个假设被第二次使用的地方发生的——第一次使用时它是对的，第二次时没有人再检查它。

## 13.12 三处撤回
撤回一：「4 倍位移」——固件是对的，错的是测试装置。2026-10-24 的 stage 6 第 6 节报告了一个实测的单位缺陷：reg_score() 以半分辨率像素移位，reg_adopt() 存 g_reg_dx_fp8 = (dx_i << 8)（文档写 1/256 半分辨率像素），而 ref_at() 施加 −(g_reg_dx_fp8 << 5) 个 Q12 源像素——是搜索量到的移位的四倍；MB_DIFF_DX 发布成 dx_fp8 / 8（文档写 1/16 源像素），也大了四倍。当时的测量：一帧真实零件画面正好平移 8 个源像素，按搜索的单位施加得 0 格 / 0 团，按 ref_at() 的方式施加得 534 格 / 460 团，不施加得 286 格；「发布的字会读 512（= 32 px），而位移是 128（= 8 px）」。当晚撤回：那个合成真值用 dx_i = 2·d 个半分辨率像素表示 d 个源像素的位移，方向反了——一个源像素是半个半分辨率像素，所以 d 个源像素是 d/2 个半分辨率像素。那个「大了四倍」的 dx_i 被喂进出厂的存储，才是 534 格的来源；而 dx_i << 6 读 8 px 只是因为两个四倍错误互相抵消。以移植过来的搜索为权威重跑：同一对 8 源像素的图它返回 dx_i = 4；出厂的存储（dx_i << 8 = 1024）让 ref_at() 正好施加 8.00 个源像素，移植的比较读 0 格 / 0 团；提出的 dx_i << 6 施加 2.00 px、读 235 格；不补偿读 286；旧测试装置的 2·d << 8 读 534。MB_DIFF_DX = (dx_i << 8)/8 = 128 = 8.00 个源像素，正是它文档里写的 1/16 单位。固件一个字节都没有改，被撤回的是从那个错单位推出来的推论：「漂移之后那 10..41 格的读数可能有一部分是比较在过度移位」——不是，它们就是配准误差本身。修正后的已知答案测试是 ps_ui/st6_shift_units.py（它从搜索推出位移，并断言四种情形），完整记录在 dl/STAGE7_20261024_shift_and_persist.md。这条撤回第一次进入本报告（第十二章写的是 10-23 的事，没有覆盖它）。
撤回二：「单元 #3 的角度差 2.12°，所以对齐是它失败的原因」。这条在会话中间发出过，这里撤回。错在两处，第二处是一般性的：① 引用的真值是一个搜索框的产物——stD_reg_fit.py 用 --th −3.0 0.2 跑，那个框返回不了 +0.2° 以上的正角度；不设框，同一个拟合在 +2.0° 找到更低的残差（9.56 对 +0.6° 处的 14.45 灰），所以那个「真值」是框的产物。② 那个拟合最小化的量不是比较所判的量：它每格采 16 个单像素样本，而比较判的是 cell_mean8 / ref_cell8 / ref_at 的 3×3 盒均值 + 基线掩模一致性。用比较自己的细格算术（ps_ui/stH_celldiff.py），固件的变换在候选里排第一（均值 5.23、9 个格 > 30），而那个拟合的答案差 4 倍（37）。一个按拟合残差打分的角度细化会去最小化错误的量；它当时已经被批准，在实现之前被这次测量撤回。代替它的是：用比较量做的角度扫描，最优在 −1.75°，而固件在 −1.52°——固件离它自己目标的最优只差 0.23°，而在那里这一对仍有约 5 个格在阈值之上，所以 #3 的 DAREA 不可能被对齐掉（13.8 的表）。
撤回三：「掩模的形状决定细代价的极小值」。这句话是当天较早时候（13.7 那一节的原始写法）的父判断：同一份固件在参考掩模是绿色规则的 534 点时不发布恒等、在背景规则的 482 点时就发布恒等，于是推成「目标函数的极小值是掩模塑形的」。实测否掉了它：在六种基线掩模变体（dump 的、膨胀一格、腐蚀一格、x 与 y 各平移一格、换结构阈值）下，stride 1 的亚像素极小值停在同一个地方（(16,2)/(15,2)/(16,2)/(15,2)/(15,2)/(16,3)，离真值全是 1.5 个半分辨率像素）；掩模改变的是分数水平（恒等处 112..135），从来不是位置（13.8 的表）。被掩模塑形的是另外两件事：① 粗阶段的最近邻采样——约 65 点、stride 2 的曲面，289 个候选里只有 14 个可打分，最近邻对双线性在同一个变换上读 79 对 101（22 单位的纯采样误差），而且有奇偶伪迹（(32,−1) 处偶-偶 77、奇-奇 123）——它在 13.8 被改成了 1/1b/2/5/6 级的亚像素打分；② 置信闸门的穿越——把参考掩模从 534 点换成 482 点，改变的是「保持的答案落在 REG_CONF_LIM 192 的哪一侧」（它偏 14.5 个半分辨率像素却只读 110..121，正在闸门之下，这才是上一版把它保持了 21 个比较的原因），不是目标函数的极小值在动。代替它的是那句更窄也更有用的话，加上 13.8 的联合细化（从参考的恒等先验起跑，并用同一套边距与同一个闸门挣到它的答案）。
未验证（这一节）：三条撤回都已写进对应的源文档（STAGE6 的更正段、STAGE_H 的第 7 节、13.8 的测量），但没有任何一条被第二块产品/第二种取景复测；撤回本身不是新测量，它只是把旧结论撤到证据能支持的位置。

## 13.13 仍未验证
以下按重要性排，每一条都写明它是什么、为什么还没解决、以及要用什么测量解决它。
① 只见过一次的交替（单元 #2、固定阈值下，FMAXD 在 45..47 与 82..90 之间来回），没有归因。AEC 的假设在能测的地方被测过、被否决：在那两跑的每一行上曝光、增益、k、状态、步数都是常数（那些字当时有记录）。交替早于 AEC 这几列存在，所以它是未识别，不是「已解释」。要解决它：用今天的构建（这几个字都会发布）重跑同一块板、同一摆位，把 FMAXD 与 MB_AEC_ 开头的那些字逐行对齐；如果交替再现，就能第一次同时看到控制器状态。
② 持续性闸门没有实现，代价是量出来的。一个建在 DAREA 组上的持续性闸门（只用 FINE_HIT 已经到达 PERSIST_N 的格来建组）设计过、没有发布：一次固件改动会强制一份新参考，而一份新参考会清空容差图（g_ref_ok 在 RAM 里，固件在每次加载后 64 个循环取新参考，main.c:12596），所以加上它要付四次重新学习加上整轮测量重来，而这会把 13.9 的验收 #2 放到风险里。它仍然是推荐的下一个改动：它不能吸收一个静态缺陷（缺陷会持续），而它能压掉一次瞬变，那正是这里存活下来的失败形状。预热代价也要一起写：一块刚摆好的板会连续 PERSIST_N−1 个比较读 DAREA 0，这通常落在 3 个 settle 槽之内，但不保证，所以缺陷那一侧的验收必须带着这一点重跑。
③ MB_FWID 的字节序读法。固件把 8 个哈希字符作为两个字、按内存顺序发布（MB_FWID1/FWID2），所以按字读会反转每四个字符；ps_fft_dual/stF_dump_20261025.tcl:27-35 因此两种都打印（raw 与 reversed），「这样报告不可能编出一个哈希」；dl/host_qc/qc_inspect.py:157-159 还有一个检查：MB_FWID0 不是预期的 'TSC1' 字节序时报警。但要紧的那件事没有测：板上打印出来的 FWID 与 dl/build_id.py 当前哈希是否相等，没有在一块刚烧写的镜像上验证过。而 STAGE_I 第 7 节记下了这一轮的实际情形：产生所有数字的镜像是 14:53 构建的；15:12 对 MB_TOL_EPOCH 的一处纯注释改动改变了哈希，15:48 重建提交的 ELF 使 ps_ui/ps_ui.elf、build_id.h、main.c 彼此一致，但板子仍然跑 14:53 那个镜像——代码相同（两个源只差一条注释），而它的 MB_FWID 戳是更早的那个哈希；故意没有重烧，因为一次烧写会强制新参考、清空学到的图，也就是会毁掉上面每一个验收数字所依赖的状态。所以一个把板上 MB_FWID 与 build_id.py 当前值相比的打包检查，在下次烧写之前会报不一致——这是预期的，记在这里而不是留给别人去发现。
④ 取参考之后的第一个比较要 204 ms（68.4 M tick，13.8 量的），是 17 ms 稳态的约 12 倍，只测到过一次，且不能按需复现。它来自联合细化（可能再加一次冷解）；没有测的是：这 204 ms 会不会把一个新取参考的工位的第一个判定推迟到取件时间之外。要解决它：在一份新参考之后连续记录前 10 个比较的 MB_DIFF_MS / MB_REG_TICKS，看它是一次尖峰还是每个比较都有。
⑤ 两个在图大小 3 上活下来的 NG 行（单元 #2）没有识别出的原因。它们是那个窗口的第一个和最后一个比较，末尾 FMAXD 从 116 → 133 → 132 → 134 往上涨；这与一次摆位边缘的扰动相符，但没有人看到操作者动过，所以它停在假设。另外，stage I 的文档把它们的消失归给「图大小 4」，而单元 #2 没有图大小 4 的跑（13.9 的更正 ①），所以那条归因一并撤回，改为「未识别」。
⑥ 方法层面的四件事：容差图对第五块好板的泛化（13.10 的留一重放说它不泛化）；缺陷落点与放宽格是否独立；MB_TOL_SCALE 的 128/64/0 走法（读码，不是测量）；那 11 个 100 灰以上的放宽格没有封顶（今天不要紧，3.1%）。
⑦ 产品/场景层面的四件事：好板取参考、污染板对着它判 NG（当天唯一取过的参考是污染板自己的，自己跟自己正确地读 PASS）；+20..30 灰的缺陷按构造不可见；一次取景之外的任何取景（这章的掩模数都是今天这一种取景下的）；「100 Hz」这个照明前提压在每一个整周期结论下面。
⑧ 一次真实零件上的真实缺陷，从头到尾：本章所有缺陷判据的分离度都是对着参考图里的合成印章量的，真实缺陷那一侧只到「污染板读 28/28 NG」为止。操作者那批约 40 块故意损坏的板是下一步：逐块取参考、记录 MB_DIFF_DAREA / DAMP / DBOX / FCELLS / VERDICT 与操作者的描述。在那个存在之前，本章不声明任何准确率，只声明两个总体之间的分离度与它们的代价。
⑨ 人力项，与前面每一章相同：上电前 J10 的 PIN35(B20)↔PIN28(V12) 跳线必须在外面；这条软件看不到、也没有被碰过，本章的每一次实测都以它为前提。
（来源：dl/STAGE_C_20261025_exposure_range_mask_latch.md、dl/STAGE_D_20261025_roi_amplitude.md、dl/STAGE_E_20261025_not_background_mask.md、dl/DEFECT1_20261025_bg_mask_real_capture.md、dl/DEFECT2_20261025_reg_confidence.md、dl/DEFECT3_20261025_structure_registration.md、dl/STAGE_H_20261025_registration_accuracy.md、dl/STAGE_I_20261025_tolerance_map.md（15:49 修订版，含第 7 节的来源说明）、dl/MB_WORDS_20261025.md、dl/STAGE6_20261024_margins_drift.md 第 6 节及其更正段、dl/STAGE7_20261024_shift_and_persist.md；正文里的每个数都能按各源文档「Reproducing any number above」一节重跑；13.9/13.10 的两处更正来自u1_seat2.csv 的归属说明与同日晚间对单元 #2 的固定阈值重测，不是对源文档的重新解释）

# 十四、四十一块真实板：四类缺陷的分布、一个工作点，与这个工作点漏掉的三块划痕板（2026-10-27 夜）
本章记录 2026-10-27 夜间在一个工位上做的一次测量：41 块真实板、42 行（因为一块被放了两次），逐块放上皮带、逐块与同一块参考板比较，每块一行。这是这条判据第一次落在一批操作者自己损坏的板上——第十二、十三章的分离度是对着参考图里注入的合成印章与单块缺陷板量的（13.3、13.9–13.10），13.13 的⑧把「操作者那批约 40 块故意损坏的板」列为下一步。本章就是那一步的结果。
本章的全部工作是离线的：只读 dl/host_qc/logs/ 下的三个文件与仓库里的源码，没有碰板子、没有 xsdb、没有写邮箱、没有改 ps_ui/main.c。真正被测量的是当晚那一次运行；本章是把它的文件读出来、把工具已经打印的数原样引用、并说明哪些数在文件里根本没有。
这一版换了一张表。前一版的第 14 章带的是当天下午 16:03:14 开始的那一次运行（dl/host_qc/logs/sweep_20261027_160133_sweep.csv，41 行 = 20 好板 + 20 缺陷板，好板最大 9 格，限 10 上检出 12/20），而那一次的曝光是漂的：自动曝光的可接受带是 150–780‰，宽到「空皮带」与「有板」会停在不同曝光点（实测 329‰ 与 525‰），而背景是固定的一张图；曝光钉住（MB_EXP_LOCK = 8698）之后，同一批板的好板离散从 0..9 收窄到 0..5 格（dl/CONFIG_20261027.md §1）。本章现在带的是 19:38:47 开始的那一次，它跑在钉住曝光之后，好板整类落在 0..5，工作点才第一次落在 6。第十五章引的仍然是 16:03 那一次（15.2、15.6），两次数不能混用——它们的参考、曝光与工作点都不是同一套。具体说清楚是哪几个数：第十五章开头写「角缺与细划痕看不见」、15.6 写「角缺 0/3、划痕 1/6」，那是 16:03 那一次加上限 10 的组合。本章换成 193725 之后，角缺仍是 3 块，读数从 3、4、7 变成 8、9、12；划痕从 6 块（2、3、6、7、8、11）变成 7 块（4、4、5、7、8、11、11）——连每一类有几块都变了。按 6 重判，这两类分别是 3/3 与 4/7。第十五章要否掉的是那两个统计量，不是这两个数——它们的零值（20 格与 825 格）由参考板对自己量出，与这两类的读数无关，所以两条结论都还站得住；但读者不要把 15.6 的 0/3、1/6 当成本章这张表的读法——它们是上一版的数。
写法沿用前几章：实测与推导分开标注，每个数字都带产生它的方法与来源，算不出来的写「未验证」，不以合理推测补齐。本章多一个标记：「会话记录」 = 这次测量会话的主持者记下的读数，仓库内没有对应的文件可供核对（d8 为什么被放了两次属于这一类：两行在 CSV 里，理由不在）。凡是写「会话记录」的数字，读者都应把它当成记录，而不是文件里的一行。

## 14.1 测的是什么，以及这个测法管不到什么
三个文件，各是一个东西：dl/host_qc/logs/sweep_20261027_193725_sweep.csv 是测量（一行一块板）；同名的 _refused.csv 是事件（181 字节，只有表头、没有数据行，见 14.5 的④）；dl/host_qc/sweep_report.py 是分析工具，本章引用的分布、重叠、混淆矩阵、区间都由它打印，命令写在 14.2 与 14.3 里。
这次运行的样子，全部可由 CSV 的列直接核（表 14-1）。
这一节的第 4 行要单独说，因为它是本章最容易写错的一个数。CSV 的 diff_lim 列（word 220）与 diff_lim_used 列（word 223）在这 42 行上都是 10——也就是说，这 42 行是在限值 10 下采的。本章的工作点是 6，它不来自那两列，而来自对同一列 DAREA 的一次重算（`--current-limit 6`）：DAREA 是「最大连通组的面积」，与限值无关，所以把同一批读数按 6 重判是算术，不是第二次测量。限值 6 是在这次运行之后才写进 word 220 的：dl/CONFIG_20261027.md §1 记着 21:10 读回 MB_DIFF_LIM_USED = 6，而本 CSV 的末行是 21:09:06——两份记录相差 54 秒，说的不是同一个瞬间。换句话说，6 是「这份样本支持的工作点被装上去了」的那个值，不是「采这些行时板上的那个值」；把这两件事合成一句话，本章就写错了。要复现本章的数，两条命令都要跑：先 `sweep_report.py <csv>`（默认取 word 223 = 10），再加 `--current-limit 6`。
测法的骨架来自 runbook（dl/SWEEP_20261027.md §3.3、§4.2–4.3），不是本章发明的：一块已知良好的参考板先取参考（MB_CMD = 9），工具在记录任何一行之前先检查参考（MB_PART_REF 的下限 400、MB_DIFF_OK、MB_REFQ_STATE、PREFLIGHT）；此后每一块板都放在同一个位置、同一个朝向，由操作者手放；工具等一个新的、可判定的比较（MB_DIFF_N 变化且 MB_DIFF_OK = 1、MB_READY = 1），再问标签与缺陷名——标签是在看到任何数字之前问的（工具故意盲问，理由写在 runbook §4.3）。
这个测法管不到七件事，逐条写下来，因为后面每一个结论都被它们界住：
① 标签是操作者的字。g/d 与四个缺陷名都是他说的，没有任何东西核对（工具在混淆矩阵的标题上就印着「truth is the operator's label; nothing here checks it」）。一个错标会移动分布，而数据不能自我纠正。
② 板子没有在相机之间移动过。两个相机通道看的是同一次摆放，不是两次独立摆放：同一个摆位误差会同时出现在两路里，本章的数不能当成「两路独立采样」。
③ 只测了一面。板子朝下/朝后的那一面从头到尾没有被看过一眼。
④ 每块板只有一次比较（一行），而 d8 是唯一的例外：它在 CSV 里有两行（第 28、29 行，DAREA 7 与 1）。所以本章的分布是「一次摆位下的读数分布」，不是「一块板的读数分布」——d8 那 6 格的跨度就是这句话的量（14.4 的（b）），而本章的分母里它只算一块板（14.2）。
⑤ 只有一个参考。每一块好板的读数里都含着「这块板与那块参考板的距离」，工具把这件事单独打印成一段：参考板对着自己读 0 格，20 块留出的好板最小 2、中位 3、最大 5 格，「That 5 is the map's out-of-sample cost on this population」。也就是说，好板那一侧的 0..5 不全是「这块板与参考一样」，里面还含着一个「换一块板就有的距离」，而这个距离与要抓的缺陷同一量级，靠这几个数分不开。
⑥ 一个工位、一名操作者、一个晚上。CSV 的 session 列只有一个值、part_ref 列只有一个值；「一名操作者、逐块手放」是这次运行的进行条件，文件里没有记录是谁放的板——这一条只能当作运行条件读，不能当成证据。
⑦ 这些数绑在一块参考上，重取参考会让整列 DAREA 平移。实测：同一块角缺板在参考 940 下读 4、在参考 909 下读 8（dl/CONFIG_20261027.md §1）；三条角缺板整类从 3、4、7（16:03 那次，参考 940）变成 8、9、12（本章，参考 909）。所以本章任何一个数都是「这块参考下的这个数」，不是「这块板的这个数」。这次运行从头到尾只有一个参考：part_ref 在 42 行上全是 909，part_ref_changed 在 42 行上全是 0。

## 14.2 分布：总体会把一切藏起来，所以按缺陷类型分开看
分析工具的命令与它自己打印的分布（原样引用，未改一个字）：
python dl\host_qc\sweep_report.py dl\host_qc\logs\sweep_20261027_193725_sweep.csv —— 它打印「good boards     : n=21  min=0  median=3.0  max=5」，values 一行是 0,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,4,4,5,5，count per value 一行是 0 x1, 2 x9, 3 x7, 4 x2, 5 x2；「defective boards: n=20  min=1  median=11.0  max=37」，values 一行是 1,4,4,5,7,8,8,8,9,11,11,11,12,16,20,21,21,23,35,37，count per value 一行是 1 x1, 4 x2, 5 x1, 7 x1, 8 x3, 9 x1, 11 x3, 12 x1, 16 x1, 20 x1, 21 x2, 23 x1, 35 x1, 37 x1。两个 n 都值得注意：好板那一侧 n=21（20 块留出的板 + 参考板自己），缺陷板那一侧 n=20——42 行里有一行（d14）没有 DAREA，工具在报告开头把它单列成 NOT USED，不进这两个分布。
21 块好板整类落在 0..5（中位 3，最大 5，最大的是 g6 与 g15），缺陷板那一侧中位 11、最大 37，但两侧仍然在 0..5 上重叠：20 行有读数的缺陷板里有 4 行读在 5 以下（d8 那次的 1、d9 的 5、d11 的 4、d12 的 4）。也就是说「缺陷板平均更高」这句话在这一段上没有意义——工具把它印成一行：「OVERLAP: the worst good board reads 5 cells and the best defective board reads 1 cells.」
所以分开看。工具的分布只分 good/defective，不按缺陷类型分；按类型分组用的是同一份 CSV 的 defect、label、diff_darea 三列，每一个读数都写在它来自的那块板旁边，可以逐行回文件里核（表 14-2）。d8 的两行在表里只出现一次（写在「划痕」那一行里，取两次读数中大的那个 7），这是本章唯一一处对 CSV 行数做的合并，理由写在 14.2 的下一段。
四类的性格完全不同，这是总体分布看不见的东西：污染是最大的一类，7 块里有 6 块读到 11 格以上（8、11、16、20、21、23、37）；弯板两块都在 21 以上，但两块相差 14 格（21 与 35），且只有 2 块，不能当成一类的检出率；划痕 7 块的跨度（4..11）压在限值两侧，7 块里有 4 块读到 7 及以下（4、4、5、7）；角缺 3 块（8、9、12）整类越线，但它们离好板的最大值（5）只差 3 格——这一类的读数为什么这么小、为什么随参考移动，写在 14.4 的（a），那一句必须和「在本章这套配置下被检出」一起读：它不是「角缺可检」。
表 14-2 最后两列的合计必须与工具打印的混淆矩阵对得上，这是这张表的一次归零检查。这一次要检查两个点，因为一个是运行、一个是重判。运行自己的那个点是 10（CSV 的 diff_lim_used 列，42 行全是 10）：6 + 2 + 2 + 1 = 11 块，与工具默认输出打印的「good 21 PASS / 0 NG」「defective 9 PASS / 11 NG」一致。把同一列 DAREA 按 6 重判，得到 7 + 2 + 4 + 3 = 16 块，与工具在 `--current-limit 6` 下打印的「good 21 PASS / 0 NG」「defective 4 PASS / 16 NG」一致。判据是 DAREA ≥ 限值，所以这次重判是精确的、不是近似的：DAREA 不依赖限值，重判只动了那一条比较；而它换来的是 5 块板（d3=8、d4=9、d8=7、d10=8、d20=8，全部读在 6..9），误杀一块也没多。所以在这份样本上，运行记下的限 10 被重判后的限 6 完全支配：误杀一样是 0/21，检出多五块。这一点要写下来，因为 10 是 CSV 里记着的那个在用值，很容易被当成「本文的限值」抄走；而 6 是事后才装上的，它不是这次运行的条件。
16/20 与 16/19 是两个不同的分母，两个都写，因为它们属于两种不同的说法。工具数的是行：42 行里 21 行好板、20 行有 DAREA 的缺陷板（d14 那行没有 DAREA，被列在 NOT USED），于是按 6 重判的检出是 16/20 = 80.0%，区间就是工具算的那个（56.3%..94.3%）。按板数是 19 块有读数的缺陷板里抓住 16 块 = 16/19 = 84.2%：分母少掉的是 d8 被放了两次（第 28、29 行），它只算一块板，而且算它抓住（用两次读数里大的 7）。再强调一次这两个数的身份：它们都是「按 6 重判」的结果，运行本身是在限 10 下采的（14.1 的第 4 行、上一段）——所以更准确的说法是「这次运行量到的 DAREA，按 6 重判得到 16/19」。本章说误杀率与检出率时用工具的 20 行（区间是它算的），说「19 块板」时用 16/19；两个数不是矛盾，是一个分子的两种分母，任何一种单独出现都会被误读。

## 14.3 重叠，以及它能换来的那一个工作点
工具在「限值」这一段的第一句就是这个结果，原样引用：「OVERLAP: the worst good board reads 5 cells and the best defective board reads 1 cells.  The two ranges overlap, so NO limit separates these boards on this measurement.」——最坏的好板 5 格，最好的缺陷板 1 格，所以没有任何一个限值能分开这 21 块好板与这 20 行缺陷板。工具随后拒绝给建议（exit 2，「NO SUGGESTION: the ranges overlap ... Sample size is not the problem here; the measurement is」），只把最不坏的折中印成一行信息：限 7 会误杀 0 块好板、漏掉 4 块缺陷板，41 块板里 4 个错判。那一行工具自己写明「That is a compromise, not a calibration」。
这不是分析失败，是四类缺陷共用一个标量的必然：划痕里最弱的三块（4、4、5）落在好板的量程里（0..5），所以工具说的「重叠」是真的。但重叠不等于没有可用的点：工具说的是「没有一个限值能分开」，不是「不能用」。按 6 重判，21 块好板一块也没误杀，缺陷板抓住 16 行——一个只分开系统看得见的那部分的工作点，是可以有的；工具拒绝给建议，因为给建议就是标定，而这一次不是标定。
这一点这样定：判据是 darea ≥ 限值，所以「不误杀这块样本里任何一块好板」的最小整数就是好板最大值加一，即 6（好板最大 5，g6 与 g15），而 5 不行：5 ≥ 5，那两块会被判 NG。要注意 6 不是工具挑的那个数——工具在 0 误杀这一档上印的是 7，因为在它的数法里 6 与 7 的错判总数一样（这份样本里没有任何一块板读 6，两个限值不可区分），7 只是它挑的那一个。本章取 6，理由是它就是「好板最大值 + 1」这个定义本身，不是在 6 与 7 之间做选择。用工具在同一个 CSV 上跑这个限值（--current-limit 6 只是分析时的覆盖，sweep 本身跑在 10 上、也从不写这个字；14.1 的第 4 行）：
按 6 重判，工具打印的原话是「good 21 PASS / 0 NG」「defective 4 PASS / 16 NG」，false-NG 0/21 = 0.0%（95% 区间 0.0% .. 16.1%，单侧 95% 上界 13.3%），检出 16/20 = 80.0%（95% 区间 56.3% .. 94.3%）；按板算是 16/19 = 84.2%（上一段）。运行自己（限 10）的那一组是 0/21 与 11/20，两者只差那 5 块读在 6..9 的板。按类型拆开（表 14-2 的最后一列），这 16 行是污染 7/7 + 弯板 2/2 + 角缺 3/3 + 划痕 4/7：这个工作点抓住污染、变形、角缺的全部，以及 7 块划痕里的 4 块；漏掉的 4 行是 d9（5）、d11（4）、d12（4）与 d8 那次的 1——按板算就是 3 块，全是划痕。
把限值再放低要付的账是可以算出来的，而且它现在是唯一还剩的那条路。漏掉的三块板读 5、4、4：要把 4 格抓进来，限值得降到 4，而在限 4 上 21 块好板里有 4 块会被判 NG（按工具打印的 count per value：读 4 的 2 块 + 读 5 的 2 块）；只抓 5 格要降到 5，代价是 2 块好板。也就是说，剩下的三块划痕与好板仍然在同一个数轴上，抬高和放低都在别处付账——这不是一个可以讨论的取舍，所以本章不提出任何低于 6 的限值，也不把 6 说成「建议」。

## 14.4 两条结构性原因，各自成段
为什么角缺与细划痕的读数总是压在好板量程的上沿，原因不在统计、在判据的构造。两条都写在源码里，两条都与上面的数对得上。
（a）判据只判「两边都说是零件」的格子，所以「少了一块」这种缺陷从构造上只有缺口内侧那一圈格子会留下信号。细格只有在活帧掩模说它是零件、并且同一个变换（同一组 Q12 系数、同一移位）映射过去的基线掩模格也说它是零件时才被判（main.c:9062、9068，判定函数 ref_part_ok() 在 main.c:8225-8246）。角缺不是让某一个被判定的格子变得不同，而是让那一圈格子不再被判定：缺口处的活帧已经不是零件了，mask 说不算，循环在第 9062 行就 continue 了。ref_part_ok() 的注释自己写着这个价格：「a real defect on a cell that the BASELINE did not segment — a cell at the very edge of the part — is judged by nothing」（main.c:8220-8224）。这条机制解释的是「读数为什么小」，不是「读数为什么没有」。三块角缺板在这套配置下读 8、9、12；按工作点 6 重判，三块全部判 NG（3/3）——这是「在这套配置下被检出」，不是「角缺可检」：换到上一个参考（940）下，同样的三块板读 3、4、7，按 6 重判是 0/3。整类抬高 5 格，抬的不是信号，是参考。所以角缺的信号是缺口内侧那圈残差在这块参考下的差值；参考一动，它整类跟着动（14.1 的⑦）。这也是为什么角缺是四类里最「安静」的一类：它不是没有信号，是信号的大小由参考决定，而参考是人为取的。
（b）8×8 格的均值把一条 2 像素宽的划痕稀释掉，于是读数贴在门限上、由摆位决定过不过。细格是 8×8 源像素，它的值取格内 4 个 3×3 盒均值（FINE_CELL 8、FINE_SAMP 2/6、FINE_TAP 3，main.c:1919-1924；两侧的计算在 main.c:8172-8203），而判定用的是这一个标量（main.c:9072-9090，门限 DEFECT_AMP = 30 灰，main.c:2663）。一条 2 像素宽、横穿格子的划痕，按面积最多覆盖 16/64 的像素；按这 4 个 3×3 取样算，最多落在 2 个盒里、每盒 6/9——两种算法都把它在格子值里的份额压到对比度的四分之一到三分之一。以 ±60 灰的划痕为例，那是 15..20 灰，正对着 30 灰的门限（这一段是算术，不是测量）。它不等于「永远看不见」：同一套重放里，2×96 像素的划痕能读到 0.88–0.92 的检出（dl/ANOMALY_20261027.md §8），所以准确的说法是贴着门限。这一次的换位重测把它量到了：同一块板 d8 被放了两次，两次读数 7 与 1——同一块板、同一条划痕、同一个参考、同一套代码，6 格的跨度。在 30 灰门限附近，6 格的差就是跨过与不跨过限值。这条证据要带着它的星号读：读数 7 那一行是 coherent=1，读数 1 那一行是那 13 行 coherent=0 之一（14.5 的③），所以 1 这个数是某一次真实比较的量，但整行与标签的对应有风险；跨度是 6 格这件事成立，跨度里两个端点各有多少不确定，本章不敢再往下说。7 块划痕板的读数 4..11 横跨在限值两侧（按 6 重判是 4/7），与这条结构相符。

## 14.5 这个结果不说明什么
① 它不是产线上的误杀率。一个工位、一名操作者、手放、一个参考、一个晚上，21 块好板。工具把区间和点值一起打印，本章两样都引：false-NG 是 0/21 = 0.0%——在 6、8、10 三个限值上都是 0/21，因为好板的最大读数是 5（95% 区间 0.0% .. 16.1%，单侧 95% 上界 13.3%）。「0 块」不等于「0%」——21 块板看不出来的东西，这个区间写着。
② 它不是检出保证。80.0%（按行）或 84.2%（按板）是这一份样本的（95% 区间 56.3% .. 94.3%，按 20 行算），而且它按缺陷类型分裂得很厉害：污染 7/7、角缺 3/3、划痕 4/7。弯板只有 2 块，2 块板给出的不是一类的检出率，本章不为它声明任何比率。另外每一块板都是对着同一块参考判的，不是对着自己的参考——好板一侧的读数因此还含着一个统一偏移（14.1 的⑤），而角缺那 3/3 还整个绑在这块参考上（14.1 的⑦）。
③ 13 行的词是边读边变的（coherent=0），所以「这一行属于哪一次比较」有风险。工具的原话：「WARNING: 13 row(s) were read while the words were changing (coherent=0): boards 3, 6, 12, 14, 17, 19, 20, 24, 29, 32, 33, 40.  Their DAREA is a real comparison's, but the rest of the row may belong to the comparison after it.」——注意它数的是 13 行、却只列了 12 个板号（sweep_report.py:424 把名单截到前 12 个），完整名单在 CSV 的 coherent 列里：13 行，标签是 g3、g6、g12、g14、g17、g19、g20、d4、d8（第二次，读 1）、d11、d12、d19、d20。后果要分开说：本章用来做分布的那一列（DAREA）是某一次真实比较的量出来的；受影响的是标签与比较的对应——对一块读数贴近限值的板，一次比较的错位就足以让它的读数记到相邻那次比较上。这一轮它正好落在两块贴着工作点的板上：d4（9，按 6 重判仍是 NG）与 d8 的第二次（1，按 6 重判是 PASS），所以它不改变本章任何一条结论，但它把 d8 那 6 格的下一半标上了星号（14.4 的（b））。本章因此不对任何单块边界板的读数单独下结论。
④ 拒绝事件文件是空的，而拒绝确实发生过。_refused.csv 是 181 字节、只有表头。那一次被拒绝的比较是 d14：它在测量 CSV 里是一行（第 35 行），diff_ok = 5（REFUSED_REGISTRATION）、没有 DAREA、coherent = 1、part_pts = 823。读码给出一条解释：工具只在判定为可比较的那一次接受（sweep.py:327-386，要求 MB_DIFF_OK = 1 且 MB_READY = 1），而随后的整份 dump 只要求两次读数彼此一致（sweep.py:389-423），不要求它描述的是刚才那次可判定的比较。于是「判定之后紧接一次被拒绝的比较」会被写成一行没有 DAREA 的行，而 coherent 仍是 1——coherent 查的是两次读数的相互一致，不是「与判定那次是同一次」。这一条对本章的分布没有影响（报告工具把它列在「NOT USED」，不进任何分布），但它与 runbook 的写法不一致（dl/SWEEP_20261027.md §6 说拒绝的事件进拒绝文件、不进测量文件）：读者不必去找一份「一行」的拒绝文件，它不存在，被拒绝的那一次在测量文件里。
⑤ 两次运行之间 d 编号是重新编的，不能跨运行当板号用。本章的三块角缺板是 d3、d4、d5；上一版（16:03 那次）的三块角缺板是 d2、d11、d6。同一块物理板在两次运行里可能拿到不同的号，而文件里没有任何一列能把它们对上（CSV 里没有序列号、没有时间戳之外的板身份）。所以本章只做整类的跨运行比较（角缺 3、4、7 → 8、9、12），不做单块板的跨运行比较。连每一类有几块都不一样：16:03 那次是污染 9、弯板 2、划痕 6、角缺 3，本章是 7、2、7、3——同一批 20 块板，两次的归类差了一块划痕与两块污染。所以两次之间的差异里，除了参考、曝光与固件，还含着一份标签的不确定性（14.5 的①）。要做跨运行的单块比较，得在下次运行时把板号写进标签，或者留一张带板号的照片。
⑥ 这些数是「这块参考下的数」，不是「这块板的数」，所以工作点 6 也只对参考 909 成立。14.1 的⑦量到同一块角缺板在 940 下读 4、在 909 下读 8；整类从 3、4、7 抬到 8、9、12。这意味着两件事：一是重取参考之后必须重扫，不能把本章的限值直接搬过去（dl/CONFIG_20261027.md §3 的第三条）；二是如果下次运行的参考变了而限值没变，本章的 0/21 与 16/19 都不再保证。这一条不是提醒，是本章最容易被误用的一条。

## 14.6 两处便宜的修法：已实现、已测量、已失败（详见第十五章）
这一节原来写的是两个提案：格内极差与掩模轮廓差，两条都没有代码、没有离线重放、没有板上的数。现在不是了。两条都实现了（stage I，19 个新邮箱字，main.c:2536-2594；publish-only，diff_verdict() 不读它们，main.c:2513），都在当天傍晚上了板、都测量过，两条都失败——不是「还没验证」，是「验证过，不成立」。修法与全部读数在第十五章；本节只说结论和原因，因为被否掉的正是本节原来给的理由。
（a）掩模轮廓差：否了，而且是量级上的否。原来的理由是「角缺不是改变某个被判定格，而是让那些格不被判，所以比较两张掩模才看得见它」。测量：stage L 修复之后，参考板对自己的零值上，这个量从 141..150 格升到 825 格，而参考掩模自身只有 766 格——825 比整张掩模还大 8%。一个缺角是几格到几十格（三块角缺板在本章这次运行里读 8、9、12，在上一版参考下读 3、4、7），而 825 是整张掩模的边界在两张不同帧的掩模之间错开一格的结果，这个量从构造上就不是缺角的量。原因：角缺是掩模差，而掩模是外观分割（「不是背景」），它的边界跟着表面走，任何表面变化都留下 1–2 格噪声——与缺角同阶（15.6）。
（b）格内极差：方向对，量不够，零仍在信号上面。原来的理由是「8×8 格的均值把 2 像素划痕稀释掉，而格内极差看得见它」。测量：stage L 之后零值从 44..80 格降到 20 格，2.2..4 倍的改善——但划痕类在在用判据上最大只读到 11 格（d6 与 d7），零仍约为它的两倍；而零的极值反而变坏：EG maxd 95..109 → 132，比修复前任何一块好板都高。把边界排除之后，仍有一个格子差到 132 灰：这个统计量的极值来自零件表面，不来自边界。所以它也没有把划痕这一类抬起来——按 6 重判这一类是 4/7，漏掉的三块读 4、4、5，而它的零是 20 格：零是那三个读数的四到五倍。
这两条失败得很有内容：失败点被量到、原因在源码里、也在数据里（两张掩模的构造不同，16:03 那 41 行的 MB_PART_PTS / MB_PART_REF 比值是 0.579..1.243、均值 0.791；本章这 42 行是 0.653..1.162、均值 0.868，方向一致——活帧掩模系统性比参考掩模小；15.4）。所以本节不留「以后再说」的尾巴——它们的门限不需要再拿好板总体去定，它们的零值本身就压在缺陷的量级之上。替代方向也换了前提：不再拿一张外观掩模做几何判断，而是按颜色对皮带分割、量四个顶点，并预先写下杀死判据（15.7——那是设计，不是结果）。

## 14.7 仍未验证
以下每一条都写明它是什么、为什么还没解决、以及要用什么测量解决它。
① 标签本身。41 块板的 g/d 与四个缺陷名都是操作者的字，没有任何东西核对；本章的每一个比率都从它出发。要解决它：对每一块读数贴近限值的板做「另一名操作者盲复标」，或者在缺陷位置上留下可回看的照片（本章两者都没有）。
② 逐格容差图在这次 sweep 里是否生效，文件不回答。CSV 没有 MB_TOL_* 列。若它生效，DAREA 就是「按这块板的容差判定的面积」，与固定的 30 灰不是同一个量；13.9–13.10 已经量到这张图能吸收一个真缺陷。要解决它：在行里加一列，记录容差图的格数与 MB_TOL_N。
③ d8 的两次摆位不是一次重复性测量。它给的是「同一块板可以差 6 格」这个存在性证据（14.4 的（b）），不是「摆位灵敏度是 6 格」这个量：n = 1 块板、2 次摆位，其中小的那一次还是 coherent=0。要解决它：同一块好板在同一工位上放 5 次、每次一行，用这 5 行算摆位引入的方差；这件事一次 sweep 的边角时间就够了，本章没做。
④ 工作点 6 从来没有端到端跑过。它是量到的 DAREA 上的算术，不是一次运行；而重跑一次要先重取参考（任何一次 reload 都会毁掉参考，参考一换整列 DAREA 就平移——14.1 的⑦）。dl/CONFIG_20261027.md §1 记着 21:10 读回 MB_DIFF_LIM_USED = 6，这是「值装上了」的证据，不是「按 6 跑过一批板」的证据；本次运行的 42 行记的是 10（14.1 的第 4 行）。所以要拿到限 6 的真实运行，得做这样一串：重取参考 → 重扫这 41 块板 → 在行里确认 diff_lim_used = 6。只装不复核的限值是一个希望，不是一次标定。另外，截至本章付印（2026-10-28），dl/CONFIG_20261027.md 有两处会绊住照抄的人：§4 的复现步骤点名的 dl/host_qc/write_pin.py 在仓库里不存在（同一行给的手工 mwr 写法可用）；§3 说 13 行 coherent=0、列了 12 个板号，因为那 12 个是从工具被截断的警告里抄的（14.5 的③，sweep_report.py:424），少的是第 13 个、板 41（d20）。本章一律以 CSV 与工具输出为准，不以任何二手名单为准。
⑤ 「角缺 3/3」的边界。角缺 3 块、弯板 2 块；角缺的 3/3 是「在这套参考下量到的读数、按 6 重判得到」的 3/3，不是「角缺这一类可检」，而且它整个绑在参考 909 上（14.1 的⑦、14.4 的（a））。要解决它：这两类各补足 10 块以上，并在两个不同参考下各扫一次——第二次扫的时候本章的 8、9、12 会变成什么，今天不知道。
⑥ 两处修法已经实现并测量过，都失败了（14.6、第十五章）：stage L 之后，格内极差的零值是 20 格、轮廓差的零值是 825 格（同一块参考板对自己）。所以「用好板总体去定它们的门限」不必再排进计划——它们的零值就在缺陷的量级之上。剩下的未知变成它们在新鲜板上的表现，而不是一个门限怎么定（15.9 的③）。
⑦ 人做的检查，与前面每一章相同：上电前 J10 的 PIN35(B20)↔PIN28(V12) 跳线必须在外面。软件看不到这一条，本章的每一次实测都以它为前提。
⑧ 限 6 与工具印的 7 在这份样本上不可区分，因为没有一块板读 6（也没有一块读 10）。换一份样本，6 与 7 会分开；在那之前，6 是「好板最大值 + 1」这个定义，不是被数据挑出来的那个数。这一条不影响本章任何一个计数，但它决定了下一份样本上该验什么。
（来源：dl/host_qc/logs/sweep_20261027_193725_sweep.csv、同名的 _sweep_refused.csv、dl/host_qc/sweep_report.py（默认即限 10，以及 --current-limit 6 与 --current-limit 8 三种跑法）、dl/host_qc/sweep.py:61-62、327-423、dl/host_qc/logs/sweep_20261027_160133_sweep.csv（只用于「上一版的整类读数」与两张掩模的比值）、dl/CONFIG_20261027.md §1 与 §3、ps_ui/main.c:1774、1919-1924、2663、8172-8203、8220-8246、9062-9099、11795-11826、dl/SWEEP_20261027.md §3.3、§4.2–4.3、§6、dl/ANOMALY_20261027.md §8、dl/REFQ_20261027.md §2；d8 的两次摆位与「误放」是会话记录（两行在 CSV 里，「误放」这个说法来自现场），仓库内没有记录它为什么被放了两次的文件）

# 十五、第二次测量：两个便宜的修法都失败了（2026-10-27 晚）

## 先读这一节：本章与第十四章是两个运行、两套数
本章测的不是板子，是两个统计量。它记录 2026-10-27 傍晚格内极差与掩模轮廓差这两个「便宜的修法」怎样被实现（stage I）、怎样被修（stage L）、怎样上板、被测量，然后被否掉——所以它是一份失败尝试的记录，不是对当前总体的陈述。它引的板端读数全部来自同一次运行：dl/host_qc/logs/sweep_20261027_160133_sweep.csv，2026-10-27 16:03:14 .. 16:33:44 采的 41 行（21 行 good + 20 行 defective；g3 那一行没有 DAREA，工具把它列在 NOT USED，所以好板一侧是 20 块），当次参考帧 MB_PART_REF = 940（该列 41 行只有一个值）。当前总体在第 14 章：dl/host_qc/logs/sweep_20261027_193725_sweep.csv，2026-10-27 19:38:47 .. 21:09:06 采的 42 行、41 块板（21 行 good 全部有读数；21 行 defective 里 d14 没有 DAREA、d8 被放了两次，所以按板是 19 块），参考 909，好板整类 0..5，工作点 6。两套数不能互相印证，也不能互相替换：参考、曝光、限值都不是同一套，缺陷类的成员也不是同一批。
把同样四个类在两个运行下并排放一次（表 15-0），本章开头那句「角缺与细划痕看不见」（14.2、14.4）与 15.6 标题里的 0/3、1/6 就有了归属：它们说的是 16:03 那次加限 10 的读法，不是 19:38 那次的读法。四个类同名，板不是同一批：16:03 那次是污染 9、弯板 2、角缺 3、划痕 6（20 块缺陷板），19:38 那次是 7、2、3、7（19 块有读数的缺陷板，见上一段）。14.5 的⑤已经把这件事量过：d 号是每次运行重编的，同一个号在两次运行里不是同一块物理板，所以能比的只有整类。
两列为什么不同：四件事不同，每一件都能指到文件或一行命令。① 参考不是同一个。16:03 那次是 940，19:38 那次是 909；同一块角缺板在参考 940 下读 DAREA 4、在 909 下读 8（dl/CONFIG_20261027.md 首段），三块角缺板整类从 3、4、7 变成 8、9、12。② 曝光。19:38 那次把曝光钉在 MB_EXP_LOCK = 8698（dl/CONFIG_20261027.md §1），好板的离散因此从 0..9 收到 0..5：16:03 那次的好板就是 0..9（最大 g14 读 9），19:38 那次最大 5（g6 与 g15 两块）。③ 限值是事后重判的，两次都不是「按这个数跑出来的一批板」。采那 41 行的时候板上是 8（CSV 的 diff_lim_used 列只有一个值 8），15.2 里 8 与 10 两个点都是对同一列 DAREA 的重判：按 8 是 13/20（划痕 2/6，多出 d10 的 8），按 10 是 12/20（划痕 1/6，d10 的 8 停在 10 以下）。采那 42 行的时候是 10（同列只有一个值 10），工作点 6 同样是对那一列的重判（14.1 的第 4 行、14.7 的④）。④ 板本身。污染与划痕的块数都变了（9 → 7、6 → 7），编号也重编过。所以每一个分数都要读成「某一次运行的 DAREA 列、按某个限值重判」；把任何一列读成「这一类今天的检出」，都会同时抹掉参考、曝光与限值这三件事。
第十四章的四类分布给出的是一个不动点：污染与变形看得见，角缺与细划痕看不见（14.2、14.4），而且看不见的原因是判据的构造，不是门限的取值。14.6 因此写了两条「便宜的修法」——格内极差与掩模轮廓差——并明确标注为提案：没有代码、没有离线重放、没有板上的数。当天傍晚，这两条都被实现、都上了板、都被测量，然后都被否掉了。本章记录这次否掉：测的是什么、零是多少、原因是什么、下一步换什么。
写法沿用前几章：实测与推导分开，每个数字带产生它的方法与来源。本章多两件事。第一，零（null）是主角：一个统计量在「没有缺陷」时的读数。第二，本章有一个数只能当会话记录读——stage L 之后的零是一次 JTAG 读数，输出没有落盘，仓库里没有这一行的文件（表 15-1 第 4 行）。凡写「会话记录」的地方，读者应把它当成记录，不是文件里的一行。
还有一条形式上的限定，因为它决定了这一轮的代价：两条新统计量都是 publish-only，diff_verdict() 一个字都不读（main.c:2513：「BOTH ARE PUBLISH-ONLY.  diff_verdict() does not read one word of this block.」）。所以在用判据、限值、容差图、配准一个数都没变；这一轮付出的是时间，不是产线行为。这也正是它们可以被否得这么干脆的原因。

## 15.1 这一轮测的是什么，以及证据是哪四份
两轮改动，各一次测量。第一轮叫 stage I：把格内极差与轮廓差算出来、发布出去，19 个新邮箱字（553..571，main.c:2536-2594），不动判据。第二轮叫 stage L：不改这两个统计量的定义，只改它们判哪些格子（以及参考掩模从什么输入建，见 15.5）。中间那一次验收是 stage I 的最后一步，它的结果决定 stage L 要不要做。
证据是四份文件加一条命令，逐份写下来（表 15-1）。没有一份是本章生成的：本章只读它们、引用它们打印的数。
一条方法上的说明，因为它会影响读者对表 15-1 第 1 行的信任：修复前那份 CSV 有 60 列，其中没有 eg_margin、eg_roi、ref_avg 这三列（它们是 stage L 才加进列集的）；stage L 之后的一板一行有 63 列。所以「哪一轮的读数」不是本章的推断，是列集自己说的。

## 15.2 工作点：这个 sweep 支持的两个点
在否掉任何东西之前，先把「要打败的东西」写下来。第十四章没有把任何限值装上去（14.3、14.7 的④），它只给了这个 sweep 能支持的两个点。这两个点本章要引用两次（15.2 与 15.6），所以在这里完整写一次，两个都带区间（表 15-2）。
两个数必须与工具自己的混淆矩阵对上，这是这张表的一次归零检查：限 8 时工具打印 good 19 PASS / 1 NG、defective 7 PASS / 13 NG；限 10 时 20 PASS / 0 NG 与 8 PASS / 12 NG。表 15-2 的检出列（13、12）与好板误杀列（1、0）就是这两对。
两个点之间的差别落在两块贴着边界的板上：好板 g14 读 9，限 8 上 9 ≥ 8 判 NG、限 10 上 9 < 10 放行——这就是限 8 那 1 块误杀；缺陷板 d10 读 8，限 8 上恰好抓住、限 10 上漏掉——这就是检出从 13 掉到 12 的那一块。所以限 8 → 10 换来的是「0 块好板误杀」，代价是「漏掉 d10」。这个交换不是标定，是算术（14.3）。
这就是这一轮的基准：两个新统计量如果想有用，必须把角缺 0/3 或划痕 1/6 这两列抬起来，而不让 0/20 掉下去。它们没有——下面每一节都对着这张表说。

## 15.3 第一次验收：第一个摆位就是零
accept_range.py 走的是一个固定的 54 摆位计划，每个摆位测三个格内门限（T = 12、18、24），不等操作者确认就进下一块。它的第一个摆位是参考板对自己：参考刚刚在同一块板上取过，操作者把板留在原处、走出画面，工具读一次比较。这一行不是「一块好板」，它是零：两张掩模来自同一场景、同一个参考，理论上应该什么都不出来。
读出来的不是零。T = 18 那一行最干净：OUT area 141 格、OUT cells 478 格、EG cells 49 格、EG maxd 101 灰。同一个摆位在 T = 12 与 T = 24 上分别是 OUT area 150 / 149、EG cells 80 / 44。表 15-3 的每一列都能在 CSV 的对应列里逐行核（out_cells、out_miss、out_area、eg_cells、eg_maxd、diff_darea、diff_fvalid）。
这三个数的量级就是问题本身。工具自己的尺子写在 accept_enter.py:112-116：「BEFORE the stage-L fix, this same row read OUT AREA 141..150 / CELLS 470..480 and EG CELLS 44..80 / MAXD 95..109.  A statistic whose null is that large cannot see a corner chip (tens of cells) or a thin scratch (ten-odd cells).」——角缺按「几十格」算、细划痕按「十几格」算，而零在 141..150 与 44..80。两个统计量要抓的东西，都在这两个数自己下面。
其余三个摆位给出的是一样的话：g1 的 OUT area 768 / 417 / 394、EG cells 130 / 72 / 51、DAREA 9 / 5 / 5；g2 的 355 / 369 / 268、108 / 64 / 39、5 / 5 / 4。第四个摆位（g3）在日志里有 T = 12 与 T = 18 两行（DAREA 2 / 5，EG cells 88 / 75，OUT area 621 / 319，EG maxd 126 / 121），第三个门限上没拿到一致的 dump，工具把它重测了一次；按 accept_range.py:647-650 的设计，一个只在三个门限里测到两个的摆位整行丢弃（「a placement measured at two of three thresholds is not that placement's row」），所以 CSV 里是 9 行 = 3 个摆位，第四个摆位只在日志里。操作者在这里停了（Ctrl+C，log:56-57）。
停得有理由，而且理由不是「感觉不对」，是工具自己打印的：那一刻的混淆矩阵是「good 2 boards: DAREA alone NG 0, with the additional conditions NG 2」「FALSE NG on good : 2/2」「DETECTION : 0/0」。也就是说，在「DAREA ≥ 10 或 EG(T=18) ≥ 4 格 或 OUT area ≥ 8」这三个条件里，两块被记录的好板都被判 NG，而缺陷板一块都还没测。一个总体如果第一步就把好板判死，再放五十块板只是在花时间。
这一停也不是随手：计划自己是 54 个摆位、日志估 19..30 分钟（log:6），而实测每个摆位约 68 秒（accept_enter.py:8-9 记着这个数），于是 54 个摆位是一小时以上。停了以后工具换了一个形状（一块板、一次 Enter、一行、一个门限），零从「表格里的一行」变成「第一行、当场问」。这件事写在 15.8。

## 15.4 原因：两张掩模不是同一种输入建的
零为什么是 141..150 而不是 0..5？不是配准错、不是摆位歪，是两张掩模的构造不一样。活帧的掩模建在 LATT_BASE 上，那是 N 帧（本次 n = 8）的平均格；参考的掩模建在单帧的格上（ref_take → latt_fill_into）。平均帧比单帧安静，越过自适应背景门限的格子就更少，于是活帧掩模系统性地比参考掩模小约一格。这件事写在 main.c:2611-2618 与 8266-8283，两处都带着同一个数。
那个数在仓库里，而且是四十块板一直带着的：committed sweep 的 41 行里，MB_PART_PTS / MB_PART_REF 逐行相除是 0.579..1.243，均值 0.791，中位 0.772（41 行全部可用；最小是 g4 的 544/940，最大是 d8 的 1168/940，两个都能在 CSV 的 part_pts、part_ref 两列里找到）。
同一晚的验收里也有这个方向：零那一行的 part_pts 是 638 / 643 / 678，part_ref 是 738——比值 0.865..0.918，方向一致（活帧更小），只是这次同一块板、同一个摆位。
格内极差为什么对这个特别敏感：极差是极值之差，边界格上比较的是「零件的一格」对上「边界的一格」，两侧内容本来就不同，极值差自然最大。main.c:2625-2630 写着这句话和它的数：「measured, the boundary cells alone produced EG maxd 95..126 on good boards」——与这一次验收里三块好板的 maxd 109..126 对得上（g1 109/120/121、g2 120/120/118、g3 126/121）。

## 15.5 stage L：修法与重测——极差好了一点，轮廓更坏
两个改动，都只碰「判哪些格子」和「参考掩模从哪来」，不碰规则本身（BG_MASK_THR、3×3 腐蚀、连通组规则、PART_MIN_PTS、配准、均值统计、DAREA、限值、容差图全部不动）。① 参考掩模改从同一份平均格建：ref_take 里把 LATT_BASE 拷进 PART_LATT（main.c:8284-8293；三种不适用的情况写在 8276-8283），由 MB_REF_AVG（574）发布，0 = 单帧（老路径）、N = N 帧均值。② 两个新统计只判两张掩模交集内缩 MB_EG_MARGIN（默认 2）格的格子，判定函数 part_margin_ok()（main.c:8734），ROI 由 MB_EG_ROI（573）发布。它只门控新统计：MB_DIFF_FVALID 与 MB_DIFF_DAREA 的总体一个格子都没变，所以在用判据不可能因此移动。
修复在板上生效这件事有文件证据，不靠断言：18:38 那次一板读数的参考检查那一行印着「REFERENCE ACCEPTED (MB_PART_REF=766, averaged over 8 frames)」（enter_20261027_183840.log:19），d2 那一行印着「margin=2 refavg=8」（同 .log:25），报告的尾部印着「margins: MB_EG_MARGIN = [2]」（.log:36）；另一次运行的前置检查直接印「ref_avg=8」（enter_20261027_184252.log:8）。MB_REF_AVG 与 MB_EG_MARGIN 这两个字只在 stage L 的固件里存在，所以 ref_avg=8 本身就是「修复加载了」的读数。stage L 的提交当时写的是 NOT FLASHED（75a65dc），也就是它在 17:36 之后、18:38 之前被加载到板上——否则 ref_avg 不可能读到 8。还有一条更直接的，也在同一行里：d2 那一行带着镜像本身的戳，fwid1 = 1110983986、fwid2 = 876101937，按内存顺序各解成四个字符是「2E8B」与「1A84」——ps_ui/build_id.h 的 FW_SRC_HASH 就是 2E8B1A84，而 MB_FWID 的字节序读法写在 13.13 的③（按字读会反转每四个字符）。所以「板上跑的是 stage L」不是推论，是那一行自己写下来的；ref_avg=8 只是第二个证据。
三条读法，都从表 15-4 里出来。
① 格内极差好了一点，但零还在信号上面。20 格（原 44..80）是 2.2..4 倍的改善，可划痕类在在用判据上最大只读到 11 格（d5），零仍然约为那一类最大读数的两倍。更要紧的是极值：EG maxd 从 95..109 变成 132，比修复前三块好板里最高的 126 还高。把边界排除之后，剩下的格子里仍有一格差到 132 灰——这个统计量的极值不是边界给的，是零件表面自己的。
② 轮廓差变坏了，而且是量级上的坏。OUT area 141..150 → 825（5.5..5.9 倍），OUT cells 470..480 → 834，OUT miss 310..315 → 436。825 比参考掩模自身的 766 格还多 8%。一个缺角是几格到几十格（角缺三块板在在用判据上读 3、4、7），而 825 是整张掩模的边界在两张不同帧的掩模之间错开一格的结果——这个量从构造上就不是缺角的量。还有一条同样从这两个数里出来的：最大的连通组占不一致格子总数的比例，修复前是 150/480、141/478、149/470（都在 30% 上下），修复后是 825/834 = 99%。也就是说，修复把「分散的小块」变成了「一整块」。main.c:2569-2573 写着这个统计量的设计假设：「A compact missing piece is one group; the scatter of an edge that quantized differently is many small ones」——这一次的零值把这句话反过来：边缘抖动本身就是一个 825 格的连通组，而一个缺角要在这个量里显形，得比整圈边界还大。
③ ROI 101 / FVALID 412：margin 把 311 个格子排除在外，占 75%。这不是顺手一提：它说明 20 这个数是在 101 个格子里数出来的（不是 412 个），也说明「只判零件内部」这句话落到实处的代价。
零这一行的来源要单独说一句：enter 模式当晚试了三次零——18:38（g0，与 d2 同一次运行）、18:42、18:43，两次「the comparison's words did not repeat (torn dump)」、一次 stdin 关闭（enter_20261027_183840 / 184252 / 184345），所以文件里零那一行是被拒绝的一行，不是读数。可用的零只有一次 JTAG 读数（ps_fft_dual/a3_null_20261027.tcl 读 367/23/496、556/557/573/572/574、565/566/567 这些字），输出没有落盘——会话记录。这一次读数不印门限（MB_EG_THR_USED = 555 不在脚本里），但 20 低于修复前三个门限下的每一个值（80、49、44），所以「改善」这个结论不依赖它是在哪个门限上读的。
同一个固件下还有一块缺陷板的一行：d2（角缺）读 DAREA 4、FVALID 559、EG roi 195、EG cells 38、EG maxd 122、OUT cells 552、OUT miss 293、OUT area 358、margin 2、refavg 8（enter_20261027_183840.csv 第 2 行，T = 18）。358 比零的 825 低——缺陷板在这个统计量上的读数比零还小。一块板，不能当检出率，但它把这个量从「推算出来的边界量」变成了一条读数：它不认缺陷，认边界。

## 15.6 两类的后果：角缺 0/3、划痕 1/6，原因在掩模的语义里
结果是这两类一块也没多出来。用 sweep 的读数说：角缺三块读 3、4、7，划痕六块读 2、3、6、7、8、11（14.2 的表 14-2）。在限 10（表 15-2 的工作点）上角缺 0/3、划痕 1/6（只有 d5 的 11 越线）；在在用的限 8 上划痕 2/6（多一块 d10 的 8）。
「在任何限值上」这句话要写准：能把 3 格角缺抓进来的最低限值是 3，而在限 3 上 20 块好板里有 13 块会被判 NG（14.3 的算术，用工具打印的 count per value）。所以不是「还没找到合适的限值」，是这两类与好板在同一个数轴上，抬高和放低都在别处付账。
原因不在统计量的实现，在掩模是什么。角缺是一个掩模差：缺掉的那一块在活帧掩模里不存在。而这张掩模是外观分割——它的规则是「不是背景」（stage E 之后的定义），不是「不是皮带」。外观分割的边界跟着表面走：反光、阴影、丝印、元件边缘、相机噪声，每一样都会让某几个格子在「是零件 / 不是零件」之间翻一次。量化在 8×8 的格上，这个抖动就是 1–2 格。而缺角本身也是这个量级——所以边界噪声与要抓的缺陷同阶，任何一个「数掩模差」的统计量都会把噪声当成缺陷。
1–2 格这个数有两个可查的来源，不是估的：一是 15.4 量到的两套掩模之间约一格；二是掩模本身量化在 8×8 格上（stage I 的轮廓统计给每一侧留 1 格容差，stage L 的 margin 取 2，两处都写着理由：main.c:2553-2557 与 2625-2630）。
两条旁证，都在 sweep 的 CSV 里，都能逐行核。① 污染板的框长到 116..120 格（9 块里 5 块，part_edge = 1，即掩模碰到画面边缘），而好板的框是 48..119 格（g5 的 48、g12..g15 的 113..119）——两类重叠，所以框不是缺陷信号，它跟的是「掩模有没有被画面边缘切掉」。② 三块角缺板的框宽是 45、56、57 格（d2 45、d6 56、d11 57），落在好板的 48..119 里面——MB_PART_BX0..BY1 完全分不开它们。也就是说，连「用外框代替掩模」这条便宜的退路也不成立。

## 15.7 下一个设计：按颜色对皮带分割，比较四个顶点（设计，不是结果）
两条修法败在同一个地方：它们都拿一张外观掩模去做几何判断。下一个设计换的是这个前提，不是参数：分割依据从「外观」换成「物理边」。板和皮带是两种材料，颜色差是实的；对皮带做颜色分割（绿色 PCB 对白皮带），得到的是零件的物理轮廓。在物理轮廓上，「少了一块」是轮廓的一个角被切掉，而不是「某些格子不再被判」。
流程：分割 → 四条边各拟合一条直线 → 四条线的四个交点就是四个顶点 → 活帧与参考帧的四个顶点相减，得到四个标量（每个顶点 dx、dy）。缺陷的信号就是受影响的那个顶点的位移，与「整张掩模的边界抖多少」无关。
在写代码之前先写下杀死判据（预注册，不许事后改）：① 同一块板对自己（零）：四个顶点偏移必须 < 1 格。做不到，这个设计就地作废，不调参数去凑。② 一块角缺板：在受影响的顶点上必须读到 ≥ 3 格。做不到，或者只有把①放松才做得到，同样作废。两条一起看才有意义：①保证零小，②保证信号在零上面一个量级。这也正是这一轮缺的东西——stage I 的两个统计量从来没有这样的两条，它们只有「看起来应该可以」。
这个设计还免费送一个答案，而那个答案今天的数说没有：空皮带上颜色掩模读约 0 格。于是「有没有零件」第一次有一个不依赖它自己要判的那张掩模的答案。今天这个站不能回答这个问题：空皮带上「不是背景」的掩模读 3520 格、框是整个画面（dl/CAM1_AEC_20261026.md:183），而相机 0 的 AEC 在 93.2 s 的 160 个样本里换了 14 次 k（2×151 / 3×9，dl/AEC_EMPTYBELT_20261026.md:27-28），因为它的掩模项把「参考里有零件、现场没有」读成「光不够」，往亮里推（同文件 §1）。同一个根本原因：掩模的范围是整帧的「不是背景」，房间里的东西也进掩模；空皮带上那些格子就是掩模。
三条限定，写在它还只是设计的时候：① 没有代码、没有离线重放、没有板上的数——本节任何一句话都不是结果。② 四个顶点要在 160×90 的格点上量到 1 格以内，这是最大的未知数：格是 8×8 源像素，顶点精度只能来自四条直线的亚格外推，而拟合本身对边缘噪声敏感。③ 它对划痕这一类什么也没说：划痕是表面缺陷，颜色分割是轮廓量。角缺与划痕是两类不同的失败，一个设计只解决其中一类是可以的，但不能假装两类都解决了。

## 15.8 流程教训：第一次摆位就是零
这一轮从实现到否掉花了两个小时，而不是两天，唯一的原因是：第一个摆位就是零，而且有人愿意停下来读它。零是表里最便宜、也最有决定性的一行——它不需要缺陷板、不需要操作者排队、不需要一整个下午，它只需要把参考板放回原处、人走出画面。第一次的实现把这一行放在 [1/54]、印出来、然后自动往下走，于是这个数被印了而没有被问；等表格出来，操作者已经放了四块板、后面还排着五十块（accept_enter.py:92-99 记着这件事）。第二次的实现把零放在第一行、印出来、并且在它不小的时候拒绝继续：out_area > 20 或 eg_cells > 10 时，它印出这两个数和一句「STOP HERE and fix the statistic; do not run a population on it.」（accept_enter.py:117-125、:315-322）。规则写下来：任何新统计量，进总体之前先测零；零不比要抓的缺陷小一个量级，就不测总体。这条规则一晚上赚回了一个下午，而且它是可执行的——它只有两个数和一个 if。

## 15.9 仍未验证
以下每一条都写明它是什么、为什么还没解决、以及要用什么测量解决它。
① stage L 的零只有一次 JTAG 读数，输出没有落盘。它是会话记录（表 15-1 第 4 行），不是文件里的一行；文件里零那一行是「torn dump」的拒读。要解决它：把 a3_null_20261027.tcl 的输出落盘，或者在 enter 模式下把零测成一行可用的读数（三次尝试都没有做到，这本身是个缺陷）。
② 「825 是整圈边界」是量级推断，不是逐格证明。掩模网格不在任何文件里（CSV 只有计数与框），所以「周长」这个数在仓库里算不出来。825 > 766 是硬的（同一份读数里的两个数），「它量的是边界」是从这个比较与 15.5 的机制推出来的。要解决它：dump 一次掩模网格，或者在固件里把 OUT 的连通组按「边界格数 / 内部格数」发布。
③ 修法只在两块板上量过。stage L 下真正量过的缺陷板只有 d2 一块（一行）；角缺 3 块、划痕 6 块都没有在 stage L 下重测。所以「修法救不了这两类」这句话，在 stage L 上是 1 块板的证据 + 零值的算术，不是 9 块板的证据。要解决它：把这 9 块板在 stage L 固件下各测一行（老工具每个摆位 68 秒，或者 accept_enter.py 的 Enter 节奏）。
④ 修复前的验收没有重跑。9 行 CSV 是那一次的全部；第四个摆位的两行只在日志里，而且第三个门限上本来就没读到。本章不补它。
⑤ 颜色分割 + 四顶点只是设计。没有代码、没有离线重放、没有板上的数，也没有好板总体去定顶点偏移的门限。预注册的杀死判据写在 15.7——它是判据，不是结果。
⑥ 工作点 6 已经装上去了（dl/CONFIG_20261027.md §1 记着 2026-10-27 21:10 读回 MB_DIFF_LIM_USED = 6），但从来没有端到端跑过：它是对 19:38 那次（采那 42 行的时候板上是限 10，CSV 的 diff_lim_used 列只有一个值 10）的 DAREA 重判到 6 得到的算术，不是一次按 6 跑过的运行；也没有在第二份样本上复核（14.7 的④仍然成立，本章没有改变它）。
⑦ 人做的检查，与前面每一章相同：上电前 J10 的 PIN35(B20)↔PIN28(V12) 跳线必须在外面。软件看不到这一条，本章的每一次实测都以它为前提。
（来源：dl/host_qc/logs/accept_range_20261027_172150.csv 与同名 .log、dl/host_qc/logs/enter_20261027_183840.csv 与同名 .log（另两次 184252、184345）、dl/host_qc/logs/sweep_20261027_160133_sweep.csv、dl/host_qc/sweep_report.py（限 8 与 --current-limit 10 两种跑法）、dl/host_qc/accept_range.py:647-650、dl/host_qc/accept_enter.py:8-17、92-125、315-322、ps_ui/main.c:2513、2536-2594、2605-2653、3428-3433、8284-8293、8734、9890-9893、ps_fft_dual/a3_null_20261027.tcl、dl/AEC_EMPTYBELT_20261026.md §1 与 :27-28、dl/CAM1_AEC_20261026.md:183；stage L 的零与它的重测数字来自会话记录，仓库内没有对应文件）

# 十六、资源、时序与延迟：98.93% 的 BRAM、+0.908 ns 的余量，与一个 176.6 ms 的循环（2026-10-28）
本章回答三个问题，每个都有可复算的来源：这块板用了多少（资源）、能不能跑在 50 MHz 上（时序）、一圈要多久（延迟）。前两个的答案在几个报告文件里，随时可以离线复算；第三个的答案只在板上的邮箱里，而它今天多数只有会话记录。两者的可信度不是一回事，所以本章把它们分开放，并在每一张表里给出处。
写法沿用前几章：每个数字带来源，实测与推导分开，测不到的写「未测」并说明用什么测才能测到。本章另加一条限定，它决定了读者该怎么用这一章：资源与时序是静态的（打开 checkpoint 跑一遍 report_utilization 就得到，跟板子通不通电无关）；延迟是动态的（必须在板上、在跑着的、在某个具体构建上读，换一个构建就不算同一个数）。

## 16.1 说的是哪个比特流：一份哈希，两个文件
本章说的「这块板」指某个具体的比特流，不是任何一个 .bit 文件。身份由一条命令确定：对 safe_bitstreams/BIT_20261024_fp1.bit 与 Vivado 实现目录里的 design_1_wrapper.bit 各跑一次 Get-FileHash -Algorithm SHA256，两个值必须相同。本章付印前又跑了一次：两个都是 BAF0DCE1C1AE941B3BED4124B6283A71B9208EFB98EE1C02B91C33E4852B2DF8，都是 4,045,676 字节。所以「实现报告说的就是出货比特流」不是推断，是同一个哈希。
Vivado 工程目录不在提交物里（在另一块盘上），仓库里只有这份比特流副本、构建脚本与两份报告的副本。评委没有那个工程也能核对本章的全部资源与时序数字：报告副本在 dl/evidence_20261027/ 下，产生它们的 Tcl 脚本（fp1_reports_20261027.tcl）也在，跑一次约两分钟，不需要板子。
固件身份另算，它不在这份比特流里：ps_ui/build_id.h 的 FW_SRC_HASH 是 7C54944F，板端 MB_FWID0..2 读回 TSC1 7C54944F（读法与字节序见 13.13 的③）。本章的每一个板端读数都属于这份镜像；资源与时序属于那份比特流。
一条要写下来的历史，否则「出货比特流」这个词会骗人：比特流是 2026-10-24 的，固件是 2026-10-27 19:21 的，两者不是同一天的东西。这一章里的资源与时序因此是「10-24 那版 PL」的数，延迟是「10-24 那版 PL + 10-27 那版 PS」的数——它们可以放在一张表里，但不能被读成「同一次构建的全部指标」。

## 16.2 资源：98.93% 的 BRAM 与 99.55% 的 DSP
实现后报告（Routed 状态，dl/evidence_20261027/fp1_util_routed_20261027.rpt，2026-10-27 19:19:08 从 routed checkpoint 重跑）给的是表 16-1。同一次实现自带的 placed 报告（10-24 13:04:21）逐格相同，所以「place 之后的网表就是最终网表」这句话有两条独立来源，而不是一句自我声明。
几个能直接读出来的事。第一，BRAM 只剩 1.5 个 tile，DSP 只剩 1 个——140 − 138.5 与 220 − 219 是减法，不是估计。任何「再加一个数据通路」的想法都得先删东西。第二，LUT 的 68.63% 里有 2,306 个是当存储器用的（分布式 RAM 260 + 移位寄存器 2,046），真正的组合逻辑是 34,207 个、64.30%，所以 LUT 这一项的余量比 68.63% 看起来的宽一点，但 BRAM 与 DSP 一点不宽。第三，Bonded IOB 只用了 62/125：这 62 个是两路相机 + LCD + 触摸，占用不高，说明这颗器件的瓶颈不在引脚，在片上存储与乘法器。
这一节没有「与基线的对比」，只有一句能站住的：2026-10-19 那次记录是 61.68% LUT / 78.21% BRAM / 99.55% DSP（dl/PERF_RESOURCE_20261019.md），今天 BRAM 从 78.21% 涨到 98.93%，涨的是四帧存储与探针，DSP 没变（CNN 一直占着）。这不是一次受控 A/B：两次之间加的是功能，不是优化；把它写成「优化过程」是不诚实的，所以本章只把它写成「这段时间资源花在哪」。

## 16.3 时序：WNS +0.908 ns、WHS +0.037 ns，以及 52.4 MHz 的推算
同一个 checkpoint 的时序摘要（dl/evidence_20261027/fp1_timing_routed_20261027.rpt，2026-10-27 19:19:41）给的是表 16-2。
最差的那条路径不在视频通路上，在卷积核里：源是 ts_cnn_top 的 gmem2_m_axi 的一个 RAMB36E1，宿是 grp_conv3x3_32_32_32 流水线的一个寄存器，数据路径 18.730 ns，其中 16.605 ns（88.7%）是布线，逻辑只有 2.125 ns。这条路径的余量是被拥塞吃掉的，不是被逻辑深度吃掉的；同理，WHS 只剩 37 ps 意味着任何一点时钟偏斜的变化都可能把它推负。这两条合起来就是本章对「还能不能加东西」的回答：不能。
设计时钟只有四个，全部来自 PS7 或端口约束，另加 ARM 自己（表 16-3）；器件里的 MMCM/PLL 一个都没用（表 16-1 的最后一行）。
两条限定。第一，lcd_pclk 由 FCLK_CLK1 驱动（输出到端口），XDC 又在端口上按 30.300 ns 建了一个钟；30.300 比实际的 30.555 ns 紧 0.84%，所以这个约束是偏保守的，不是放松。第二，ARM 的 667 MHz 不是本章读的：它来自 PS7 的 IP 参数与同一天早些时候的板端 SLCR 读回（dl/RESOURCES_AND_LATENCY_20261027.md §4.1）。PS 的时钟树不随固件变，所以这条可以搬；但严格的写法是「在 PS7 的 XSA 与那一次读回上成立」，本章这样写。

## 16.4 那 219 个 DSP：一个能跑、但没有任何判定读它的加速器
资源表里最大的一笔是 DSP：219/220，几乎全在 HLS 卷积核 ts_cnn_top 里。BRAM 的大部分也在它那里。这一节是本章唯一一条「资源花了、回报没有落在判定上」的事实，所以它单独占一节。
到 2026-10-27 为止，它一个结果也没产出过，原因不在加速器，在数据：权重从来没有进过 DDR。cnn_init() 只把六个指针写进 s_axi_control_r，而那 147,672 字节的 wq/mtab/stab/btab 只编进了 cnn_weights.h，main.c 不包含它。于是 IP 读的是 DDR 的上电垃圾。MB_CNN_OK = 1 只证明 AXI-Lite 通，不证明它算出了东西。
同一天晚上这条被修好了，而且是主机侧修的，固件一个字没改——不重编就不换 build_id，不换 FWID，也就不会丢掉已经验证过的参考帧。修法：用 JTAG 把四个 blob 写进 DDR，再发 MB_CMD = 7，让固件自己的 cnn_selftest_run() 跑全部 8 条测试向量、与 Vitis HLS 的 csim 结果逐位比较。结果：MB_CNN_PASS = 8/8，16 个 logit 全部逐位相同（ps_fft_dual/logs/cnn_kat_20261027.log，2026-10-28 10:46:02 的又一次运行；dl/CNN_KAT_20261027.md §2 记着 2026-10-27 21:25–21:35 之间的五次）。一次命令跑八条向量是 212 ms，前一天的五次是 220–247 ms，即每条约 26–31 ms。它现在每 16 个循环跑一次（main.c:15243），所以它确实在按帧工作。
然后必须写清楚它没做什么。第一，它的输出没有任何判定读：判定路径里没有一个 CNN 字，g_cnn_pass / g_cnn_ok 只出现在发布与显示代码里（dl/CNN_KAT_20261027.md §5）。第二，8/8 证明的是通路，不是精度：被比较的另一端是同一份源码的 csim 答案，而这套权重不是在这个项目的缺陷数据集上训出来的——用我们的数据重训仍然是待办（dl/PENDING_20261028.md 第 13 条）。用一句话说：它今天算的是一个 HLS 模型的答案，不是这条产线的答案。第三，面板上那行还写着 "CNN NOT IN PATH"：这句话今天在「它在不在跑」上是过时的，在「判定读不读它」上仍然是准确的。
评分细则对这一笔有明文要求。3.3.4 的第一条是「在目标器件上取得可测量的性能表现，并给出与基线的对比」，第二条是「合理使用片上资源，避免以显著的资源代价换取有限的性能收益」（dl/amd_guide_text.txt:850-855）。用 99.55% 的 DSP 换一条不进判决的通路，按这条标准读就是「显著的资源代价、有限的性能收益」。本章不把这句话说圆：这 219 个 DSP 目前是一笔可辩护、但没有回报的支出。可辩护的部分是它证明了 PL 侧的 AI 通路在本工程里能跑通、而且与 HLS 仿真逐位一致——这是一个真实的工程结论，不是摆设；没有回报的部分是它不改变任何一块板的判定，也不改善任何一次测量。要把「支出」变成「投资」，只有两条路：把它接进某个判据（需要重训 + 重烧 + 重扫，见 dl/PENDING_20261028.md 第 13 条），或者把资源让出来（第 14 条记着为什么这一版不删）。两条本章都没做。

## 16.5 为什么比较、配准、AEC 与门限留在 ARM 上
这一段是设计理由，不是结果，但「硬件加速在哪」一定会被问，所以它写在报告里，而不是留在心里。
第一层：比较这件事摊薄之后很小。一次比较 135.3 ms（16.6），但它每 16 个循环才做一次，摊到每循环是 135.3 / 16 = 8.5 ms，占一个 176.6 ms 循环的 4.8%（上一版三个窗口是 4.8–6.4%，dl/RESOURCES_AND_LATENCY_20261027.md §7）。也就是说：即使把它做成一个零耗时的 PL 块，循环最多快 5%，而这 5% 还要先付掉 DDR 带宽与四帧存储的代价——而 BRAM 只剩 1.5 个 tile（16.2）。每循环真正的开销是三项：渲染（约 43 ms，推导见 16.6）、8 帧平均采样（每次 29.4 ms，每 16 循环 8 次，摊薄 14.7 ms）、零件跟踪（MB_PART_TK_MS，同一天上一版读 4.86–12.55 ms）。把比较搬走，省的是最小的一项。
第二层：PL 没有余量，PS 也没有。PL 那一边是 98.93% 的 BRAM 与 99.55% 的 DSP（16.2）；PS 这一边更紧——固件被压在 128 KB 的 OCM 里，2026-10-27 两次实测分别是 131,016/131,072（剩 56 字节，dl/CNN_KAT_20261027.md §4）与 127,812/131,072（剩 3,260 字节，dl/STAGE_Q_20261027_colour_edge_quad.md:15-20）。一个新数据通路在两边都没有地方放。
第三层：这不是「软件慢所以先算了」。比较、配准、AEC 与门限之所以在 A9 上，是因为它们要读的是 PS 已经映射好的帧缓冲、要改的是 PS 已经写好的参考与容差图、要判的是跨 6 个循环的历史（16.8 的去抖）。把它们搬进 PL，搬的不只是算法，还有一整套状态与一致性。这一条是判断，不是测量，本章把它标成判断。

## 16.6 延迟：176.6 ms 的循环怎么拆
下面这一节的读数全部来自一个 32 循环窗口的邮箱和，定义在 main.c:10116-10125：MB_T_* 是 32 个循环的累加和，除以 MB_T_N（本次 = 32）、再除以 334,800（全局定时器的 334.8 MHz，一个 tick 约 2.987 ns）就是毫秒。
这一整节的来源是会话记录。产生它们的脚本在仓库里（ps_fft_dual/a3_latency_20261028.tcl 与 a3_e2e_20261028.tcl，只读 mrd），脚本的输出没有落盘。测量时间 2026-10-28 10:55，板上跑的是出货构建 7C54944F——不是 dl/RESOURCES_AND_LATENCY_20261027.md 量的那个 stage-L 构建（那一份的固件哈希是 2E8B1A84），所以本章不搬那一份的数；那一份只作旁证，写在 16.7 的末段。要把它变成可核对的行，把这两个脚本的输出重定向进一个文件即可（16.10 的①）。
最后一行是这张表的归零检查：六段之和恰好等于总字。这不是巧合，也不是四舍五入的运气——六个数各取到 0.1 ms，最大能偏 ±0.3 ms，而它们加起来正好是 176.6，说明它们来自同一个窗口、同一次发布。（第七个字段 MB_T_PUB（78）只发布计数，量级 0.0004 ms，在 0.1 ms 的刻度上不可见，所以这张表只有六段。）
段名不能照字面读。cam = 66.0 不等于「渲染 66.0 ms」：比较在 cam 段里（每循环摊 135.3/16 = 8.5 ms），平均采样也在里面（每 16 循环 8 次，摊 29.4/2 = 14.7 ms）。用固件自己的子字拆开是推导：draw_camera ≈ 66.0 − 8.5 − 14.7 = 42.8 ms。所以「每循环真正的开销」是渲染约 43 ms、平均采样摊薄 14.7 ms、零件跟踪 5–13 ms——这三项加起来已经超过一个循环的 60%，而比较只占 4.8%。这个拆法是算术，不是测量；要把它变成测量，得给 draw_camera 一个自己的计时字。
三个更小的字各是一次动作的成本（表 16-5）。它们都是「最近一次」的量，不是均值。
两个坑要写下来，否则读者会自己撞上。第一，这个字的名字叫 MB_DIFF_MS，但它的单位是 ticks：main.c:2346 写着「ticks the last comparison took」，主机除以 334,800 才是毫秒。照名字当毫秒读，45,298,440 就是 12.6 小时，不是 135.3 ms。第二，配准的 11.9% 是 16.1 / 135.3 算出来的（上一版是 10.4–12.5%），不是读出来的。

## 16.7 端到端：141.4 ms 的均值，345.7 ms 的尾巴
固件自己量的还有另一条路径，它比「循环」更接近用户看到的东西：从 cam_bracket_sync() 之后（「看见一帧采集完成」）到 DIS_PARK 翻页之后（「这一帧成为显示屏扫描源」），中间包含比较与绘制。main.c:15530-15533 把 sum / max / n / last 发布在字 160..163，而单位是全局定时器的 tick，不是微秒——main.c:15444-15450 写着这句话和理由（主机除以 334.8 MHz，固件里不除，免得给一个要被拿去和它的分段比较的数字再加一次取整）。
同一个 32 循环窗口：均值 141.4 ms，最大 345.7 ms（n = 32）。会话记录（16.6 第一段的第二句适用于本节每一个数）。
自洽检查有一条能用：稳态下 E2E ≈ 循环 − 等采集交接 = 176.6 − 35.8 = 140.8 ms，与 141.4 差 0.6 ms（0.4%）。两个独立的字（160 与 70/76）互证，这是这两组数属于同一台板、同一段时间的证据——如果它们是两次不同时期的读，这个等式不会闭合到 0.4%（上一版的窗口 B 就没闭合，差 24 ms，dl/RESOURCES_AND_LATENCY_20261027.md §5.4a 记着这件事）。尾巴 345.7 ms 是这 32 个循环里最坏的一次，约为均值的 2.4 倍；上一版三个窗口的最坏值是 324.5 / 351.5 / 377.6 ms，同量级。
一个不要照抄脚本的坑。a3_latency_20261028.tcl 打印这一行时把 sum/n 与 max 都除以 1000.0 并标成「ms」。对 334.8 MHz 的 tick 来说这个除数是错的（结果偏大 334.8 倍），照抄它的输出会读成四万七千多「ms」。本节的 141.4 与 345.7 与 /334,800 一致、与那一行不一致。要复现，就用 a3_e2e_20261028.tcl 打原始四个字，自己按 334,800 除。这条与 13.13 的③、15.5 的字节序是同一类事故：单位与字节序写在源码注释里，不写在变量名里。

## 16.8 判定上屏：一个推导出来的区间
上面两个量都不是「判定上屏」的时间，而面板上显示的是判定。这两件事差一整轮循环，而且比一轮更远，原因在代码顺序里：判定投票（main.c:15145-15168）读的是上一次比较发布的字（本循环的比较在后面才跑），所以比较 N 的结果在循环 N+1 才进投票；去抖（main.c:15153-15166）规定 NG 立即采纳，而 PASS / CANNOT JUDGE 必须连续 6 个循环一致才发布。
上一版三个窗口给的是 0.42–0.45 s（新 NG）与 1.24–1.33 s（新 PASS）；这一个窗口落在上端，因为它 141.4 ms 的均值本身就比上一版的 118.6 与 130.8 高。所以可以引的区间是 ≈0.42–0.45 s 与 ≈1.24–1.33 s。
这一张表的每一个数都是推导，不是测量。diff、mean 与循环周期是实测的（或者说是会话记录的），但「判定上屏」在固件里没有任何计时字；要把它变成实测，得在 draw_panel() 之前加一个字记录本次判定的循环号或时戳，那是改设计 + 重编 + 重烧，本次离线规则不允许，所以不做。本章因此只给到「一个区间 + 它的推导式」，不给更精细的说法，也不在面板上那句话的含义上做任何更强的声明。

## 16.9 四个没有计时字的地方
下面四件事没有被计时。本章不为它们给任何数，也不写「应该不慢」——按前几章的规矩，未测就是未测，附上用什么测才能测到。
① 一帧的曝光 + VDMA 写入（「光子到 store 完整」）。要测它需要 ILA 或 PL 时戳，属改设计。固件里唯一相关的是采集间隔 MB_CAP_PERIOD（96,991 / 114,866 µs，两次读），但那是帧率的倒数，不是这一段的延迟；把采集间隔当成「曝光时长」会多算一整个读出时间。
② ref_take() / 背景采集。它只在开机或命令时跑一次，没有计时字。这是本章最容易被追问的一处：参考的质量闸门（REFQ）就发生在它里面，参考掩模要不要按 N 帧平均建也由它决定（MB_REF_AVG），而它自己的成本没有数。要测它：在 ref_take() 前后各加一个字，或者在主机侧量 MB_CMD = 9 的响应时间（那会把 JTAG 轮询也算进去）。
③ LCD 扫描输出本身。翻页只是把 DIS_PARK 写过去，之后到肉眼看见最多还要一个面板帧；要测需要光电或相机对拍。所以 16.8 的「上屏」严格说是「成为扫描源」，不是「出现在玻璃上」——两者的差最多一个面板周期，本章不替它猜一个数。
④ 面板那条「判定」文字从投票到上屏的路径，也就是 16.8 推导的那一段。它没有自己的计时字；draw_panel() 的 1.0 ms 只是「画」的时间，不含去抖的等待。

## 16.10 仍未验证
本章的每一条限制都写在这里，以及要用什么测量解除它。
① 16.6–16.8 的板端读数只有会话记录。脚本在仓库里、输出不在（16.6 第二段）。要解决它：把 a3_latency_20261028.tcl 与 a3_e2e_20261028.tcl 的输出重定向进 dl/evidence_20261028/ 下的文件；两条都只做 mrd，不改任何东西，是一次纯读取。这是本章最便宜、也最该先做的一件事。
② 六段是一个窗口的均值，不是分布。一个 32 循环窗口给不出方差；上一版量过三个窗口（159.1 / 176.6 / 177.5 ms），说明窗口与窗口之间能差 11%，本窗口落在中位。所以本章不写「循环是 176.6 ms」，写「这个窗口是 176.6 ms」。要解决它：连读三个窗口，把三个总字一起写出来。
③ 判定上屏全程是推导（16.8）。它有代码依据（投票读上一次比较、NG 立即、PASS/UNK 六循环），但没有任何计时字。要解决它：在 draw_panel() 之前加一个字节的时戳或循环号，重编重烧后再测——那会换 FWID，也就意味着重取参考与重扫（14.1 的⑦），代价不是一行代码。
④ 那一笔 219 个 DSP 的回报仍未取得。它的输出不改变任何判定（16.4），而它占了 99.55% 的 DSP 与大部分 BRAM。要么把它接进某个判据（需要重训 + 重烧 + 重扫），要么把资源让出来；两件事本章都没做，也不声称其中哪一件容易。
⑤ ARM 的 667 MHz 是在另一天的固件上读的（16.3 的第二条限定）。PS 的时钟树不随固件变，所以这条可以搬，但本章把它写成「在 PS7 的 XSA 与那一次板端读回上成立」，不写成「本章读到的」。
⑥ 「与基线的对比」只有一处是真的对比。16.2 那次 10-19 → 这份比特流（10-24）的资源变化不是受控实验（两次之间加的是功能）；16.5 的分段占比是同一份样本内部的算术。评分项 3.3.4 要的那张「优化前后」表，本工程今天拿不出受控版本——拿得出的只有 dl/PART_MASK_PERFRAME_20261026.md §4 的那一次（同一版本、只改 MB_PART_TK_ON，循环 104.9 → 138.0 ms），而它是让循环变慢的。这一条本章不掩饰。
⑦ 人做的检查，与前面每一章相同：上电前 J10 的 PIN35(B20)↔PIN28(V12) 跳线必须在外面。本章的每一个板端读数都以它为前提。
（来源：dl/evidence_20261027/fp1_util_routed_20261027.rpt、dl/evidence_20261027/fp1_timing_routed_20261027.rpt、dl/evidence_20261027/fp1_reports_20261027.tcl、safe_bitstreams/BIT_20261024_fp1.bit 与其实现产物（Get-FileHash，同哈希同字节数）、ps_ui/build_id.h、ps_ui/main.c:1774、2216、2346、2439、10116-10125、15145-15168、15153-15166、15243、15444-15450、15530-15533、ps_fft_dual/vivado/two_fft.xdc:10、ps_fft_dual/logs/cnn_kat_20261027.log、dl/CNN_KAT_20261027.md §2、§4、§5、dl/RESOURCES_AND_LATENCY_20261027.md §2.2、§3、§3.1、§4.1、§5、§7、dl/STAGE_Q_20261027_colour_edge_quad.md:15-20、dl/PERF_RESOURCE_20261019.md、dl/PART_MASK_PERFRAME_20261026.md §4、dl/PENDING_20261028.md 第 13、14 条、dl/amd_guide_text.txt:850-855、dl/CONFIG_20261027.md §1；16.6–16.8 的板端数字来自会话记录（ps_fft_dual/a3_latency_20261028.tcl 与 a3_e2e_20261028.tcl 的输出没有落盘），仓库内没有对应的输出文件）

## 16.11 更正（2026-10-28 补记）：平均采样的上限、class 的构成，与一个时钟常数
【更正一：平均采样的上限不是 14.0 ms】16.5 与表 16-5 用的是 `MB_AVG_TICKS` 的 29.4 ms/次，据此「摊薄 14.7 ms」；扣掉替换读的 1.4 ms/次，上限就是 14.0 ms，占那个 176.6 ms 窗口的 7.9%。这两个数都不对。2026-10-28 在同一个构建上连采 20 个窗口，`MB_AVG_TICKS` 读 mean 39.00 ms、min 29.61、max 47.80（dl/REPORT_ADDENDUM_20261028.md §1）。调用密度是 0.5 次/循环（`DIFF_EVERY` 16、`AVG_N` 8，即 16 循环 8 次），所以 PS 每循环在它上面付 0.5 × 39.00 = 19.5 ms；把这个块接上去、换成一次 46,800 字节的统计量读取（约 0.7 ms/循环），上限是 ~18.8 ms/循环。这个数应当以毫秒写，因为循环均值本身在同一构建的三次 20/10 窗口批次里量到 170.8、165.8、141.3 ms：同样的 18.8 ms 是合并 168.27 ms 的 11.2%、是 141.3 ms 那一批的 13.3%。所以正确的写法是 ~18.8 ms/循环（11%–13%，取决于哪一批），而不是一个固定百分比。
同一批测量还改了两个数，一并写在这里。① 循环均值：两个专门的噪声地板批次（20 个窗口）给 168.27 ms，sd 21.63，不是 16.6 的 176.6 ms——176.6 是另一次会话的一个窗口。16.10 的②已经写着「这个窗口是 176.6 ms」，那一句仍然成立；这里补的是它的对照，不是把它推翻。② 时钟常数：16.6、16.7 与全章所有毫秒换算用的是 334,800 tick/s（334.8 MHz，一个 tick 约 2.987 ns）。2026-10-28 两次环绕计数测得 333.448 与 333.383 MHz，构建 `904A1527` 把 12 处常数改成 333,415 tick/s；也就是说 16.6–16.7 的每一个毫秒数都偏低 0.415%。本节不改那些数字（它们是那个构建的记录），只把换算常数更正在这里；前后对比不受影响，因为 0.415% 在比值里抵消。
【更正二：`class` 不是「存储选择 + 失效 + 跟踪」】表 16-4 把 `MB_T_CLASS`（71）记作 58.4 ms，内容写成「存储选择、2.76 MB 的 dcache_invalidate、part_track()、AEC 与参考逻辑」——漏掉了它里面最贵的那两件事。固件自己在这个量上的注释是「class = publish + cache invalidate + classify + bright counts」（`ps_ui/main.c:15675`）。20 个连续 32 循环窗口量到的是 mean 30.82、min 11.29、max 58.74、sd 13.53：58.4 是三档里的最高档，不是均值；这一段同时是循环总方差的主要来源（与总字 r = +0.997）。里面的时间主要由两次独立的全帧遍历构成：`cam_mean_green(g_long_buf)`（`main.c:14514`）与 `cam_bright_count(g_long_buf)`（`main.c:14517`），各走全部 921,600 个源像素，按每次未命中读约 30 ns 推算约 27.6 ms 一次、两次约 55 ms，与 58.74 ms 的高档吻合；`part_track()` 自身只占 4.86–9.93 ms（固件自己量的），2.76 MB 的 `dcache_invalidate` 按每行几个周期算不到 1 ms，都不是答案。`corr(class, sync) = +0.952`：一个必须装下整数个采集帧的循环，算得越久、等得也越久。机制仍是假设：`main.c:14504` 的 `dcache_invalidate` 之后这两次遍历看到什么缓存状态（驻留约 12 ms、冷约 59 ms）与上面每个数都相容，但没有被证明。要证明它，得在现有 `GTIMER` 模式上加六行固件，把两次遍历分别计时到两个空字（573、574），再构建一次。
这些更正不改这个块自己的数：1,863 LUT（1,125 逻辑 + 738 LUTRAM）、571 FF、0 BRAM、0 DSP；46,800/46,800 个值在真实帧上逐位相同；噪声地板 168.27 ms（min 126.28、max 226.37、极差 79.25%、sd 21.63 = 12.85%，20 窗口预注册）。也不改 16.5 的结论方向：这个块能移动的 `cam` 相位是循环里最稳的一段（sd 2.1%，与总字 r = −0.30），总方差住在它碰不到的 `class` 里；所以主张该落在 `cam` 上，理由是噪声的构成，不是这个块有多大。16.11 与 16.1–16.10 冲突时以本节为准；本节不改正文，只把两处数更正过来。（来源：dl/REPORT_ADDENDUM_20261028.md §1–§5；dl/class_regime_windows_20261028.csv 的 20 个原始窗口；dl/PL_INTEGRATION_20261028.md §9；dl/LOOP_MEASURE_20261028_step1.md §5–6；ps_ui/main.c:14504、14514、14517、14546、15675）

# 十七、两次 AI 尝试以及它们为什么输
评分细则把 100 分里的 30 分给「创新性与应用价值」，并且说在完整性与工程水平之上这一项占最高权重，要的是理由、不只是结果（dl/amd_guide_text.txt:830-831 与 909-911 的权重表）。所以本章不写「我们没做 AI」，写的是我们做了三次、在同一批板上量过、并且知道它们为什么输——输的原因是被诊断出来的，不是猜出来的。
三次尝试分两层。前两次是真正的 AI：① 只学良品的异常检测；② 把已经进比特流的板载卷积网用本项目自己的数据重训。第三次把「AI」缩到最小，用台站自己已经测的七个量学一个判据，用来分清失败到底出在模型容量还是出在标签。三次都不碰板、不改固件：异常检测只读 2026-10-27 从板上 dump 的帧；重训只读 41 块板的 frame.bin 与四张格点数组；学判据只读同一次 sweep 的 CSV 与快照。唯一一次想把新权重送进 PL 的板上步骤被台站的 PS 调试口挡住了（17.3）。本章的每一个数都能回到这三个文件族里的一行、一列或一条命令。

## 17.1 为什么值得试：规则的短板正好是「格均值看不见」的那一类
先把短板指出来。在第 14 章的工作点（限值 6、41 块板）上，规则抓到 16/19、良品误杀 0/21；漏掉的三块 d9、d11、d12 全是划痕，它们在台账 CSV 的 diff_darea 列上读 5、4、4，而 21 块良品读 0..5（dl/learned_rule/out/features_20261028.csv 的 row_darea_worst 列；台账 dl/host_qc/logs/sweep_20261027_193725_sweep.csv）。也就是说，在这三块板上规则自己的证据与良品重合：不是「差一点」，是落在良品的区间里面。划痕整类 4/7（第 14 章）。
为什么恰好是这一类难，有代码与算术两条依据。一条划痕是 2–3 像素宽的线，而判据的格是 8×8 像素：这样一条线能在格内极差里加几十个灰阶，却只把格均值挪动几个灰阶——固件在这段代码上就写着这句话（ps_ui/main.c:9504-9507：「A thin scratch adds tens of counts here while moving the cell MEAN … by a couple of grey levels」）。而判决读的正是格均值。另一条是几何下限：一个缺陷要覆盖至少 8 个连通的 8×8 格才可能过面积判据，等于边长约 √(8×64) ≈ 22.6 像素（dl/ANOMALY_20261027.md §8 的算术，实测 24 像素）。比这更短、更淡的划痕，在任何对比度下都不可能让这条判据开火。
于是有两条值得试的假设，各自对应一种「AI 可能补上」的理由。① 异常检测：只学良品，不需要缺陷标签——如果良品的正常范围能被学好，任何偏离都是候选，细划痕也许就在里面；而且它不受「8 个连通格」的几何约束。② 卷积网：在原生分辨率的 64×64 裁块上看纹理，而不是每格一个均值——划痕在纹理上比在均值上明显得多。两条都建了、都量了，都输给同一条规则；17.4 的第三次尝试是把模型缩到七个可解释的量，用来分清「输在容量」还是「输在标签」。
表 17-1 是这一章的主表。每一行的「规则」都是同一批板上的同一条限值判据，所以 AI 与规则的差不是换了评测集得来的；每一行的评测集都写出来，因为三次尝试的板数不同（第一次 4 块，后两次 41 块）。
表 17-1 的三行结论一致，但不要读成「三次都输了所以 AI 没用」：三次输的方式不一样，落到的原因却是同一个（17.5）。下面逐次给数。

## 17.2 尝试一：只学良品的异常检测（2026-10-27）
这次要回答的是「不借缺陷标签、只学良品，能不能比规则更早看见缺陷」。手里有四次独立摆放的良品拍摄（u1、u2、u3、map_full）。第五次 u4 是 u3 的重复拍摄：u3 与 u4 的逐格平均差只有 1.58 灰，比 u3 与它自己第二次拍摄的 1.61 灰还小（dl/analysis/pairwise.json 前三行），所以 u4 被当成同板对照、不当第四块板——邮箱里 MB_TOL_N 读 4，实际能独立比较的良品总体只有 3 块训练板（dl/ANOMALY_20261027.md §3）。map_full 在源文档里没有记对应哪一块板，是因为它与其它每一块的差都可测（5.98–16.1 灰）才被当作第四块。
方法是刻意的「最小 AI」：每格 4 个手工描述子（mu8 局域均值、sd8 局域标准差、mu16 双尺度均值、mu8−mu16 邻域对比），两种模型——PaDiM 式（每格均值 + 池化方差，Mahalanobis 距离）与 PatchCore 式（512 条 coreset，最近邻距离）。判决结构与规则完全相同：同一个 8×8 格、同一张掩模、同一个 8 连通、同一个限 8；唯一的差别是每格统计量（dl/ANOMALY_20261027.md §5）。阈值 τ 只用训练板定，留出板从不参与。描述子没有再加大：LBP 与 HoG 的算术是矩统计的 2–4 倍，而实测的瓶颈不是描述子容量，是良品总体 6–9 灰的离散（同文件 §4）。
结果见表 17-2。最刺眼的两行是：两个模型在留一板下都比规则更爱误杀；而 PatchCore 漏掉了磁盘上唯一一块污染板的证据（最大连通块 6，限 8）——同一块板，规则的最大块是 9，余量只有 1 格。
「它输在成本上」这句话只对 PatchCore 成立：PaDiM 只要细比较的 0.08 倍（424,710 ops/帧），所以它被否掉的原因是精度，不是代价（§9、§10）。真正的分界线是噪声地板：模型把一块板与别的板比，规则把一块板与它自己的参考比。按最佳整格移位对齐之后，一块良品与另一块良品的逐格平均差是 5.98–8.77 灰（dl/analysis/align.json 的 mad_at_best），同一块板重拍的差是 1.31 与 1.61 灰（dl/analysis/pairwise.json），而缺陷阈值是 30 灰（ps_ui/main.c 的 DEFECT_AMP）。一个不用每板参考的检测器，起跑就比规则多出约 4–6 倍的噪声。加大描述子、换协方差结构都改不了这一条；只有更大的良品总体，或者一条参考，能改。
四条限定写在结果旁边，不放到脚注里。① 这次只有 4 块独立良品与 1 块污染板，结论的分辨率是「块」，不是百分比。② 污染板是对固定 30 灰规则评的，不是对容差图——四单元容差图下的那一帧不在磁盘上（§1.2、§11）。③ 规则那个 1/4 是单帧回放、是逐格超容差数的上界，固件自己的误杀可能更低（§11 ③）。④ 最小可检尺寸那张表是在「校准看见全部四块板」的 oracle 工作点上量的——对两个模型是偏宽的条件，所以「32 px、划痕全灭」不是被苛刻阈值压出来的（§8）。
这次尝试在 2026-10-27 就地停下，没有上板。理由不是它难，是它在被提出要做的唯一一件事——「检测更小的缺陷」——上也被量输了：规则 24 px、两个模型 32 px（边长 1.33 倍、面积 1.78 倍），而细划痕是规则能看见、两个模型在任何测试宽度下都看不见的。这个结论把下一次尝试推到了 41 块真实板上（17.3），因为 4 块板的分母撑不住任何「赢」的说法。

## 17.3 尝试二：板载卷积网重训——先证工具链，再量输赢（2026-10-28）
第二次换的是「真正的网络」，而且先解决一个更基本的问题：输了要能说清是模型输的还是管道坏的。答案先把管道钉死。把出货权重从头重生成一遍——quantize、export_for_hls、gen_cnn_bins 三个脚本原地重跑——params.bin（148,792 B）与 vectors.bin（820,804 B）的 SHA-256 与 2026-10-27 过板端 KAT 的那两份逐字节相同：7C0CBA2C6952DC61FB396222B3D783D5394A80DD7041D92A84BA8ACF2FA2A013 与 F7C48682D27C6850E8B7415CD3B0DBEB1E649FA99CFC2FCFA68D914B5E4905F1（本机 Get-FileHash 复算）。C 内核用重生成的 params.bin 跑 200 条向量（每条 2 个 logit）：200/200 逐位相同、worst |logit delta| = 0（dl/cnn_retrain/tb/tb_cnn_rerun.log）。工具链这一关先过，下面的 8/19 才是「网络输给规则」，不是「管道坏了」。
数据是 41 块真实板：21 块良品、20 块不良（19 块有 DAREA，d14 被拒判）。训练集 209 个正样本块（20 块不良板上，以比对自己的超容差格为中心）、350 个负样本块（21 块良品，每两块取一块）；评测集是每块板 32 像素网格上的全部裁块，1514 块、平均 36 块/板。裁块是 64×64 原生分辨率——不是整帧 64×64 抽稀，因为抽稀后工件只剩约 24×30 像素、划痕直接没了（dl/CNN_RETRAIN_20261028.md §2）。网络架构不变（3 个卷积块、7.80 M MACs，就是比特流里那一个），41 折留一：留出板不参与训练、不参与量化校准、不参与 k 的选取。
结果是 8/19 对 16/19、误杀 1/21 对 0/21，逐类见表 17-3：没有一类赢（变形 2/2 平，其余三类全输）。配对方向是单向的：8 块只有规则抓到、0 块只有网络抓到。精确 McNemar 双侧检验 p = 0.0078；dl/cnn_retrain/analyze.py 打印的是 0.0156，因为它在 scipy 已经给出双侧的 binomtest 上又乘了一次 2——两种口径都远小于 0.05，结论不依赖这个差别。
这 8/19 是整数参考的数，不是硅上的数。把新权重送进 PL 的那一步没跑成：2026-10-28 10:38–10:43 的只读尝试里，PS 调试口回 APB AP transaction error（DAP status 0x30000021）、没有 Cortex-A9 target、所有 mrd 都 ERR；随附的 KAT 脚本在自己的 FWID 闸门读到 0xFF 后拒绝写入（闸门做了它该做的事）。所以新权重与出货权重逐字节可对应、C 内核逐位复现，但新 blob 本身没有上过硅；出货权重那次 8/8 的 KAT 也没能重跑，只能靠「blob 与当时逐字节相同」来承接。这一段是本章最需要被追问的地方，所以单独写出来（dl/CNN_RETRAIN_20261028.md §1、§5）。
两条限定，防止把 8/19 读强。① k（整板判 NG 需要多少块投票）在训练折的良品上校准，观察到 5–16 块；把 k 在同一批板上重算，训练集内是 7/19、0/21——它连自己训练板的评测块都不能全放行，过拟合是实的，留一才是唯一诚实的数。② 量化代价：int 与 float 的 argmax 在 200 块上一致率 0.97，不是 1.00；没有按类量这个差别的影响（§3、§7）。
代价也要写清楚，因为它决定这条路能不能内联：一块 64×64 在板上 29–31 ms（2026-10-27 实测），36 块的整件扫描 1.08 s/板，在 200 ms 的节拍上不能内联；4 块候选的混合扫描 120 ms。比特流没动，DSP 仍 219/220，所以单次推理的代价与出货网络相同，变的是推理次数（§6）。这次比较不是给它找一条上板的路——16.4 已经说明它的输出不进判决；它回答的是一个科学问题：同一批板、同一条基线，它会不会赢。答案是不会。

## 17.4 尝试三：从工位自己的七个量学一个判据（2026-10-28）
第三次把「AI」缩到最小，用来分清两件事：如果模型容量不是瓶颈，那么在一个已经测得很好的七维量上做最简单的学习，也应该能看出这条路走不通到底是因为特征不够，还是因为标签不对。七个量全部来自台站一次比对已经有的四张数组（160×90 的 fine_deep、fine_tol、mask 与 meta 的 bbox）：dar（最大 8 连通块格数，就是台站现在的判据）、g_mean、g_peak、edge、dens、cover、base；每一个的物理理由都写在预注册里（dl/learned_rule/PREREG_20261028.md §1）。模型是最小的一步：标准化 + L2 逻辑回归（λ=1，牛顿/IRLS，截距不罚），41 折留一，标准化参数只用训练折的 40 块。判定标准在拟合之前写死：检出 > 16/19、误杀 = 0/21、McNemar p < 0.05，三条同时成立才算赢；不换特征子集、不改 λ、不换阈值再试。
把标准化折回原始量纲、在全部 41 块上拟一次，方程是（系数只为复现，性能结论一律以留一为准；dl/learned_rule/out/loto_20261028.json 的 deploy_equation）：
NG  iff  0.128266·dar − 0.007517·g_mean + 0.017519·g_peak − 0.025769·edge + 19.076471·dens + 12.378615·cover + 0.448850·base − 11.374125 ≥ 0
41 折的标准化系数里，dar、base、cover、dens、g_peak 五个 41/41 同号；edge 39/41、g_mean 40/41 且均值≈0（§3）。两件事直接读出来：模型基本是一维的（dar 权重 1.15、base 1.08、cover 0.70、dens 0.58），后三个描述的是「这块板整体差得多不多」，不是「哪里有缺陷」；而当初按「边缘块 = 配准残差」放进去的 edge 没有信息——41 折系数均值 −0.08，在 2 折里换号。后面这一条与 17.5 的①是同一件事的两个方向。
留一结果：15/19、1/21，对基线的 16/19、0/21；配对 2:1，p = 1.0000；三条判据一条没过（检出 15 ≤ 16、误杀 1 ≠ 0、p ≥ 0.05）。误杀的是良品 g18（p=0.633），唯一的「新检出」是 d9（p=0.628）——两者都贴着判决边界。按预注册的规矩，判定到此为止，探索项（λ 扫描、深度 2 的树、逐特征消融）只列不判。
真正把这条路否掉的不是 15 对 16，是常数扫描：同样一批板，把判据换回「DAREA ≥ L」，在 0 误杀这个工作点上常数就是比学出来的好（表 17-4）。在同样 15 块检出上，常数限值 8 是 0 误杀、学出来的是 1；在 0 误杀上，常数限值 6 或 7 是 16、学出来的是 15；想多抓两块，常数付 2 块误杀（限值 5）。学出来的判据没有提供任何「同样误杀、更多检出」的新点。
判决：不建议上固件。三条理由按代价排序。① 没有性能理由：在（检出, 误杀）平面上被常数曲线压制。② 没有精度理由：这次要分辨的 1 块板差别小于测量自身的重复性——同一条限值 6 的判据，只把输入从 CSV 行 DAREA 换成同一块板 20 秒后的快照 DAREA，就从 16/19 掉到 15/19（17.5 的③）。③ 没有工程理由：常数判据是一个字（MB_DIFF_LIM），这个模型是七个特征 + 七个系数 + 七个 mu/sd + 一次整板格扫描；而且 DAREA 会随参考帧整体平移（同一块缺角板在参考 940 下读 4、909 下读 8，dl/CONFIG_20261027.md 首段），系数必须随参考重拟，限值只要改一个字。

## 17.5 共同的病因：标签的循环性
把两次 AI 的失败放在一起看，原因不是「网络不够大」或「特征不够多」，是同一个：整条流水线里唯一能给出「哪里是缺陷」的逐格标签，是它自己判超容差的格子。用它当监督信号，学到的必然是这套比对的判别面，包括它的盲区。三条支撑测量，前两条量「标签看不见什么」，第三条量「这次比较能分辨多小」。
① 位置不指向缺陷。旧的说法是「最大的那些块坐在工件底部/外缘的系统带上」（dl/CNN_RETRAIN_20261028.md §2.2 的原话：sit on a systematic band on the part's bottom/outer edge）。逐块量 41 份证据快照，这句话不成立：最大块压在外框边界上的 0/41，离边界 ≤1 格的 3/41、≤2 格的 8/41（dl/learned_rule/edge_and_holes.py 的输出；CSV 的 edge_min 列）。质心落在下三分之一的不良 7/20、良品 2/21，上三分之一 7/20 对 7/21：两个分布在中上部大量重叠。站得住的只有更弱的一句——最大块的位置不指向缺陷。它为什么要紧：重训时正样本块就是以这些格为中心裁的；把边缘与过孔当成划痕，网络学到的自然是配准残差。
② 未判定 = 未测量。判决跳过掩膜外的格子（ps_ui/main.c:9482），而 fine_deep.bin 在掩膜外恒为 0（ps_ui/main.c:9476 先清零、9545 才写值）。这次逐块复算 41/41 块成立：读 41 个 fine_deep.bin 与 mask.bin，掩膜外的最大值全是 0。外框以内被判的比例只有 0.323–0.544，即 46%–68% 的格从不参与判决（同一次复算；dl/learned_rule/out/edge_holes_20261028.csv 的 judged 与 bbox_area 两列）。掩模的空洞在金属线圈与接插件上，有几条划痕正是从空洞上穿过或贴着它们。那里的信息既不在标签里、也不在任何特征里——不是「学不到」，是没有数。
③ 重复性。同一块板、物理没动、两次比对相隔约 20 秒：DAREA 差 |Δ| = 0 格 ×17、1 格 ×12、2 格 ×7、3 格 ×1、4 格 ×1、6 格 ×2（40 块板；dl/learned_rule/PREREG_20261028.md §5，逐板值在 dl/learned_rule/out/features_20261028.csv 的 row_darea_worst 与 snap_darea 两列）。限值 6 的余量是 1 格（良品最大 5），比最坏重复性小 5 格；限值 6 下有两块板在两次测量之间翻判决（d10 8→2、d11 4→10）。所以任何「1 块板」的差别都不能当成信号——这既是 17.4 判「没赢」的依据，也是「再训一个网络也证明不了赢」的原因。
把三条合起来，就得到那三块漏掉的划痕板的读数：d9/d11/d12 在台账行上读 5/4/4（良品 0..5），在快照的超容差格总数上是 36/32/20（良品 0..37）——它们在这套证据里与良品重合。反过来，良品 g18 的最大块只有 2 格，块内峰值 108，比 d9 的 47、d12 的 92 都深；任何「又深又小 = 缺陷」的判别面都会先打到 g18。17.4 的模型正是这样：它唯一的误杀是 g18，唯一的「新检出」是 d9。这不是模型的偶然，是「从比对自己的证据里学」的必然。

## 17.6 怎么才算「赢」：独立标注，以及那个便宜的下一步
结论不是「AI 在这个任务上不可能赢」，而是「在这套标签上不可能赢」。要赢，需要的是独立于比对的缺陷位置，不是更多的训练。最直接的一条：人工标出 7 块划痕板的像素位置。它一次给出两样东西——第一次能独立检验规则自己的 4/7，以及一个「划伤 vs 残差」判别器所需的真标签。代价约 1 人日，收益不确定（划痕只占 7/19）；风险是标注一致性只有一个人，没有第二个人复核（dl/CNN_RETRAIN_20261028.md §8、dl/WHY_AI_FAILED_20261028.md §3）。
还有一条更便宜、也更符合本项目性格的路：固件已经每帧在算一个独立的格内极差统计量，专门针对「细划痕几乎不动格均值」这个已测事实（ps_ui/main.c:9504-9507 的注释就是为它写的）。它的字是 MB_EG_CELLS 556、MB_EG_MAXD 557、MB_EG_AT 558，外框 559–562，默认阈值 14 灰（ps_ui/main.c:2583-2589 定义、9687-9699 发布；EG_THRESH_DEFAULT = DIFF_THRESH = 14）。这次扫描没有记录这些字——台账 CSV 的表头里没有一个 eg 列。所以「它能不能分开那三块划痕板」是未测的，本章不宣称它有效。要测：主机侧加几列，约 40 分钟台站时间，不动固件、不重建、不重取参考。它是这两条里更便宜的一条：不用训练任何东西，先问「这个独立的量到底分不分得开」。
两条路的代价与收益并排放一次（表 17-5）。
反过来，什么不是答案：换更大的网络、加层、调学习率、再换一个特征子集或阈值。前两条已经在 41 块板上量过（17.3、17.4），后两条被预注册明确禁止——那正是「调到赢为止」，而这次实验存在的意义就是不做这件事（PREREG §6）。

## 17.7 这个结论怎么用：一段给评委看的话
给评委的一段话，可以直接引用：我们没有把 AI 撤下来是因为它难，而是因为它在同一批板上输给了我们自己的一条规则，而且输的原因被量出来了——标签是规则产的，规则看不见的地方标签也看不见。三次尝试、同一批板、同一条基线：异常检测输在良品总体本身的 6–9 灰离散（同板重复性是 1.3–1.6 灰，阈值 30 灰），板载卷积网输成 8/19 对 16/19（p = 0.0078），七个特征学出来的判据被常数扫描压住。要真正超过这条规则，下一步不是换网络、加层数或调学习率，而是把缺陷本身标出来——那是一件标注工作，不是一次训练。这也是我们敢把「创新性」写进报告的原因：创新不只是「用了 AI」，还包括知道它在这里为什么不行，以及下一步该量什么。
这条经验已经进了技能包：一个从检测器自己的证据里训练出来的学习器，继承那个检测器的盲区（skill/pitfalls/measurement-traps.md 的 M56）。下次再有人提「用 AI 直接学」，先问一句：标签从哪来？如果答案是「从现有判据的超阈格子来」，那么上限就是现有判据。
本章的未测项与限定。① 三次尝试都没有上板：异常检测与学判据是离线计算；重训的硅上那一步被台站挡住（17.3）。② 异常检测只有 4 块独立良品与 1 块污染板，且污染板是对固定 30 灰规则评的（17.2）。③ 划痕的像素级真相不存在，本章所有「检出」都是对被比对量的判决，不是对真相的判决；「纹理 CNN 能在划痕上赢」这个假设因此没有被检验，被检验的是更窄的一句「拿规则自己的证据训一个 CNN 不能」。④ MB_EG_* 从未在这次扫描里记录，它分不分得开那三块板是未测。⑤ 换参考帧后 17.4 的系数是否仍成立未测（只测过参考 909）。⑥ 人做的检查，与前面每一章相同：上电前 J10 的 PIN35(B20)↔PIN28(V12) 跳线必须在外面（本章没有板端操作，这一条是为后续复测留的）。
（来源：dl/ANOMALY_20261027.md（提交 e8f3138）、dl/anomaly_table_20261027.csv、dl/analysis/align.json、dl/analysis/pairwise.json；dl/CNN_RETRAIN_20261028.md（提交 bed52da）、dl/cnn_retrain/out/analysis.json、dl/cnn_retrain/analyze.py:101-103、dl/cnn_retrain/tb/tb_cnn_rerun.log 与 tb_new_weights.log、dl/hls/data/params.bin 与 vectors.bin 的 Get-FileHash；dl/LEARNED_RULE_20261028.md（提交 cb731ac）、dl/learned_rule/PREREG_20261028.md、dl/learned_rule/out/loto_20261028.json、features_20261028.csv、constant_sweep_20261028.csv、edge_holes_20261028.csv、loto_predictions_20261028.csv、dl/learned_rule/edge_and_holes.py；41 块板的格点数组 dl/sweep_frames/20261027_193725_sweep/ 与台账 dl/host_qc/logs/sweep_20261027_193725_sweep.csv；ps_ui/main.c:2583-2589、9476、9482、9504-9507、9545、9687-9699；dl/CONFIG_20261027.md 首段；dl/amd_guide_text.txt:830-831、909-911；dl/WHY_AI_FAILED_20261028.md；skill/pitfalls/measurement-traps.md 的 M56）

# 十八、外部复核：十一条发现、四项已修、两项有意不修
2026-10-28，一位队友对提交包 `TrustScope_submission_20261028.zip` 做了一次独立复核：把它解压到自己的目录里，不启动 Vivado 或 Vitis，不下载固件，不碰串口与电机，只用 Python 3 与 numpy 在解压出来的树上离线复算。交回四份文件——`代码审查与改进建议.md`（20,672 字节）、`review_checks.py`（3,658 字节）、`review_checks.json`（1,714 字节，它自己那台机器的可机读输出）、`layout_check.log`（804 字节）——以及 11 条发现：6 条 P1、5 条 P2（解压在 `.tmp/teammate_review_20261028/`）。这一章写我们拿这 11 条做了什么。它带来的不是一次表扬，是一次可以逐条核对的检查：这是这份报告里唯一一段由别人算出来的数。
处理结果是四类，分开写。四项已在固件里修好并上板读回（P1-04、P2-03、修它时才量出的时钟常数、P2-04，构建 `904A1527`，提交 `9f4f022`）；第十一条 P1-01（交付物不齐）在包里修好（`528137d`、`44042d9`）；两项有意不修，并在代码处留下问题与修法（P1-02、P1-03）；其余五条仍未修，18.8 的未证项里逐条列清。这一章不把「复核通过」当结论：复核确认的是它能离线确认的那一半，硬件的那一半仍由本报告的测量承担——而这两半现在有了一个共同的坐标，就是 18.7 的两个构建号。

## 18.1 复核是怎么做的：解压、不启动工具链、离线复算
对象是提交包，不是工作树。它把包安全解压到自己的 `source/` 下，然后只做五件事：检查 `src/ps`、PC 引擎、CNN 驱动、关键上板与构建脚本、扫描 CSV 与交付依赖；跑包内的布局检查；对 `src/`、`sim/` 下每个 `.py` 做语法解析；用包里的文件重算源码哈希；独立复算 CSV 并跑一次 PC 引擎的连续缺陷回归。它没有启动 Vivado 或 Vitis，没有下载固件、操作串口或转动电机，没有重新综合、编译 ARM 镜像，也没有做任何板上验证。它把这条限定写在自己的报告里：「文档中的『已实测』是队友的记录，除本报告明确写出的本机离线复核项目外，本次没有重新验证这些硬件结论。」这一章后面每说到「复核确认」，都只到这一层。
它的脚本 `review_checks.py` 是七步，全部可重放：① 读 `data/board_sweep_20261027/sweep_20261027_193725_sweep.csv`，重算行数、标签数、有效缺陷数、`coherent=0`、记录阈值、d8 重复与 d14 拒判，以及 6/8/10 三个阈值的重放；② 对 `src/`、`sim/` 的每个 `.py` 做 `ast.parse`；③ 跑 `src/ps/check_layout.py src/ps/main.c`，把 stdout 与 stderr 存成 `layout_check.log` 并记录 exit code；④ 按名字检查七个「当前交付物」是否存在（位流、四个 CNN blob、`sweep.py`、`preflight.py`）；⑤ 用 `legacy/fpga_snapshot_20261019/dl/build_id.py` 的原始标签与顺序，对包里的 `src/ps` 与字体重算源码哈希；⑥ 导入 `src/pc/engine.py` 的 `Inspector`，喂 9 张良品、再连续喂同一缺陷 12 次，分别在不锁定与锁定参考两种情形下记录判决；⑦ 算一个 FPS 公式的标量例子（10 帧 / 1.25 s → 打印 10、真值 8）。
它的可机读输出是 `review_checks.json`，人读的是 `代码审查与改进建议.md`。我们做了一件事，让它不只是「一次外来意见」：把 `review_checks.py` 原样对着当前的 `submission/` 再跑一次（脚本把 `source/` 当解压目录，就指向这棵树）。结果与它那一份逐键相同，只有一项变了：`missing_current_deliverables` 的七个键全为 `false`（它那次全为 `true`，P1-01 正是在说这件事）；`layout_check.log` 逐行相同；`recomputed_source_hash_using_shipped_font` 仍是 `7C54944F`；`layout_check_exit` 是 0；`python_syntax_errors` 是空的；`persistent_defect_unlocked` 仍是前 5 次 NG、第 6–12 次 OK。18.3 那张表里的「复核」一列，就是这第二次运行的结果，不是抄它的文字。

## 18.2 它确认我们对的地方：四条，每条都可复算
第一条：`src/ps` 的合并与 `legacy` 的归档没有改掉源码身份。复核按开发树里的原始标签（`ps_ui/main.c`、`ps_ui/cam_i2c.c`、…、`dl/ts_cn_font.h`）与原始顺序重算 13 个文件，字体从 `legacy/fpga_snapshot_20261019/dl/` 取、其余从 `src/ps/` 取，得到 `7C54944F`——与 `src/ps/build_id.h`、与板端 `MB_FWID0..2` 读回的 `TSC1 7C54944F` 相同。它自己加了限定：「这确认了源码集合的标签一致，不能替代当前 ELF 和板端镜像验证。」这个限定我们接受，18.7 把它写进了两个构建的关系：哈希一致说明「包里这套源码就是那个号」，不说明「任何一次重新编译出的 ELF 都逐字节相同」。
第二条：布局。`layout_check.log` 的头两行是 `mailbox: 413 MB_* words, 413 distinct word indices, 0 collisions` 与 `4 indices written by literal offset, 0 also claimed by an MB_* name`；接着 `regions cover 384000/384000 pixels, 0 outside`；最后 `all layout checks pass (384000 pixels tiled, no overlap, all stores aligned)`，exit 0。复核的原话是「实际运行通过：413 个邮箱字段无索引重复，显示区域覆盖完整，建模的缩放路径不越行。它没有证明所有动态裁剪、缓存和 DMA 时序正确。」后一句我们照收——18.8 会说明这一条检查为什么不够。
第三条：`cnn_drv.c` 的缓存维护。输入在交给 PL 前 clean（`CNN_IMG_ADDR`），输出在 PL 写完之后 invalidate（`CNN_LOGITS_ADDR`），等待有基于计时器的上限。复核据此写明「此前缓存维护缺失问题不能继续照搬为当前缺陷」。这一条对 16.4 是补强：那一节自己说过 KAT 8/8 证明的是通路不是精度，但缓存这一环此前只有我们自己的检查；现在有第二个人在解压出来的树上读过、并从同一个包里重新生成了 CNN 的四个 blob。
第四条：`data/README.md` 的主动披露。它写明 41 块板 sweep 的配置（`TSC1 7C54944F`、`BIT_20261024_fp1.bit`、参考 909、曝光锁 8698、`MB_DIFF_DAREA >= MB_DIFF_LIM_USED`），写明重取参考会把 DAREA 整体平移（同一块板参考 940 下读 4、909 下读 8），也写明 `solder_defects/` 的样本数为零、示例文件只是格式示意。复核把它列为「已确认有改善」的第 6 项。披露不是免责，但它使「这个包知道自己的边界」成为可核的事实——在 18.3 的分母争议上，这一点直接有用。
这四条都不是「复核说我们好」：每一条都指向一个可复算的数、一个可读的文件或一段可重放的脚本。写在这里是因为，一份只有自我测量的报告，其可信度上限就是那个测量本身。复核还确认了一件不是缺陷的事：显示用的是 Park 配置，旧版「bit1 写成 Circular」不是本轮问题。确认不是问题，也是确认。

## 18.3 它独立复算的检出率，与我们一致
复核最花时间的一件事，是把检出率用我们包里的 CSV 重算了一遍。这一节只给一张表，因为「被外部独立复算过」是这份报告最需要的第三方证据：它的每一行都能用 `python src\host_qc\sweep_report.py data\board_sweep_20261027\sweep_20261027_193725_sweep.csv` 或 `python review_checks.py` 复现。
表 18-1 把两张表并成一张：左两列是我们第 14 章的记录，右两列是复核在它自己机器上的复算。
表注三条，每一条都是这张表最容易被读错的地方。① 分母 20 是有效缺陷测量次数，不是 20 个不同的缺陷件：缺陷记录 21 次、不同缺陷件 20 块，其中有 DAREA 的 20 次 / 19 块（d14 拒判，DAREA 空白）。d8 的两次读数（7 与 1）必须留作重复性证据，不能同时充当两个独立物理工件。② 三个阈值的重放分母固定为那 20 次有效测量，所以是 16/20、15/20、11/20；把分母换成 21 是另一件事，不要混。③ 限 6 那一行是事后重设阈值，不是原运行配置：采数时 42 行的 `diff_lim_used` 全是 10，限 6 是采完之后才装上的；16/20 与 16/19 的差别也只是分母（测量次数与板数），不是两次不同的运行。
这张表还有一层：复核的脚本与我们自己的 `sweep_report.py` 是两条独立实现，它们在同一份 CSV 上给出同一组数。我们自己的工具打印 `rows 42 (21 good, 20 defective, 1 not usable)`、`NOT USED … board 35 label=d14`、`WARNING: 13 row(s) … coherent=0`、`NO SUGGESTION`、`exit 2`。一处小的不一致要写出来：那行 WARNING 后面列了 12 个板号（3、6、12、14、17、19、20、24、29、32、33、40），而 CSV 里 `coherent=0` 是 13 行，第 13 行是索引 41 / d20——工具把这行的板号漏在名单外了。这不影响计数（13 是对的），但它是「工具打印的东西也要核」的又一个例子。
复核还指出一处措辞：`data/README.md` 把重判结果写成 `16 of 20 defective`，仍容易被读成「20 块缺陷板」。这个意见接受，处理方式与第 14 章相同——记录不改，报告解释：`data/README.md` 是那批测量的原始陈述，改它等于改记录；分母的含义写在这里与 14.2，两边都看得到。

## 18.4 已修的四项：问题、修复、上板读回的字
四项改动在同一个构建里（`904A1527`，提交 `9f4f022`，13 个源文件）：一次编译、一次加载，每一项都在板上读回字之后才算完成。表 18-2 每项一行。读回的顺序都先过 FWID 闸门：`MB_FWID0..2` 与 `build_id.h` 不一致时，任何读数都不采信。
P1-04 的读回值得单独说，因为它不是「跑一次 KAT 就算修好」。为证明闸门真的关得住，专门造了一个 7/8 的变体构建（源戳 `C779163F`，第二版 `F3E94104`），在板上让自检只过 7 条：`MB_CNN_PASS=7`，而 `MB_CNN_RUNS` 在 151 个循环里保持 0、`VALID=0`、`SEQ=0`——旧闸门会在这块板上打开推理。然后把 8/8 的 `904A1527` 装回去：`PASS=8`，`RUNS` 1→7、`SEQ` 1→7（94 个循环、12 s）。13:24:05 那次 KAT 的日志还记着 16 个 logit 与 csim 逐位相同、耗时 426 ms（`ps_fft_dual/logs/r4_kat_20261028.log`）；日志里命令之前的 `PASS=7` 是 DDR 邮箱跨镜像留下的旧值，脚本认这个 8 的方式是：命令仍是 7 的时候先看到它归 0、然后才看到 8。
表 18-2 的第三行不在复核的 11 条编号里：它是修 P2-03 时按复核的要求「用实际 tick 差」算速率，才量出来的。334,800 → 333,415 tick/s，12 处：`GTICKS_PER_MS`、`GTICKS_MS`、`ARM_DELAY_TICKS`、四个传感器时序界、`LINE10_TICKS`、NS/TICK 乘数、运行时间除数、采集周期除数，加上 `verdict.c` 的 `TICK_HZ` 与 `cam_i2c.c` 的 I2C 间隔。它单独占一行，因为它把本报告里每一个毫秒数都往正确的方向挪了 0.415%——包括第 16 章的那些（16.11 记着后果）。比值不受影响，所以所有以比值成立的结论不动。
P2-04 那一行留了一个 E2：回读证明的是「裁剪仍然覆盖相机」（zoom1 时两种视图状态都读 131）与「回显字往返正确」，没有隔离开「切换那一轮源与裁剪不同步」本身——`MB_ZOOM` 是读完立刻回写的，主机看不到消费时刻。所以这个修复的验证是「改后的行为对」；改前那个错误窗口是从代码顺序读出来的，不是从板上抓到的。

## 18.5 有意不修的两项，与六天内不动它们的理由
P1-02：证据快照跨轮拼接。复核给的机制是：第 N 轮比较完成，把 DAREA、verdict、bbox 等元数据抄进 buffer 并置 pending；第 N+1 轮重新选 `g_long_buf`，`evid_copy()` 复制的是这一帧的新像素，而随行的掩膜与差分数据还是第 N 轮的。于是「照片的校验和正确」与「掩膜的校验和正确」只证明各自复制正确，不能证明它们来自同一次检测输入。工件移动、曝光变化或只短暂出现的缺陷，都会让保存的照片与保存的判定不一致；多帧平均开着时，判定还可能描述一个窗口，而不是一张照片。
原来的函数头写着 `the snapshot and the verdict cannot describe different frames`。这句话是假的，已经删掉，换成了上面这个实测出来的次序（`ps_ui/main.c:5528` 的注释块）。修它要的是缓冲所有权：先取得一张 DMA 不能改写的快照，再让定位、差分、CNN 与证据导出都消费这一张，每个结果带 `capture_seq` / `job_id` / `reference_id` / 配置版本。只把复制延后没有用——那个地址仍然是 DMA 的。
P1-03：结果块逐字发布。主机读到的「一个结果」是 `MB_DIFF_VERDICT`、`MB_DIFF_N`、`MB_DIFF_DAREA`、`MB_DIFF_FVALID`、`MB_DIFF_CELLS`、`MB_DIFF_OK`、`MB_REG_*` 与 bbox 的一组独立 32 位写；一次 burst 读可以落在两次写之间，拿到两个比对的混合。包内 CSV 的 13/42 行 `coherent=0` 就是这个症状的实测记录（行的分布见 18.3）。它不说明哪一个 DAREA 错了，说明的是这样取到的一行不是快照、不能当快照用。同轮重算 verdict 缩短了这个窗口，但那是收窄，不是原子边界。
修法是单写者序列锁或双缓冲结果块：写者把版本置奇数 → 写完整块 → 屏障 → 版本置下一个偶数；读者读版本、拷块、再读版本，只接受相等且为偶数；主机对版本变化、超时、未就绪明确拒收并重试。这是与所有主机脚本共享的协议改动（`ps_ui/main.c:15280` 的注释块写了同样的内容）。
为什么六天内不动：两条都要求改判定链中段或改主机协议，改完换 build id、换 FWID，参考与 41 块板的 sweep 全部作废、要重取重扫；而它们的失败模式是「记录不完整」，不是「判定错」——判定那条链的证据反而在 18.3 里被独立复算过，结论没变。所以选择是：把问题写在代码处、写在报告里，让读者知道哪一列能用、哪一列不能；不在截止前六天动一条已经跑过 42 次测量、被第 14 与 15 章引用过的链。两项的注释块都写了机制与修法的形状，代码不会再和文档悄悄不一致。

## 18.6 同一次构建里的链接器修复：`.bss` 挪到 0x24000
链接器修复不在复核的 11 条里，但它在同一次构建里，而且它是这批改动能不能上板的前提。四项修复加了 100 字节，链接就失败了：`region ocm overflowed by 48 bytes`——上一个构建在 128 KB 的 `ocm` 里只剩 52 字节余量。不解决它，表 18-2 的四行一行也装不进板子。
处理：把 `.bss` 从 `ocm` 挪到没用过的 `ocm_free`（`0x24000..0x2EFFF`，44 KB）。四条理由，每条都能在源码里核：① `mmu.c` 已经把 `0x0..0x3FFFFF` 四个 1 MB 段映射成 write-back cacheable，所以 `0x24000` 的属性与 `.bss` 原来的地址相同；② `0x24000` 在实测可用的 OCM 范围内；③ 它在页表（`0x20000..0x23FFF`）之上、栈（`0x2F000..0x2FFFF`）之下，装不下时链接器会失败，所以「不许长进页表」这条不变量由构造保证；④ `.bss` 是 NOLOAD，不占镜像字节，`startup.S` 仍按 `__bss_start`/`__bss_end` 清零，清零代码一个字没改。
数：`.text` 118,968 + `.data` 108 = 119,076 字节留在 `ocm`，`131,072 − 119,076 = 11,996` 字节余量（提交信息里取整成 12,000；差 4 字节是取整，不是第四个数）；`.bss` 12,076 字节落在 `0x24000`，`ocm_free` 还剩约 33 KB。装载器看到的镜像结束于 `0x1D124`，页表 `0x20000..0x24000` 不与任何可装载段重叠（`dl/_build_r4_variant.txt` 的构建输出）。
一条限定：`.bss` 换地址意味着所有静态数组的地址都变了。判定链读写的数组、索引与算术没变，所以判定结果按构造相同；但地址会不会通过缓存组、对齐之类的路径影响时序，本章没有证明，也不声称。这就是 18.7 里「按构造」三个字的分量。

## 18.7 两个构建的关系：表对两者成立，但只在其中一个上跑过
报告里现在有两个构建号。它们不是版本号，也不是新旧关系，不可以互换：`7C54944F` 是测量构建（第 14–17 章的数字属于它），`904A1527` 是修完的构建（只有 18.4 的读回属于它）。表 18-3 把它们分开写。
第一，表建在 `7C54944F` + 参考 909 上。采数时板上是限 10（CSV 42 行的 `diff_lim_used` 全是 10），限 6 是采完之后 21:10 才装上的；第 14 章表里按 6 的数字是对记录的 DAREA 做重判，不是一次「按 6 跑过的采样」（14.2、14.3 与 `submission/data/board_sweep_20261027/CONFIG_20261027.md` 都这么写）。所以「工作点 6」要带着它的来源读：规则是 6，运行是 10，表是重判。
第二，`904A1527` 的改动不触及 DAREA 判定链，因此表对两个构建成立——这是按构造，不是重测过。逐条对回去：`diff_frame()`、`diff_verdict()`、`ref_take()` 里没有一行算术被改；`part_track()` 里只改了一行注释（`/334800` → `/333415`）。`git diff 9f4f022^ 9f4f022 -- ps_ui/main.c` 的 32 个 hunk 落在 `draw_panel`、`cnn_infer`、`main_loop` 的发布与显示段、`sensor_timing_derive`、`busy_loop` 与注释块上；另外改了 `verdict.c` 的 `TICK_HZ`、`cam_i2c.c` 的 I2C 间隔与 `lscript.ld` 的 `.bss` 区域。发布的字、显示的文字、时间的单位、`.bss` 的地址——没有一样进入「哪一格超过容差、最大连通块有多大、是否 ≥ 限值」这条链。
第三，表从来没有在 `904A1527` 上重跑过。这是缺口，必须写在这里：四项修复里有两项（时钟常数、`.bss` 换址）在原理上可以改变时序甚至缓存行为，而表是对另一个构建、另一次会话的记录。要关闭这个缺口，需要把 `904A1527` 当测量构建重新取参考、重扫 41 块板——17.6 对同一次动作的估计是「主机加列 + 约 40 分钟复扫」，再外加逐块摆板的人工，本次没做。所以在拿到那次重扫之前，「表对两个构建都成立」只到「按构造」这一层；谁要在 `904A1527` 上引用 16/19 这个数，得先做那次重扫。
第四件必须写清：还有 61 个文件写着 `7C54944F`。统计口径是工作树里除 `backups/`、`.tmp/`、`submission_package/` 之外的文本文件 60 个（`dl/` 35、`submission/` 17、`ps_fft_dual/` 5、`career_handoff/` 3），加上包里的 `board/ps_ui.elf` 本身（字符串表里是 `TSC17C54944F`）；其中 51 个受版本控制（`git grep -l 7C54944F` 的结果，含那个 ELF）。随包交付的是 18 个：17 个文本加这个 ELF。这些引用描述的是上一个构建，不是错误；错的是让读者以为它们描述的是当前的板。所以本章的作用是给这个号一个上下文：看到 `7C54944F` 读「测量构建」，看到 `904A1527` 读「修完的构建，只有 18.4 的读回属于它」。报告自己的 docx 与 pdf 不计入这 61 个——它们引用的正是本章要修的说法，改完就在本章里。
包里现在有两个 ELF。`board/ps_ui.elf`（200,308 字节）是测量的那一个，没有换；`board/ps_ui_904A1527.elf`（200,504 字节，SHA-256 `A5BEAA87…D930C4`）是修完的那一个，新加。要复现第 14 章的表就装前者；要核对 18.4 的四项修复就装后者。`src/pl/strict_load_cores.tcl` 的闸门是 `TSC17C54944F`，它会拒收 `904A1527` 这个镜像——那是闸门在做它该做的事，不是脚本坏了。两个 ELF 的 DAREA 行为按构造相同，但后者没有重测过——这句话同时写在 `board/ARTEFACTS.md` 与 `board/REPRODUCE.md` 里，不是只在报告里说。

## 18.8 这次复核教给我们的一条：名字检查与字面偏移检查看不见计算下标
这条教训来自 P1-04 的第一次实现。新增的两个发布字 `MB_CNN_VALID` / `MB_CNN_SEQ` 第一版放在 241 / 242。依据是当时能做的两条检查：241/242 没有任何 `MB_*` 名字占用；`check_layout.py` 报 0 冲突（413 个名字、413 个不同下标）。两条都过。
上板是另一回事：241 读到 1，再读 10，再读 −2；242 读到 8。一个自己会变的字说明有第二个写者。写者是数组块 `MB_SETTLE_ROWM`（基址 240，34 行占 240..273）：它的写法是 `MAILBOX + (MB_SETTLE_ROWM + (gy - READY_Y0)) * 4u`，用计算下标写一段连续的字。名字检查看的是 `#define` 的常量，字面偏移检查看的是代码里写死的数字；`240 + gy` 这样的下标两者都不在视野里。二次扫描（`ps_fft_dual/r4_mbscan_20261028.tcl`，两次读相隔 2500 ms，范围 232..258）看到 240..258 每一个字都在动。
修法不是「再找一个没有名字的字」，是换权威：`python dl/mb_words.py` 带数组范围（基址 240..307、315..326、330..365、416..460；最后一个具名字 571；`WORD_LIMIT` 640），所以 572..639 才是既无名字、也无数组的区间；取 580/581，离当前末尾九个字，给未来数组长大时留出让碰撞先发生的余量。然后在板上两次读确认稳定。一个旁证：加了这两个字之后 `check_layout.py` 报 415 个字、仍然 0 冲突——名字表本身是干净的，问题从来不在名字表里。
这条教训的指向是工具的 LIMITS，不是一次事故。`skill/scripts/wordmap_check.py` 的 LIMITS 写着它 `compares NAMES to NUMBERS`，字节偏移与结构体成员不在模型里；现在要加第三项——用计算下标写的数组块。`skill/pitfalls/measurement-traps.md` 里最近的一条是 M45（「新字段读不到，我先改了三次代码——因为没有对照字」）：那是缺一个对照字，这一条是对照字在、检查器看不见覆盖它的数组，同类而机制不同。给后来者的一句话判据是：在邮箱里认领一个新字，「名字表 + 数组范围」两样都对过、并且在板上两次读稳定，才算认领成功；名字检查通过不是证据。
本章的未证项，一条不省。① 表没有在 `904A1527` 上重跑（18.7 第三句）。② view/zoom 的「一轮不一致」没有隔离开，两条探针都是 E2（18.4）。③ P1-02、P1-03 有意未修（18.5）；P1-05、P1-06、P2-01、P2-02、P2-05 仍未修：P1-05 的 PC 引擎默认入口仍会把持续缺陷吸收成参考（本机复现：前 5 次 NG、第 6–12 次 OK；锁定参考后 12 次全 NG），P1-06 的电机闭环不在包里，P2-01 的 `batch_build.tcl` 静默失败未动（随包的 `strict_load_cores.tcl` 已改成硬失败，但不等于整套脚本都改了），P2-02 的「提交显示切换不等于已切换」与端到端命名未动，P2-05 的双读不是事务（该函数目前未被调用）。④ 本章没有板端操作；J10 的 PIN35(B20)↔PIN28(V12) 跳线检查仍是一切板端读数的前提。
（来源：.tmp/teammate_review_20261028/ 的 代码审查与改进建议.md（20,672 B）、review_checks.py（3,658 B）、review_checks.json（1,714 B）、layout_check.log（804 B）；把 review_checks.py 对着当前 submission/ 再跑一次的同一份 JSON 与 layout_check.log（18.1–18.3 的数取自这一次）；submission/data/board_sweep_20261027/sweep_20261027_193725_sweep.csv 的逐行复算与 submission/src/host_qc/sweep_report.py 的输出；submission/src/ps/build_id.h、build_id.py、check_layout.py、cnn_drv.c、data/README.md；提交 9f4f022（构建 904A1527：四项修复、两项未修、链接器与板端读回的全部记录）、528137d 与 44042d9（P1-01 的交付物补全与 -CheckOnly）；ps_ui/main.c:5528（P1-02）、12786–12816（P1-04 与 241/242 的碰撞）、15280（P1-03）、15675（class 的构成）、15681（P2-03）；ps_fft_dual/logs/r4_kat_20261028.log、r4_mbscan_20261028.tcl、r4_tick_20261028.tcl、r4_looprate_20261028.tcl、r4_viewzoom_20261028.tcl；ps_ui/lscript.ld 与 ps_ui/ps_ui.map、dl/_build_r4_variant.txt 与 dl/_build_variant_7of8.txt；dl/mb_words.py 的输出；board/ARTEFACTS.md、board/REPRODUCE.md、board/ps_ui_904A1527.elf、board/REVIEW_FIXES.patch；skill/scripts/wordmap_check.py 的 LIMITS、skill/pitfalls/measurement-traps.md 的 M45）