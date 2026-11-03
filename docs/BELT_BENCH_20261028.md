# BELT_BENCH_20261028 -- first live run of the stop-and-inspect sequencer

Status: **not yet executed.**  The sequencer and its seven simulated cases are
finished and green (`python dl\belt_selftest.py` -> 72/72).  This file is the
procedure for the day the station is free: another agent is measuring timing on
it for three days from 2026-10-28, and **any belt command now would move the
belt under its camera and invalidate its numbers.**

Read this whole file before touching anything.  The commands are ASCII on
purpose: the bench console is a Chinese Windows codepage.

| # | step | command | proves |
|---|---|---|---|
| 0 | identify the firmware | `--identify` | which wire protocol answers, with no motion possible |
| 1 | read-only station audit | `preflight.py` | the station can prove a stop at all |
| 2 | measure the stop distance ONCE | `stm32_link.py --run --hold` | how far the belt travels after STOP (coast) |
| 3 | one live cycle | `qc_belt.py --cycles 1` | the closed loop: stop, prove still, judge, release |
| 4 | falsify the stillness proof | `qc_belt.py` + a hand on the board | that "unchanged bbox" is not a stale publisher |
| 5 | two boards back to back | `qc_belt.py --cycles 2` | no verdict is reused, no cycle drifts |
| 6 | record | fill the sheets in section 8 | the numbers the report may quote |

---

## 1. Physical safety checks (before any command)

1. **The belt is clear along its whole length.**  No boards, tools, cables or
   loose tape anywhere between the idler and the drive.  Walk it once with your
   hand while the power is off.
2. **Someone is at the power switch** for the first live cycle.  Agree on the
   word before you start.
3. **The motor's serial port is named out loud and written down.**  A wrong
   `COMx` with an `R` on it can start something else.  Read the name from the
   device manager and copy it into section 8; do not type it from memory.

       Get-CimInstance Win32_SerialPort | Select-Object DeviceID,Description

4. **Nothing else is talking to that port.**  No `qc_conveyor.py`, no
   `stm32_hold.py`, no serial terminal, no Arduino IDE.  Two writers on one
   UART is how a stop is lost.
5. **The emergency path is the serial port itself.**  Closing the port sends
   nothing, and both wire protocols are built so that *no command means no
   motion*:
   * single-character firmware (`R`/`S`/`Q`, 3000 ms run cap): the run ends by
     itself 3 s after the last `R`;
   * framed firmware (`0xA5|CMD|SEQ|D0|D1|XOR`): 500 ms without a heartbeat and
     the firmware stops the motor and latches a fault (`LINK_TIMEOUT_MS`,
     `STOP_WATCHDOG` in `dl/stm32_conveyor_main.c`).
   So Ctrl-C the script, or pull the USB cable.  **Do not rely on the PC being
   alive to stop the belt** -- that is the property being used here.
6. **The station is yours.**  Confirm the other agent has finished and that no
   xsdb session of theirs is open.

---

## 2. Step 0 -- identify the firmware (cannot move the belt)

The brief says the validated motor firmware is the single-character protocol.
This repository's only motor firmware source (`dl/stm32_conveyor_main.c`) speaks
the framed protocol.  **Do not guess which one is on the bench**: ask, with a
STOP first (the one command that means "stop" under both protocols) and then a
query.

    python dl\host_qc\stm32_link.py --port COM7 --status
    python dl\host_qc\qc_belt.py --identify --motor char --port COM7

| observed | conclusion | next |
|---|---|---|
| framed STATUS answered (`{'state': 0, 'result': 0, ...}`) | framed firmware | use `--motor framed` |
| `Q` answered (any bytes printed) | single-character firmware | use `--motor char` |
| neither answers | wrong port, wrong baud (115200 8N1), or no power | stop; do not run a cycle |

Record the answer.  A protocol mismatch is not a thing to work around: the
sequencer would send the wrong escape code to a motor that is holding a board.

---

## 3. Step 1 -- read-only station audit

The sequencer needs words the firmware may not publish on every build.  It
refuses to move at all if they are missing (exit 5, `REFUSED_PRECONDITION`), and
this step is where you find that out with the belt still.

    python dl\host_qc\preflight.py

Expect one line and exit 0.  Then read the words the sequencer needs, belt still,
with the read-only tool (it starts no motion and writes no word):

    python dl\host_qc\qc_inspect.py --json

(`qc_inspect.py` lives in the development tree only; `submission/src/host_qc/`
has `preflight.py` and `record.py`, which read the same map.)

Expected words, **empty belt, belt stopped** -- these are the values recorded on
this bench on 2026-10-25 (`qc_conveyor.py` header; `dl/host_qc/logs/`), quoted
here as *expectations to confirm*, never as guarantees:

| word | index | empty belt | board wholly in view |
|---|---|---|---|
| `MB_PART_INVIEW` | 69 | 0 | 1 |
| `MB_PART_PTS` | 366 | 33..137 | ~5745 |
| `MB_PART_EDGE` | 167 | 0 | >= 2 cells |
| `MB_PART_BX0/BY0/BX1/BY1` | 115/116/136/166 | 0,0,0,0 | a box well inside 0..79 x 0..44 |
| `MB_PART_TK_N` | 514 | advancing every read | advancing every read |
| `MB_AEC_STATE` | 144 | 1 (converged) or 0 (idle) | same |
| `MB_BG_CELLS` | 229 | ~950..1020 with `MB_BG_STATE=4` | rises with the board |
| `MB_DIFF_OK` | 180 | **5** (`REFUSED_REGISTRATION`: nothing to register) | 1 when judged |
| `MB_READY` | 224 | 0 or 1 | 1 when settled |

Two of these are traps and the sequencer treats them as such:

* **`MB_DIFF_OK=5` on an empty belt is normal.**  A detector that required
  `MB_DIFF_OK == 1` before believing a board is here would never stop the belt
  for a real board (during motion the firmware refuses to compare a moving
  picture).  A detector that vetoed on 5 would stop on every empty-belt refusal.
* **`MB_PART_TK_N` must be advancing.**  Before the per-loop mask publication
  (2026-10-26) `MB_PART_PTS`/`MB_BG_CELLS` held one value for 1.5-2.4 s
  (`dl/commit_msg_conveyor_20261025i.txt`, item 2).  If it is frozen, the
  sequencer still judges -- but it refuses to call the belt `STOPPED_PROVEN`,
  because identical words from a stale publisher are not evidence of stillness.

---

## 4. Step 2 -- measure the stop distance, ONCE (and write it down)

"The stop command was accepted" and "the belt is mechanically still" are
different statements.  The sequencer proves stillness from the image (N
consecutive identical bboxes on a live publisher), but **how far the board
travels while it coasts still decides whether the board ends inside the view
band**.  Measure it once, for the duty you will run, and record it.

Preparation: a strip of masking tape on the belt surface, two marks 200 mm apart
on the frame, and a phone recording at 30 fps (or better) pointed at both.

1. Put the known-good board at the left of the view, belt clear behind it.
2. Start the belt for exactly two seconds, then let the tool stop it:

       python dl\host_qc\stm32_link.py --port COM7 --run 100 --hold 2.0

   The tool sends `STOP` on exit (the framed path); on the single-character path
   the run cap expires on its own.  **Note the wall-clock second the STOP was
   sent** -- the tool prints it, and the log line is the start of the coast.
3. In the video, find the last frame in which the tape mark moved.  Coast time =
   (that frame - the STOP frame) / 30.  Measure the belt speed from the marks:
   coast distance = speed x coast time.
4. Repeat three times.  Record all three; the **maximum** is the number the
   station lives with.

| run | duty | STOP time (s) | last-moving frame | coast time (s) | speed (mm/s) | coast (mm) |
|---|---|---|---|---|---|---|
| 1 | 100 | | | | | |
| 2 | 100 | | | | | |
| 3 | 100 | | | | | |
| **max** | | | | | | |

**The criterion.**  `MB_PART_INVIEW` is 1 only for a board wholly inside the
frame with at least 2 lattice cells (16 source pixels) of border clearance.  The
belt is stopped at the instant the station first says `MB_PART_INVIEW=1`, then
coasts.  So:

    coast distance  <  the distance from the detection point to the far edge of
                       the view band

If the measured coast is larger, the board comes to rest cut by the frame edge
(`MB_PART_INVIEW` falls back to 0) and the cycle will end
`STOPPED_UNKNOWN reason=NO_STILLNESS` -- correctly, but uselessly.  Then, in this
order:

1. **Lower the duty** (`--duty 60` ... the bench note in `qc_conveyor.py` is that
   40 % and 70 % do not move this belt at all, so this may not be available);
2. **Shorten the detection latency**: `--poll-running-s 0.03` and
   `--transport fast` (the fast transport is 60 ms median per poll; the legacy
   one is 1.1-3.6 s per read and is not usable with a 3000 ms run cap);
3. **Move the station's trigger earlier in the field of view** -- that is a
   camera/geometry change, not a host change, and it is the real fix;
4. never by widening the stillness tolerance: that would make the proof weaker
   while the boards still land in the wrong place.

---

## 5. Step 3 -- one live cycle

    python dl\host_qc\qc_belt.py --motor framed --port COM7 ^
        --presence-min 550 --cycles 1 ^
        --log dl\host_qc\logs\belt_YYYYMMDD_HHMMSS

(`--motor char --char-reissue-ms 2000 --char-cap-ms 3000` if step 0 answered the
single-character firmware.  `--presence-min` is **required**: there is no
default, and the sequencer refuses to move without a measured threshold.  Take
it from step 1: between the empty-belt `MB_PART_PTS` (33..137) and the board's
(~5745), e.g. 550.)

Expected trace, in this order:

    IDLE -> RUNNING -> SETTLING -> JUDGING -> RELEASING -> IDLE
    status=COMPLETE belt=STOPPED_UNKNOWN cycles=1 released=1 exit=0

and the words that must be visible in the printed lines at each step:

| state | what must be printed | what it means |
|---|---|---|
| RUNNING | `diff_ok=5` while the belt is empty | the empty-belt refusal, not a fault |
| RUNNING -> SETTLING | `board detected (MB_PART_PTS=... >= 550, MB_PART_INVIEW=1)` | the station's own words stopped the belt |
| SETTLING -> JUDGING | `PROVEN: 5 reads over 0.60 s: bbox=..., MB_PART_PTS ... ; MB_PART_TK_N advanced N -> N+1` | the belt is mechanically still AND the publisher is live |
| JUDGING -> RELEASING | `PASS: MB_DIFF_DAREA=<n> < limit 8, MB_DIFF_FVALID=<n>` | the verdict is corroborated by its own words |
| RELEASING -> IDLE | `the judged board has left the view` | the release ended on geometry, not on a timer |
| end | `belt=STOPPED_UNKNOWN` | **expected**: an empty belt has no landmark, so stillness is not claimed.  Confirm the belt is stopped **with your eyes**. |

If `MB_READY=0` persists, the picture is still moving or the exposure has not
converged: the sequencer will not judge, and it will say which gate it is on.
If `MB_AEC_STATE=2` appears, wait -- the exposure controller is adjusting; if it
is `3` (STUCK) the firmware's own comparison refuses and no host can fix it.

---

## 6. Step 4 -- falsify the stillness proof (the review's exact worry)

A proof that has never failed is not a proof.  Two cheap refusals, both safe:

1. **Stillness refusal.**  Start a cycle (`--cycles 1`) and, while the trace says
   `SETTLING`, put a hand on the board and slide it 5 mm.  Expected:

       status=STOPPED_UNKNOWN reason=NO_STILLNESS belt=STOPPED_UNKNOWN exit=1

   and the message quotes the bbox move.  If instead it says `PROVEN`, stop the
   bench day: the stillness window is not measuring what it claims, and
   `--still-reads`/`--still-poll-s` must be re-derived before any board is
   judged.
2. **Refusal is not a pass.**  With a board in view and the belt proven still,
   change the light (hand or a lamp) so `MB_DIFF_OK` goes to 3
   (`REFUSED_IMAGE_UNTRUSTWORTHY`).  Expected:

       status=HELD_REFUSED belt=STOPPED_PROVEN ... exit=4

   The board stays at the station.  The message names `MB_DIFF_OK=3`; a PASS
   sitting in `MB_DIFF_VERDICT` at that moment must **not** be consumed.  Put the
   board back and remove the light change before continuing.

Clear either condition by answering the prompt/aborting the script; the belt is
already stopped and the sequencer never writes the mailbox.

---

## 7. Step 5 -- two boards back to back

    python dl\host_qc\qc_belt.py --motor framed --port COM7 ^
        --presence-min 550 --cycles 2 --log dl\host_qc\logs\belt_YYYYMMDD_HHMMSS_b2

Expected: `IDLE -> RUNNING -> SETTLING -> JUDGING -> RELEASING -> IDLE` twice,
`status=COMPLETE cycles=2 released=2 exit=0`.  The second cycle must show a
**newer** `MB_DIFF_N` than the first: a verdict that predates the second stop is
refused by name (`no comparison newer than the stop`), which is the stale-PASS
trap that `qc_conveyor.py` documents.

Record the cycle times (seek time, settle time, time to verdict, release time)
from the log file -- these are the numbers that say whether the station keeps up.

---

## 8. Symptom -> action

| printed | what happened | do this |
|---|---|---|
| `REASON=NO_PART` | no board was confirmed within `--no-part-s` | is the board actually on the belt? is `--presence-min` above the board's `MB_PART_PTS`? the belt may be slipping |
| `REASON=NO_STILLNESS` | the scene never held still for N reads | read the quoted bbox: if it moves, the belt creeps -- re-measure section 4; if `MB_PART_TK_N` is frozen, the firmware publishes at comparison cadence and the host correctly refuses to claim a stop (firmware change, not host) |
| `REASON=NO_VERDICT` with a gate | a board is held, nothing judgeable arrived | the gate in the message names `MB_READY`, `MB_DIFF_OK` or the averaging arm; fix the station, then re-run |
| `HELD_REFUSED` | the station refused; a board is held | never treat as a pass; check light/reference/registration |
| `REASON=PART_LOST_WITHOUT_VERDICT` | the board left the view while the belt was commanded stopped | the coast is too long (section 4) or the belt crept; the board was **not** judged |
| `REASON=RELEASE_STUCK` | the judged board is still in view after `--release-s` | a jam.  STOP is already commanded; power down before touching the belt |
| `REASON=MOTOR_SILENT` | the motor link stopped answering | check USB/power.  Before touching the motor, confirm **by eye** that the belt is stopped: the firmware's own protection (500 ms watchdog / 3000 ms cap) is what stops it, and this host can no longer confirm it |
| `REASON=STATION_SILENT` | the mailbox stopped answering while the belt was running | xsdb/DAP problem; the belt is commanded stopped, the last comparison may still be in the mailbox -- do not re-run a cycle until stage 1 passes again |
| `REFUSED_PRECONDITION` (exit 5) | a word the sequencer needs is not published, or `--presence-min` is missing | nothing was moved; fix the word/threshold and re-run |

---

## 9. Sheets

Motor port (from step 1): `COM____`   protocol: framed / char
Presence threshold used: ______   duty: ______   transport: fast / plain
Stop distance (max of three): ______ mm at duty ______
Reference in force (label / date): ______________________

| cycle | date-time | seek s | settle s | verdict s | release s | verdict | DAREA | limit | status | exit |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |

---

## 10. What this day does NOT prove

* One board type, one light, one belt speed, one duty.  The stillness window
  (`--still-reads 5`, `--still-poll-s 0.15`, first to last read 0.60 s) is an
  **argument** until this day's data either supports it or replaces it.
* The single-character protocol has no firmware source in this tree.  If step 0
  answered `char`, the day is also the first test of that code path against
  hardware; record it as such and say so in the report.
* Stop distance is measured at one duty.  A different duty needs its own row.
* The sequencer never writes a mailbox word, never stops a core, never loads a
  bitstream.  It is a supervisor, not a calibration tool.

---

## 11. What changes for the station

Until today the station was a **static bench**: a board was placed under the
camera by hand, the operator pressed a key, and the "conveyor" was a separate
experiment measured by a separate script.  With this sequencer running, the
station is a **stop-and-inspect machine**: motion is authorised only as a
consequence of a measurement, a board is judged only after the image proves the
belt has stopped, and a board is released only after a verdict exists.  Three
words change meaning as a result -- `MB_PART_INVIEW` is no longer a diagnostic
but the trigger, `MB_DIFF_OK` is no longer only the judge's gate but the reason a
board may be held instead of advanced, and "the belt is stopped" is no longer
something the station asserts: it is something the station has to prove, and
when it cannot prove it, it says `STOPPED_UNKNOWN` and waits for a person.
