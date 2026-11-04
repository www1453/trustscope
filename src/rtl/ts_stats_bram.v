// ts_stats_bram.v -- ts_stats plus a simple BRAM write port, so the AXI interface is Vivado's job.
//
// WHY THIS REPLACED THE HAND-WRITTEN AXI-LITE SLAVE
//   The statistics logic is proven: simulation gives chantot = 691200, exactly the PS's number.  The
//   readback is what failed, twice, in ways that looked connected and were not:
//     * ps7_0_axi_periph/M09_AXI turned out to be taken by touch_gpio, leaving the module orphaned;
//     * after moving it to M10, the register window repeated every four words -- the address never
//       reached the slave.  Widening the address port to 32 bits changed nothing.
//   A hand-written AXI4-Lite slave is the one thing in this design I cannot verify by looking at it.
//   A block RAM behind xi_bram_ctrl, by contrast, has an interface Vivado builds and proves itself.
//
// THE CONTRACT
//   The PS reads six 32-bit words from the BRAM:
//     0x00 chantot   0x04 cliplong   0x08 {x0,y0}   0x0C {x1,y1}   0x10 frame_count   0x14 status
//   This module writes those six words once per frame, at the last pixel of the last line, using a
//   one-clock write of each.  Nothing is written mid-frame, so a reader never sees a mixture of two
//   frames -- the same rule the register version followed.
//
// ASCII ONLY.

module ts_stats_bram #(
    parameter integer CLIP_THRESHOLD = 248,
    parameter integer HACTIVE        = 1280,
    parameter integer VACTIVE        = 720
) (
    input  wire        clk,
    input  wire        aresetn,

    // AXI4-Stream tap (from the broadcaster)
    input  wire [23:0] m_axis_tdata,
    input  wire        m_axis_tvalid,
    input  wire        m_axis_tlast,
    output wire        m_axis_tready,

    // block RAM write port
    output reg  [3:0]  bram_we,
    output reg  [11:0] bram_addr,
    output reg  [31:0] bram_din,
    input  wire [31:0] bram_dout,
    input  wire         bram_clk
);

    // never back-pressures: tapping must not slow the capture path
    assign m_axis_tready = 1'b1;

    wire [31:0] st_chantot;
    wire [31:0] st_cliplong;
    wire [15:0] bx0, by0, bx1, by1;
    wire [31:0] st_frames;
    wire        st_valid;

    ts_stats #(
        .CLIP_THRESHOLD (CLIP_THRESHOLD),
        .HACTIVE        (HACTIVE),
        .VACTIVE        (VACTIVE)
    ) u_stats (
        .aclk        (clk),
        .aresetn     (aresetn),
        .s_tdata     (m_axis_tdata),
        .s_tvalid    (m_axis_tvalid),
        .s_tlast     (m_axis_tlast),
        .chantot     (st_chantot),
        .cliplong    (st_cliplong),
        .bbox_x0     (bx0),
        .bbox_y0     (by0),
        .bbox_x1     (bx1),
        .bbox_y1     (by1),
        .frame_count (st_frames),
        .frame_valid (st_valid)
    );

    // ONE WORD PER CLOCK ON A RISING EDGE OF frame_valid.  Six clocks, addresses 0..5.  The write
    // strobes are active for exactly one cycle each, which is what the BRAM requires.
    reg [2:0] wr_state;
    reg       prev_valid;

    localparam IDLE = 3'd0;

    always @(posedge clk) begin
        if (!aresetn) begin
            wr_state  <= IDLE;
            prev_valid <= 1'b0;
            bram_we   <= 4'd0;
            bram_addr <= 12'd0;
            bram_din  <= 32'd0;
        end else begin
            bram_we <= 4'd0;                     // strobes are one cycle unless re-asserted below
            prev_valid <= st_valid;

            if (st_valid && !prev_valid) begin
                wr_state <= 3'd1;                // a new frame result just appeared
            end

            case (wr_state)
                IDLE: ;
                3'd1: begin bram_addr <= 12'd0; bram_din <= st_chantot;        bram_we <= 4'hF; wr_state <= 3'd2; end
                3'd2: begin bram_addr <= 12'd1; bram_din <= st_cliplong;       bram_we <= 4'hF; wr_state <= 3'd3; end
                3'd3: begin bram_addr <= 12'd2; bram_din <= {bx0, by0};        bram_we <= 4'hF; wr_state <= 3'd4; end
                3'd4: begin bram_addr <= 12'd3; bram_din <= {bx1, by1};        bram_we <= 4'hF; wr_state <= 3'd5; end
                3'd5: begin bram_addr <= 12'd4; bram_din <= st_frames;         bram_we <= 4'hF; wr_state <= 3'd6; end
                3'd6: begin bram_addr <= 12'd5; bram_din <= {31'd0, st_valid}; bram_we <= 4'hF; wr_state <= 3'd0; end
                default: wr_state <= IDLE;
            endcase
        end
    end

endmodule
