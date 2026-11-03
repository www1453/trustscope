# 质检台实时化 —— dl/dashboard_feed.py（2026-11-02）

## 它读什么（每个地址都在 ps_ui/main.c 逐条 grep 过，没有猜）
- 一个常驻 xsdb 会话，每 ~2 s 一次 `mrd -bin -file 0x10F00000 1024` 块读（20–60 ms，只读不写）；新起一个 xsdb 进程（启动+attach+首读+退出）实测 2.29 s（attach 0.34 s、首读 0.49 s），所以做不到"每采样 attach 一次"。
- 判定 150、差分臂票 222、双相机票 204/205、面积 23、实际上限 32、件 366、比较次数 189、源码戳 634、循环计数 10、环速字 7。
- 质量：饱和 61 / 上限 68 / 门 66 / 通道 56 / 长曝饱和 54；AEC 均值 151（255 的千分数）；背景 230/229；参考质量 544；AEC 状态 144。
- 两个陷阱：2/3/5/6/9 是 host 写、固件只读的字（读出的是旧垃圾），所以判定只认 150；220 也是 host 字（读到 0x5E2FF9CE，固件回落 8），上限只认 32。
- 已知答案对照：634 读到 0xCC73517D = ps_ui/build_id.h 的 FW_SRC_HASH；10 在递增 → 证明不是缓存读。

## 陈旧门（三态）
- 当次块读成功 + 第 0 字 == 0x54534331 + MB_PS_FRAMES 仍在动 → `stale:0`；否则 `stale:1` + 原因码，production/quality/system 全 null（不是 0）。
- 原因码：stale_no_link / stale_read_timeout / stale_partial / stale_magic / stale_counter_stalled / stale_feed_stopped / stale_feed_gone。
- feed_stopped 由进程干净退出时自己写；feed_gone 由看门狗在心跳停 9 s 后写——页面没有 age 门，没有它强杀会永远停在最后一帧数字。
- board_time 仍 null、board_time_note 原文保留；calibration 与 source 原样（from_board:false）。

## A / B / C 结果
- **A 通过**：20:13:25 抓到 status.json `stale:0`、magic_ok:true、words 1024、verdict 0（合格）、darea 4 / lim 8、diffok 1、reg 1、refq 0；同一秒 `dl/qc_all_20261101.py` 行 feedB = OK darea 4→4 limit 8 diffok 1 reg 1 refq 0（20:13:26）。20:11:55 另有一次同样一致。
- 站台会在合格与无法判定之间来回切（20:12 窗口 0↔2；20:16:57 读到 diffok=6「件未完全入视野」）。feed 只发布板子当时那个字，不追平、不插值。
- **B 通过**：干净停写入 stale_feed_stopped，强杀后 9.7 s 写入 stale_feed_gone；两次无头 Edge 重载顶部都是 mode-frozen「数据陈旧 —— 不把旧数当实时」「快照 2026-10-17 17:29:11」，数值回到冻结快照（CLIP 1.3% / mean 48），不是刚才的实时数（0.4% / —）。
- **C 通过**：JSON 解析 OK；status.js 真赋 window.__TSC_STATUS__ 且与 status.json 逐字相同；把打包里的 `ep()` 抽出来跑该文档不抛异常、映射值 == 发布值；无头 Edge 渲染出 mode-live「读取于 2026-11-02 20:17:03」。
- **D**：index.html、assets/*、stereo/* 的 mtime 仍是 19:07:48（未动）；只改了 status.json、status.js（喂数）与 打开说明.txt（加一行，UTF-8 BOM 保留）。

## 常量 vs 实时（诚实清单）
- 常量：calibration（stereo RMS 0.137、mono 0.156/0.115、20/20、0.5 px 上限）及其 source；board_time 恒为 null——固件不发布墙钟。
- 实时（同一次块读）：150、222、204/205、23、32、366、189、61、68、66、56、54、151、230、229、544、144、634、10、7。
- 主机算：generated_at、feed 运行时长、循环率（Δframes/Δt，可由 trend 里的 ps_frames 复算）、trend（内存环形，进程重启即清空）。
- 写 null 而不猜：total/ng/unsure/pass_rate、alarm、classifier（固件没有 CNN 字），以及页面那三格 mean/sigma/focus——`ep()` 把它们硬编码成 null，所以我读到的 151 只在 JSON 里。
- snapshots.files 改为页面真实使用的 6 张图，age_s 每次按文件 mtime 重算（当前 ~1.1 h，会自己变大）。

## 没做到 / 必须说清
- 页面不显示 stale_reason 原文，只把它当布尔用、换成固定横幅："为什么陈旧"只在 JSON 里；打开说明新加的那行按实际行为写。
- 旧文档"读不到板子时整页不显示数字"不准确：实际会回退到冻结的面板快照（有数字，但标着 快照/冻结证据）；只许加一行，故未改那句。
- 原因码验证：no_board / feed_stopped / feed_gone / no_link 是真实故障下跑出来的；magic / partial / counter_stalled 用合成块读验证（dl/_gate_selftest.py，不碰板子）。
- verdict=1（NG）在 30 s 内没有出现（站台现在是合格件）；NG 路径只是 150 的另一个取值，未在实测中遇到。
