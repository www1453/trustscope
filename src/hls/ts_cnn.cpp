//=============================================================================
// ts_cnn.cpp -- TrustScope quantised CNN kernel (W4/W5)
//
// Structurally rewritten on 2026-09-24 after Vitis HLS rejected the first
// version with
//     ERROR: [HLS 214-134] Pointer to pointer is not supported
// because the parameter set was a struct OF POINTERS. Pointers-to-pointers are
// not synthesizable, and a "host prettiness" struct is not a reason to give up:
// the parameters become FLAT ARRAYS plus compile-time offsets, which is also
// how they will be laid out in DDR.
//
// One code path serves everything on purpose:
//   * g++ host testbench  (seconds, checks the algorithm)
//   * vitis_hls csim      (same source, same answers)
//   * vitis_hls csynth    (same source, becomes hardware)
// If csim used one implementation and the FPGA another, a disagreement between
// them would prove nothing (the project has been bitten by two implementations
// disagreeing before -- case M19).
//
// ARITHMETIC CONTRACT (identical to int_reference.py; do not "improve" it):
//   activations uint8 affine, weights int8 symmetric per output channel,
//   int32 accumulate,
//   out = clamp( ((acc*M + (1<<(sh-1))) >> sh) + z_out, 0, 255 )
//   >> is an ARITHMETIC shift: round half toward +infinity.
//   The last layer is NOT requantised; argmax is taken on the int32 logits.
//
// HLS pragmas are inert under g++ so the same file builds for the host check.
//=============================================================================

#include <cstdint>

#ifndef TS_MAX
#define TS_MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

// ------------------------------------------------------------- flat layout
// Offsets into the concatenated weight blob (int8) and table blobs.
// Keep in sync with export_for_hls.py; the testbench prints the consumed size
// so a mismatch shows up immediately instead of silently reading garbage.
#define W_C1    144          // 16 * 1 * 3 * 3
#define W_C2   4608          // 32 * 16 * 3 * 3
#define W_C3   9216          // 32 * 32 * 3 * 3
#define W_F1 131072          // 64 * 2048
#define W_F2    128          // 2 * 64

#define W_OFF_C1     0
#define W_OFF_C2 (W_OFF_C1 + W_C1)
#define W_OFF_C3 (W_OFF_C2 + W_C2)
#define W_OFF_F1 (W_OFF_C3 + W_C3)
#define W_OFF_F2 (W_OFF_F1 + W_F1)

#define T_C1  16
#define T_C2  32
#define T_C3  32
#define T_F1  64
#define T_F2   2
#define T_OFF_C1     0
#define T_OFF_C2 (T_OFF_C1 + T_C1)
#define T_OFF_C3 (T_OFF_C2 + T_C2)
#define T_OFF_F1 (T_OFF_C3 + T_C3)
#define T_OFF_F2 (T_OFF_F1 + T_F1)

// activation map sizes. NOTE the two 32-channel 16x16 maps are DIFFERENT sizes
// and must not share a buffer: the conv3 INPUT is the pooled conv2 output
// (32*16*16 = 8192) while the conv3 OUTPUT after pooling is 32*8*8 = 2048.
// Reusing one array for both (tried on 2026-09-24) silently reads past the end
// and produced logits that were simply wrong -- caught by the bit-exact
// testbench in seconds, which is the whole reason that testbench exists.
#define P1  (16 * 64 * 64)
#define P2  (32 * 32 * 32)     // pool of conv1  -> conv2 input
#define P3  (32 * 16 * 16)     // pool of conv2  -> conv3 input
#define P4  (32 * 8 * 8)       // pool of conv3  -> fc1 input

// ------------------------------------------------------------- arithmetic
static inline uint8_t requant(int32_t acc, int64_t M, int64_t sh, int32_t z_out)
{
#pragma HLS INLINE
    int64_t t = (int64_t)acc * M + ((int64_t)1 << (sh - 1));
    t = t >> sh;                       // arithmetic shift: floor for negatives
    t += z_out;
    if (t < 0)   t = 0;
    if (t > 255) t = 255;
    return (uint8_t)t;
}

// ------------------------------------------------------------- conv 3x3
// STREAMING REWRITE -- STREAMING_KERNEL_SPEC.md.
//   Step 1 (done): window register file -> block-RAM line buffer.
//                  measured: 55.956 ms, LUT 115% -> 88%, Fmax 157 -> 205 MHz.
//   Step 2 (THIS change): input-channel loop moved OUTERMOST; accumulation
//                  across channels is carried in a row accumulator
//                  out_acc[oc][x] that lives in block RAM.
//
// Failure log that motivates this rewrite (all measured, not guessed):
//     v1 direct conv          : 79.6 ms, LUT 35%   (1.6 cycles per MAC)
//     v2 + OC_PAR=8 unrolled  : 56.1 ms, LUT 111%  (HLS unrolled ic too)
//     v3 window registers     : 56.8 ms, LUT 121%  (parallelism never took)
//     v4 add tree             : bit-for-bit IDENTICAL -> anomaly, see T14
//     v6 weights as 72B burst : 56.8 ms, LUT 115%
//
// FORENSICS THAT DRIVES STEP 2 (hls_proj/sol1/sol1.log, [HLS 200-880]):
//   the binding II constraint on the conv2/conv3 inner loop is a CARRIED
//   DEPENDENCE BETWEEN TWO WEIGHT (gmem1) BUS READS -- required II 71 for 72
//   weight reads per iteration, achieved II 72. conv1: required 143 for 144
//   reads. The slope is exactly one weight byte per cycle in all three convs.
//   So the limiter is the per-MAC weight fetch from off chip, not the window
//   and not the multiplier allocation (conv3x3_3 allocates 40 DSPs, not 1).
//
// STEP 2 scope -- ONE change only (plus deleting a duplicated #define left
// behind by the step-1 edit, which is a no-op):
//   loop order: input channel OUTERMOST, so the weights become invariant with
//   respect to the pixel loop; cross-channel accumulation moves into out_acc.
//   Weight storage, tiling, OC_PAR and the arithmetic contract are untouched.
//   Buffering the weights on chip is STEP 3 and must not be mixed in here.
//
// KNOWN RISK, recorded before the run: out_acc is read-modify-write inside the
//   II=1 pixel loop (OC_PAR reads + OC_PAR writes per cycle). If HLS does not
//   bank it, out_acc -- not the weights -- becomes the limiter. If II lands in
//   2..4 the fix is to repartition out_acc, NOT to change the loop order again.
//
// The arithmetic contract is unchanged: the accumulation order over ic is
// identical (ascending ic, same 9-tap tree within each ic), so the 200-vector
// bit-exact test still means what it meant before.
#define OC_PAR 8
#define MAXC   32
#define MAXW   64    // widest input row width (conv1 reads 64-wide rows)
#define MAXO   32    // widest output-channel count (conv2/conv3 use 32)

// STEP W6-i: the OUTPUT array is now three-dimensional so its row and column
// dimensions can each be split cyclically by 2. A flat array cannot be banked
// usefully here: maxpool2 reads A, A+1, A+W and A+W+1, and because W is a power
// of two, A and A+W land in the SAME bank under any small cyclic factor.
// NOTE the output is taken BY REFERENCE, not as `uint8_t out[OC][OH][OW]`.
// As a by-value parameter an array decays to a pointer and the FIRST dimension
// is lost, so OC cannot be deduced at all (compile error), and more importantly
// HLS would no longer see a three-dimensional array to partition. A reference
// to the array keeps all three bounds in the type.
template <int OC, int OH, int OW>
static void conv3x3(const uint8_t *in, int cin, int H, int W,
                    uint8_t (&out)[OC][OH][OW],
                    const int8_t *w, const int64_t *M, const int64_t *sh,
                    const int64_t *b, int cout, int z_out)
{
#pragma HLS INLINE off
    const int P = H * W;
    // STEP 1: the register window is gone; lb is a block-RAM line buffer holding
    // input row (y+r-1) of channel ic, with one zero-padded column on each side,
    // so input column (x-1+kx) is simply lb[*][*][x+kx].
    uint8_t lb[3][MAXC][MAXW + 2];
    // STEP 2: the row of accumulators, one row per output channel, in block RAM,
    // so the channel loop can be outermost and still accumulate across channels.
    int32_t out_acc[MAXO][MAXW];

    // STEP 3b: cache the two requant tables on chip for this layer.
    // Reason (measured): a plain scalar hoist was NOT enough in the conv store
    // loop, because HLS FUSES the oc and x loops -- the report names the fused
    // region LOOP_212_16_LOOP_226_17, i.e. two loop ids in one body -- so the
    // M[oc]/sh[oc] loads land INSIDE the fused body and still cost gmem2
    // requests. The same hoist DID work in 'linear', whose oc and k loops HLS
    // did not fuse, which is why only 1 of the 4 gmem2 violations went away.
    // Fix: read both tables once per layer, before the row loop, into fully
    // partitioned on-chip arrays (MAXO entries x 64 bit = registers). With no
    // gmem2 request left inside any loop the port limit disappears.
    // The pointer interface, the AXI ports and the arithmetic are unchanged.
    int64_t Ml[MAXO];
    int64_t shl[MAXO];
    // TIER-1 change #1 (2026-09-25). The bias table is cached on chip as well.
    // BEFORE: a separate pass per output row wrote out_acc[oc][x] = b[oc] for
    // every (oc, x) pair -- that is cout*W reads of the bias from DDR (gmem2)
    // per row, PLUS a full serial pass over the accumulator row.
    // AFTER: the bias is read once per layer into bl[] (registers), and the
    // seed is folded into the FIRST input-channel pass (ic == 0).
    // Arithmetic is unchanged: ic=0 initialises where it used to accumulate,
    // and the ic order is identical, so the host bit-exact test must still
    // pass 200/200. Predicted saving: 1,024 cycles/row in conv2 (1,024 in
    // conv1, 512 in conv3), plus the removal of the per-pixel bias DDR read.
    int64_t bl[MAXO];
#pragma HLS ARRAY_PARTITION variable=Ml complete dim=1
#pragma HLS ARRAY_PARTITION variable=shl complete dim=1
#pragma HLS ARRAY_PARTITION variable=bl complete dim=1
    for (int oc = 0; oc < cout; ++oc) {
#pragma HLS PIPELINE II=1
        Ml[oc] = M[oc];
        shl[oc] = sh[oc];
        bl[oc] = b[oc];
    }

    for (int y = 0; y < H; ++y) {
        // load the three input rows this output row needs (zero outside image)
        for (int r = 0; r < 3; ++r) {
            int yy = y + r - 1;
            for (int ic = 0; ic < cin; ++ic) {
                lb[r][ic][0] = (uint8_t)0;
                lb[r][ic][W + 1] = (uint8_t)0;
                for (int xx = 0; xx < W; ++xx) {
#pragma HLS PIPELINE II=1
                    lb[r][ic][xx + 1] = ((yy >= 0 && yy < H)
                                         ? in[ic * P + yy * W + xx] : (uint8_t)0);
                }
            }
        }

        // (bias seed pass removed -- see the bl[] cache above. ic == 0 seeds
        //  the accumulator from bl[] instead of accumulating into it.)

        // STEP 2: CHANNEL LOOP OUTERMOST. One input channel at a time, so the
        // 72 weight bytes of a given (ic, oc-group) are invariant across the
        // whole x loop -- that invariance is what step 3 turns into an on-chip
        // weight buffer. The pixel loop is now the pipelined one.
        for (int ic = 0; ic < cin; ++ic) {
            for (int oc0 = 0; oc0 < cout; oc0 += OC_PAR) {
                for (int x = 0; x < W; ++x) {
#pragma HLS PIPELINE II=1
                    int32_t acc[OC_PAR];
#pragma HLS ARRAY_PARTITION variable=acc complete dim=1
                    for (int o = 0; o < OC_PAR; ++o) {
#pragma HLS UNROLL
                        acc[o] = (ic == 0) ? (int32_t)bl[oc0 + o]
                                           : out_acc[oc0 + o][x];
                    }
                    // nine taps summed as a TREE (depth 4), not a 9-deep chain;
                    // int32 addition is exact, so the reordering cannot change
                    // the result: the bit-exact test still passes.
                    int32_t pr[9][OC_PAR];
#pragma HLS ARRAY_PARTITION variable=pr complete dim=0
                    for (int ky = 0; ky < 3; ++ky) {
#pragma HLS UNROLL
                        for (int kx = 0; kx < 3; ++kx) {
#pragma HLS UNROLL
                            uint8_t v = lb[ky][ic][x + kx];
                            for (int o = 0; o < OC_PAR; ++o) {
#pragma HLS UNROLL
                                pr[ky * 3 + kx][o] = (int32_t)v *
                                    (int32_t)w[(ic * cout + (oc0 + o)) * 9 + ky * 3 + kx];
                            }
                        }
                    }
                    for (int o = 0; o < OC_PAR; ++o) {
#pragma HLS UNROLL
                        int32_t s = ((pr[0][o] + pr[1][o]) + (pr[2][o] + pr[3][o]))
                                  + ((pr[4][o] + pr[5][o]) + (pr[6][o] + pr[7][o]));
                        acc[o] += s + pr[8][o];
                    }
                    for (int o = 0; o < OC_PAR; ++o) {
#pragma HLS UNROLL
                        out_acc[oc0 + o][x] = acc[o];
                    }
                }
            }
        }

        // all input channels accumulated: requantise the row and write it out
        for (int oc = 0; oc < cout; ++oc) {
            // Reads the on-chip copies from step 3b, not gmem2. This is what
            // removes the bus request from the (fused) body. Same values, same
            // arithmetic -- the host bit-exact test must still pass 200/200.
            // maxpool's three violations are deliberately NOT fixed here.
            for (int x = 0; x < W; ++x) {
#pragma HLS PIPELINE II=1
                out[oc][y][x] =
                    requant(out_acc[oc][x], Ml[oc], shl[oc], z_out);
            }
        }
    }
}

// ------------------------------------------------------------- maxpool 2x2
// STEP W6-i: the input is taken as a 3-D array so it can be partitioned.
// A POINTER CANNOT BE PARTITIONED -- no pragma on a flat pointer banks an
// array -- which is why the SIGNATURE changes and not just the declaration.
// The same recipe applies to all three instances; it is one change to shared
// code, not one change per call site.
//
// Recipe (reviewer-specified, and the only one that works):
//   #pragma HLS ARRAY_PARTITION variable=in dim=2 cyclic factor=2   (rows)
//   #pragma HLS ARRAY_PARTITION variable=in dim=3 cyclic factor=2   (columns)
//     A     =(2y  ,2x  ) -> bank00      A+1 =(2y  ,2x+1) -> bank01
//     A+W   =(2y+1,2x  ) -> bank10      A+W+1=(2y+1,2x+1)-> bank11
//   All four concurrent reads land in four different banks.
//   The factor MUST be 2. Block partitioning (and ARRAY_RESHAPE) put A and A+1
//   in the SAME block, which makes the partition a no-op.
//   BRAM does not grow: the same bytes are distributed over 4 banks.
//   max is commutative, associative and exact, so no value can change.
// No PIPELINE pragma is added: HLS already auto-pipelines this loop with
// target II=1 (achieved 2). The only thing being changed is the storage.
// NOTE: taken BY REFERENCE. As a by-value parameter the array would decay to
// `const uint8_t (*)[H][W]`, losing the first dimension so C cannot be deduced,
// and HLS would see a pointer-to-2-D rather than a real 3-D array -- which is
// exactly the situation where a partition pragma silently does nothing.
template <int C, int H, int W>
static void maxpool2(const uint8_t (&in)[C][H][W], uint8_t *out)
{
#pragma HLS INLINE off
#pragma HLS ARRAY_PARTITION variable=in dim=2 cyclic factor=2
#pragma HLS ARRAY_PARTITION variable=in dim=3 cyclic factor=2
    int Ho = H / 2, Wo = W / 2;
    for (int c = 0; c < C; ++c) {
        for (int y = 0; y < Ho; ++y)
            for (int x = 0; x < Wo; ++x) {
                uint8_t m = in[c][2 * y][2 * x];
                m = TS_MAX(m, in[c][2 * y][2 * x + 1]);
                m = TS_MAX(m, in[c][2 * y + 1][2 * x]);
                m = TS_MAX(m, in[c][2 * y + 1][2 * x + 1]);
                out[c * Ho * Wo + y * Wo + x] = m;
            }
    }
}

// ------------------------------------------------------------- linear
static void linear(const uint8_t *in, int K, uint8_t *out, const int8_t *w,
                   const int64_t *M, const int64_t *sh, const int64_t *b,
                   int cout, int z_out)
{
#pragma HLS INLINE off
    for (int oc = 0; oc < cout; ++oc) {
        // STEP 3 (scalar hoist), same defect as the conv store loop: the
        // requant on line 252 reads M[oc] and sh[oc] from gmem2, and HLS pulls
        // both loads into the pipelined k loop -> two gmem2 requests per
        // iteration -> II = 2, target 1. Read them once per output channel
        // instead. Same values, same arithmetic, bit-exact must still hold.
        int64_t Mv = M[oc];
        int64_t shv = sh[oc];
        int32_t acc = (int32_t)b[oc];
        for (int k = 0; k < K; ++k) {
#pragma HLS PIPELINE II=1
            acc += (int32_t)in[k] * (int32_t)w[oc * K + k];
        }
        out[oc] = requant(acc, Mv, shv, z_out);
    }
}

static void linear_logits(const uint8_t *in, int K, int32_t *out, const int8_t *w,
                          const int64_t *b, int cout)
{
#pragma HLS INLINE off
    for (int oc = 0; oc < cout; ++oc) {
        int32_t acc = (int32_t)b[oc];
        for (int k = 0; k < K; ++k) {
#pragma HLS PIPELINE II=1
            acc += (int32_t)in[k] * (int32_t)w[oc * K + k];
        }
        out[oc] = acc;                             // last layer: no requantise
    }
}

// Activation buffers at file scope so a debug hook can hand them out and the
// first diverging stage can be identified by comparison instead of by reading
// the code and hoping. The stage names here are the CANONICAL ones used by
// dump_trace.py in the Python reference:
//   s0 conv1 out  s1 pool1 out  s2 conv2 out  s3 pool2 out
//   s4 conv3 out  s5 pool3 out  s6 fc1 out    s7 logits
// STEP W6-i: s0/s2/s4 -- the three maxpool INPUTS -- are 3-D so they can be
// banked. s1/s3/s5 (maxpool outputs, read by conv3x3 through a flat pointer)
// stay flat: they are not on the critical path and partitioning them buys
// nothing.
static uint8_t s0[16][64][64];   // conv1 out      16*64*64
static uint8_t s1[16384];        // pool1          16*32*32  (conv2 in)
static uint8_t s2[32][32][32];   // conv2 out      32*32*32
static uint8_t s3[P3];           // pool2          32*16*16  (conv3 in)
static uint8_t s4[32][16][16];   // conv3 out      32*16*16
static uint8_t s5[P4];           // pool3          32*8*8    (fc1 in)
static uint8_t s6[T_F1];         // fc1 out
static int32_t s7[2];            // logits

// Debug hook used ONLY by the host testbench. Vitis HLS defines __SYNTHESIS__
// during csynth, so the pointer-returning function is compiled out of the
// synthesizable build instead of confusing the tool.
#ifndef __SYNTHESIS__
extern "C" const void *ts_dbg_ptr(int which, int *len)
{
    switch (which) {
    case 0: *len = P1;    return s0;
    case 1: *len = 16384; return s1;
    case 2: *len = 32768; return s2;
    case 3: *len = P3;    return s3;
    case 4: *len = P3;    return s4;
    case 5: *len = P4;    return s5;
    case 6: *len = T_F1;  return s6;
    case 7: *len = 2;     return s7;
    default: *len = 0;    return 0;
    }
}
#endif

// ------------------------------------------------------------- top
// Flat pointers only -- this is the signature both the host testbench and HLS
// use, so the verified algorithm and the synthesized one are the same code.
extern "C" void ts_cnn_top(const uint8_t *img,
                           const int8_t  *wq,
                           const int64_t *mtab,
                           const int64_t *stab,
                           const int64_t *btab,
                           int32_t       *logits)
{
#pragma HLS INTERFACE m_axi port=img    offset=slave bundle=gmem0 depth=4096
#pragma HLS INTERFACE m_axi port=wq     offset=slave bundle=gmem1 depth=145168
#pragma HLS INTERFACE m_axi port=mtab   offset=slave bundle=gmem2 depth=146
#pragma HLS INTERFACE m_axi port=stab   offset=slave bundle=gmem2 depth=146
#pragma HLS INTERFACE m_axi port=btab   offset=slave bundle=gmem2 depth=146
#pragma HLS INTERFACE m_axi port=logits offset=slave bundle=gmem0 depth=2
// FIXED 2026-09-24: this used to read `bundle=ctrl`, which created a SECOND
// AXI-Lite slave (s_axi_ctrl) holding ONLY the block-control registers
// (AP_CTRL/GIE/IER/ISR), while every pointer register landed on the DEFAULT
// bundle -- s_axi_control. The block design connected s_axi_control and tied
// s_axi_ctrl to constants, so ap_start was being written to offset 0x00 of a
// slave that has no register at 0x00: writes silently did nothing and reads
// returned 0, which looked exactly like a dead slave.
//
// Evidence trail: the exported driver header carried TWO macro families
// (XTS_CNN_TOP_CONTROL_ADDR_* at 0x10+ and XTS_CNN_TOP_CTRL_ADDR_* at 0x00-0x0C)
// and they were read as ONE table; the generated netlist showed
// .s_axi_ctrl_*_VALID tied to 1'b0; and a register-existence check on hardware
// round-tripped all seven s_axi_control offsets while 0x00-0x0C stayed 0.
//
// `control` is HLS's default bundle name, so this MERGES the two slaves into one
// and makes the original map (AP_CTRL 0x00 / IMG 0x10 / ...) true. Preferred
// over exporting two slaves: it removes an address space permanently.
#pragma HLS INTERFACE s_axilite port=return bundle=control

    conv3x3(img, 1, 64, 64, s0, wq + W_OFF_C1, mtab + T_OFF_C1, stab + T_OFF_C1,
            btab + T_OFF_C1, T_C1, 0);
    maxpool2(s0, s1);
    conv3x3(s1, 16, 32, 32, s2, wq + W_OFF_C2, mtab + T_OFF_C2, stab + T_OFF_C2,
            btab + T_OFF_C2, T_C2, 0);
    maxpool2(s2, s3);
    conv3x3(s3, 32, 16, 16, s4, wq + W_OFF_C3, mtab + T_OFF_C3, stab + T_OFF_C3,
            btab + T_OFF_C3, T_C3, 0);
    maxpool2(s4, s5);
    linear(s5, P4, s6, wq + W_OFF_F1, mtab + T_OFF_F1, stab + T_OFF_F1,
           btab + T_OFF_F1, T_F1, 0);
    linear_logits(s6, T_F1, s7, wq + W_OFF_F2, btab + T_OFF_F2, T_F2);
    logits[0] = s7[0];
    logits[1] = s7[1];
}
