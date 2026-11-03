#!/usr/bin/env python3
"""make_report_figures_20261103.py -- draw the report's four diagrams.

WHY
    The report has four figure placeholders ([图 1] to [图 4]) that no photograph can fill: they are
    diagrams of the architecture, the data flow, the evidence grid and the corner measurement.  They
    are also the only placeholders that need no camera and no operator, so they can be produced
    unattended.

WHAT IT DRAWS
    图 1 系统框图        -- the two cameras, the PL, the PS, the panel, the host
    图 2 PL-PS 数据流     -- what crosses the AXI boundary, and the mailbox words the host reads
    图 3 证据网格        -- 160x90 cells over a 1280x720 frame, with the defect group marked
    图 4 四角测量        -- the board inside the frame and the four corner windows

STYLE
    White background, thin grey lines, no colour except where a state is being distinguished
    (OK green, NG red, unknown amber) -- the same palette the panel uses.

USAGE
    python dl\\make_report_figures_20261103.py
    -> dl/figures_20261103/fig1_architecture.png ... fig4_corners.png  (300 dpi)
"""
import os
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle, FancyArrowPatch
import matplotlib.font_manager as fm

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'dl', 'figures_20261103')

# a CJK face, if this machine has one; the labels are Chinese because the report is
CJK = None
for cand in ('Microsoft YaHei', 'SimHei', 'Noto Sans CJK SC', 'Source Han Sans SC'):
    try:
        if fm.findfont(cand, fallback_to_default=False):
            CJK = cand
            break
    except Exception:
        continue
if CJK:
    plt.rcParams['font.sans-serif'] = [CJK]
plt.rcParams['axes.unicode_minus'] = False

GREEN = '#1e8e3e'
RED = '#c0392b'
AMBER = '#c98700'
INK = '#1a1a1a'
GREY = '#7f8c8d'


def box(ax, x, y, w, h, label, sub='', fc='#f7f9fa', ec=GREY, lw=1.0, fs=9, z=2, ty=0.5):
    """A rounded box with a label.

    ty is the label's height fraction inside the box: 0.5 centres it (a leaf box), 0.86 puts it at
    the top (a GROUP box whose children are drawn below).  Added after the first render drew group
    titles underneath their own children.
    """
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.012,rounding_size=0.02',
                                fc=fc, ec=ec, lw=lw, zorder=z))
    ax.text(x + w / 2, y + h * ty + (0.016 if sub else 0), label, ha='center', va='center',
            fontsize=fs, color=INK, zorder=z + 1, fontweight='medium')
    if sub:
        ax.text(x + w / 2, y + h * ty - 0.024, sub, ha='center', va='center',
                fontsize=fs - 2.2, color=GREY, zorder=z + 1)


def arrow(ax, x1, y1, x2, y2, label='', color=GREY, style='-|>', lw=1.1, fs=7.5, rad=0.0):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style, mutation_scale=9,
                                 lw=lw, color=color, zorder=1,
                                 connectionstyle='arc3,rad=%s' % rad))
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 0.022, label, ha='center', va='bottom',
                fontsize=fs, color=color)


def canvas(w=8.2, h=4.4):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    return fig, ax


def fig1():
    fig, ax = canvas(8.4, 4.6)
    # left: the optics
    box(ax, 0.03, 0.60, 0.20, 0.22, '相机 0', 'OV5640 / 1280x720')
    box(ax, 0.03, 0.26, 0.20, 0.22, '相机 1', '第二视角（未参与判决）')
    # middle: the PL
    box(ax, 0.30, 0.44, 0.26, 0.40, 'PL', '采集 + FFT + VDMA', fc='#eef4f7', ty=0.87)
    box(ax, 0.33, 0.47, 0.20, 0.11, '帧缓冲 A/B', '', fs=7.5)
    box(ax, 0.33, 0.61, 0.20, 0.11, 'FFT', '', fs=7.5)
    # right: the PS
    box(ax, 0.62, 0.44, 0.34, 0.40, 'PS（裸机）', '判决 / 面板 / 触摸', fc='#fdf6ec', ty=0.87)
    box(ax, 0.65, 0.62, 0.28, 0.11, '格阵重算 160x90', '', fs=7.5)
    box(ax, 0.65, 0.48, 0.28, 0.10, '三态判决', '', fs=7.5)
    # bottom: the displays
    box(ax, 0.62, 0.10, 0.16, 0.16, '面板', 'HDMI', fs=8)
    box(ax, 0.81, 0.10, 0.16, 0.16, '主机', 'JTAG 邮箱', fs=8)
    box(ax, 0.30, 0.10, 0.26, 0.16, '传送带 + STM32', 'L9110S / 串口', fs=8)
    arrow(ax, 0.23, 0.71, 0.30, 0.71, '')
    arrow(ax, 0.23, 0.37, 0.30, 0.52, '')
    arrow(ax, 0.56, 0.64, 0.62, 0.64, '')
    arrow(ax, 0.79, 0.44, 0.70, 0.26, '')
    arrow(ax, 0.79, 0.44, 0.89, 0.26, '')
    arrow(ax, 0.62, 0.18, 0.56, 0.18, '', color=GREY, style='<|-|>')
    ax.text(0.5, 0.955, '图 1  系统框图：两台相机经 PL 进入 PS，判决与拒判都在 PS',
            ha='center', va='center', fontsize=10, color=INK)
    fig.savefig(os.path.join(OUT, 'fig1_architecture.png'), dpi=300, bbox_inches='tight',
                facecolor='white')
    plt.close(fig)


def fig2():
    fig, ax = canvas(8.4, 4.4)
    ax.text(0.5, 0.955, '图 2  PL-PS 数据流与主机可读的邮箱字',
            ha='center', va='center', fontsize=10, color=INK)
    box(ax, 0.04, 0.60, 0.26, 0.22, '相机 0/1', '1280x720 BGR', fs=9)
    box(ax, 0.04, 0.26, 0.26, 0.22, 'PL 采集 + FFT', 'AXI Stream', fs=9, fc='#eef4f7')
    box(ax, 0.40, 0.26, 0.26, 0.56, 'PS 主循环', '约 1 Hz（见 3.4）', fs=9, fc='#fdf6ec')
    box(ax, 0.74, 0.62, 0.22, 0.20, '面板', '帧 + 判决', fs=8.5)
    box(ax, 0.74, 0.34, 0.22, 0.20, '主机', 'JTAG 读邮箱', fs=8.5)
    arrow(ax, 0.30, 0.71, 0.40, 0.71)
    arrow(ax, 0.30, 0.37, 0.40, 0.37)
    arrow(ax, 0.66, 0.72, 0.74, 0.72)
    arrow(ax, 0.66, 0.44, 0.74, 0.44)
    # the word list sits inside the PS box and must not cross its bottom edge (first render clipped
    # the last line); y raised from 0.30 to 0.42 and the size dropped a notch to keep all four lines
    # inside.
    ax.text(0.53, 0.42, 'MAILBOX 0x10F00000\nMB_LOCAL_VERDICT 150\nMB_DAREA 23   MB_DIFF_OK 180\nMB_REG_STATE 232  MB_REF_Q0 544',
            ha='center', va='center', fontsize=6.6, color=GREY, family='monospace')
    ax.text(0.53, 0.14, '判决不离板；主机只读，不改判决', ha='center', va='center',
            fontsize=8, color=INK)
    fig.savefig(os.path.join(OUT, 'fig2_dataflow.png'), dpi=300, bbox_inches='tight',
                facecolor='white')
    plt.close(fig)


def fig3():
    fig, ax = canvas(8.4, 4.2)
    ax.text(0.5, 0.96, '图 3  证据网格：1280x720 帧切成 160x90 个 8x8 像素格',
            ha='center', va='center', fontsize=10, color=INK)
    ax.add_patch(Rectangle((0.08, 0.10), 0.84, 0.72, fc='#f4f6f7', ec=GREY, lw=1.0))
    for i in range(1, 16):
        ax.plot([0.08 + 0.84 * i / 16, 0.08 + 0.84 * i / 16], [0.10, 0.82],
                color='#d5dbdb', lw=0.4, zorder=1)
    for j in range(1, 10):
        ax.plot([0.08, 0.92], [0.10 + 0.72 * j / 10, 0.10 + 0.72 * j / 10],
                color='#d5dbdb', lw=0.4, zorder=1)
    # a defect group: 8-connected cells over the threshold
    for (cx, cy) in [(7, 6), (7, 5), (8, 6), (8, 5), (9, 5), (9, 4)]:
        ax.add_patch(Rectangle((0.08 + 0.84 * cx / 16, 0.10 + 0.72 * cy / 10),
                               0.84 / 16, 0.72 / 10, fc=RED, ec=RED, alpha=0.75, zorder=3))
    # the callout goes into the EMPTY right-hand area of the grid, not above it: at y=0.86 it
    # collided with the figure title on the first render.
    ax.annotate('最大 8 连通组\n面积 darea = 6 格\n≥ 限值 8 → NG',
                xy=(0.08 + 0.84 * 8.5 / 16, 0.10 + 0.72 * 5.5 / 10),
                xytext=(0.60, 0.60), fontsize=8.5, color=RED,
                arrowprops=dict(arrowstyle='->', color=RED, lw=1.0))
    ax.text(0.5, 0.045, '逐格 |live − ref| > 30 灰度 记为差异格；判决取最大连通组面积',
            ha='center', va='center', fontsize=8, color=INK)
    fig.savefig(os.path.join(OUT, 'fig3_grid.png'), dpi=300, bbox_inches='tight',
                facecolor='white')
    plt.close(fig)


def fig4():
    fig, ax = canvas(8.4, 4.4)
    ax.text(0.5, 0.955, '图 4  四角测量：板面积约 12% 落在四个角窗内',
            ha='center', va='center', fontsize=10, color=INK)
    ax.add_patch(Rectangle((0.16, 0.14), 0.68, 0.68, fc='#eaf2f8', ec=INK, lw=1.4))
    ax.text(0.5, 0.48, 'PCB', ha='center', va='center', fontsize=13, color=INK)
    w = 0.13
    for (x, y, name, dx, dy) in [(0.16, 0.14 + 0.68 - w, 'TL', 0.005, -0.035),
                                 (0.16 + 0.68 - w, 0.14 + 0.68 - w, 'TR', -0.045, -0.035),
                                 (0.16, 0.14, 'BL', 0.005, 0.028),
                                 (0.16 + 0.68 - w, 0.14, 'BR', -0.045, 0.028)]:
        ax.add_patch(Rectangle((x, y), w, w, fc='none', ec=AMBER, lw=1.8, ls='--', zorder=3))
        ax.text(x + w / 2, y + (w / 2), name, ha='center', va='center', fontsize=9,
                color=AMBER, zorder=4, fontweight='bold')
    # the example goes into the caption, not into an arrow: a leader line from the title to the BR
    # corner crossed the whole board and collided with the subtitle.  A figure annotation that has
    # to travel across the subject to reach its label is telling you it belongs in the caption.
    ax.text(0.5, 0.062, '四角窗内覆盖率变化 ≥10 点判缺角（例：BR 缺料 −10.4 点 → NG）；良品波动 ±1.2 点',
            ha='center', va='center', fontsize=8.5, color=INK)
    fig.savefig(os.path.join(OUT, 'fig4_corners.png'), dpi=300, bbox_inches='tight',
                facecolor='white')
    plt.close(fig)


def main():
    os.makedirs(OUT, exist_ok=True)
    fig1(); fig2(); fig3(); fig4()
    files = sorted(os.listdir(OUT))
    print('wrote %d figures to %s' % (len(files), OUT))
    for f in files:
        p = os.path.join(OUT, f)
        print('  %-26s %7.1f KB' % (f, os.path.getsize(p) / 1024.0))
    if not CJK:
        print('\nWARNING: no CJK font found -- the Chinese labels will render as boxes.')
    else:
        print('\nfont: %s' % CJK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
