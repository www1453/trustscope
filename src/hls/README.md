# HLS CNN 自检通道

`ts_cnn.cpp` 是量化 CNN 核（W4/W5 权重、uint8 激活、int32 累加），输入 32×32 灰度 ROI，
输出 2 类 logits；`tb_cnn.cpp` 是同一份源码的逐位对拍测试台，`run_hls.tcl` 驱动 Vitis HLS
2023.1 的 csim/csynth，`export_ip.tcl` 把已综合结果打包成 IP 供 Block Design 调用。

**它不在判决路径上**：三态判决由 PS 上的逐格比对完成，CNN 只做旁路自检，不参与 OK/NG 判定。

实测（出货比特流）：8/8 bit-exact（逐位一致）；单次推理 29–31 ms；DSP 219/220、BRAM 138.5/140。
