# 构建 Tcl（Vivado 2023.1）

**先跑**：`vivado -mode batch -source src/build/verify_env.tcl`（0=输入齐全，1=缺，逐条打印缺什么）

## 本仓库**没有**分发的东西

| 缺什么 | 为什么 | 怎么补 |
|---|---|---|
| Vivado 工程 `.xpr` | 厂商 ALINX 板级文件与生成的 IP 产物不随包分发 | 新建工程 → `source src/build/bd/design_1_bd.tcl` 重建 BD → 加 `src/two_fft.xdc` → 跑下面 2–5 |
| `capture_ram.v`/`analyzer_fe.v`/`spi_gen.v` 等 module_ref 源 | 同上（BD 按模块名引用） | 先入工程，或设 `TRUSTSCOPE_RTL` |
| `FFT.xsa`、`.bit` | XSA 是构建**产物**，比特流数 MB 被 `.gitignore` 排除 | 由构建生成 |

**已在仓库里**：`bd/design_1_bd.tcl`（整流设计 Tcl 重放）、`src/two_fft.xdc`（引脚约束）。

## 顺序（在包根执行）

1. `set TRUSTSCOPE_XPR=<你的工程>.xpr`
2. `vivado -mode batch -source src/hls/run_hls.tcl`（`TS_HLS_MODE=csynth`）
3. `vivado -mode batch -source src/hls/export_ip.tcl` → 打包 `ts_cnn_top`
4. `vivado -mode batch -source src/build/cnn_integrate.tcl`
5. `vivado -mode batch -source src/build/batch_build.tcl`（综合→实现→比特流→XSA）

脚本内**无绝对路径**：全部由 `[info script]` 推导包根，可用 `TRUSTSCOPE_XPR/XSA/RTL/IPREPO/LOG/RUNS` 覆盖，日志在 `<包根>/build_logs/`。`cnn_build.tcl` 是第 5 步不导 XSA 的轻量版。出货比特流（2026-10-24）：DSP 219/220、BRAM 138.5/140、WNS +0.908 ns。
