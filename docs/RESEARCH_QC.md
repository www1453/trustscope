# 真实质检是怎么做的 · 调研与对照（2026-10-03）

本文回答两件事：**行业里的自动化质检到底怎么干**（有出处），
以及**我们相对它差在哪、下一步买什么**。所有结论都标注了是"检索到的"还是"我们实测的"。

---

## 一、行业做法（出处）

**1）光源是被设计的子系统，不是配件。**
Effilux 产品负责人（[Imaging and Machine Vision Europe 专题](https://www.imveurope.com/article/beyond-catalogue-oem-machine-vision-lighting-strategies)）：
*"Machine vision lighting is not a commodity component... it can either become a source of risk
or a performance enabler"*；以及
*"What functions perfectly under controlled conditions may fail when confronted with real-world
variables — ambient light fluctuations, temperature extremes, vibration, contamination: these are
system-level challenges."*
同文真实案例：汽车白车身线 **65 台/小时**（≈55 s/台），检**亚毫米**间隙与面差，
靠**专门设计的照明几何**在紧凑工位里取得对比度，中间**多轮原型迭代**。
同文还有一条：*"Laboratory validation provides necessary but insufficient evidence of production
suitability. On-site testing under actual operating conditions reveals issues invisible in
controlled environments."*

**2）难打光的表面靠"换照射几何 / 多张不同打光的图"，不靠相机动态范围。**
光源本身就是这套打法的目录：Bar / Ring / **Dome** / Coaxial / **Backlight** / **Dark Field**
（[TPL Vision](https://www.tpl-vision.com/knowledge-hub/how-to-illuminate-mirrored-and-shiny-surfaces-in-machine-vision-2/)）。
镜面/高反件用**暗场**让缺陷散射、**同轴**消反光、**穹顶**把点光变成面光。
多方向 → 多张图 → 光度立体（photometric stereo），用于 2.5D 缺陷检测
（[机器视觉网综述](https://china-vision.org/index.php/paper-detail/232163.html)、
[IEEE：多视角多光谱光度立体用于连铸板坯在线表面缺陷检测](https://ieeexplore.ieee.org/document/11371385)）。
线扫应用同样把照明当独立设计项（[Chromasens](https://chromasens.de/sites/default/files/light_solutions_for_line_scan.pdf)）。

**3）相机按标准量化。** EMVA 1288 是工业相机成像性能的标准
（[Release 4.1 论文](https://ksp.kit.edu/site/chapters/10.58895/ksp/1000174496-2/download/8032/)）。
一台在售 5GigE 工业相机（Sony IMX545，12-bit ADC）的公开数据：
**Dynamic Range 69.51 dB = 11.54 bits**，读出噪声 2.32 e⁻，满阱 8 693 e⁻，SNR max 39.4 dB
（[Teledyne FLIR EMVA 1288 数据](https://softwareservices.flir.com/FG-P5G-120S6/latest/EMVA/EMVA.html)）。

**4）检验机本身要被验收，而且要配人工复核。**
IPC 有专门针对 AOI 设备特性化与验证的标准 **IPC-9262**
（[目录](https://www.ipc.org/TOC/IPC-TOC-9262.pdf)、[介绍](https://pcbsync.com/ipc-9262/)）；
能力评估用**属性数据 MSA / 属性一致性分析**
（[SEIPI 论文 §3.1.3](https://seipi.org.ph/wp-content/uploads/2025/06/CHALLENGE-TO-ERROR-PROOFING-AUTOMATED-INSPECTION-SOLUTIONS-TO-EMBEDDED-COSMETIC-DEFECTS-ON-OPTICAL-DIFFUSER-WAFER-USING-HIGH-RESOLUTION-CHROMA-EQUIPMENT.pdf)）；
现场看两个指标：**误报 false call** 与 **漏报 escape**，且 AOI 后面永远接**人工复核工位**
（[PCBSync](https://pcbsync.com/aoi-setup-optimization/)、[SMTnet 讨论](https://smtnet.com/Forums/index.cfm?fuseaction=view_thread&CFApp=1&Thread_ID=24464&)）。

> 抓取说明：以上 1）3）是**读到的正文**；2）4）部分正文被截断，条目内容取自检索结果的
> 标题/摘要与标准编号，**未逐字引用**。引用时请按此区分。

---

## 二、我们和它的对照

| 行业做法 | 我们的状态 | 判断 |
|---|---|---|
| 光源是设计的；视场里**没有窗** | 桌上拍，视场里就有一扇窗 | ❌ 根因，软件补不了 |
| 难表面 → 换照射几何 / 多张图 | 一直在改映射和曝光救**同一张图** | ❌ 方向错三轮 |
| 相机 DR 按 EMVA 1288 ≈ **11.5 stops** | 8 bit 链路；实测场景还要 **2.7 stops** 以上，且 **1.62% 像素两档全饱和 = 无测量** | ❌ 硬件级差距 |
| 能力靠**属性 MSA**：误报 + 漏报 | 有混淆矩阵与风险-覆盖率曲线 | ✅ 对口 |
| **人工复核工位** | 三态 + `/api/review`（append-only） | ✅ **这就是行业形态，不是妥协** |
| 现场测试才算数 | 每条结论都上板量 | ✅ |
| 光源要可重复、可维护 | 已锁定曝光/增益，明确反对在线自适应 AE/AWB | ✅ |

---

## 三、本轮实测（代码在本仓库，可复跑）

### 3.1 多角度打光（光度立体）值不值 —— `ps_ui/ps_study.py`

合成**已知答案**表面（沟槽划痕 / 高斯凹坑 / 纯反照率污渍），Lambertian 正演 4 方向图再反解：

**单张图的极限**（就是今天这条路的极限）：

| 缺陷 | 单张图亮度差 |
|---|---|
| 划痕（形状型） | −10.56 灰阶 |
| 凹坑（形状型） | **−2.09 灰阶**（几乎看不见） |
| 污渍（反照率型） | −30.39 灰阶 |

单张图里三者给出的都是【暗】这**同一种**信号 —— 分不清是把东西划了还是脏了。

**光度立体的输出**：

| 缺陷 | 反照率变化 | 法向偏离平面 | 反解角误差 |
|---|---|---|---|
| 划痕 | −0.03（无） | **23.12°** | 0.72° |
| 凹坑 | +0.06（无） | **10.99°** | 0.76° |
| 污渍 | **−42.81** | 1.04°（无） | 1.04° |

→ **形状型缺陷给出大的法向偏离、几乎不变的反照率；反照率型缺陷反之。**
单张图做不到这个区分。**单张图里几乎看不见的凹坑，在法向上是 11° 的强信号。**

**它怕什么**（未知方向、未知强度的一盏灯 = 没遮住的窗）：

| 未知光强度 | 全图法向角误差 | 缺陷区角误差 |
|---|---|---|
| 0.0 | 0.75° | 0.72° |
| 0.1 | 0.80° | 1.79° |
| 0.3 | 0.95° | 4.10° |
| 1.0 | 1.30° | **9.04°** |
| 3.0 | 1.70° | **14.49°** |

→ 未知光与已知光同量级时，缺陷区的法向误差从 0.72° 涨到 **9.04°（12.6 倍）**。
**光度立体的正确性前提是"只有我已知的那几盏灯在照"** ——
这就是**必须先遮光、再多角度打光**的顺序原因，不是建议。

> 口径：合成 Lambertian 研究，量的是**机制与敏感度**，不是我们这台硬件的实测性能。

### 3.2 属性检验能力 —— `app/msa.py`

判据与 `test_engine.py` 一致（k_sigma=6.0 / t_low=1000 / t_high=4000），
缺陷是**程序注入的已知幅度圆盘**：

| 项 | 结果 |
|---|---|
| 对比度检测门限 | 阈值 = max(6σ, 8) = **17.8 灰阶**；低于它超阈像素数为 **0**（硬崖，不是概率低） |
| 幅度 12 / 16 灰阶 | 超阈像素 **0 个** → 判 OK（**漏报**） |
| 幅度 20 灰阶 | 42 个超阈像素，分数 778 |
| 幅度 34（半径 4） | 分数 1668 → **无法判定**，永远到不了 NG |
| 误报（60 件已知好件） | **0/60 = 0.0%**；无法判定 0/60 |

**分数 = 面积 × 对比度，而对比度上限是 256、面积没有上限** → 小缺陷的分数必然够不到
t_high。实测（幅度固定 60 灰阶）：半径 3 → 1511（不能 NG）、半径 4 → 2955（**不能 NG**）、
半径 6 → 6836（能 NG）。**所以"小但很确定的缺陷"在三态里只能进"无法判定"，永远不是 NG** ——
它不是被放行，是被**推给人工**。这符合三态的设计，但意味着**小缺陷的自动化覆盖率是 0**。

**重复性：一个真问题，而且是最危险的那一类。**

同一件（幅度 60、半径 8）连着看 12 次：

```
 第n次  判定    分数     参考图 9 帧里有几帧是这件坏的
   1   NG         11800    1
   ...
   5   NG         11267    5
   6   OK             0    6      <-- 从这里开始，这件坏的成了"背景"
   ...
  12   OK             0    9
```

**机制**：每一帧（含正在判的那一帧）都会进入参考历史（`engine.py` 的 `observe`）。
中位数背景在**缓冲里超过半数**变成同一个缺陷时，缺陷就成了"正常"。
K=9 → 第 6 次翻面。

**这条在产线上的含义正是最坏的一种**：如果**同一个系统性缺陷连续出现在若干件上**
（刀具磨损、夹具偏移 —— 正是"批次热点"要抓的东西），
检验机会**把它学成背景，然后停止报告**。表面现象是
**"第一件报出来了，后面几件全部放行"**。

**修法方向**（行业做法）：参考图必须**锁定**（golden reference，开机时用已知好件标定一次并冻结），
漂移另设一路报警；而**不是**让参考图跟着产线滑。
这与本项目已有的"冻结模型 + 版本号"是同一思路 —— 引擎的参考图目前是这条链上
**唯一还在自适应**的一环。

> **已实现并验证（2026-10-03）**：`engine.Inspector.lock_reference()` / `reference_locked`。
> 同一件（首判 NG）连看 12 次的对照：
>
> | 参考图 | 判定序列 | 分数 |
> |---|---|---|
> | 滑窗（现状） | NG×5 → **OK×7** | 11800 → 0（第 6 次翻面） |
> | **锁定** | **NG×12** | **11800，12 次完全相同** |
>
> 即：锁定之后重复性从"必然翻转"变成"逐次一致"，而且分数标准差为 0。
> 这也让"同一件反复看"在产线上第一次成为**有意义的动作**。

> 口径：合成标准件。上面的数字是**方法演示与算法能力**，
> 不是本机在真实产线上的能力 —— 后者必须用**真实标准件**重做一遍。

---

## 四、要买什么（针对"成像单元"这一版）

见对话中的采购建议；核心顺序是：
**① 遮光外壳 → ② 多角度可触发光源 + 恒流控制器 → ③ 偏光 → ④ 夹具 → ⑤ 标准件**。
**传送带不在第一期清单里**（理由见对话：本机节拍瓶颈是自己，不是搬运；
且光度立体要求工件在 N 张图期间**静止**）。
