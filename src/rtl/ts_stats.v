// ts_stats.v -- streaming pixel statistics in the fabric.  v3: last-box accounting fixed by simulation.
//
// WHY THIS BLOCK EXISTS
//   The PS reads 2.76 MB per frame and walks 230,400 output pixels to produce CHANTOT, CLIPLONG and a
//   bounding box -- 41.7 ms of a 54.7 ms frame.  The fabric does it while the pixels stream past.
//
// THE THREE BUGS THIS FILE HAS BEEN THROUGH, EACH FOUND BY SIMULATION RATHER THAN BY REBUILDING
//   1. v1 approximated the row above with the current row's pixel.  Cannot produce the PS's numbers.
//   2. v2 treated tlast as end-of-frame.  On this video stream tlast marks end of LINE, so the
//      accumulators were cleared 720 times per frame and the register read 3 (one box).
//   3. v3a handled the frame end one cycle late, outside tvalid, so it never ran at all.
//   What v3 does: on the last box of the last line, the latched value is the accumulator PLUS that
//   box's own contribution.  No ordering trick, no delayed flag: the arithmetic simply includes the
//   final box by construction.
//
// EXACTNESS: EVERY CHOICE IS COPIED FROM draw_camera(), NOT INVENTED
//   * 2x2 box average of the long exposure, per channel, B then G then R byte lanes.
//   * Truncating (a+b+c+d)>>2, not a rounded average.
//   * The clip test runs on the raw averages, before the tone table (whose blue gain maps 255 to 234
//     and would erase exactly the "channel is blown" information).
//   * One box is one output pixel; the bbox records output-pixel coordinates.
//   The acceptance test is exact equality with the PS, so any deviation is a bug here.
//
// INTERFACE
//   AXI4-Stream slave, 24-bit tdata (B,G,R), the camera's post-converter stream.  Never back-pressures.
//   Results are latched at the last pixel of the last line so the PS never reads a partial frame.
//
// ASCII ONLY.

module ts_stats #(
    parameter integer CLIP_THRESHOLD = 248,
    parameter integer HACTIVE        = 1280,
    parameter integer VACTIVE        = 720
) (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [23:0] s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tlast,

    output reg  [31:0] chantot,
    output reg  [31:0] cliplong,
    output reg  [15:0] bbox_x0,
    output reg  [15:0] bbox_y0,
    output reg  [15:0] bbox_x1,
    output reg  [15:0] bbox_y1,
    output reg  [31:0] frame_count,
    output reg         frame_valid,
    // DIAGNOSTIC OUTPUTS.  Simulated logic gives 691200 while the board reads 3, so the
    // open question is what the block RECEIVES, not what it computes.  beat_count counts
    // every accepted beat, line_count every tlast; their ratio is the real beats-per-line.
    output reg  [31:0] beat_count,
    output reg  [31:0] line_count
);

    // ---------------------------------------------------------------- one-line buffer
    reg  [23:0] linebuf [0:HACTIVE-1];
    reg  [10:0] wr_col;
    reg  [23:0] row_above;
    reg         row_valid;

    // ---------------------------------------------------------------- 2x2 members
    reg  [23:0] prev_pixel;
    reg         prev_valid;
    reg  [23:0] row_above_left;

    // ---------------------------------------------------------------- accumulators
    reg [31:0] acc_chantot;
    reg [31:0] acc_cliplong;
    reg [15:0] acc_x0, acc_y0, acc_x1, acc_y1;
    reg        acc_any;

    reg [15:0] px;
    reg [15:0] py;
    reg [31:0] acc_beats;
    reg [31:0] acc_lines;

    wire [7:0] b0 = s_tdata[23:16];
    wire [7:0] g0 = s_tdata[15:8];
    wire [7:0] r0 = s_tdata[7:0];

    wire [7:0] pb = prev_pixel[23:16];
    wire [7:0] pg = prev_pixel[15:8];
    wire [7:0] pr = prev_pixel[7:0];

    wire [7:0] qb = row_above[23:16];
    wire [7:0] qg = row_above[15:8];
    wire [7:0] qr = row_above[7:0];

    wire [7:0] qlb = row_above_left[23:16];
    wire [7:0] qlg = row_above_left[15:8];
    wire [7:0] qlr = row_above_left[7:0];

    wire [9:0] sum_b = {2'b00, pb} + {2'b00, b0} + {2'b00, qb} + {2'b00, qlb};
    wire [9:0] sum_g = {2'b00, pg} + {2'b00, g0} + {2'b00, qg} + {2'b00, qlg};
    wire [9:0] sum_r = {2'b00, pr} + {2'b00, r0} + {2'b00, qr} + {2'b00, qlr};

    wire [7:0] avg_b = sum_b[9:2];
    wire [7:0] avg_g = sum_g[9:2];
    wire [7:0] avg_r = sum_r[9:2];

    wire box_ready = s_tvalid && prev_valid && row_valid && px[0] == 1'b1 && py[0] == 1'b1;

    wire clip_b = (avg_b >= CLIP_THRESHOLD);
    wire clip_g = (avg_g >= CLIP_THRESHOLD);
    wire clip_r = (avg_r >= CLIP_THRESHOLD);
    wire [1:0] clip_cnt = {1'b0, clip_b} + {1'b0, clip_g} + {1'b0, clip_r};

    wire [15:0] out_x = {1'b0, px[15:1]};
    wire [15:0] out_y = py[15:1];

    // the last box of the frame: its contribution must be included in the latched values
    wire last_box = box_ready && (px == HACTIVE - 1) && (py == VACTIVE - 1);

    wire [31:0] box_clip = {30'd0, clip_cnt};
    wire        box_any  = (clip_cnt != 2'd0);

    wire [15:0] nx0 = (box_any && out_x < acc_x0) ? out_x : acc_x0;
    wire [15:0] ny0 = (box_any && out_y < acc_y0) ? out_y : acc_y0;
    wire [15:0] nx1 = (box_any && out_x > acc_x1) ? out_x : acc_x1;
    wire [15:0] ny1 = (box_any && out_y > acc_y1) ? out_y : acc_y1;
    wire        nany = acc_any | box_any;

    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_col <= 11'd0;
            row_valid <= 1'b0;
            prev_valid <= 1'b0;
            px <= 16'd0;
            py <= 16'd0;
            acc_chantot  <= 32'd0;
            acc_cliplong <= 32'd0;
            acc_x0 <= 16'hFFFF;
            acc_y0 <= 16'hFFFF;
            acc_x1 <= 16'd0;
            acc_y1 <= 16'd0;
            acc_any <= 1'b0;
            chantot     <= 32'd0;
            cliplong    <= 32'd0;
            bbox_x0     <= 16'hFFFF;
            bbox_y0     <= 16'hFFFF;
            bbox_x1     <= 16'd0;
            bbox_y1     <= 16'd0;
            frame_count <= 32'd0;
            frame_valid <= 1'b0;
            acc_beats <= 32'd0;
            acc_lines <= 32'd0;
            beat_count <= 32'd0;
            line_count <= 32'd0;
        end else if (s_tvalid) begin
            acc_beats <= acc_beats + 32'd1;
            if (s_tlast) acc_lines <= acc_lines + 32'd1;

            linebuf[wr_col] <= s_tdata;
            row_above <= linebuf[wr_col];
            if (py != 16'd0) row_valid <= 1'b1;

            prev_pixel     <= s_tdata;
            prev_valid     <= 1'b1;
            row_above_left <= row_above;

            if (last_box) begin
                chantot     <= acc_chantot + 32'd3;
                cliplong    <= acc_cliplong + box_clip;
                bbox_x0     <= nany ? nx0 : 16'hFFFF;
                bbox_y0     <= nany ? ny0 : 16'hFFFF;
                bbox_x1     <= nany ? nx1 : 16'd0;
                bbox_y1     <= nany ? ny1 : 16'd0;
                frame_count <= frame_count + 32'd1;
                frame_valid <= 1'b1;
                beat_count <= acc_beats + 32'd1;
                line_count <= acc_lines + (s_tlast ? 32'd1 : 32'd0);
                acc_beats <= 32'd0;
                acc_lines <= 32'd0;
                acc_chantot  <= 32'd0;
                acc_cliplong <= 32'd0;
                acc_x0 <= 16'hFFFF;
                acc_y0 <= 16'hFFFF;
                acc_x1 <= 16'd0;
                acc_y1 <= 16'd0;
                acc_any <= 1'b0;
            end else if (box_ready) begin
                acc_chantot  <= acc_chantot + 32'd3;
                acc_cliplong <= acc_cliplong + box_clip;
                acc_x0 <= nx0;
                acc_y0 <= ny0;
                acc_x1 <= nx1;
                acc_y1 <= ny1;
                acc_any <= nany;
            end

            if (px == HACTIVE - 1) begin
                px <= 16'd0;
                prev_valid <= 1'b0;
                wr_col <= 11'd0;
                py <= (py == VACTIVE - 1) ? 16'd0 : py + 16'd1;
            end else begin
                px <= px + 16'd1;
                wr_col <= wr_col + 11'd1;
            end
        end
    end

endmodule
