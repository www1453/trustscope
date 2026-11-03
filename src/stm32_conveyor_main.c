/*
 * main.c -- STM32F103 conveyor drive with the USB-TTL command link.
 *
 * Board: STM32F103C6 (or any F103 with PA6/PA7 and USART1 on PA9/PA10).
 * Driver: L9110S.  PA6 = INA, PA7 = INB.  TIM3_CH1/CH2 = PWM on both.
 *
 * WHAT THIS FILE DOES NOT DO, on purpose:
 *   - it does not power the motor from the 3.3 V rail.  The L9110S VCC must
 *     come from the motor supply (5 V or the battery); this code cannot cause
 *     or prevent that, so wire it correctly.
 *   - it never writes both inputs HIGH at the same time.  One channel carries
 *     the PWM, the other stays LOW.  Direction is fixed forward.
 *   - it never exceeds MOTOR_DUTY_MAX.  That cap was 50 % while the motor was
 *     unknown; as of 2026-10-25 it is 100 %, on a measured finding: at 5 V
 *     through an L9110S this motor/gearbox only overcame the belt at ~full
 *     duty (40 % and 70 % hummed without moving), so there is no usable speed
 *     range below it.  The 8 ms-per-percent ramp still limits inrush, and the
 *     500 ms heartbeat watchdog is the protection that matters.  Re-lower the
 *     cap only with the same kind of measurement.
 *
 * SAFETY ORDER AT START-UP, and it matters:
 *   1. both pins as GPIO push-pull, driven LOW, before anything else;
 *   2. then the timer starts producing PWM;
 *   3. only then are the pins switched to alternate function.
 * Reverse that order and the pins float while the timer is not yet running,
 * which is an undefined input to the L9110S.
 *
 * CLOCK: the timings below assume SYSCLK = 72 MHz.  If your SystemInit leaves
 * the part on its 8 MHz HSI, nothing dangerous happens -- the motor runs at
 * 1/9 the PWM frequency and the serial link will not talk -- but change
 * SYSCLK_HZ and the prescalers together, do not change one.
 *
 * ---------------------------------------------------------------------------
 * WHY THE PREVIOUS BUILD STOPPED THE MOTOR IMMEDIATELY AFTER "RUN"
 *
 * The wire log was: RUN 30 -> reply state 1 (running), then within a second
 * GET_STATUS -> state 0, and the motor never turned.  The watchdog is the only
 * code that stops a motor without an explicit STOP, and it sets state 2; the
 * observer saw state 0.  Both facts have one explanation, and it is not the
 * framing:
 *
 *   1. motor_run() never touched s_hb_ms.  The heartbeat timestamp was still
 *      0 from reset, so the very first watchdog test after RUN compared
 *      g_ms (thousands of ms since power-on) against 0 and fired at once:
 *      stop, state = FAULT.  The RUN reply had already gone out saying 1.
 *   2. the HEARTBEAT handler then did `if (s_state == ST_FAULT) s_state =
 *      ST_STOPPED`, so the next heartbeat (<= 200 ms later) erased the fault
 *      report and answered with 0.  That is why the observer saw 0 and not 2.
 *
 * So: the watchdog called stop, and the heartbeat handler hid it.  The fix is
 * (1) a fresh RUN is its own 500 ms grace window, and (2) FAULT is sticky --
 * only an explicit STOP clears it.  Both are visible in the counters below,
 * which is how this was measured rather than guessed.
 *
 * ---------------------------------------------------------------------------
 * DIAGNOSTICS (host side: dl/host_qc/stm32_link.py, stm32_conveyor_probe.py)
 *
 * The 6-byte reply cannot carry 16 counters, so two extra commands were added.
 * The wire format is unchanged and an old host still parses every reply,
 * because every reply is still  A5 | CMD|0x80 | SEQ | D0 | D1 | XOR  (6 bytes).
 *
 *   CMD_WORD 0x05 : D0 = word index, D1 = half (0 low 16 bits, 1 high 16 bits)
 *                   reply D0|D1 = that half of that word.
 *   CMD_KNOB 0x06 : D0 = knob, D1 = value; reply is the normal state|result.
 *
 * The word that answers "who called stop" is DW_LAST_STOP_CAUSE, together with
 * DW_FAULT_TRIPS, DW_STOP_WHY_*, DW_HB_CLEARED_FAULT, DW_LAST_RUN_MS and
 * DW_RUN_TO_STOP_MS.  No STOP frame -> DW_STOP_CMDS and DW_STOP_WHY_CMD stay
 * put; a watchdog trip bumps DW_FAULT_TRIPS and DW_STOP_WHY_WATCHDOG.
 *
 * OUTPUT BACKENDS.  Two ways to drive PA6, selectable at run time (diag knob 0):
 *   BACKEND_HW (0, DEFAULT): TIM3_CH1 alternate function, 20 kHz.  Proven at
 *       100 %: the belt moved.  A 100 % segment is DC on both paths, so it was
 *       the frequency-free comparison that settled an earlier and WRONG
 *       reading of "the alternate-function path is dead" -- 20 kHz is above
 *       hearing, so a stalled motor is silent on it while the 250 Hz software
 *       path buzzes.  Silence was never evidence.
 *   BACKEND_SW (1): software PWM on PA6 as a plain GPIO, 250 Hz.  Kept as a
 *       selectable fallback (it energised the coil at 40 %); costs CPU.
 *
 * DUTY CAP.  MOTOR_DUTY_MAX (100 %) is the cap in force after every reset.  A
 * diagnostic knob (3) can lower it (0..100) for a bench test; it is not saved.
 *
 * FAULT IS STICKY.  After a heartbeat timeout the state stays 2 until an
 * explicit STOP arrives; RUN is refused with result 2 while in FAULT.  A
 * heartbeat proves the PC is alive, not that the fault is gone, so it must not
 * erase the report (that behaviour was fault 1.2 above).
 */

#include <stdint.h>

#define SYSCLK_HZ 72000000u
/* Measured on the bench: 100 % is what moves the belt, so that is the cap. */
#define MOTOR_DUTY_MAX  100u   /* percent; see the note above */
#define MOTOR_RAMP_MS     8u   /* one step every 8 ms: no current step */
#define LINK_TIMEOUT_MS 500u

/* A frame is 6 bytes = 0.52 ms at 115200.  A partial frame older than this is
   garbage left behind by a lost byte and is dropped, so a stale fragment can
   never be glued onto the next frame.  20 ms is 38 byte times: a healthy frame
   cannot trip it, and it is well inside the protocol's 50 ms frame timeout. */
#define LINK_INTERBYTE_MS 20u

/* Software PWM: 250 Hz, i.e. 4 ms per period.  At 72 MHz the phase resolution
   is one loop pass (~1 us), so the duty is accurate to 0.03 %.  The period is
   long compared with a 6-byte reply (0.52 ms), so a reply distorts at most a
   tenth of one period; that is why a few hundred Hz, not a few kHz. */
#define SW_PWM_PERIOD_US 4000u

/* ---- registers, so this file needs no CMSIS headers --------------------- */
#define R32(a) (*(volatile uint32_t *)(a))
#define APB2ENR 0x40021018u
#define APB1ENR 0x4002101Cu
#define GPIOA_CRL 0x40010800u
#define GPIOA_CRH 0x40010804u
#define GPIOA_ODR 0x4001080Cu
#define TIM3_CR1  0x40000400u
#define TIM3_CCMR1 0x40000418u
#define TIM3_CCER  0x40000420u
#define TIM3_PSC   0x40000428u
#define TIM3_ARR   0x4000042Cu
#define TIM3_CCR1  0x40000434u
#define TIM3_CCR2  0x40000438u
#define TIM3_EGR   0x40000414u
#define USART1_SR  0x40013800u
#define USART1_DR  0x40013804u
#define USART1_BRR 0x40013808u
#define USART1_CR1 0x4001380Cu

#define SR_PE   (1u << 0)
#define SR_FE   (1u << 1)
#define SR_NE   (1u << 2)
#define SR_ORE  (1u << 3)
#define SR_RXNE (1u << 5)
#define SR_TC   (1u << 6)
#define SR_TXE  (1u << 7)

#define SCB_AIRCR 0xE000ED0Cu

/* ---- a millisecond tick, from the loop itself (no interrupt) ------------ */
static volatile uint32_t g_ms;

/* SysTick, not a general-purpose timer.  Two builds in a row had a dead
   timebase -- first a dead loop that advanced every ~4 us, then a TIM4 whose
   UIF polling never fired -- and the watchdog depends on this being real.  So
   use the core timer: it needs no peripheral clock enable and no interrupt,
   and its COUNTFLAG is a documented 1 ms edge. */

#define STK_CTRL 0xE000E010u
#define STK_LOAD 0xE000E014u
#define STK_VAL  0xE000E018u

static void tick_ms(void)
{
    if (R32(STK_CTRL) & (1u << 16)) {          /* COUNTFLAG, cleared by read */
        ++g_ms;
    }
}

uint32_t millis(void) { tick_ms(); return g_ms; }

static void systick_init(void)
{
    R32(STK_LOAD) = (SYSCLK_HZ / 1000u) - 1u;  /* 1 ms */
    R32(STK_VAL)  = 0u;
    R32(STK_CTRL) = 0x5u;                      /* ENABLE | CLKSOURCE, TICKINT deliberately OFF: the vector table's SysTick entry parks in a loop, so enabling the interrupt froze the whole firmware on the first flash of this build */
}

/* ---- which code stopped the motor (the whole point of the counters) ----- */

#define STOP_BOOT     0u   /* power-on / reset: the only safe first state  */
#define STOP_CMD      1u   /* an explicit STOP frame                        */
#define STOP_WATCHDOG 2u   /* no heartbeat for LINK_TIMEOUT_MS              */
#define STOP_BACKEND  3u   /* a host request changed the output backend     */

#define BACKEND_HW 0u      /* TIM3_CH1 alternate function, 20 kHz           */
#define BACKEND_SW 1u      /* bit-banged PA6 as plain GPIO, 250 Hz          */

static uint32_t g_stop_total;
static uint32_t g_stop_why[4];
static uint32_t g_last_stop_ms;
static uint32_t g_last_run_ms;
static uint8_t  g_last_stop_cause;

/* ---- motor ------------------------------------------------------------- */

static uint8_t  s_duty;        /* what the motor is doing right now        */
static uint8_t  s_target;      /* what it is ramping towards               */
static uint32_t s_ramp_ms;
static uint8_t  s_running;
/* Hardware TIM3 PWM is the shipped default: at 100 % (DC on both paths, so no
   audibility confound) it moved the belt and it costs no CPU.  The software
   path stays selectable as a fallback with diag knob 0. */
static uint8_t  s_backend = BACKEND_HW;
static uint8_t  s_pa6_on;
static uint8_t  g_duty_cap = MOTOR_DUTY_MAX;  /* knob 3 may change it, not saved */

/* The heartbeat timestamp and the legacy switch are declared up here because
   motor_run() stamps the timestamp: that stamp IS the fix for the observed
   "RUN then immediately stopped" fault.  They are used by the link below. */
static uint32_t s_hb_ms;
static uint8_t  g_legacy_mode;  /* reproduce the old (faulty) semantics     */

static void pins_output_low(void)
{
    R32(APB2ENR) |= (1u << 2);   /* IOPAEN, or the CRL writes below are ignored */
    /* PA6 and PA7: output push-pull 2 MHz, then ODR bits low */
    uint32_t v = R32(GPIOA_CRL);
    v &= ~((0xFu << 24) | (0xFu << 28));       /* PA6 = bits 24..27, PA7 = 28..31 */
    v |=  ((0x2u << 24) | (0x2u << 28));       /* 0b0010: output push-pull 2 MHz  */
    R32(GPIOA_CRL) = v;
    R32(GPIOA_ODR) &= ~((1u << 6) | (1u << 7));
    s_pa6_on = 0u;
}

static void pins_alternate(void)
{
    /* PA6 -> TIM3_CH1, PA7 -> TIM3_CH2: AF push-pull 50 MHz (0b1011) */
    uint32_t v = R32(GPIOA_CRL);
    v &= ~((0xFu << 24) | (0xFu << 28));
    v |=  ((0xBu << 24) | (0xBu << 28));
    R32(GPIOA_CRL) = v;
}

static void tim3_pwm_init(void)
{
    R32(APB1ENR) |= (1u << 1);   /* TIM3EN, or every TIM3 write below is a no-op */
    /* 20 kHz PWM: 72 MHz / 1 / 3600 */
    R32(TIM3_PSC) = 0u;
    R32(TIM3_ARR) = (SYSCLK_HZ / 20000u) - 1u;

    /* CH1 and CH2: PWM mode 1, preload enabled */
    R32(TIM3_CCMR1) = (0x6u << 4) | (1u << 3) | (0x6u << 12) | (1u << 11);
    R32(TIM3_CCR1) = 0u;
    R32(TIM3_CCR2) = 0u;                        /* CH2 stays at zero for ever */
    R32(TIM3_CCER)  = (1u << 0) | (1u << 4);    /* CC1E | CC2E */
    R32(TIM3_EGR)   = 1u;                       /* UG: load the preloads     */
    R32(TIM3_CR1)   = 1u;                       /* CEN                        */
}

/* One choke point.  Every stop goes through here and records who asked, so the
   host can tell a STOP frame from a watchdog trip from the ramp. */
static void stop_with_reason(uint8_t why)
{
    ++g_stop_total;
    if (why < 4u) { ++g_stop_why[why]; }
    g_last_stop_cause = why;
    g_last_stop_ms    = g_ms;

    s_running = 0u;
    s_target  = 0u;
    s_duty    = 0u;
    /* back to plain GPIO first, so the level is defined immediately */
    pins_output_low();
    R32(TIM3_CCR1) = 0u;
    R32(TIM3_CCR2) = 0u;
}

void motor_stop(void) { stop_with_reason(STOP_CMD); }

/* Duty in percent, 1..100.  A fresh RUN is its own heartbeat grace window:
   the PC has just spoken, so it gets exactly LINK_TIMEOUT_MS to send the first
   heartbeat.  Without this the stale timestamp from reset trips the watchdog
   on the next loop pass (that was the "RUN then immediately stopped" fault). */
void motor_run(uint8_t duty)
{
    if (duty == 0u) { stop_with_reason(STOP_CMD); return; }
    if (duty > g_duty_cap) { duty = g_duty_cap; }
    s_target  = duty;
    s_running = 1u;
    s_ramp_ms = g_ms;
    g_last_run_ms = g_ms;
    if (g_legacy_mode == 0u) { s_hb_ms = g_ms; }
    if (s_backend == BACKEND_HW) { pins_alternate(); }
    else                         { pins_output_low(); }
}

/* call from the loop; ramps one percent per MOTOR_RAMP_MS */
static void motor_tick(void)
{
    if (!s_running || s_duty == s_target) { return; }
    if ((uint32_t)(g_ms - s_ramp_ms) < MOTOR_RAMP_MS) { return; }
    s_ramp_ms = g_ms;
    if (s_duty < s_target) { ++s_duty; } else { --s_duty; }
    if (s_backend == BACKEND_HW) {
        R32(TIM3_CCR1) = ((R32(TIM3_ARR) + 1u) * (uint32_t)s_duty) / 100u;
    }
}

/* Software PWM on PA6 as a plain GPIO.  The phase comes from SysTick's
   down-counter, so it needs no timer channel and no interrupt -- the same
   timebase the watchdog already trusts.  Called from the main loop and from
   the UART transmit wait, which is the only long block in the loop. */
static void sw_pwm_pump(void)
{
    uint32_t load, val, phase, whole, on;
    if (s_backend != BACKEND_SW) { return; }
    tick_ms();
    load  = R32(STK_LOAD);
    val   = R32(STK_VAL);
    phase = load - val;                       /* 0 .. load, wraps cleanly */
    whole = g_ms * 1000u + phase / (SYSCLK_HZ / 1000000u);
    phase = whole % SW_PWM_PERIOD_US;
    on = (phase < (uint32_t)s_duty * (SW_PWM_PERIOD_US / 100u)) ? 1u : 0u;
    if (on != s_pa6_on) {
        s_pa6_on = (uint8_t)on;
        if (on) { R32(GPIOA_ODR) |=  (1u << 6); }
        else    { R32(GPIOA_ODR) &= ~(1u << 6); }
    }
}

/* ---- link (same protocol as dl/STM32_LINK_PROTOCOL.md) ------------------ */

#define LINK_SOF      0xA5u
#define CMD_STOP      0x01u
#define CMD_RUN       0x02u
#define CMD_HEARTBEAT 0x03u
#define CMD_STATUS    0x04u
#define CMD_WORD      0x05u   /* added: read one diagnostic word            */
#define CMD_KNOB      0x06u   /* added: set one diagnostic knob             */

#define ST_STOPPED 0u
#define ST_RUNNING 1u
#define ST_FAULT   2u
#define RES_OK        0u
#define RES_BAD_DUTY  1u
#define RES_BAD_STATE 2u
#define RES_BAD_FRAME 2u      /* same value as RES_BAD_STATE, by protocol   */

#define FRAME_LEN 6u
#define RX_BUF_SIZE 16u

static uint8_t  s_state, s_result, s_last_result, s_last_seq, s_have_seq;
static uint8_t  s_pending_reset;

/* counters, all readable from the host */
static uint32_t g_rx_bytes, g_frames_ok, g_bad_xor, g_resync_drops;
static uint32_t g_overruns, g_bad_prefix, g_run_cmds, g_stop_cmds;
static uint32_t g_hb_recv, g_hb_applied, g_dup_seq, g_status_cmds, g_diag_cmds;
static uint32_t g_fault_trips, g_hb_cleared_fault, g_reject_state, g_tx_bytes;

static uint8_t s_rx[RX_BUF_SIZE];
static uint8_t s_head, s_tail, s_cnt;
static uint32_t s_last_rx_ms;

static void uart1_init(void)
{
    R32(APB2ENR) |= (1u << 2) | (1u << 14);      /* IOPAEN | USART1EN */
    {
        uint32_t v = R32(GPIOA_CRH);
        v &= ~((0xFu << 4) | (0xFu << 8));       /* PA9, PA10       */
        v |=  ((0xBu << 4) | (0x4u << 8));       /* AF PP50, float  */
        R32(GPIOA_CRH) = v;
    }
    R32(USART1_BRR) = (SYSCLK_HZ + 115200u / 2u) / 115200u;
    R32(USART1_CR1) = (1u << 13) | (1u << 3) | (1u << 2);   /* UE|TE|RE */
}

static void uart1_tx(uint8_t b)
{
    uint32_t guard = 0u;
    while ((R32(USART1_SR) & SR_TXE) == 0u) {
        sw_pwm_pump();          /* keep the software PWM in phase while waiting */
        if (++guard > 200000u) { return; }
    }
    R32(USART1_DR) = b;
    ++g_tx_bytes;
}

static void reply(uint8_t cmd, uint8_t seq, uint8_t d0, uint8_t d1)
{
    uint8_t f[FRAME_LEN]; uint8_t x = 0u; uint32_t i;
    f[0] = LINK_SOF; f[1] = (uint8_t)(cmd | 0x80u); f[2] = seq; f[3] = d0; f[4] = d1;
    /* The XOR covers CMD..DATA1, i.e. bytes 1..4.  It must NOT include the SOF:
       dl/STM32_LINK_PROTOCOL.md section 4 and dl/host_qc/stm32_link.py both
       define it that way, and until 2026-10-25 this firmware XORed five bytes
       (SOF included).  Measured on the board: the old GET_STATUS reply was
       a5 84 01 00 00 20 where 0x20 = A5^84^01, and the PC tool's parse_frame
       rejects exactly that (it expects 0x85 = 84^01).  The PC could therefore
       never read a reply; the raw hex in the fault report was captured with a
       terminal, not with the host tool. */
    for (i = 1u; i < 5u; ++i) { x ^= f[i]; }
    f[5] = x;
    for (i = 0; i < FRAME_LEN; ++i) { uart1_tx(f[i]); }
}

/* ---- diagnostic words --------------------------------------------------- */

#define DW_MS              0u
#define DW_RX_BYTES        1u
#define DW_FRAMES_OK       2u
#define DW_BAD_XOR         3u
#define DW_RESYNC          4u
#define DW_OVERRUN         5u
#define DW_BAD_PREFIX      6u
#define DW_RUN_CMDS        7u
#define DW_STOP_CMDS       8u
#define DW_HB_RECV         9u
#define DW_HB_APPLIED     10u
#define DW_DUP_SEQ        11u
#define DW_STATUS_CMDS    12u
#define DW_DIAG_CMDS      13u
#define DW_FAULT_TRIPS    14u
#define DW_HB_CLEARED_FAULT 15u
#define DW_LAST_STOP_CAUSE 16u
#define DW_STATE_RESULT   17u
#define DW_DUTY_TARGET    18u
#define DW_HB_MS          19u
#define DW_LAST_STOP_MS   20u
#define DW_LAST_RUN_MS    21u
#define DW_HB_GAP_MS      22u   /* last_stop_ms - hb_ms: the measured timeout */
#define DW_STOP_TOTAL     23u
#define DW_STOP_WHY_BOOT  24u
#define DW_STOP_WHY_CMD   25u
#define DW_STOP_WHY_WDOG  26u
#define DW_STOP_WHY_BACKEND 27u
#define DW_BACKEND        28u
#define DW_PIN_CFG        29u   /* GPIOA_CRL bits 31..24: PA7|PA6 nibbles */
#define DW_ODR            30u   /* PA6/PA7 output levels, bit0 = PA6      */
#define DW_TX_BYTES       31u
#define DW_REJECT_STATE   32u
#define DW_RUN_TO_STOP_MS 33u   /* last_stop_ms - last_run_ms              */
#define DW_DUTY_CAP       34u   /* the cap in force (100 unless the knob)  */
#define DW_MAX            34u

static uint32_t diag_value(uint8_t i)
{
    switch (i) {
    case DW_MS:              return g_ms;
    case DW_RX_BYTES:        return g_rx_bytes;
    case DW_FRAMES_OK:       return g_frames_ok;
    case DW_BAD_XOR:         return g_bad_xor;
    case DW_RESYNC:          return g_resync_drops;
    case DW_OVERRUN:         return g_overruns;
    case DW_BAD_PREFIX:      return g_bad_prefix;
    case DW_RUN_CMDS:        return g_run_cmds;
    case DW_STOP_CMDS:       return g_stop_cmds;
    case DW_HB_RECV:         return g_hb_recv;
    case DW_HB_APPLIED:      return g_hb_applied;
    case DW_DUP_SEQ:         return g_dup_seq;
    case DW_STATUS_CMDS:     return g_status_cmds;
    case DW_DIAG_CMDS:       return g_diag_cmds;
    case DW_FAULT_TRIPS:     return g_fault_trips;
    case DW_HB_CLEARED_FAULT: return g_hb_cleared_fault;
    case DW_LAST_STOP_CAUSE: return g_last_stop_cause;
    case DW_STATE_RESULT:    return (uint32_t)s_state | ((uint32_t)s_result << 8);
    case DW_DUTY_TARGET:     return (uint32_t)s_duty | ((uint32_t)s_target << 8);
    case DW_HB_MS:           return s_hb_ms;
    case DW_LAST_STOP_MS:    return g_last_stop_ms;
    case DW_LAST_RUN_MS:     return g_last_run_ms;
    case DW_HB_GAP_MS:       return (g_last_stop_cause == STOP_WATCHDOG)
                                    ? (g_last_stop_ms - s_hb_ms) : 0u;
    case DW_STOP_TOTAL:      return g_stop_total;
    case DW_STOP_WHY_BOOT:   return g_stop_why[STOP_BOOT];
    case DW_STOP_WHY_CMD:    return g_stop_why[STOP_CMD];
    case DW_STOP_WHY_WDOG:   return g_stop_why[STOP_WATCHDOG];
    case DW_STOP_WHY_BACKEND: return g_stop_why[STOP_BACKEND];
    case DW_BACKEND:         return s_backend;
    case DW_PIN_CFG:         return (R32(GPIOA_CRL) >> 24) & 0xFFu;
    case DW_ODR:             return (R32(GPIOA_ODR) >> 6) & 0x3u;
    case DW_TX_BYTES:        return g_tx_bytes;
    case DW_REJECT_STATE:    return g_reject_state;
    case DW_RUN_TO_STOP_MS:  return (g_last_run_ms != 0u)
                                    ? (g_last_stop_ms - g_last_run_ms) : 0u;
    case DW_DUTY_CAP:        return g_duty_cap;
    default:                 return 0xFFFFFFFFu;
    }
}

static uint16_t diag_word(uint8_t i, uint8_t half)
{
    uint32_t v;
    if (i > DW_MAX) { return 0xFFFFu; }
    v = diag_value(i);
    return (uint16_t)((v >> (half ? 16u : 0u)) & 0xFFFFu);
}

/* ---- diagnostic knobs --------------------------------------------------- */

#define KNOB_BACKEND 0u   /* 0 = TIM3 alternate function, 1 = software PWM  */
#define KNOB_LEGACY  1u   /* 1 = old semantics: stale hb stamp on RUN and
                             heartbeat clears FAULT (reproduces the fault)  */
#define KNOB_RESET   2u   /* 1 = reply, then SYSRESETREQ (only when stopped)*/
#define KNOB_DUTY_CAP 3u  /* 0..100: raise the duty cap for a bench ladder.
                             DIAGNOSTIC ONLY.  It is not saved, a reset puts it
                             back to MOTOR_DUTY_MAX, and the ladder is only run
                             with an operator watching a known motor, driver and
                             load.  Nothing else may raise the cap. */

static void do_knob(uint8_t knob, uint8_t val)
{
    switch (knob) {
    case KNOB_BACKEND:
        if (val > BACKEND_SW) { s_result = RES_BAD_FRAME; return; }
        if (s_state == ST_RUNNING) {
            stop_with_reason(STOP_BACKEND);
            s_state = ST_STOPPED;
        }
        s_backend = val;
        if (val == BACKEND_SW) { pins_output_low(); }
        break;
    case KNOB_LEGACY:
        g_legacy_mode = val ? 1u : 0u;
        if (g_legacy_mode) { s_hb_ms = 0u; }   /* the stale stamp from reset */
        break;
    case KNOB_RESET:
        if (val == 0u) { return; }
        if (s_state == ST_RUNNING) { s_result = RES_BAD_STATE; return; }
        s_pending_reset = 1u;
        break;
    case KNOB_DUTY_CAP:
        if (val > 100u) { s_result = RES_BAD_FRAME; return; }
        g_duty_cap = val;
        if (s_running && s_target > g_duty_cap) { s_target = g_duty_cap; }
        break;
    default:
        s_result = RES_BAD_FRAME;
        break;
    }
}

/* ---- frame reception ---------------------------------------------------- */

static uint8_t cmd_known(uint8_t c)
{
    return (c == CMD_STOP || c == CMD_RUN || c == CMD_HEARTBEAT ||
            c == CMD_STATUS || c == CMD_WORD || c == CMD_KNOB) ? 1u : 0u;
}

static uint8_t rx_peek(uint8_t i)
{
    return s_rx[(uint8_t)((s_tail + i) % RX_BUF_SIZE)];
}

static void rx_drop(uint8_t n)
{
    s_tail = (uint8_t)((s_tail + n) % RX_BUF_SIZE);
    s_cnt  = (uint8_t)(s_cnt - n);
}

static void rx_flush(void)
{
    s_head = 0u; s_tail = 0u; s_cnt = 0u;
}

static void handle(uint8_t cmd, uint8_t seq, uint8_t d0, uint8_t d1);

/* Bytes are consumed from the FRONT of the ring and a frame is only accepted
   when it starts at a frame boundary: 0xA5, then a known CMD, then a matching
   XOR.  On a bad byte the ring slides by ONE byte instead of dropping six, so
   a lost byte can neither shift a frame nor swallow the next frame's header.
   That is the "requires the parser to be at a frame boundary" resync rule. */
static void rx_byte(uint8_t b)
{
    uint8_t i, x;

    ++g_rx_bytes;
    if (s_cnt >= RX_BUF_SIZE) { rx_flush(); ++g_resync_drops; }
    s_rx[s_head] = b;
    s_head = (uint8_t)((s_head + 1u) % RX_BUF_SIZE);
    ++s_cnt;
    s_last_rx_ms = g_ms;

    while (s_cnt >= FRAME_LEN) {
        if (rx_peek(0u) != LINK_SOF) { rx_drop(1u); ++g_bad_prefix; continue; }
        if (!cmd_known(rx_peek(1u))) { rx_drop(1u); ++g_bad_prefix; continue; }
        x = 0u;
        for (i = 1u; i < 5u; ++i) { x ^= rx_peek(i); }   /* CMD..DATA1, no SOF */
        if (x != rx_peek(5u)) { rx_drop(1u); ++g_bad_xor; continue; }
        {
            uint8_t cmd = rx_peek(1u), seq = rx_peek(2u);
            uint8_t d0  = rx_peek(3u), d1  = rx_peek(4u);
            rx_drop(FRAME_LEN);
            ++g_frames_ok;
            handle(cmd, seq, d0, d1);
        }
    }
}

static void handle(uint8_t cmd, uint8_t seq, uint8_t d0, uint8_t d1)
{
    if (cmd == CMD_HEARTBEAT) { ++g_hb_recv; }

    /* protocol idempotence: the same SEQ is answered again, not re-executed.
       The answer is the one that command produced, not the current one. */
    if (s_have_seq && seq == s_last_seq) {
        ++g_dup_seq;
        if (cmd == CMD_WORD) {
            uint16_t w = diag_word(d0, d1);
            reply(cmd, seq, (uint8_t)(w & 0xFFu), (uint8_t)(w >> 8));
        } else {
            reply(cmd, seq, s_state, s_last_result);
        }
        return;
    }
    s_last_seq = seq;
    s_have_seq = 1u;
    s_result   = RES_OK;

    switch (cmd) {
    case CMD_STOP:
        ++g_stop_cmds;
        stop_with_reason(STOP_CMD);
        s_state = ST_STOPPED;          /* an explicit STOP is the fault reset */
        break;
    case CMD_RUN:
        ++g_run_cmds;
        if (d0 < 1u || d0 > 100u) { s_result = RES_BAD_DUTY; break; }
        if (s_state == ST_FAULT) { ++g_reject_state; s_result = RES_BAD_STATE; break; }
        motor_run(d0);
        s_state = ST_RUNNING;
        break;
    case CMD_HEARTBEAT:
        ++g_hb_applied;
        s_hb_ms = g_ms;
        /* FAULT is sticky: only an explicit STOP clears it.  In legacy mode
           the old behaviour is restored, so the historical log can be
           reproduced and measured on the same board. */
        if (g_legacy_mode && s_state == ST_FAULT) {
            ++g_hb_cleared_fault;
            s_state = ST_STOPPED;
        }
        break;
    case CMD_STATUS:
        ++g_status_cmds;
        break;
    case CMD_WORD:
        ++g_diag_cmds;
        {
            uint16_t w = diag_word(d0, d1);
            s_last_result = s_result;
            reply(cmd, seq, (uint8_t)(w & 0xFFu), (uint8_t)(w >> 8));
            return;
        }
    case CMD_KNOB:
        ++g_diag_cmds;
        do_knob(d0, d1);
        break;
    default:
        s_result = RES_BAD_FRAME;
        break;
    }
    s_last_result = s_result;
    reply(cmd, seq, s_state, s_result);
}

static void link_poll(void)
{
    uint32_t sr;

    /* 1. the watchdog: the only path that stops a motor without a STOP frame,
          and it says so in g_stop_why[STOP_WATCHDOG]. */
    if (s_state == ST_RUNNING && (uint32_t)(g_ms - s_hb_ms) > LINK_TIMEOUT_MS) {
        ++g_fault_trips;
        stop_with_reason(STOP_WATCHDOG);
        s_state = ST_FAULT;
        /* protocol rule 6: do not let an old RUN in the buffer authorise a
           restart once the link has been declared dead */
        rx_flush();
        ++g_resync_drops;
    }

    /* 2. a partial frame whose bytes stopped arriving: drop it, so the next
          frame starts at a boundary instead of completing a shifted one */
    if (s_cnt > 0u && s_cnt < FRAME_LEN &&
        (uint32_t)(g_ms - s_last_rx_ms) > LINK_INTERBYTE_MS) {
        rx_flush();
        ++g_resync_drops;
    }

    /* 3. one received byte.  SR is read before DR: reading SR then DR is the
          documented way to clear ORE/RXNE together.  A byte that arrives with
          an overrun or a framing error is not trustworthy -- the byte that was
          lost may be the one that carried the command -- so it is dropped and
          the frame is abandoned rather than completed with a hole in it. */
    sr = R32(USART1_SR);
    if (sr & SR_RXNE) {
        uint8_t b = (uint8_t)(R32(USART1_DR) & 0xFFu);
        if (sr & (SR_ORE | SR_FE | SR_NE | SR_PE)) {
            ++g_overruns;
            rx_flush();
            ++g_resync_drops;
            return;
        }
        rx_byte(b);
    }
}

/* A reset is the only way to re-test the power-on rule without touching a
   cable, so the knob asks for one -- but only after the reply has left the
   shift register, and only when the motor is already stopped. */
static void maybe_reset(void)
{
    uint32_t guard;
    if (!s_pending_reset) { return; }
    s_pending_reset = 0u;
    for (guard = 0u; guard < 200000u; ++guard) {
        if (R32(USART1_SR) & SR_TC) { break; }
    }
    R32(SCB_AIRCR) = 0x05FA0004u;   /* VECTKEY | SYSRESETREQ */
    for (guard = 0u; guard < 1000000u; ++guard) { __asm volatile("nop"); }
    /* If the core ignored SYSRESETREQ we keep running rather than hanging with
       no link: the motor is stopped here, so the fail-safe state is safe. */
}

/* ---- main -------------------------------------------------------------- */

/* ---- clock: 8 MHz HSE crystal x9 = 72 MHz ------------------------------ */
/* This was missing in the first flash and the link did not talk: the part ran
   on its 8 MHz HSI while every divisor below assumed 72 MHz, so the real baud
   rate was 1/16 of the intended one and the replies arrived as 0xFF/0x7F
   noise.  Nothing was damaged -- it simply could not be understood. */

#define RCC_CR    0x40021000u
#define RCC_CFGR  0x40021004u
#define FLASH_ACR 0x40022000u

static void clock_72mhz(void)
{
    uint32_t guard;

    /* flash: two wait states, prefetch on */
    R32(FLASH_ACR) = (R32(FLASH_ACR) & ~0x7u) | 0x2u | (1u << 4);

    /* HSE on, wait for it (8 MHz crystal on the blue pill) */
    R32(RCC_CR) |= (1u << 16);
    guard = 0u;
    while ((R32(RCC_CR) & (1u << 17)) == 0u && ++guard < 200000u) { }
    if (guard >= 200000u) {
        /* no crystal: stay on HSI and cut the divisor to keep the UART alive.
           The motor still runs; the PWM is slower.  Safe, just slower. */
        return;
    }

    /* PLL: HSE, x9 = 72 MHz.  APB1 /2 (max 36 MHz), APB2 /1, AHB /1 */
    R32(RCC_CFGR) = (R32(RCC_CFGR) & ~((0xFu << 18) | (1u << 16) | (1u << 17))) |
                    (0x7u << 18) | (1u << 16) |
                    (0x4u << 8) |                       /* PPRE1 = /2 */
                    (0x0u << 11) |                      /* PPRE2 = /1 */
                    (0x0u << 4);                        /* HPRE  = /1 */
    R32(RCC_CR) |= (1u << 24);                          /* PLLON */
    guard = 0u;
    while ((R32(RCC_CR) & (1u << 25)) == 0u && ++guard < 200000u) { }
    (void)guard;

    R32(RCC_CFGR) = (R32(RCC_CFGR) & ~0x3u) | 0x2u;     /* SW = PLL */
    guard = 0u;
    while (((R32(RCC_CFGR) >> 2) & 0x3u) != 0x2u && ++guard < 200000u) { }
}

int main(void)
{
    /* 0. BEFORE ANY PIN: make sure the bridge sees a defined level.
          pins_output_low() sets both inputs LOW, which is L9110S "coast". */
    pins_output_low();

    /* 0b. then the clock, because every divisor below is derived from it */
    clock_72mhz();
    systick_init();   /* the 1 ms timebase the watchdog depends on */

    /* 1. tick source: a crude loop counter is enough at 72 MHz; replace with
          SysTick if your project already configures it. */
    {
        volatile uint32_t i;
        for (i = 0; i < (SYSCLK_HZ / 900000u); ++i) { __asm volatile("nop"); }
    }

    /* 2. the timer, then the pins as alternate function */
    tim3_pwm_init();
    /* the pins stay GPIO-LOW until a RUN command arrives; motor_run() switches
       them to alternate function, so no float state is ever exposed */

    /* 3. the link */
    uart1_init();
    s_state = ST_STOPPED; s_result = RES_OK; s_last_result = RES_OK;
    s_duty = 0u; s_target = 0u;
    s_have_seq = 0u; s_hb_ms = 0u;
    rx_flush();
    stop_with_reason(STOP_BOOT);   /* power-on state is stopped, and recorded */

    for (;;) {
        /* The 1 ms timebase is SysTick, not this loop: the loop just has to be
           fast enough.  The delay below is a settle of ~1 us, not a 1 ms
           delay -- counting it as one was one of the earlier faults. */
        tick_ms();
        motor_tick();
        sw_pwm_pump();
        link_poll();
        maybe_reset();

        {
            volatile uint32_t i;
            for (i = 0; i < (SYSCLK_HZ / 900000u); ++i) { __asm volatile("nop"); }
        }
    }
}
