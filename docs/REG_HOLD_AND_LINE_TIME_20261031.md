# 2026-10-31 — 注册的 "hold"（393=2）与传感器行时间 / 毫秒曝光

> 只读 `ps_ui/main.c`（+ `ps_ui/cam_i2c.c` 的曝光写入）。**来源自证**：`python dl\build_id.py --show`
> 对工作树 13 个源文件算出 `EDC634BF`，与板上 `TSC1EDC634BF` 一致（印章由 build.ps1 写入镜像，main.c:49-59）。
> 单位：代码的 "half-res px" = **2 source px** (main.c:8660-8662)；`MB_DIFF_DX` = **1/16 source px** (main.c:2896)。

## 一、问题一：注册的 hold 模式

**1.1 393 谁写、各值含义。** 语义表在定义处：1 = 局部窗口赢；**2 = 扫过一个候选但保留了 held answer**；
3 = UNSTABLE；4 = 冷搜索跑完并发布；5 = RE-AIM（采纳但动了，本帧比较拒绝）(main.c:2270-2285)；
常量 `REG_MODE_WARM/HOLD/UNST/COLD/REAIM` = 1/2/3/4/5 (main.c:7894-7900)。唯一写入函数
`reg_mode_after()` (main.c:8182-8194)：`g_reg_move100 >= REG_REAIM_100(100)` 时**强制改写为 5**、
`g_reg_ok = 2u`、`++g_reg_n_reaim` 后 return；否则 `g_reg_mode = mode` 并按 warm/hold/cold 计数。
直写另有入口清 0 (main.c:8747) 与 UNSTABLE 的 3 (main.c:9311)；发布 `PB(MB_REG_MODE, g_reg_mode)` (main.c:11447)。
**设 2 的分支有两个**（都调 `reg_mode_after(REG_MODE_HOLD)`）：暖路径 main.c:8861（紧接 8858-8860 用 held 的原数
`reg_adopt`）；冷路径 main.c:9302（冷搜索跑完、`better` 为假、且 `e_inc <= REG_CONF_LIM`；若 `e_inc > 192` 改判 3，main.c:9303-9314）。

**1.2 hold 判据（逐字）。** 前提：`if (g_reg_have != 0u)` (main.c:8751) 且 held 在本帧可测
`e_inc = reg_score(g_reg_hold_dx_i, ...)` (main.c:8756)；不可测则 `can_widen = 1` (main.c:8772) 且 8819 整段跳过。
暖路径 hold 需三条同时成立：
1. `reg_warm_search(...) != 0u` —— 窗口给了答案，而不是"要扩窗" (main.c:8819-8820)；
2. 该答案**没**过采纳门：`if (werr <= REG_CONF_LIM && (e_inc > REG_CONF_LIM || werr + REG_WARM_MARGIN < e_inc))` 为假 (main.c:8830-8831)；
3. `if (e_inc <= REG_CONF_LIM && g_reg_seeded == 0u)` (main.c:8838) → held 原样重发 → `reg_mode_after(REG_MODE_HOLD)` (main.c:8858-8861)。

`g_reg_seeded == 1` 表示 held 只是取参考时的恒等先验、不算答案，直接落到冷搜索 (main.c:8850-8857,10354-10355)。
冷路径：`margin = far ? REG_JUMP_MARGIN : REG_WARM_MARGIN` (main.c:9289)、
`better = (err16 <= REG_CONF_LIM && (e_inc == 0xFFFFFFFFu || err16 + margin < e_inc))` (main.c:9294-9295)，
`!better && e_inc != 0xFFFFFFFF` → 重发 held → 2 或 3 (main.c:9296-9314)；`far` 由 `|Δ| > REG_JUMP_R/A/S` 判 (main.c:9278-9279)。
阈值：`REG_CONF_LIM 192` = 1/16 灰度级的平均 |ΔGM|（即 12 级）(main.c:2215,2237)；`REG_WARM_MARGIN 16`（1 级）、
`REG_JUMP_MARGIN 32`（2 级）(main.c:7907-7908)；暖窗 `REG_WARM_R 6` half-res px / 步 2、角度 ±40(0.40°)/步 10、
尺度 ±2/256 (main.c:7902-7906)；"far" 界 `REG_JUMP_R 8`、`REG_JUMP_A 60`、`REG_JUMP_S 6` (main.c:7909-7911)。
**判据里没有任何"动了多远"的项**：`REG_JUMP_R` 只用于在 16 与 32 之间选 margin (main.c:9278-9289,8802-8808)。

**1.3 2–5 mm 会不会击穿判据。** 代码自己的 mm↔px 只有两处：`REG_R 128` half-res px = ±19.7 mm (main.c:2118)
→ 1 half-res px ≈ 0.154 mm ≈ 2 source px；`±20 half-res px = ±40 source px = ±3 mm` (main.c:8784) → **13.0–13.3 px/mm**。
代码里没有 20 px/mm。按代码 2–5 mm ≈ 26–66 source px ≈ **13–33 half-res px**（按 20 px/mm 则 20–50 half-res px）——
两种算法都远超暖窗 ±6，**新最优点一定在窗口外**。

但"窗口够不到"≠"判据被击穿"：判据只问 `e_inc ≤ 192` 与"候选是否赢 16/32"。本文件自己的实测表：
同一对图上偏离 2/4/8 half-res px 只读到 **70/83/102**（4.4/5.2/6.4 级），全部远低于 192，并明确写
"**IT NO LONGER SEPARATES A GROSSLY WRONG ALIGNMENT ON THIS PAIR**" (main.c:2219-2227)。
故 13–33 half-res px 的位移**预期不会**把 `e_inc` 推过 192 → hold 仍可用 → 2 是代码在此场景下的预期输出。
冷搜索即使跑出真答案，也要赢 `REG_JUMP_MARGIN 32` 才被采纳 (main.c:9289-9295)，而该度量从 2 px 到 8 px 误差的
全部落差只有 32 单位 (main.c:2219-2221)：冷答案被 margin 驳回、退回 held (main.c:9296-9302) 自洽，
与现场"九次 −164 逐位相同、残差 0.767→1.400"一致（变换没跟上摆放，格子判据在变）。

所以 **393=2 既不能证明也不能否认搜索重跑过**：2 同时来自 8861 与 9302。要分清需同快照的
`MB_REG_WWHY 234`（2 = 平移离窗且外面仍更优，说明宽搜索跑过）(main.c:2337-2343)、`NWARM/NHOLD/NCOLD 396-398`、
`CANDERR 395` (main.c:2288-2301,11448-11453)；且 2 要与 `MB_DIFF_OK/OVER` 同读才分得清"保留"与"刚采纳、太年轻"
(main.c:2283-2285)。

**1.4 搜索每次都尝试吗。** 是。`reg_search();` 在 `diff_frame()` 里**无条件**调用 (main.c:11409)；外层门只是
`g_ref_ok != 0u && (frames % DIFF_EVERY) == 0u` (main.c:18432)、`DIFF_EVERY 16` (main.c:1896)，再上是
AEC STUCK/削顶的拒绝 (main.c:18439)。到 11409 之前唯一的提前 return 是"零件没完整在视场内" (main.c:11371-11389)。
相机 1 也每槽跑 `diff_frame(src1)` (main.c:17048,18480)。hold 是搜索**内部**的决定；判据不通过才继续冷搜索
(main.c:8865-8868,8894-8902)。

**1.5 g_reg_dx16：算在哪 vs 发在哪。** 入口清零 (main.c:8688)、换参考清零 (main.c:10337)；拒绝时由
`reg_restore_hold()` 用 held 值重算 (main.c:8144-8147)；采纳时 `g_reg_dx_fp8 = (dx_i << 8) + (ox << 4);`
`g_reg_dx16 = reg_div_round(g_reg_dx_fp8, 8)` (main.c:8102-8108)，单位见 main.c:8660-8662；冷搜索窗口边饱和的三个
拒绝分支直接赋值 (main.c:8942-8943,9106-9107,9154-9155)。发布 `PB(MB_DIFF_DX, (uint32_t)g_reg_dx16 & 0xFFFFu)`
(main.c:11492)，`MB_ALIGN_DX` 同值 (main.c:11494)；低 16 位按 int16 读：−164 = **−10.25 source px**。
**该字每帧都发，但不携带新鲜度**：mode 2 时它来自 held 原样重发 (main.c:8858-8860/9298-9299)，此时 `move == 0`
不重新武装窗口 (main.c:8085-8092)，所以多次摆放**逐位相同**。新鲜还是保留只看 393/232/491/493 (main.c:11431,11447,11456-11458)。

## 二、问题二：行时间与毫秒曝光

**2.1 推导（`sensor_timing_derive()`，main.c:9681-9748）。** 帧周期**实测**：轮询 `CAP_FRPTR & CAP_WRBIT` 跳变
~597 ms (main.c:9688-9707)，`stores = 2u * (n - 1u); frame = (tlast - tfirst) / stores;` (main.c:9709-9710)，
2…100 ms 内才用 (main.c:9711,9510-9511)。VTS **从传感器读**：0x380E/F 读两次须一致、64…4096 (main.c:9713-9721)；
HTS 读 0x380C/D (main.c:9715,9722)。`line = frame / vts;` (main.c:9724) —— **行时间 = 实测帧周期 ÷ VTS**（整数除），
2…200 us 内才收 (main.c:9725,9508-9509)。`line10 = (16u * LINE10_TICKS) / line;` (main.c:9726)，
`LINE10_TICKS 3334150` = 10 ms 的 tick (main.c:9512) → `g_line10` = 一个 10 ms 周期折成 **1/16 行** (main.c:9514)。
kmax：`g_kmax = ((vts > 4u) ? (((vts - 4u) * 16u) / line10) : 1u);`，钳 1…16 (main.c:9737-9739)。
发布 503 FRAME_TICKS / 504 LINE_PS / 509 LINE10 / 510 SEN_TIMING (main.c:9741-9747,3371-3375)。
**VTS 不是这里写的**：`sensor_frame_length_set()` 写 1200（`SENSOR_VTS_TARGET` main.c:9582；写/回读 main.c:9590-9607），
推导只把读回值当事实（FAIL-SAFE main.c:9578-9580）。相机 1 用**同一个 g_line10** + 自己的 VTS：
`g_cam1_kmax = ((vts - 4) * 16) / g_line10` (main.c:9778-9800)，顶棚 `(vts-4)*16` (main.c:9809-9810)。

**2.2 数值。** main.c:9726 反解 `line_ticks = 16 × 10 ms / MB_LINE10`，1 tick = 2.999 ns (main.c:9740)：
**T_line(us) = 160000 / MB_LINE10**。4331 → **36.94 us**（line_ticks ≈ 12317）；注释里的 4349 (main.c:9554,9735) → 36.79 us。
`MB_AEC_EXP`(145) 的单位是 **1/16 行**：`lock_exp = aec_k * g_line10` (main.c:13320,13743)、
`MB_AEC_K = aec_exp / g_line10` (main.c:13777)，g_line10 的定义注释即 "1/16 line" (main.c:9514)
（main.c:1508 写 "lines" 不精确：真按行算，8662 行 = 320 ms 会超过 44 ms 的帧）。
**公式 T_exp(ms) = MB_AEC_EXP × 10 / MB_LINE10**：8662 → **20.00 ms**（k=2）；4331 → **10.00 ms**（k=1）。
反证量子是 4331 而非注释的 4349：控制器只写 `aec_k × g_line10` (main.c:13320,13743)，8662 = 2 × 4331，
而 8662 不是 4349 的整数倍（除非走 host pin 路径 main.c:13293-13298）。顶棚 `(VTS-4)*16 = 19136` (main.c:9809-9810)，8662 用掉 45%。

**2.3 MB_FPSX10 是循环率。** 注释原文 "iterations per second of THIS main loop. Not a camera frame rate"
(main.c:18883-18886)；定义 `MB_FPSX10 7u` (main.c:14917)；计算 `x10 = (nn - fps_n0) * 10 * win / dt`，
`nn = frames`、`win = GTICKS_PER_MS * 1000` (main.c:18905-18917)；喂它的计数器是主循环的 `frames`，
同一次自增写出 `MB_PS_FRAMES`：`R32(MAILBOX + MB_PS_FRAMES * 4u) = ++frames;` (main.c:18935)。

**2.4 帧周期该用哪个：(ii)。** `1/MB_FPSX10` = 主循环时间（被判帧循环拖到 ~137 ms, main.c:9564），不是传感器帧
（注释自己给出 44.1 ms / ~22.7 fps，main.c:9563-9569）。"另一样东西"固件里已经发布：
`MB_FRAME_TICKS 503` = 实测捕获存储周期 tick (main.c:3371,9741)，`ms = 503 / 333415`（`GTICKS_MS` main.c:3504,9583）；
交叉校核 `VTS × 16 × 10 ms / MB_LINE10` = 1200 × 36.94 us = **44.3 ms**。

## 三、未确定（只凭代码判不了）

1. 那十次 mode 2 出自哪条分支（8861 暖 / 9302 冷）：需同快照的 234/395/396/397/398。
2. 那些帧 held 是否可测、`e_inc` 是否真的 ≤192：需 394(INCERR)；代码只给判据不给观测值。
3. 摆放位移在**被评分结构**上究竟多少 source px：main.c 只有 2118/8784 两处 mm↔px（13.0–13.3 px/mm），
   与来件的 20 px/mm 矛盾，哪个对代码判不了。
4. mode 2 是"保留"还是"刚采纳、太年轻"：需 180/OVER 同读 (main.c:2283-2285)。
5. "4331" 在 `ps_ui/main.c` **无任何字面出现**（grep 只命中 `0x54534331`）；结论靠 8662 = 2×4331 的算术，
   不靠代码常量。注释的 4349 与它差 0.4%，代码判不了谁对。
6. `MB_LINE_PS 504` 的单位：算式 `line*2999/1000` (main.c:9740-9742)、注释写 picoseconds (main.c:3372)，
   但该数（≈36940）只有按**纳秒**读才等于 36.94 us → 注释单位与算式差 1000 倍。
7. 曝光寄存器低 4 位是否就是"1/16 行"：main.c 只给 1/16 行量子与 20 位写 (cam_i2c.c:343-355)，
   而 main.c:1508 写 "lines"；光凭 main.c 判不了，需传感器手册。
8. 残差 0.767→1.400 与"变换没跟上"的因果：比较/残差链不读注册误差，代码不构成这条因果证据。
