# 预测（改动前写，2026-10-23 09:2x）

## 要做的动作（单变量）
从 constrs_1 移除 `submission/fpga_prize/board/two_fft_j11.xdc` 这一个文件。
不改 BD、不改 RTL、不改 PS 代码、不改其余三个 XDC。

## 取证依据（已机械核对，非推断）
constrs_1 实际含 4 个 XDC（读自 `two FFT.xpr` L265-L294）：

| 文件 | PACKAGE_PIN 条数 |
|---|---|
| ps_fft_dual/vivado/two_fft.xdc | 67 |
| dl/touchfix/two_fft_rgb888.xdc | 47 |
| submission/fpga_prize/board/two_fft_j11.xdc | 45 |
| dl/touchfix/touch_gpio.xdc | 2 |

跨文件按"引脚"聚合后：
- two_fft.xdc 与 two_fft_rgb888.xdc：同名引脚取值**全部相同**（一致冗余）
- touch_gpio.xdc 与 two_fft.xdc：F19/F20 上同为 `lcd_touch_gpio_tri_io[1]/[0]`，一致
- two_fft_j11.xdc 与 two_fft.xdc：45 个端口同名、45 个引脚**全部不同**
  （j11 把 `vid_io_out_0_data[2]`=T14 等映射到本工程 `cmos_d_0[5]` 的脚上）
- j11 **没有任何**端口是其余三份文件未约束的 → 删它不会留下悬空端口

## 假设 H1
H1：place_design 的 `failed to commit all instances` 由 two_fft_j11.xdc 造成的
引脚重复分配引起；移除该文件后，引脚冲突消失、place 能完成、能出比特流。

若 H1 成立，应观测到：
1. 构建日志里"cannot be placed on ... because the pad is already occupied"这类
   placer 报错条数 = **0**（当前 53）
2. `impl_1` 状态推进到 `write_bitstream Complete!`，且
   `two FFT.runs/impl_1/design_1_wrapper.bit` 修改时间 **晚于本次启动时刻**
3. 新比特流字节数与 `BIT_20261020_1951.bit` (4,045,676 B) **不必相同**
   （BD 有改动），这点不能当判据

若读数仍是 53 条占用冲突，则 H1 被推翻，进入已排除清单。

## 归零检查（判据有效性）
- 判据用"错误消息条数"，不看 launch_runs 的返回值（案例集 B18）
- "构建成功"只看：btn 文件存在 **且** mtime 是本次构建产生的 **且** 日志里有
  `write_bitstream Complete!`。三者缺一即视为未构建。
- 启动前先记录旧 bit 的 mtime/hash；若构建后 mtime 未变 → 说明读的是旧产物（T6）

## 明确不做的事
- 不 reset BD、不 generate_target、不动 PS 代码
- 不用 `rst -system` 当"干净加载"
- 不在同一轮里改第二个变量

## 本次测不到的（先声明，防事后外推）
- 触屏是否恢复：XDC 修完只证明"能构建"，不证明触屏活。要看 `MB_TOUCH_OK`。
- 新比特流是否让 probe_stream 看到数据：那是任务二，单独测。
