# 交接 2026-10-22 深夜（覆盖 EVENING 那份里有冲突的说法）

> 板子主链路仍然好的（实测 19.0 fps）。触屏**没修好**，但换掉了两个错误归因，
> 并把真正的判别点缩小到"FPGA 里跑的到底是哪一版比特流"。
> 交付物**不是"一项未做"**——报告/视频/清单都已存在，问题在于过期与里面有假陈述。

---

## 零、这一份改了什么说法（先看这张表）

| EVENING 里写的 | 实测 | 处理 |
|---|---|---|
| "`touch_last_pid()` 返回的不是 `g_last_pid`" | `touch.c:91` 返回的就是 `g_last_pid`；`build_id` 也证明源码与镜像同源 | **作废**，见 `dl/TOUCH_FIX_20261022.md` §二 |
| "根因是 BD 丢了 `C_TRI_ENABLE`"（本轮我先提出、又自己推翻） | axi_gpio v2.0 **没有**这个参数；用交付配置生成 IP，RTL 里 `gpio_io_t/i` 都在；wrapper 里 `tri_t` 已接到 IOBUF 的 T | **撤回**，见 §7.1 / §8.2 |
| "触屏只能靠固件自己发布状态" | 对。JTAG 读 PL 被 DAP 明确拒绝（`PL AXI slave ports access is not allowed`） | 保留 |
| "11/4 交付物 一个都没做" | 报告 docx/pdf、demo.mp4、MANIFEST、三个 zip 都在（10-16～10-21） | **改正**，见 `dl/DELIVERABLE_GAP_20261022.md` |
| "没有 RAR 工具" | `C:\Users\user\Rar.exe`（RAR 7.20 x64，试用）已安装，只是不在 PATH | **改正** |
| 视频上限 "5 分钟/500MB" | 提交清单写的是 **≤3 分钟/≤300MB** | 以清单为准 |
| `master 最新 4b53359` | HEAD 是 `1b72ab8` | 改正 |

---

## 一、板子现在的状态（2026-10-22 20:15 实测）

| 量 | 值 | 判据 |
|---|---|---|
| `MB_FPSX10` | **190**（19.0 fps） | 两次运行一致 |
| `MB_PROGRESS` | 2 | 主循环在转 |
| `MB_TOUCH_OK` | 0 | |
| `MB_TOUCH_PID` | **`0xCCCC0000`** | 诊断标记，见下 |
| 板内固件 | FWID `72426270`（邮箱 word169 = `0x32343237` = "7242"） | 用 FWID 前 4 字符做"新镜像是否在跑"的已知答案对照 |
| 之前那版固件 | `A1E6D5D1`（曾读到 "A1E6"） | 同法验证过 |

**固件本轮改了什么**（`ps_ui/touch.c`，已构建、已上板、已实测 19 fps）：
1. `g_last_pid` 改 `volatile` —— 阶段标记原本是"死存储"，`-O2` 有权把它们全删掉，
   那会让诊断在它最该起作用的时候说谎。备份：`backups/20261022_195546__touch-trifix-20261022`。
2. `touch_start()` 在释放两条线之后加一段**已知答案自检**，并**先测功能后果、再记录寄存器回读**：
   - 写 `GPIO_TRI (0x41220004) = 0x3`（释放两条线），然后读 `GPIO_DATA (0x41220000) & 3`
   - 返回 `0xCCCC0000 | (tri_rd<<8) | lines` —— 释放后线没变高
   - 返回 `0xDDDD0000 | (tri_rd<<8) | lines` —— 线对了但 TRI 回读不对
   - 这样一次上板就能把"释放没生效"和"读到的是锁存"分开，不再靠猜。

---

## 二、触屏：现在知道什么、不知道什么

### 已测到（E2）

1. **回归时间点**：`ps_fft_dual/logs/ps_touch_check.log`（10-16 **19:18**）记录
   `OK=1 PID=39313100 STATUS=0x00 ERR=0`、`READ HEALTH: 0 permanent failures` —— **触屏那天是通的**。
   把 `touch_gpio` 改成双通道的 `bd_cam1_frmptr.tcl` 是 **10-16 21:09**。之后一直 `OK=0`。
2. **今天**：固件确实进入 `touch_start()`、确实把两条线"释放"了，但 `GPIO_DATA` 读回 **0,0**，
   `GPIO_TRI` 回读 **0**。
3. **离线网表**（`dl/touchfix/netprobe.tcl`，不综合不上板）：用**交付的 BD** 重建后，
   wrapper 里 `lcd_touch_gpio_tri_t_0/_1` 接到 `IOBUF` 的 `.T` —— **导出设计的三态控制是接通的**。

### 仍未知（不要当成结论）

- FPGA 里到底跑的是哪一版比特流。**启动脚本烧的 `ps_fft_dual/design_1_wrapper_bitpair_50m.bit`
  mtime 是 2026-09-27 22:52，哈希与 `safe_bitstreams/` 五个存档和交付的 `BIT_20261018_2130.bit` 全不匹配**，
  而 09-27 当天的 BD 备份里只有旧的 `lcd_touch_i2c`、没有 `touch_gpio`。
  但 `0x41220000` 上确实有从设备在应答（否则会 data abort、程序会冻住），所以"一定跑的是 09-27 那版"**未被证明**。
- GT911 本体是否完好。目前没有任何一次成功应答。

### 下一个会话的第一件事（最便宜、判别力最强）

```
1. 先 `fpga -f` 一个哈希已知的存档（safe_bitstreams/BIT_20261018_2130.bit，与交付那份同哈希）
2. 走 HANDOVER_20261022_EVENING.md 第二节的启动流程（live14_bitpair.tcl 里要把 $BIT 改指到这份）
3. 读邮箱 w91 (MB_TOUCH_PID)
   判据: 变 0x39313100  => 触屏不是驱动问题，是一直加载了陈旧比特流（案例集 T6 类）
   判据: 仍 0xCCCC0000  => 再看 §8.2 的网表结论，此时才值得改 BD + 重建
```

**不要再来一遍**：不要再从 BD 导出文件的"缺属性"去推断比特流行为（本轮就是这么错的两次）；
axi_gpio 的参数名以 `D:\vitis\Vivado\2023.1\data\ip\xilinx\axi_gpio_v2_0\xgui\axi_gpio_v2_0.tcl` 为准。

---

## 三、交付物：真实状态（详见 `dl/DELIVERABLE_GAP_20261022.md`）

| # | 项 | 现状 |
|---|---|---|
| 1 | 演示视频 ≤3min/≤300MB | `submission/video/demo.mp4` 7.34 MB / H.264 / **114 s** ✔ 但内容停在 **10-16**（旁白是 16.54 fps，今天 19–20） |
| 2 | 技术文档 PDF ≤50MB | **已改并重导出**：docx 97,052 / pdf 905,664，36 页不变；27 处预注册改动的表在 `dl/_reportfix/CHANGES.md` |
| 3 | 全部代码 RAR ≤200MB | **已生成并校验**：`dist/submission_code.rar` 52,187,794 B，`Rar.exe t` → `All OK`，289 条目（257 文件 + 32 目录），无 `_pl_rebuild`、无 `*.zip` |
| 4 | 承诺及使用授权书 | **未办，需人签字** |
| 5 | 作品海报（选填） | 无 |
| 6 | GitHub 链接 | **无 remote**；跟踪内容 1.14 GB，超上限 5.7 倍 → 必须发**全新单提交仓库**（见下） |
| 7/8 | 全景图 / 板照片 | **需人拍** |
| 9 | 作品简介 | 草稿 10-16 |

### 已修的硬伤

- **学校信息红线 3 处已删**：`submission/data/shopping_and_todo.md`（"学校教练组/QQ群 1087309750"、"学院实验箱"）、
  `submission/docs/project_definition_tightened.md`（"导师"）。
  **注意**：这两份的**源**在 `dl/SHOPPING_AND_TODO.md` 与 `ps_fft_dual/PROJECT_DEFINITION_TIGHT.md`，
  只改 submission 副本的话，下一次 `refresh_submission.py` 会把红线**改回去**。源也已经改了，别再动回去。
- **报告 27 处假陈述已改**：触屏"已应答/配置表已写入"、CNN `cnn_ok=1`、面板文案"CNN NOT RUN"、
  "视频未做"、"没有 RAR 工具"、18 fps 基线、`C_TRI_ENABLE=1`、附录 D 的"已验证"、章节次序 九→十一→十。
- **CNN 关闭这件事已经写进正文 §9.1**（交接 §7 的要求），不再只是"没提"。

### 报告/PDF 的流水线方向（**这一步错了会把整晚的修改撤掉**）

```
源 -> submission 的单向复制（refresh_submission.py:142-143）
  dl/report/technical_report.docx -> submission/report/technical_report.docx
  dl/report/technical_report.pdf  -> submission/report/technical_report.pdf
```

所以要改报告的**正确顺序**是：改 `dl/report/` 里的那份 → 用 LibreOffice Kit 导出 PDF 到 `dl/report/` →
再 `python dl/refresh_submission.py`。本轮是反过来做的（改 submission 再回写源），已经同步好，
但下次别再反着来。

**PDF 转换命令**（系统里没有 soffice，用 harness 自带的 LibreOffice Kit）：
```
& "D:\DeepSeek Harness\resources\runtime\primary-runtime\dependencies\node\bin\node.exe" `
  "D:\DeepSeek Harness\resources\app.asar.unpacked\dsh\node_modules\@deepseek-ai\libreoffice-kit\lib\cli.js" `
  convert --input <docx> --output <pdf>
```

### 还剩什么

1. **GitHub（人做发布）**：现有仓库跟踪 1.14 GB，不能直接推。做法：把 `submission/` 导出成一个**全新目录**、
   `git init` + **单次提交** + 推到一个空仓库。`_pl_rebuild/` 已在 `.gitignore` 里，但那是针对旧仓库；
   新仓库直接从 `submission/` 建，天然不含它。
2. **视频重录**（可选但价值高）：`dl/make_demo_video.py` 生成，帧与旁白要换成本轮数字（19–20 fps、CNN 关闭、
   触屏不通）。它已经不是"没做"，是"内容过期"。
3. **需人**：签名授权书、全景图、板照片、海报。
4. `git commit` 还没做——本轮改动都在工作区，只靠 `backups/` 和 `dl/_reportfix/*.bak` 兜底。


---

## 四、磁盘上本轮新增的东西（可以删，删前先看用途）

```
dl/TOUCH_FIX_20261022.md           本轮全部触屏取证、预注册、撤回记录   ← 留着
dl/DELIVERABLE_GAP_20261022.md     交付物九项审计                      ← 留着
dl/touchfix/design_1_bd_touchfix.tcl  加了 C_TRI_ENABLE 的 BD 副本 —— 证明该参数不存在，**不要再用了**
dl/touchfix/netprobe.tcl + .log       网表取证脚本与结果               ← 留着
dl/touchfix/ipprobe.*                 同一配置生成 IP、看 gpio_io_t 的证据
dl/touchfix/out/ netprobe/ ipprobe/   三个 Vivado 工程（占空间，可删）
```

**注意**：`dl/touchfix/rebuild_touchfix.tcl` 是基于**已被推翻的假设**写的，它停在 BD 断言处、
没有产出任何比特流，**也没有烧过任何新比特流**。要用它之前必须先改判据。
