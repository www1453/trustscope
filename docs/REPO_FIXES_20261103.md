# 仓库审查修复记录（2026-11-03）

1. **README §1 过度声明**：原文“全部判定在 Zynq-7020 的裸机 PS 上完成，不依赖上位机”改为
   “三态判决在板端裸机 PS 完成；缺角的四角覆盖通道在工位控制端运行（两通道设计见报告 §2.3）”；
   `README.en.md` §1 同步改为英文两通道表述。两 README 与 `docs/HISTORY_20261021.md` 不再有同句。
2. **scratch 双 `%`**：`recompute_field_20261103.py` 的 `0.0%%` → `0.0%`；`threshold_sweep_20261103.py`
   scratch 列补成 `x/16 = y.y%`，t=8 行输出 `0/16 = 0.0%`；README 里“双 % 是笔误”的说明已删。
   计算值未动（scratch 仍 0/16）。
3. **补 CNN 源码与构建脚本**：9 个新文件、54,151 B（未含比特流）：
   `src/hls/`：ts_cnn.cpp 21,516、tb_cnn.cpp 6,571、run_hls.tcl 3,689、export_ip.tcl 2,385、README.md 595 B；
   `src/build/`：cnn_integrate.tcl 9,361、batch_build.tcl 5,752、cnn_build.tcl 3,176、README.md 1,106 B。
4. **README 围栏检查**：两版首行均为 `# TrustScope`，无整页 ``` 围栏，无需改动。

冻结指标块 §2 的 sha256 前后一致（`007AE737…246`），未改。
同句另见 `docs/ABSTRACT_20261103.md`（逐字摘要快照）、`docs/REPORT_BODY_DRAFT_20261101.md`（草稿）与
`docs/CLONE_CHECK_20261103.md`（克隆记录），属日期化记录，未改。
推送：`git push origin main` 成功；`git ls-remote origin main` 与本地 HEAD 一致。
