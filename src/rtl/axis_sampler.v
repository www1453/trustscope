//=============================================================================
// axis_sampler.v
//
// PL side probe sampler.
//
//   probe_i  -- 9 bit probe bus, sampled once per aclk.
//   Aquisition:
//     1. IDLE   : wait for a rising edge on probe_i[1] (hsync).
//     2. FILL   : store LEN samples into an on-chip buffer.
//                 word = { time_cnt[22:0], probe_i[8:0] }
//     3. SEND   : stream the buffer out as a 32 bit AXI4-Stream,
//                 tlast on the final beat, then re-arm.
//
//   The output stream feeds axi_vdma_0 S2MM, which writes it to DDR.
//   Clock/reset: FCLK_CLK0 (50 MHz) / proc_sys_reset_0 peripheral_aresetn.
//
//   Note: probe_i lives in the 33 MHz video domain and is sampled by a
//   50 MHz clock, so this is an asynchronous tap. That is acceptable for
//   a debug probe but every sample is not guaranteed to be metastability
//   free; it is a monitor, not a timed measurement path.
//=============================================================================

`timescale 1ns / 1ps

module axis_sampler #(
    parameter integer PROBE_W = 9,
    parameter integer LEN_W   = 13,      // 2**13 = 8192 samples per acquisition
    parameter integer LEN     = 8192,
    parameter integer LINE_W  = 9,       // 2**9 = 512 beats per VDMA "line"
    parameter integer LINE    = 512
)(
    input  wire                aclk,
    input  wire                aresetn,

    input  wire [PROBE_W-1:0]  probe_i,

    output reg  [31:0]         m_axis_tdata,
    output reg                 m_axis_tvalid,
    output reg                 m_axis_tlast,
    input  wire                m_axis_tready
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_FILL = 2'd1;
    localparam [1:0] ST_SEND = 2'd2;

    reg [1:0]       state;
    reg [LEN_W-1:0] idx;
    reg             trig_d;
    reg [22:0]      time_cnt;

    // Sample buffer. Synchronous write, synchronous read -> block RAM.
    // NOTE: do not name this "buf" -- buf is a Verilog gate primitive keyword.
    reg [31:0] mem [0:LEN-1];

    wire trig_now  = probe_i[1];            // hsync
    wire trig_edge = trig_now & ~trig_d;    // rising edge

    // tlast marks the end of one VDMA "line". The AXI VDMA S2MM line buffer
    // is only 512 beats deep, so a single 8192-beat line (the whole capture)
    // is far outside its normal operating range. Emitting tlast every
    // LINE beats makes the frame look like a normal 16-line video frame.
    wire beat_tlast = (idx[LINE_W-1:0] == LINE[LINE_W-1:0] - 1'b1);

    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= ST_IDLE;
            idx           <= {LEN_W{1'b0}};
            trig_d        <= 1'b0;
            time_cnt      <= 23'd0;
            m_axis_tdata  <= 32'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            trig_d   <= trig_now;
            time_cnt <= time_cnt + 23'd1;

            case (state)

            // ------------------------------------------------------------
            ST_IDLE: begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
                if (trig_edge) begin
                    idx   <= {LEN_W{1'b0}};
                    state <= ST_FILL;
                end
            end

            // ------------------------------------------------------------
            ST_FILL: begin
                mem[idx] <= { time_cnt, probe_i };
                if (idx == LEN[LEN_W-1:0] - 1'b1) begin
                    idx   <= {LEN_W{1'b0}};
                    state <= ST_SEND;
                end else begin
                    idx <= idx + 1'b1;
                end
            end

            // ------------------------------------------------------------
            // One beat is presented while tvalid is low, then held until
            // tready. This costs one bubble per beat but is unambiguous.
            ST_SEND: begin
                if (!m_axis_tvalid) begin
                    m_axis_tdata  <= mem[idx];
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= beat_tlast;
                end else if (m_axis_tready) begin
                    if (idx == LEN[LEN_W-1:0] - 1'b1) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                        idx           <= {LEN_W{1'b0}};
                        state         <= ST_IDLE;
                    end else begin
                        idx           <= idx + 1'b1;
                        m_axis_tvalid <= 1'b0;
                    end
                end
            end

            // ------------------------------------------------------------
            default: state <= ST_IDLE;

            endcase
        end
    end

endmodule
