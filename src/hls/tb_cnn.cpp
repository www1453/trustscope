//=============================================================================
// tb_cnn.cpp -- host testbench: does the C kernel reproduce the Python
// reference BIT FOR BIT?
//
// This runs under plain g++ (MinGW shipped with Vitis HLS), before any HLS
// project exists. The point is to catch algorithm mistakes in seconds instead
// of after a synthesis run, and to have a gold answer the FPGA must match later.
//
// It deliberately reports the WORST case, not just the pass rate: a single
// differing LSB in an int32 logit means the hardware contract is not met.
//
// ASCII only.
//=============================================================================

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

// The design is a SEPARATE translation unit, exactly as Vitis HLS expects for
// csim (testbench and design are compiled and linked, not #included). Including
// the .cpp here would put two copies of every symbol in the link.
extern "C" void ts_cnn_top(const uint8_t *img, const int8_t *wq,
                           const int64_t *mtab, const int64_t *stab,
                           const int64_t *btab, int32_t *logits);
#ifndef __SYNTHESIS__
extern "C" const void *ts_dbg_ptr(int which, int *len);
#endif

// Per-layer records live only long enough to be concatenated into the flat
// buffers; the kernel no longer has a struct-of-pointers interface (HLS 214-134).
static std::vector<int8_t>  g_w[5];
static std::vector<int64_t> g_M[5], g_sh[5], g_b[5];

// Flat buffers, exactly the layout the kernel and the FPGA use. The testbench
// concatenates the per-layer records into them so the SAME code path runs here
// and in hardware.
static std::vector<int8_t>  fl_w;
static std::vector<int64_t> fl_M, fl_sh, fl_b;

static std::vector<uint8_t> read_all(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> v((size_t)n);
    if (fread(v.data(), 1, (size_t)n, f) != (size_t)n) { fprintf(stderr, "short read\n"); exit(1); }
    fclose(f);
    return v;
}

int main(int argc, char **argv)
{
    const char *pdir = (argc > 1) ? argv[1] : "data";
    char ppath[512], vpath[512];
    snprintf(ppath, sizeof(ppath), "%s/params.bin", pdir);
    snprintf(vpath, sizeof(vpath), "%s/vectors.bin", pdir);

    std::vector<uint8_t> pb = read_all(ppath);
    size_t off = 0;
    size_t woff = 0, toff = 0;
    for (int li = 0; li < 5; ++li) {
        int32_t hdr[6];
        memcpy(hdr, &pb[off], sizeof(hdr));
        off += sizeof(hdr);
        int cout = hdr[0], cin = hdr[1], kh = hdr[2], kw = hdr[3];
        int last = hdr[4], z_out = hdr[5];

        size_t wn = (size_t)cout * cin * kh * kw;
        g_w[li].assign((const int8_t *)&pb[off], (const int8_t *)&pb[off] + wn);
        off += wn;

        g_M[li].resize(cout); g_sh[li].resize(cout); g_b[li].resize(cout);
        memcpy(g_M[li].data(),  &pb[off], cout * 8); off += cout * 8;
        memcpy(g_sh[li].data(), &pb[off], cout * 8); off += cout * 8;
        memcpy(g_b[li].data(),  &pb[off], cout * 8); off += cout * 8;

        fl_w.insert(fl_w.end(), g_w[li].begin(), g_w[li].end());
        fl_M.insert(fl_M.end(), g_M[li].begin(), g_M[li].end());
        fl_sh.insert(fl_sh.end(), g_sh[li].begin(), g_sh[li].end());
        fl_b.insert(fl_b.end(), g_b[li].begin(), g_b[li].end());
        woff += wn; toff += cout;

        printf("layer %d: cout=%-4d cin=%-4d %dx%d last=%d z=%d\n",
               li, cout, cin, kh, kw, last, z_out);
    }
    printf("params consumed %u of %u bytes\n", (unsigned)off, (unsigned)pb.size());
    printf("flat: w=%u (expect %u)  tables=%u (expect %u)\n",
           (unsigned)fl_w.size(), (unsigned)woff,
           (unsigned)fl_M.size(), (unsigned)toff);

    std::vector<uint8_t> vb = read_all(vpath);
    int32_t n;
    memcpy(&n, vb.data(), 4);
    const uint8_t *X = vb.data() + 4;
    const int32_t *E = (const int32_t *)(vb.data() + 4 + (size_t)n * 64 * 64);
    printf("vectors: %d\n\n", n);

    int rows_ok = 0, pred_ok = 0, worst = 0;
    std::vector<uint8_t> img(64 * 64);
    int do_dump = (argc > 2) && (strcmp(argv[2], "dump") == 0);
    for (int i = 0; i < n; ++i) {
        memcpy(img.data(), X + (size_t)i * 64 * 64, 64 * 64);
        int32_t logits[2] = {0, 0};
        ts_cnn_top(img.data(), fl_w.data(), fl_M.data(), fl_sh.data(),
                   fl_b.data(), logits);

        if (do_dump && i == 0) {
            // Same layout as dump_trace.py: per stage, int32 count then int32
            // values. Raw bytes of the uint8 stages are widened to int32 so a
            // single reader handles both.
            FILE *fd = fopen("data/trace_c.bin", "wb");
            if (!fd) { fprintf(stderr, "cannot write data/trace_c.bin\n"); return 2; }
            for (int st = 0; st < 8; ++st) {
                int len = 0;
                const void *p = ts_dbg_ptr(st, &len);
                fwrite(&len, 4, 1, fd);
                if (st == 7) {
                    fwrite(p, 4, len, fd);
                } else {
                    const uint8_t *u = (const uint8_t *)p;
                    for (int k = 0; k < len; ++k) {
                        int32_t v = (int32_t)u[k];
                        fwrite(&v, 4, 1, fd);
                    }
                }
            }
            fclose(fd);
            printf("wrote data/trace_c.bin\n");
        }
        int d0 = logits[0] - E[i * 2 + 0];
        int d1 = logits[1] - E[i * 2 + 1];
        int d = (d0 < 0 ? -d0 : d0);
        int d2 = (d1 < 0 ? -d1 : d1);
        if (d2 > d) d = d2;
        if (d > worst) worst = d;
        if (logits[0] == E[i * 2 + 0] && logits[1] == E[i * 2 + 1]) rows_ok++;
        if ((logits[1] > logits[0] ? 1 : 0) == (E[i * 2 + 1] > E[i * 2 + 0] ? 1 : 0)) pred_ok++;
        if (i < 5) {
            printf("  #%d  C=[%d,%d]  py=[%d,%d]  %s\n", i,
                   logits[0], logits[1], E[i * 2 + 0], E[i * 2 + 1],
                   (logits[0] == E[i * 2 + 0] && logits[1] == E[i * 2 + 1]) ? "exact" : "DIFFERS");
        }
    }

    printf("\nlogits bit-exact rows : %d / %d\n", rows_ok, n);
    printf("argmax agreement      : %d / %d\n", pred_ok, n);
    printf("worst |logit delta|   : %d\n", worst);
    printf("\n%s\n", (rows_ok == n) ? "C KERNEL == PYTHON REFERENCE (bit exact)"
                                    : "*** MISMATCH - the kernel does not meet the contract ***");
    return (rows_ok == n) ? 0 : 1;
}
