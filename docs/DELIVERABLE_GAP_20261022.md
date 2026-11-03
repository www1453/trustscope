# Deliverable Gap Audit — TrustScope — 2026-10-22 evening

Scope: read-only audit of the submission package against the nine required upload items.
Nothing under `submission/` was modified, moved or created. No Vivado / xsdb / board command was run.
This is the only file written.

Legend used throughout:

- **[V]** = verified here by a command I ran or a file I read (command/file named inline).
- **[I]** = inferred from what I measured; the reasoning is shown so it can be checked.
- Baseline for "current state" = `dl/HANDOVER_20261022_EVENING.md` (UTF-8, 5,370 B, mtime 2026-10-22 19:48:44)
  plus `ps_ui/main.c` as it stands on disk.

---

## 0. Three corrections to the audit brief itself

These matter because the brief's own numbers would drive the wrong decisions.

### 0.1 The checklist is UTF-8, not GBK  [V]

`submission/report/submission_checklist.md` decodes cleanly as UTF-8 and **produces mojibake when decoded as GBK**
(the classic `鎻愪氦娓呭崟` pattern means UTF-8 bytes read as GBK).

```
Get-Content -Encoding utf8 submission/report/submission_checklist.md   -> correct Chinese
[Encoding]::GetEncoding(936).GetString(bytes)                          -> 鎻愪氦娓呭崟妫€鏌ヨ〃 ...
UTF8Encoding(throwOnInvalidBytes).GetString(bytes)                     -> no exception => valid UTF-8
```

`dl/SUBMISSION_CHECKLIST.md` is byte-identical: both SHA-256 = `9B1EEB72FF44C6C6661452F62F3D630DF8E5A02DFF8B60A7B12F5BD4F3ACD7A4`.
So the "second copy" is not a second opinion — it is the same file.

Related [V]: `dl/scan_school.py`'s docstring states that `dl/SHOPPING_AND_TODO.md` "is NOT UTF-8: they decode as GBK".
My encoding-aware sweep decoded `submission/data/shopping_and_todo.md` as **UTF-8** on the first attempt and found the needles.
Two project documents therefore disagree with each other about the encoding of the same tree; both cannot be right.

### 0.2 The size/time limits in the audit brief do not match the authoritative checklist  [V]

The brief says the checklist is authoritative, so here is what the checklist actually says (line numbers are line numbers of the checklist):

| # | Item | Brief says | Checklist actually says (line) | Verdict |
|---|---|---|---|---|
| 1 | Demo video | MP4/H.264, **≤5 min**, **≤500MB** | `≤3 分钟` / `≤300MB` (line 13) | **brief is wrong on both** |
| 2 | Technical doc | PDF **≤20MB** | PDF `≤50MB` (line 14) | brief too strict |
| 3 | All code | RAR ≤200MB | RAR `≤200MB` (line 15) | agree |
| 4 | Commitment letter | PDF **≤10MB** | PDF `≤50MB` (line 16) | brief too strict |
| 5 | Poster (optional) | PDF/PPT **≤20MB** | PDF 或 PPT `≤50MB` (line 17) | brief too strict |
| 6 | GitHub link | mandatory | mandatory (line 18) | agree |
| 7 | Overview photo | JPG/PNG **≤20MB**, max 1 | JPG/PNG `≤10MB`, 最多 1 张 (line 19); item name is 作品**全貌**图 | brief wrong on size |
| 8 | Board photos | JPG/PNG **≤20MB**, max 4 | JPG/PNG `≤10MB`, 最多 4 张 (line 20) | brief wrong on size |
| 9 | Project intro | plain text box | 文本框 (line 21) | agree |

**There is no "≤5 min / ≤500MB" document anywhere in the repo.** A grep over all `*.md` for
`500MB|500 MB|5 分钟|5分钟|300MB|3 分钟|3分钟` returned only `≤3 分钟 / ≤300MB` statements
(`submission/report/submission_checklist.md:13`, `dl/SUBMISSION_CHECKLIST.md:13`,
`submission/video/README.md:23,100-101`, `submission/video/STORYBOARD.md:16-17,347-348`,
`submission_package/PACKAGE_README.md:32`, `dl/HANDOVER_20261016.md:17`).
So the discrepancy is **between the brief and every project document**, not between two project documents.
The real, current limits to build against are the checklist's: **3 min / 300MB video, 50MB PDFs, 10MB images.**

### 0.3 The brief's "STALE" anchor is itself slightly behind the tree  [V]

`dl/HANDOVER_20261022_EVENING.md` §3 records firmware `FW_SRC_HASH 8EE12942`, 144,300 bytes.
The tree on disk now reports:

```
ps_ui/build_id.h:2   #define FW_SRC_HASH "A1E6D5D1"   (13 source files)
ps_ui/ps_ui.elf      144,524 B   2026-10-22 19:57:04
ps_ui/touch.c         15,398 B   2026-10-22 19:55:58   <- edited 7 min AFTER the handover was written
```

The handover was written at 19:48:44; `touch.c` changed at 19:55:58 and the ELF was rebuilt at 19:57:04.
So the in-progress touch fix is **newer than the handover**, and the handover's `8EE12942` no longer describes the tree.
I use "2026-10-22 evening" as the staleness anchor as instructed, but note that the tree is ~7 minutes ahead of it.

---

## A. The nine upload items

Sizes are exact bytes from `Get-Item`; "MiB" = 1024². Status per the brief's definitions;
`NEEDS-HUMAN` is used where only a person can produce the artifact.

| # | Item (limit per checklist) | Artifact(s) on disk | Size | Last modified | Format/size check | Status |
|---|---|---|---|---|---|---|
| 1 | Demo video — MP4 / H.264 / ≤3 min / ≤300MB | `submission/video/demo.mp4` (+ `demo.avi`, `_verify/*.png`, `README.md`, `STORYBOARD.md`) | **7,337,994 B (7.00 MiB)**; avi 117,070,936 B (111.65 MiB) | **2026-10-16 22:44** | **[V] passes format**: MP4 `ftyp isom…avc1mp41`, sample entry `avc1`, `mvhd` timescale 1000 / duration 114000 → **114.00 s**, stsd 1280×720; 7.0 MiB ≪ 300MB | **STALE** |
| 2 | Technical doc — PDF / ≤50MB / must follow official template | `submission/report/technical_report.pdf` + `.docx` (identical to `dl/report/` copies) | pdf **896,320 B (0.85 MiB)**, docx 94,161 B | **2026-10-21 10:29:48 / 10:29:45** | **[V]** 36 pages, within 50MB; **template never obtained** — no official template file exists anywhere in the repo | **STALE** |
| 3 | All code — RAR / ≤200MB | **no `.rar` exists anywhere in the workspace** [V: `Get-ChildItem -Recurse -Filter *.rar` → empty]. Stand-in: `submission.zip` | `submission.zip` 129,361,660 B (123.4 MiB) | 2026-10-21 16:08:19 | zip is not RAR; content is stale anyway (see B3) | **MISSING** |
| 4 | Commitment & authorisation — PDF / ≤50MB / signed | none | — | — | — | **MISSING + NEEDS-HUMAN** |
| 5 | Poster (optional) — PDF or PPT / ≤50MB | none [V: no `*.ppt*` anywhere] | — | — | — | **MISSING** |
| 6 | GitHub link — mandatory | **no git remote configured** [V: `git remote -v` → empty] | — | — | — | **MISSING + NEEDS-HUMAN** (publish action) |
| 7 | Overview photo — JPG/PNG / ≤10MB / max 1 | none [V: no file matching 全景/全貌/panorama/poster] | — | — | — | **MISSING + NEEDS-HUMAN** |
| 8 | Board photos — JPG/PNG / ≤10MB / max 4 | none; `submission/board/` holds only `two_fft.xdc`, `RESTORE.md`, `README.md` | — | — | — | **MISSING + NEEDS-HUMAN** |
| 9 | Project intro — plain text box | `dl/PROJECT_INTRO_DRAFT.md` (ships as `submission/report/project_intro_draft.md`) | 4,543 B | **2026-10-16 21:53** | size n/a | **STALE** |

Cross-cutting defect behind items 2/3/6 — **the shipped code and shipped binary do not match the sources** [V]:

```
python dl/check_package.py   ->  EXIT=1
FAIL -- 15 problem(s):
  STALE COPY: src/ps/main.c, src/ps/cam_i2c.c, src/ps/mmu.c, src/ps/touch.c, src/ps/build_id.h
  STALE COPY: build/ps_run.tcl
  STALE COPY: fpga_prize/ps_ui/{main.c,mmu.c,cam_i2c.c,touch.c,build_id.h}
  STALE COPY: fpga_prize/board/ps_ui.elf, fpga_prize/board/ps_ui.bin
  UNSTAMPED: fpga_prize/board/ps_ui.bin does not contain TSC1A1E6D5D1
  UNSTAMPED: fpga_prize/board/ps_ui.elf does not contain TSC1A1E6D5D1
```

The repo's own gate exists precisely for this failure mode; its docstring records that the *previous* review found the same
class of drift ("the delivered ELF had been built from a DIFFERENT main.c than the one shipped beside it"). It has recurred.

---

## B. STALE / MISSING items: the pipeline that exists, how to run it, what is missing

### B1. Video (item 1) — STALE

- Generator **[V] exists**: `dl/make_demo_video.py` (65,275 B, 2026-10-16 22:40).
- Invocation (from its docstring):
  `python dl/make_demo_video.py` (also `--frames 24`, `--no-mp4`, `--keep-frames`). Writes both containers into `submission/video/`.
- It renders frames itself, then encodes the MP4 via ffmpeg/libx264. It **refuses** to emit an MP4 if no libx264 build is found.
- Dependencies today **[V]**: `D:\oopz\ffmpeg.exe` and `D:\flexsim2022\program\ffmpeg\ffmpeg.exe` both **present**;
  `ffmpeg` is *not* on PATH (that is fine — the script has a fixed candidate list); Pillow is available.
  So the toolchain is **not** the blocker.
- **What is actually missing** [I from the timestamps]: the *inputs*. The video is a 2026-10-16 render.
  Since then the board state moved (fps 19.0–20.0 today vs 16.54 as scripted; AEC converged; diff on; touch still failing;
  CNN switched off on 10-22). Any scene that shows the panel as the "current" state, or that implies touch/CNN work,
  is now wrong. Re-running the script unchanged reproduces the *old* narrative byte-for-byte (it is deterministic).
- **Consequence**: re-running the generator without new frames does not fix the staleness; new frame captures are needed.
  The video also cannot be re-recorded tonight without the board (not this audit's job).

### B2. Technical document (item 2) — STALE

- **There is no reproducible generator in the repo** [V]. `submission/report/README.md` says it plainly:
  > "生成脚本为一次性脚本，不随仓库分发；要改内容请直接改这份 docx 或重建脚本。"

  The 2026-10-16 builder is therefore **lost**, which also means the docx cannot be rebuilt from scratch — only patched.
- What *does* exist [V]:
  - `dl/update_report_1021.py` — inserts blocks before named anchors in `submission/report/technical_report.docx`
    (python-docx; "only INSERTS blocks … so every pre-existing paragraph keeps its own formatting"). Run: `python dl/update_report_1021.py`
    (it hard-codes `DOC = r"submission\report\technical_report.docx"`, i.e. must be run from the repo root).
  - `dl/fix_report_bold.py` — turns literal `**` markers into bold runs. Run: `python dl/fix_report_bold.py`.
  - `dl/_report_backup_20261021_102555.docx` and `dl/_report_pdf_1016_backup.pdf` — the pre-10-21 fallbacks.
  - Inspection helpers: `dl/doc_outline.py`, `dl/dump_report.py`, `dl/doc_styles.py`, `dl/_pdfpages.py`, `dl/_fix_tbl_bold.py`.
- PDF export path [V/I]: the PDF's `Producer` is `LibreOfficeDev 26.8.0.3`; `creationDate D:20261021102948+08'00'` matches the docx mtime
  to the second, so docx→PDF was in sync on 10-21.
  **But LibreOffice is not currently installed/findable**: not on PATH, absent from `C:\Program Files\LibreOffice`,
  `C:\Program Files (x86)\LibreOffice`, `C:\Program Files\LibreOfficeDev`, no "LibreOffice" uninstall registry entry,
  and no `soffice.exe` under `D:\DeepSeek Harness` (bounded recursive search). [I] the docx→PDF step currently has no converter
  unless the harness's office-export path supplies one — I did not test that, so treat PDF re-export as *unavailable until proven*.
- **Missing for item 2**: (a) the official template — never downloaded, so template compliance is unverifiable;
  (b) a converter for docx→PDF; (c) content updates for the 10-22 state (see C2).

### B3. Code RAR (item 3) — MISSING

- **No RAR generator in the repo** and no `.rar` file. The packaging script that exists is `dl/package_submission.py` (8,793 B, 2026-10-16 21:55)
  and it produces **zip**, not RAR.
- The *content* pipeline exists and is sound [V]:
  - `python dl/refresh_submission.py` — copies the curated source list into `submission/` and regenerates `MANIFEST.txt`;
    `--check` validates without writing. Its docstring states the intent: "提交仓库 = 本脚本的输出，单次提交，无历史包袱".
  - `python dl/check_package.py` — the drift gate (exit 0 = consistent). **Currently exit 1 with 15 problems.**
  - `powershell -ExecutionPolicy Bypass -File submission/fpga_prize/build/rebuild.ps1` — rebuilds the ELF from the package alone,
    verifying all 16 inputs first. Its default toolchain
    `D:\Vitis\Vitis\2023.1\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe` **exists** [V],
    so this step is runnable.
  - `submission/fpga_prize/docs/check_ddr_layout.py` (7,084 B) — DDR region overlap checker with a reverse self-test.
    Its own docstring says "Run: `python dl/check_ddr_layout.py`", but it ships at `docs/check_ddr_layout.py` —
    **the run instruction inside the shipped file points at a path that does not exist in the package** [V].
    (A near-duplicate `dl/check_ddr_layout.py`, 4,798 B, 2026-10-18, also exists; they are different files.)
- **Missing for item 3**: the RAR container itself, and a refresh of the stale copies first (refreshing is *not* a write I was allowed to do).

### B4. Commitment letter (item 4) — MISSING + NEEDS-HUMAN

No official form in the repo (the checklist lists "下载参赛作品承诺及使用授权书" as an undownloaded attachment).
Only a human can download, sign and scan it. Nothing to generate.

### B5. Poster (item 5) — MISSING

No generator, no `.ppt*`, no artwork sized for a poster. Would be written from scratch. Optional per the checklist.

### B6. GitHub link (item 6) — MISSING + NEEDS-HUMAN

See E. The publish action is a human decision; the repo preparation is doable by an agent.

### B7 / B8. Overview photo & board photos (items 7, 8) — MISSING + NEEDS-HUMAN

Physically require the object in front of a camera. No generator can substitute.
Guard against the obvious trap: photographs of a screen that shows `MB_TOUCH_OK=0` / `CNN NOT RUN` are honest, but a photo
captioned as a working touch panel would contradict the mailbox.

### B9. Project intro (item 9) — STALE

- Draft [V]: `dl/PROJECT_INTRO_DRAFT.md` (4,543 B, 2026-10-16 21:53) → copy at `submission/report/project_intro_draft.md` (same file, MANIFEST hash `CB8EF42310CE0E35`).
- Its "在研与未完成" section already says the right thing about CNN ("尚未集成进本次板级设计") and about touch
  ("I2C 通路已在设计中，PS 侧驱动未完成"), which is *closer* to today's truth than the report is. But:
  - it quotes "实测帧率 16.54 fps"; the 10-22 reading is **19.0–20.0 fps** [V, handover §1];
  - its "电容触摸多模式切换" wording ("PS 侧驱动未完成") understates today's finding: the driver exists but the GT911
    never answers and the code path is a crash source (see C2/T1);
  - no text has been produced for the actual submission text box yet.

---

## C. How the report was produced, and where it contradicts the current state

### C.1 Provenance  [V unless marked]

| Fact | Evidence |
|---|---|
| Two artifacts, in sync | `submission/report/technical_report.docx` 94,161 B @ 2026-10-21 10:29:45; `.pdf` 896,320 B @ 10:29:48; bytes identical to `dl/report/` copies (SHA-256 equal) |
| PDF built from that docx | PDF `creationDate D:20261021102948+08'00'`, `Producer LibreOfficeDev 26.8.0.3`, `Creator Writer` |
| Size | 36 pages (`fitz` page_count); docx has 367 paragraphs, 39 tables |
| Original builder | **not in the repo** — `submission/report/README.md`: "生成脚本为一次性脚本，不随仓库分发" |
| Incremental editor | `dl/update_report_1021.py` (10,769 B, 2026-10-21 10:25:52) then `dl/fix_report_bold.py` (2026-10-21 10:29:23) |
| Version line in the doc | "版本：2026-10-21（10-16 基线 + 10-19 至 10-21 的实测增补…）" |
| Metadata | docx `author`/`last_modified_by` = "TrustScope Project"; PDF author = "TrustScope Project"; **no** `wzh`, no `Users`, no school string in the PDF strings or docx properties |
| Identity claim | para 11: "全文不含任何人员、单位或编号身份信息；这是提交的硬性要求，已在交付前逐字复查。" — **[V] true for the report itself** (docx body+tables+core props and PDF metadata swept; zero hits). The claim is false for the *package as a whole* (see F). |
| Structural defect | Heading order is `… 九、未完成项与风险` → **`十一、全分辨率（5 MP）…`** → **`十、附录`**. Chapter 11 was inserted before chapter 10 (`dl/update_report_1021.py` inserts before an anchor). A reviewer reading top-to-bottom sees an out-of-order report. |
| Template compliance | **unverifiable**: 9.5 admits it ("官方模板尚未下载到仓库"); I confirm no template file exists anywhere in the repo (searched `*.docx`/names matching 模板|template). |

### C.2 Claims in the report that contradict the current state

Below, "report" = `submission/report/technical_report.docx` (paragraph index from python-docx, 0-based).

**T1 — Touch: the report says the controller answered. It never did.**  [V]

- Report, §4.6 first bullet (para 122):
  > "一根手指：**控制器已应答、配置表已写入、状态轮询稳定**；但「手指按下 → 切换视图」需要人去点一下屏幕。… 判为未验证。"
- Contradicting evidence:
  - `dl/HANDOVER_20261022_EVENING.md` §1: `触屏/放大  ❌ MB_TOUCH_OK=0，GT911 无应答`; §4: `MB_TOUCH_OK=0、MB_TOUCH_PID=0、MB_TOUCH_ST=0`.
  - `ps_ui/main.c:2489` — `#define MB_TOUCH_OK 87u   /* byte 348: 1 = the GT911 identified itself (id 911) */`
    → `MB_TOUCH_OK` never became 1, so by the project's own definition the panel never identified itself.
  - `ps_ui/main.c:4076` — "and **MB_TOUCH_OK has read 0 every time: the GT911 never answered.**"
  - `ps_ui/main.c:4093-4099` (the `#else` branch, i.e. what happens when the switch is off) — "…the death is inside touch_start()…".
  - `ps_ui/main.c:4091` currently takes the `#if WANT_TOUCH` path (`WANT_TOUCH` is **1** at line 2374), so `touch_start()` runs
    and fails; `g_touch_ok = 0` is published at line 4103.
- Every one of "已应答 / 配置表已写入 / 状态轮询稳定" is therefore false as of 2026-10-22. The report softens a failure into an
  unverified success. **This is the most dangerous sentence in the document.**

**T2 — CNN: the report says the self-test is integrated and reports cnn_ok=1; the current build has CNN switched off and
reports cnn_ok=0.**  [V]

- Report, §9.1 "2026-10-21 更正" (para 302):
  > "当前源码有 cnn_selftest_run() 作为上电自检 … 板上读到 **cnn_ok = 1、cnn_pass = 0 / 8** —— 即握手正常、8 组已知答案全部不通过。
  > 因此状态应更新为：**已接入自检**、结果不正确、仍未接入判定回路。"
- Contradicting evidence:
  - `ps_ui/main.c:2373` — `#define WANT_CNN 0`.
  - `ps_ui/main.c:4039-4053` — under `#if WANT_CNN` the code calls `cnn_init()`; under `#else` it sets `g_cnn_ok = 0u`.
    The `#else` comment (written 2026-10-22) says: *"Measured 2026-10-22 with the beacon pair 0xF1/0xF2: the first four writes
    … go through and 0xF2 is published, after which the application never reaches the next code -- so it **dies in the two writes
    at +0x44/+0x50 or inside cnn_init()**. A fabric block that does not answer must not take the whole machine down …
    so it is **switched off here**."*
  - `ps_ui/main.c:4052` — `g_cnn_ok = 0u;` → `MB_CNN_OK` is published as **0**, not 1.
- **The report does not contain the string `WANT_CNN` at all** [V: docx text sweep for `WANT_CNN` → 0 hits], and never says
  "the CNN is switched off". The instruction in `HANDOVER_20261022_EVENING.md` §7 ("报告里要写明 CNN 当前是关闭的") is **not satisfied**.

**T3 — §9.1 contains two mutually exclusive statements, and the stale one comes first.**  [V]

- para 300: "但 **cnn_init() / cnn_run() 在本程序里没有任何调用点（搜过，不是假设）**"
- para 302 (same section, three paragraphs later): "上段 … 已不再成立"
- Current source proves para 300 wrong: `ps_ui/main.c:4042` — `g_cnn_ok = (cnn_init() == 0) ? 1u : 0u;` (inside `#if WANT_CNN`).
  It also proves para 302 wrong in the present configuration (`WANT_CNN 0`). Both sentences are retained; a reviewer reading
  only the top of 9.1 gets the outdated claim, and a reviewer reading on gets a claim that is also no longer true.

**T4 — §9.5 says the demo video was never made; a 114 s H.264 video has existed since 10-16.**  [V]

- Report, table after para 321, row 演示视频: "**未做**（交接文件记录为 0%）"
- On disk: `submission/video/demo.mp4`, 7,337,994 B, 114.00 s, `avc1`, mtime 2026-10-16 22:44.
  The report's own §9.5 is thus wrong in the *safe* direction only in the sense that the video is stale, not absent.
  (The real defect is the video's content, not its existence — see B1.)

**T5 — §9.5 repeats the RAR blocker verbatim, and the blocker is false.**  [V]

- Report, table row 全部代码 RAR: "未做，且有硬依赖：本机 **rar / winrar / 7z / 7za 全部未安装**，且 7-Zip 只能解压 RAR、不能…"
- Measured today: **WinRAR 7.20 (64-bit) is installed** and `Rar.exe` is present and runs (see D).
- This is the same false claim as checklist 阻塞 1, copied into the report. It will be read by judges as an excuse.

**T6 — "current baseline" label is stale.**  [V]

- Report §5.7 is titled "帧率与画面质量的**当前基线**（2026-10-20 实测）" and its table works from 8.00 → 18.00 fps.
- `dl/HANDOVER_20261022_EVENING.md` §1 measures **19.0–20.0 fps** on 2026-10-22.
- Not a contradiction of a fact (different day), but the word "当前" is now wrong, and the number a judge will compare
  against the video (which shows the older panel) differs.

**T7 — §4.2/§4.5 assert the touch path's final design as "GPIO 软件位翻转" and that axi_iic is the only broken part.**
Today the GPIO bit-bang path is *also* unusable: `ps_ui/main.c:4074-4086` records that re-enabling it "crashed the program again
and took the screen with it", with the crash "inside touch_start, before the first stage marker, i.e. in the GPIO line setup" [V].
The report's §4 conclusion ("唯一坏的是「让 PL 的 axi_iic 当 I2C 主机」这条路") is therefore **incomplete**: a second fault was
found on 10-22 in the chosen replacement path. [I] this does not invalidate the axi_iic finding, it adds to it.

**What the report gets right (checked, so it is not all bad):** the shipping-tables row for 技术文档 honest-limits wording
("未验证是否与官方模板结构一致") is accurate; the 9.4 power-up-state risk section matches the handover; the identity sentence
in para 11 is true *for the report*; and the PDF's metadata is clean.

---

## D. The RAR blocker — the checklist is wrong, and it was wrong when written

### D.1 What I ran  [V]

```
Get-Command rar,winrar,7z,7za,7zr,7zG
  -> nothing.  Only:  zip.exe  (D:\texlive\2026\bin\windows\zip.exe)
                      tar.exe  (C:\WINDOWS\system32\tar.exe)

Test-Path 'C:\Program Files\7-Zip'            -> False
Test-Path 'C:\Program Files\WinRAR'           -> False
Test-Path 'C:\Program Files (x86)\7-Zip'      -> False
Test-Path 'C:\Program Files (x86)\WinRAR'     -> False
Test-Path 'C:\Program Files\Bandizip'         -> False
```

So far the checklist looks right. It is not:

```
Registry (HKLM\...\Uninstall):
  DisplayName     : WinRAR 7.20 (64-bit)
  DisplayVersion  : 7.20.0
  InstallLocation : C:\Users\wzh
  DisplayIcon     : C:\Users\wzh\WinRAR.exe
HKLM\SOFTWARE\WinRAR  exe64 = C:\Users\wzh\WinRAR.exe

Test-Path C:\Users\wzh\Rar.exe      -> True   836,304 B   2026-02-02 02:16:53
Test-Path C:\Users\wzh\WinRAR.exe   -> True 3,420,880 B   2026-02-02 02:17:02
Test-Path C:\Users\wzh\UnRAR.exe    -> True   560,848 B
Test-Path C:\Users\wzh\Default.SFX  -> True
Test-Path C:\Users\wzh\rarext.dll   -> True

& 'C:\Users\wzh\Rar.exe'
  RAR 7.20 x64   Copyright (c) 1993-2026 Alexander Roshal   1 Feb 2026
  Trial version             Type 'rar -?' for help
```

**Conclusion: a real RAR writer is installed and runnable.** `Get-Command` misses it because the install is a per-user
install into `C:\Users\wzh\` which is **not on PATH** — exactly the "measured it the wrong way" failure the project's own
M-discipline warns about (a scan that cannot see the thing it is scanning for).

`[I]` The binaries carry a 2026-02-02 timestamp and an install registry entry, so the install **predates** the 2026-10-16
checklist. The checklist's "实测：全部未安装" was therefore false when written, not merely stale.

### D.2 Can anything else make a RAR?

- **7-Zip is absent** (no `7z`/`7za`/`7zr`/`7zG`, no install dir), so the checklist's warning "7-Zip 只能解压 RAR，不能生成 RAR"
  is true but **irrelevant here** — there is no 7-Zip to be tempted by. It is the documented behaviour of 7-Zip, not something
  I measured.
- `zip.exe` (Info-ZIP, from TeX Live) and `tar.exe` (bsdtar) **cannot** produce RAR. They can only produce zip/tar.
- **Only `C:\Users\wzh\Rar.exe` can produce a real RAR.** Command shape: `C:\Users\wzh\Rar.exe a -r -m5 <out.rar> <dir>`.
- **Licence caveat** `[I]`: no `rarreg.key` exists (checked `C:\Users\wzh`, `%APPDATA%\WinRAR`, `C:\Program Files\WinRAR`),
  and the binary self-reports "Trial version". WinRAR is 40-day shareware; an installed copy from 2026-02 is well past that.
  Whether the CLI still creates archives and whether that is acceptable for a competition entry is a **human/legal call**,
  not something I can settle — and I deliberately did **not** create a test archive, because that would have written a file.

### D.3 Candidate archives vs the 200MB cap  [V]

Cap = 200MB. Even at the strict decimal reading (200,000,000 B) all three pass.

| Archive | Bytes | MiB | mtime | vs 200MB (209,715,200 B) |
|---|---|---|---|---|
| `submission.zip` | 129,361,660 | 123.4 | 2026-10-21 16:08:19 | **passes**, 61.7% of cap |
| `submission_reviewed_20261021.zip` | 128,883,418 | 122.9 | 2026-10-21 10:36:30 | passes |
| `submission_package.zip` | 30,821,964 | 29.4 | 2026-10-16 21:55:24 | passes |

`submission.zip` internals [V]: 257 entries, all under a single top-level `submission/`, uncompressed total 163.27 MiB,
and **0 entries matching `_pl_rebuild`** — so it was built before that tree appeared (2026-10-22 12:49).

### D.4 What dominates the size  [V]

`submission/` totals **171,739,356 B = 163.78 MiB, 321 files**.

| Directory | Bytes | MiB | share | note |
|---|---|---|---|---|
| `submission/video` | 126,445,198 | 120.59 | **74%** | `demo.avi` alone = 117,070,936 B (111.65 MiB) |
| `submission/stereo` | 28,172,106 | 26.87 | 16% | calibration/corner PNGs |
| `submission/fpga_prize` | 10,079,307 | 9.61 | 6% | includes `_pl_rebuild/` (64 files, 0.45 MiB) |
| `submission/dashboard` | 4,706,965 | 4.49 | 3% | |
| `submission/report` | 1,173,926 | 1.12 | 1% | docx + pdf |

**The single largest lever is `demo.avi`** — 117MB of an MJPEG AVI that is *not* a required deliverable (the requirement is MP4/H.264,
and `demo.mp4` is 7MB). Dropping `demo.avi` from the RAR takes the archive to roughly **12–13 MiB**. The AVI is a nice proof of
hand-written RIFF, but it costs 111 MiB of the 200MB budget for that proof.
Second lever: `submission/stereo` (26.87 MiB) is mostly evidence PNGs and can be trimmed.

**Packaging hazard** [V]: `submission/fpga_prize/_pl_rebuild/` is a live Vivado build tree (created 2026-10-22 12:49) sitting
**inside** the tree that gets archived. Its 64 files include `vivado.jou`, `runme.log`, `.vivado.begin.rst` containing
`Owner="wzh" Host="LAPTOP-TUME59U3"` and full local paths. A naive `rar a -r submission.rar submission\` will sweep it in.
It is git-ignored, so it will not reach GitHub, but a RAR built from disk will contain it.

---

## E. The GitHub blocker

All of the following is **[V]** from commands run at the repo root.

| Check | Result |
|---|---|
| `git remote -v` | **empty output — no remote configured at all** (not a stale URL: none) |
| Current branch | `master` |
| Last commit | `1b72ab8e2b6fd9b938bd56e379a300b794e89c92`, 2026-10-22 19:48:55 +0800, "Handover: list the skills the next session must load, with the exact opening prompt" |
| Parent | `e3b855d75b45878fbb8a457b4260d66547f13a8b` ("Evening handover: …") |
| Handover's claim "master 最新 4b53359" | **contradicted** — `4b53359` is neither HEAD nor its parent |
| `.gitignore` excludes `submission*.zip` | **yes** — lines `submission_reviewed_*.zip`, `submission*.zip`, `_pl_rebuild/`, `submission/fpga_prize/_pl_rebuild/` |
| Tracked file count | **9,368** files |
| Tracked size (sum of worktree sizes) | **1,195,393,197 B = 1,140.0 MiB** |
| Tracked size (sum of git blob sizes, `ls-tree -r -l HEAD`) | **1,202,907,682 B = 1,147.2 MiB** |
| Under 200MB? | **No. Over by ~5.7×** |

Largest tracked files (from `git ls-tree -r -l HEAD`):

```
117,070,936  submission/video/demo.avi
 97,186,951  app/data/inspections/20261003/parts.jsonl
 85,848,064  .venv-calib/Lib/site-packages/cv2/cv2.pyd
 49,454,817  dl/data/synth_128.npz
 30,876,160  .venv-calib/Lib/site-packages/cv2/opencv_videoio_ffmpeg500_64.dll
```

Two additional contradictions of project documents:

1. Checklist 阻塞 2 says "跟踪内容 **480MB**". Measured: **1,140–1,147 MiB**. Off by ~2.4×.
2. Checklist 阻塞 2 says "历史里仍有 **44 个厂商文档**". Measured: **280 tracked files** match `vendor/` (4,615,923 B).
   [I] the "44" may have counted only `*.pdf`-like documents rather than all tracked vendor files; either way the number in the
   document does not match the index.

Mechanism note [V]: `.gitignore` cannot untrack already-tracked files. This is visible in `git status` right now —
`M ps_fft_dual/logs/live14_bitpair.log` is reported as modified even though `.gitignore` lists `ps_fft_dual/logs/` and `*.log`.
So "add to .gitignore" is not a fix for the 1.1 GiB; only a **new repo published from `submission/`** is (which is what the
checklist itself proposes, and what `dl/refresh_submission.py` is built to produce).

**What is blocked:** only the human publish action. Preparing a clean repo is a mechanical step: `submission/` is 163.78 MiB on disk
and 123.4 MiB zipped, so a fresh single-commit repo from its *contents* fits the 200MB envelope — but note that even that repo is over
the 200MB cap if `demo.avi` is included alongside the rest and the cap is interpreted per-repository rather than per-upload.

---

## F. School-information sweep over what would actually ship

Method [V]: encoding-aware scan of the `submission/` tree (decode each file as UTF-8, falling back to GBK;
binary extensions skipped) — **234 text files scanned** — plus a targeted sweep of the report's docx text/tables/core properties
and the PDF's metadata and raw strings, `MANIFEST.txt`, the `README.md` files, and `submission/video/STORYBOARD.md`.
Needles: 学校 / 大学 / 学院 / 学号 / 班级 / 毕业 / 导师 / 指导教师 / 本科 / 论文, `university|college|school|advisor`,
plus the project's own list from `dl/scan_school.py` (`wust|whu|hust|uestc`), plus the personal-path and host-name patterns.
I also ran the repo's grep-based equivalent to cross-check the encoding-aware pass.

### F.1 Hits that are genuine red-line violations

| # | File : line | Offending string | Why it is a violation |
|---|---|---|---|
| F1 | `submission/data/shopping_and_todo.md:107` | "找**学校**教练组或 QQ群 `1087309750`" | school reference **and** an external contact number |
| F2 | `submission/data/shopping_and_todo.md:109` | "传送带能不能借到（**学院**实验箱，只能夹装不能拆）" | college/lab reference |
| F3 | `submission/docs/project_definition_tightened.md:3` | "本文件按**导师**评审意见重写" | advisor reference |

These three are exactly the categories the checklist itself lists (学校名/简称/老师姓名/内部路径).
They sit in files that are **copy-listed in `MANIFEST.txt`** (`data/shopping_and_todo.md 6536 46BCCBA046AEFA8B`,
`docs/project_definition_tightened.md 12173 368DC5BA2D4F2E49`) and therefore ship in the RAR *and* in the GitHub repo.
Note F1/F2 are in the same file the checklist believed it had already sanitised (its line 6 was fixed to "赛区公开通知");
**the fix was partial and nobody re-scanned the rest of the file.**

### F.2 Hits that are rule text, not identity (lower severity, but decide deliberately)

| File : line | Text | Assessment |
|---|---|---|
| `submission/report/submission_checklist.md:4,41,58,67,102` | "不能出现任何与学校相关的信息" etc. | quoting the rule. Harmless in content, but puts the word 学校 in the shipped tree 5×; if the scan is mechanical it will trip |
| `submission/report/project_intro_draft.md:3-4` | "本稿不含学校名、简称、老师姓名…" | same |
| `submission/data/competition_guide_amd.txt` (30 hits) | "全国大学生嵌入式芯片与系统设计竞赛'2026 选题指南（AMD）", "本科生", "大学一年级至三年级在读" | **not** school identity — it is the official competition guide. But it is a **third-party document (58,705 B) being redistributed**, which the repo's own policy forbids: `.gitignore` says "三方材料：绝不入库（版权不归我们，开源分发即侵权）". Publishing it on GitHub is a copyright question, not a red-line question |
| `submission/report/README.md`, `technical_report.pdf` | none | clean |

### F.3 Personal paths / username / host name  [V]

The checklist names "内部路径（含个人用户名）" as a thing that must not appear. Measured:

| Category | Files | Lines | Where |
|---|---|---|---|
| `C:\Users\wzh\…` / `C:/Users/wzh/…` | **30** | **1,528** | 15 files / 100 lines in the shipped tree proper; 15 files / 1,428 lines inside `fpga_prize/_pl_rebuild/` |
| Host name `LAPTOP-TUME59U3` | **18** | **18** | 5 shipped `fpga_prize/docs/design_1_wrapper_*.rpt` reports; 13 in `_pl_rebuild` |

The 15 shipped-tree files carrying `wzh` paths (excluding `_pl_rebuild`):

```
board/RESTORE.md                        build/run_diag4.tcl               build/stereo_recon2.tcl
build/batch_build.tcl                   build/gpio_a_build.tcl            fpga_prize/board/board_session_A.tcl
build/focus_sweep.tcl                   build/gpio_a_revert.tcl           fpga_prize/board/rebuild_pl.tcl
build/live14_bitpair.tcl                build/ps_bootcheck.tcl            fpga_prize/docs/hls/cosim_diff_detect_stream.log
build/ps_boxbase.tcl                    build/ps_run.tcl                  report/hardware_safety.md:1558
```

Worst single line [V]: `submission/video/README.md:50` reproduces the full ffmpeg command line including
`C:\Users\wzh\Documents\trustscope\submission\video\_frames\f%05d.png` — i.e. the **delivery documentation for the video**
prints the personal path. `submission/report/hardware_safety.md:1558` does the same with
`C:\Users\wzh\Documents\zynq 文献\AN970_UG.pdf`.

Severity assessment [I]: these are not school identity, and build scripts with absolute paths are normal engineering practice.
But the rule as written ("内部路径（含个人用户名）") makes them violations, and `wzh` is a username that appears 1,528 times.
A judge who greps for the entrant's identity will find it instantly. The honest reading is: **F1–F3 are the disqualifying class;
F.3 is the "will be noticed and looks careless" class.** Both should be fixed before the RAR is built, and the
`_pl_rebuild` subtree should not be shipped at all (it alone is 1,428 of the 1,528 path hits).

### F.4 What is clean

- `submission/report/technical_report.docx` — body and tables: **0** hits for 学校/大学/学院/导师/wzh/Users/论文.
- `submission/report/technical_report.pdf` — **0** hits for `wzh`/`Users` in the raw bytes; PDF metadata author = "TrustScope Project".
- `submission/video/STORYBOARD.md` — the targeted sweep found no school/identity string (its `wzh` exposure is in the sibling
  `README.md`, not the storyboard).
- No non-ASCII filenames anywhere under `submission/` [V] — the competition's `3.3.5.4` naming rule is satisfied.

---

## G. Ordered action list

Ordered by "what unblocks the most with the least risk", not by effort.

### Do first (agent-doable, no human, no board)

1. **Fix the three red-line strings (F1–F3).** Highest severity because the rule is absolute and stated three times.
   Edit `submission/data/shopping_and_todo.md:107,109` and `submission/docs/project_definition_tightened.md:3`
   (and their sources `dl/SHOPPING_AND_TODO.md` if it still carries them), then re-run the encoding-aware scan.
   *Why first:* it is the only finding that can invalidate the whole entry regardless of technical quality, and it is a text edit.
2. **Fix the shipped-vs-source drift, then re-run the gate.** `python dl/refresh_submission.py` (rebuild the copies + MANIFEST),
   then `python dl/check_package.py` must reach exit 0. Today it is exit 1 with 15 problems, including an ELF that does not carry
   the tree's source hash. Do **not** archive until this passes — otherwise the RAR ships a binary nobody can reproduce.
3. **Decide and act on `demo.avi`.** Excluding it drops the RAR from ~123 MiB to ~12 MiB and removes 111 MiB of non-required
   evidence. If the hand-written-RIFF proof is worth keeping, keep it in the repo but not in the upload archive.
   Also exclude `submission/fpga_prize/_pl_rebuild/` (build tree + 1,428 personal-path lines) from any archive explicitly.
4. **Build the RAR with the installed WinRAR** — `C:\Users\wzh\Rar.exe a -r -m5 <out>.rar submission\` — after steps 1–3.
   The checklist's "cannot make RAR" blocker is false; delete that claim from the checklist and from report §9.5 (T5).
   Confirm the licence situation with the human (Trial version, no key file).
5. **Update the report's contradictions** (T1 is the priority: delete "控制器已应答…"; then T2/T3 add "CNN is switched off
   (`WANT_CNN 0`), the fabric block takes the machine down"; T4 fix §9.5's "视频未做"; T5 delete the RAR excuse;
   T6 relabel 5.7's "当前基线"). Then fix the chapter order (十一 before 十) and re-export the PDF.
   **Note the PDF export is blocked**: no LibreOffice found on this machine — resolve that before promising a new PDF.

### Needs the human (cannot be delegated)

6. **Photographs**: 1 overview photo (item 7) + up to 4 board photos (item 8). Only a person with the object.
7. **Signed commitment & authorisation letter** (item 4): download the official form, sign, scan to PDF.
8. **GitHub publish** (item 6): the repo has **no remote at all**; publish `submission/` as a fresh single-commit repo.
   Do not push the dev repo: it carries 9,368 tracked files / ~1.14 GiB and vendor material.
9. **Confirm the licensing of the RAR tool** and the decision to redistribute `submission/data/competition_guide_amd.txt`.
10. **Obtain the official report template** and check the 36-page report against its structure — currently unverifiable.

### Single highest-risk item

**The three school-related strings in the shipped tree (F1 `shopping_and_todo.md:107`, F2 `:109`, F3
`project_definition_tightened.md:3`).**

Reasoning: every other finding costs points or causes rework; this one is stated as an absolute prohibition three times at the
top of the authoritative checklist and again in `AGENTS.md`, it sits in files already listed in `MANIFEST.txt`, and it will ship in
*both* the RAR and the GitHub repo unless someone edits three lines. It is also the cheapest thing on this list to fix — which is
precisely why it is inexcusable to ship it.

Runner-up, and much more expensive to fix: the **stale-code/stale-binary drift** (`check_package.py` FAIL, 15 problems). A judge
who reads §9.1 and then opens the code will find a report and a binary that describe two different machines.

---

## Appendix — commands actually run (so every claim above is reproducible)

```powershell
# encoding
Get-Content -Encoding utf8 submission\report\submission_checklist.md
[System.Text.Encoding]::GetEncoding(936).GetString([IO.File]::ReadAllBytes($p))     # -> mojibake
(New-Object System.Text.UTF8Encoding($false,$true)).GetString($bytes)              # -> no exception
Get-FileHash submission\report\submission_checklist.md, dl\SUBMISSION_CHECKLIST.md -Algorithm SHA256

# inventory / sizes
Get-ChildItem -Force <dir> | Select Mode,LastWriteTime,Length,Name
Get-ChildItem submission -Recurse -File | Measure-Object Length -Sum
Get-ChildItem submission\video,board,docs,build -Recurse -File | Sort Length -Desc

# archives
Get-ChildItem . -Filter *.zip | Sort Length -Desc
[IO.Compression.ZipFile]::OpenRead('submission.zip')   # 257 entries, 0 _pl_rebuild, 163.27 MiB uncompressed

# rar tooling
Get-Command rar,winrar,7z,7za,7zr,7zG
Test-Path 'C:\Program Files\7-Zip','C:\Program Files\WinRAR','C:\Program Files (x86)\7-Zip','C:\Program Files (x86)\WinRAR'
Get-ItemProperty HKLM:\SOFTWARE\...\Uninstall\* | ? DisplayName -match 'WinRAR|7-Zip'
Test-Path C:\Users\wzh\Rar.exe
& 'C:\Users\wzh\Rar.exe'      # -> "RAR 7.20 x64 ... Trial version"

# git
git remote -v                 # -> empty
git rev-parse --abbrev-ref HEAD ; git log -2 --format='%H %ad %s'
git ls-files | Measure-Object          # 9368
git ls-tree -r -l HEAD                 # sum of size column = 1,202,907,682 B

# code/package consistency
python dl\check_package.py              # EXIT=1, 15 problems

# report
python -c "from docx import Document; ..."        # paragraphs, headings, core_properties, keyword sweep
python -c "import fitz; fitz.open(pdf).page_count" # 36 pages, metadata
# PDF info dict extraction via regex over raw bytes (/Author /Creator /Producer)

# video container (no ffprobe on this machine)
python -c "parse MP4 boxes: ftyp/moov/mvhd/stsd"   # brand avc1mp41, timescale 1000 dur 114000, stsd avc1 1280x720
Get-FileHash submission\video\demo.mp4 -Algorithm SHA256   # matches README's claimed hash

# encodings-aware leak sweep
python -c "os.walk(submission); decode utf-8 then gbk; needles; aggregate by group"
```

Files read in full or in the relevant part: `submission/report/submission_checklist.md`, `dl/SUBMISSION_CHECKLIST.md`,
`dl/HANDOVER_20261022_EVENING.md`, `submission/report/README.md`, `dl/PROJECT_INTRO_DRAFT.md`, `submission/MANIFEST.txt` (head+tail),
`submission/video/README.md`, `dl/make_demo_video.py` (docstring), `dl/refresh_submission.py` (docstring+file list),
`dl/check_package.py`, `dl/scan_school.py`, `submission/fpga_prize/build/rebuild.ps1`,
`submission/fpga_prize/docs/check_ddr_layout.py` (docstring), `ps_ui/main.c` (lines 2366-2395, 4020-4110),
`ps_ui/build_id.h`, `AGENTS.md`, `submission/data/shopping_and_todo.md` (lines 1-12, 104-113).
