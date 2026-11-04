//=============================================================================
// capture_ram.v
//
// PL side probe sampler with a CPU readable capture buffer.
//
//   probe_i  -- 9 bit probe bus, sampled once per aclk (FCLK_CLK0 = 50 MHz).
//
//   Acquisition:
//     IDLE : wait for ctrl_i[31] (rearm) AND a rising edge on probe_i[1] (hsync)
//     FILL : store LEN samples into an on-chip memory, then latch done
//
//   The buffer is frozen once a capture completes, so the CPU can read it
//   without tearing. The CPU reads through axi_gpio_1:
//     ch1 (output) -> ctrl_i : bit31 = rearm, bits[LEN_W-1:0] = read address
//     ch2 (input)  <- data_o : bit31 = done,  bits[30:0] = sample
//
//   sample = { time_cnt[21:0], probe_i[8:0] }   (31 bits)
//
//   This replaces the AXI4-Stream + axi_vdma_0 S2MM path. That path never
//   completed a frame (ERR_INTERNAL / ERR_FSZ_MORE, S2MM frame count stayed
//   0), and the root cause is not readable from the VDMA registers. A plain
//   address/data window has no handshake, no frame size checking and no
//   sticky error bits to get stuck on.
//
//   Clock/reset: FCLK_CLK0 / proc_sys_reset_0 peripheral_aresetn.
//   NOTE: do not name the memory "buf" -- buf is a Verilog gate primitive.
//=============================================================================

`timescale 1ns / 1ps

module capture_ram #(
    parameter integer PROBE_W = 9,
    parameter integer LEN_W   = 13,      // 2**13 = 8192 samples per capture
    parameter integer LEN     = 8192
)(
    input  wire                aclk,
    input  wire                aresetn,

    input  wire [PROBE_W-1:0]  probe_i,

    input  wire [31:0]         ctrl_i,   // axi_gpio_1 ch1 output
    output reg  [31:0]         data_o    // axi_gpio_1 ch2 input
);

    localparam [LEN_W-1:0] LAST = LEN - 1;

    reg [30:0]      mem [0:LEN-1];
    reg [LEN_W-1:0] wr_idx;
    reg [21:0]      time_cnt;
    reg             trig_d;
    reg             busy;
    reg             done;

    reg [30:0]      rd_reg;

    wire trig_now  = probe_i[1];            // hsync
    wire trig_edge = trig_now & ~trig_d;    // rising edge

    // ---------------- capture ----------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_idx   <= {LEN_W{1'b0}};
            time_cnt <= 22'd0;
            trig_d   <= 1'b0;
            busy     <= 1'b0;
            done     <= 1'b0;
        end else begin
            trig_d   <= trig_now;
            time_cnt <= time_cnt + 22'd1;

            if (!busy) begin
                /* TRIGGER CHANGED: the capture used to wait for a rising edge on
                 * probe_i[1], which was wired to v_tc hsync. After probe_i was
                 * repointed at cmos_d_0 (the external J10 pins) that bit is a
                 * floating input with no edges, so the sampler NEVER started,
                 * never asserted done, and every readback returned zeros --
                 * visible as a flat 800-sample window and a 2 s timeout per
                 * frame in sample_wait(). A logic analyser should capture on
                 * demand, so rearm alone now starts it. Combinatorial triggers
                 * become a feature to add, selected by a spare ctrl_i bit. */
                if (ctrl_i[31]) begin
                    wr_idx <= {LEN_W{1'b0}};
                    busy   <= 1'b1;
                    done   <= 1'b0;
                end
            end else begin
                mem[wr_idx] <= { time_cnt, probe_i };
                if (wr_idx == LAST) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    wr_idx <= wr_idx + 1'b1;
                end
            end
        end
    end

    // ---------------- read port ----------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_reg <= 31'd0;
            data_o <= 32'd0;
        end else begin
            rd_reg <= mem[ctrl_i[LEN_W-1:0]];
            data_o <= { done, rd_reg };
        end
    end

endmodule
