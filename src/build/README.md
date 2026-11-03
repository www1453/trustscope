# 构建 Tcl

本目录是 2026-10 出货比特流的构建脚本，**不含比特流**（`.bit` 有数 MB，由 `.gitignore` 排除）。
出货比特流来自 2026-10-24 的构建：DSP 219/220、BRAM 138.5/140、WNS +0.908 ns；
生成后位于 `<Vivado 工程>/two FFT.runs/impl_1/design_1_wrapper.bit`。

- `cnn_integrate.tcl`：把 `src/hls/` 导出的 `ts_cnn_top` IP 集成进 `design_1` Block Design
  （地址 0x43C20000 / 0x43C30000）；改完先 validate 再 save。
- `batch_build.tcl`：重生成 BD 产物 → 重置全部 run → 综合 → 实现 → 比特流 →
  `write_hw_platform` 导出 XSA。
- `cnn_build.tcl`：CNN 集成后的构建（wrapper → 综合 → 实现 → 比特流），不导出 XSA。

**怎么构建**：用 Vivado 2023.1 打开厂商 AX7020 双相机基础工程（本机为 `two FFT.xpr`），
先按脚本顶部改 `XPR` / `XSA` / `SRCD` 等绝对路径，再依次执行
`vivado -mode batch -source cnn_integrate.tcl`、`vivado -mode batch -source batch_build.tcl`。
脚本里的绝对路径取自 10-21 工作树，只为记录，换机器必须改。
