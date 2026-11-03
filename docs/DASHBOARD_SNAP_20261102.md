# 仪表盘图片刷新：dl/dashboard_snap.py（2026-11-02 20:55）

一条命令 `python dl\dashboard_snap.py`（`--which camera|panel` 只刷一路，`--dry-run` 只验不写，`--url` 指向死 JTAG 即验收 B）。

## 两个来源（地址取自现有工具，不是新猜的）
- 相机 0：`0x10000000`，691,200 字 = 2,764,800 B，1280×720 BGR、stride 3840（`dl/_snap.tcl` 同址同字数；`ps_ui/main.c:184` `CAM_BUF`）。
- 面板：ADDR1 `0x10800000` / ADDR2 `0x10A00000`，288,000 字 = 1,152,000 B，800×480 BGR、stride 2400（`ps_fft_dual/disp_fix_20261023.tcl` 回读同址；`main.c:1453` `UI_A/UI_B`）。
- 扫的是哪块：**停机之后**读 `0x43010000+0x28`（PARK_PTR）取 `& 0x1F`，0→A、1→B；原字在 0x00000001 / 0x00010001 之间跳，整字比较会误报"硬件故障"（`dl_fb_dump_20261024.tcl` 的教训）。本次多次抓取 A、B 两块都命中过（日志 `SNAP PARK` / `SNAP STORE`）。
- 前置：`MB_MAGIC`(0x10F00000)=`0x54534331` 否则整次拒绝；`MB_PS_FRAMES`(字 10) 读两次，不动只告警。

## 空白帧怎么判（黑帧在这里是真实故障模式）
停机后 `mrd` 会返回全零。判据：像素**三字节全为 0** 记为空像素；**空像素 > 99 %** 判该来源空白 → 点名来源、**一个字都不写**。
写盘前对每个来源各判一次，全部通过才写（没有"刷一半"）；写盘后再逐文件复核：PNG 格式、期望像素尺寸、空像素比例。

## 文件名映射（只写这三个；index.html / CSS / JS / 其余资产一律不动）
- `assets/cam2_pcb_full.png` ← 1280×720 原始相机帧（页面 `<img>` 声明 w:1280 h:720，不缩放）
- `assets/cam2_live_panel.png` ← 800×480 正在扫描的面板帧存（w:800 h:480）
- `assets/cam1_bench_nopcb.png` ← **同一张相机帧**裁 (760,250,1280,720)=520×470（w:520 h:470，沿用 `assets/SOURCES.json` 的裁切框）。这条 JTAG 路径只暴露相机 0 的帧存，**没有第二路视图**：它就是同一张图，不冒充第二台相机。

## A / B / C
**A 板子在线**：20:55:35–36 一条命令写入 3 个文件，均有效 PNG、尺寸符合、非空白、mtime 全新：cam2_pcb_full 1280×720 / 363,752 B、cam2_live_panel 800×480 / 206,073 B、cam1_bench_nopcb 520×470 / 53,631 B（连续几次抓到的画面各不相同，与旧图 mean|Δ|=110、96 % 像素差 > 20，说明取的是当前场景）。
**B JTAG 不可达**：`--url tcp:127.0.0.1:39999` → `SNAP FATAL connect failed: no answer`、exit 3、`REFUSED, NOTHING WRITTEN`；`--xsdb` 指向不存在的路径同样 exit 3。两次运行前后 3 个文件的 SHA-256 与毫秒级 mtime 完全不变（files_changed=0）。
**C 网页**：`http://127.0.0.1:8123/assets/…` 取回的字节与磁盘逐字节相同（sha 721e77e9 / 48ee2813 / 01e6b849），`Last-Modified 12:55:35–36 GMT` = 本地 mtime 20:55:35–36 +0800；刷新即见新图。

## 三条如实记录
1. 相机帧**会撕**：停机只停 PS，PL 采集通道照写（每 4 帧回写 store A 一次），2.7 MB 读要 5 s，画面里能看到横向拼接；证据留在 `dl/_snapwork/cam_torn_example_2054.png`。日志有 row-mean std，但它在本次对照里分不开撕裂帧与干净帧，所以**不断言无撕裂**；要根治得停采集通道（动 PL，明确不在本次范围）。
2. 一次刷新停机约 7.4–7.7 s（相机 5.1 s + 面板 2.3 s），`dashboard_feed.py` 的"连续 3 次计数不动"可能让页面闪一次 `stale_counter_stalled`，随后自愈（20:55:56 复查 status.json 仍 stale=false）。
3. 页面 `<img>` 的 w/h 与图注写死在 bundle 里，图注仍按旧图描述（如"暗箱"）；改页面不在本次范围。回退点：`backups/20261102_204943__20261102_before_dashboard_snap`（三个旧文件 + MANIFEST）。
