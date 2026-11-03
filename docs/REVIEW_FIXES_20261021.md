# 审查整改记录（2026-10-21）

来源：对 `submission.zip` 的外部审查（12 条 P1/P2）。
本文件只记**做了什么、怎么验证、什么没做、什么试过但没用**。
等级：E2 = 板上/脚本实测可重放；E1 = 静态检查或按构造正确，未执行；E0 = 推断。

---

## 一、已修并实测（E2）

| # | 审查条目 | 修法 | 验证 |
|---|---|---|---|
| 1 | 两份 main.c 漂移，默认构建回旧配置 | `fpga_prize/ps_ui/` 改为由 `dl/refresh_submission.py` 从 `ps_ui/` 生成；`src/ps/` 补齐编译行用到的全部文件 | `dl/check_package.py` 逐个比对 101 个副本；旧包 21 FAIL → 新包 PASS |
| 1b | 清单没绑定源码版本 | 镜像里带 `TSC1`+13 个源文件哈希（邮箱 168–171） | 板上读回 `TSC14EE2D8FD`；包内独立重建产物**逐字节相同** |
| 2 | VDMA `CR bit1=1` 是 Circular 不是 Park | CR 改 `0x00010001`；`ps_run.tcl` 里启动用的 `0x00010003` 同步改掉；两处说反的注释改正 | 两色自检：Circular 时红蓝在**扫描率**上混成紫色；改成 Park 后变成**每次渲染**换一色（可数）。寄存器回读 `CR=0x00010001`，`PARK_PTR` bit0 跟随 |
| 3 | 放大取样错、跳行、长短帧坐标不一致 | zoom 改 3 字=4 像素单行 1:1；短帧同坐标 | `check_layout.py` 建模两种映射；板上 `corr(UI 行, 相机行)`：1:1 模型 0.980 vs 旧锯齿 0.949，对 `source[2x]` −0.16 |
| 7 | `-GccPath` 收了不传、依赖表漏项 | `build.ps1` 加 `param`；`rebuild.ps1` 转发并补齐 16 个依赖 | 包内 `build/rebuild.ps1` 单独跑：exit 0，产物与交付件字节相同 |
| 9 | `check_ddr_layout.py` fail-open | 链接脚本改为相对脚本查找（三候选 + argv），读不到直接 FAIL；输出声明覆盖范围 | 包内 CLEAN（程序区来自包内 `lscript.ld`）；拷到仓库外 → exit 1 |
| 5 | GPIO 不是空闲脚 | **没接入**，改为在 `verdict.c` 头部写明为什么不能接 | 静态：`design_1_bd.tcl:1170`，`gpio_io_o` → `capture_ram_0/ctrl_i` + `spi_gen_0/ctrl_i` |

## 二、改了但只能靠"读代码"保证的（E1）

**#6 `verdict_step()` 的七个缺口**：上电/重装即 HOLD；别板结果丢弃后回 WAIT；非法码 → HOLD + S_PROTO；
先查截止再收结果；两字读取做撕裂检查；`job_id=0` 首调也 arm；32 位计时器按无符号差、预算钳 12000 ms。
**未执行过**：本机没有 host 编译器，也没有安全的输出目标（那条 GPIO 会打到两个调试模块）。

## 三、试过、量过、没用，已回退（这是一条负结果，也有价值）

**#4 右相机固定读 A 缓冲。** 先测底：两个相机 1 帧存都在被写（2 秒内各 55% 字节变化），审查这条成立。
再试三种改法，同一场景、同一镜像、各 412 次渲染：

| 变体 | 撕裂/渲染 | 比例 |
|---|---|---|
| 固定读 A（原行为） | 156 / 412 | 37.9% |
| 按帧指针选，不等待，INVERT=1 | 181 / 412 | 43.9% |
| 按帧指针选，不等待，INVERT=0 | 151 / 412 | 36.7% |
| **等一次交接再选** | 100 / 274 | 36.5%，但帧率 13.7→9.1 fps |

结论：**渲染读一帧 ≈ 采集写一帧（都约 40 ms）**，任何足够读完的窗口都会被写覆盖；选择只有在对齐到窗口起点时才有意义，
而对齐本身要付掉正好那 40 ms。撕裂计数器也因此在观察期（同一配置下 36–38%）不可信，随实验一起撤掉，不留一个没人能辩护的数字。

真要修需要**第三个缓冲**：把选中的帧存 memcpy 到快照（2.7 MB，几毫秒，被覆盖窗口从 100% 降到约 10%），再从快照渲染。
代价是一次 MMU 段（`0x12000000` 只映射了 4 MB，camera 0 store D 已占 2.7 MB）。这是有地址表后果的改动，不适合在没人看屏时盲改。

## 四、准备就绪、只差人眼的（不需要了——已经做完）

显示帧存所有权那条已用两色自检判完并修好，过程见上表第 2 行。
工具留在 `ps_fft_dual/`：`disp_selftest.tcl on|off|dump`、`disp_park_test.tcl park|circ`、`disp_vdma_regs.tcl`。

## 五、明确不做（以及为什么）

| 条目 | 原因 |
|---|---|
| 接入 `verdict_step()` | 它驱动的 `axi_gpio_1` 接的是两个调试模块的 `ctrl_i`。先要有独立端口 + 约束 + 驱动板 |
| `rebuild_pl.tcl` 补 add_files/wrapper/状态检查 | 修了就必须跑一次完整综合才能证明修对；不跑就是又一份"看起来修好了"的脚本 |
| 用合成方块推光学分辨率（#10） | 结论超出实验范围，但这是**报告措辞**问题，改报告而不是改代码 |

## 六、复现命令

```powershell
powershell -File ps_ui\build.ps1            # 判据：有 OK: 且无 error:
python dl\refresh_submission.py             # 重新生成 submission/
python dl\check_package.py                  # 判据：PASS（101 副本 + 镜像哈希 + 129 条清单）
xsdb ps_fft_dual\ps_run.tcl                 # 下固件（不烧 PL）
xsdb ps_fft_dual\fwid_read.tcl              # 板上回读源码哈希
xsdb ps_fft_dual\disp_selftest.tcl on       # 两色自检（看一秒即可）
python dl\build_id.py --show                # 当前树哈希与参与文件
```
