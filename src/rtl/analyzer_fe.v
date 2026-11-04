// =============================================================================
// analyzer_fe.v -- TrustScope capture front-end (W1 static closed loop)
//
// Samples NCH digital channels, renders them as a logic-analyzer style raster,
// and emits the frame as an AXI4-Stream byte stream. The stream is stored into
// DDR by axi_vdma_0 (S2MM) and read back by axi_vdma_1 (MM2S) to drive the RGB
// LCD -- i.e. it takes over the camera data path with an equivalent interface.
//
// FRAME FORMAT must match the existing display chain exactly:
//   800 x 480, 24 bpp packed RGB888, stride 2400 bytes
//   -> 600 32-bit words per line, 480 lines, 1,152,000 bytes per frame
//   Byte order is little-endian inside each 32-bit word:
//       tdata[7:0]=byte0, [15:8]=byte1, [23:16]=byte2, [31:24]=byte3
//   (verified against the working LCD application, not assumed)
//
// SAMPLE SOURCE is selectable via ctrl[1] so the whole loop can be verified
// with NOTHING connected to the board:
//       ctrl[1]=0 : sample the ch_i input pins
//       ctrl[1]=1 : sample an internal pattern generator (counter bits)
//   The pattern generator doubles as the self-calibration stimulus later.
//
// Sampling is frame-locked: during line 0 one sample set is captured per pixel
// column, then read back for lines 1..479, giving one coherent snapshot per
// frame instead of a tearing live view.
//
// DESIGN NOTES (why it looks like this):
//   * row/channel decode uses COUNTERS, not  line_y / BAND_H ; a division by a
//     constant still costs real logic and is pointless for a fixed 30-row band
//   * the sample RAM is distributed (async read) so the raster pipeline needs
//     no BRAM-latency alignment
//   * one bank is enough: line 0 writes, lines 1..479 read the same bank
//
// ASCII ONLY -- Vivado parses .v through the same Tcl/GBK layer as .tcl on
// zh-CN Windows, and a non-ASCII byte can produce a bogus syntax error.
//
// A timescale is MANDATORY here: xelab fails with [XSIM 43-4099] if one module
// in the design has a timescale (the testbench) and another does not.
// =============================================================================

`timescale 1ns / 1ps

module analyzer_fe #(
    parameter H_ACTIVE = 800,          // pixels per line
    parameter V_ACTIVE = 480,          // lines per frame
    parameter NCH      = 16,           // digital channels displayed
    parameter DATA_W   = 8,            // bits per colour component
    parameter IDX_W    = 10,           // log2(H_ACTIVE) rounded up  (800 -> 10)
    parameter WORD_CW  = 10,           // log2(H_ACTIVE*3/4) rounded up (600 -> 10)
    parameter Y_CW     = 9             // log2(V_ACTIVE) rounded up (480 -> 9)
)(
    input  wire                aclk,
    input  wire                aresetn,

    // ---- sampled inputs -------------------------------------------------
    input  wire [NCH-1:0]      ch_i,

    // ---- control / status ----------------------------------------------
    input  wire [31:0]         ctrl,    // [0] enable, [1] internal pattern
    output wire [31:0]         status,

    // ---- AXI4-Stream master (packed RGB888, 32-bit) ---------------------
    // tkeep and tuser were MISSING in the first version. The VDMA's
    // s_axis_s2mm_tkeep then floated, so every byte was treated as null and
    // the S2MM channel wrote nothing at all (frame count 0, ERR_INTERNAL set,
    // buffer left untouched). For a 32-bit stream where all four bytes are
    // always valid, tkeep is a constant 4'hF. tuser marks start-of-frame in
    // AXI4-Stream Video; the design does not use it, so it is tied low.
    output wire [31:0]         m_axis_tdata,
    output wire [3:0]          m_axis_tkeep,
    output wire                m_axis_tvalid,
    output wire                m_axis_tlast,
    output wire                m_axis_tuser,
    input  wire                m_axis_tready
);

    localparam integer LINE_BYTES = H_ACTIVE * 3;             // 2400
    localparam integer LINE_WORDS = LINE_BYTES / 4;           // 600
    localparam integer BAND_H     = V_ACTIVE / NCH;           // 30
    localparam integer BR_CW      = (BAND_H <= 16) ? 4 : 6;   // band-row counter width

    // -------------------------------------------------------------------------
    // Sample RAM: one bank of H_ACTIVE entries x NCH bits, async read.
    // 800 x 16 = 12.8 kbit -- comfortably fits in distributed RAM.
    // -------------------------------------------------------------------------
    (* ram_style = "distributed" *) reg [NCH-1:0] samp [0:H_ACTIVE-1];

    // -------------------------------------------------------------------------
    // Raster state
    // -------------------------------------------------------------------------
    reg  [WORD_CW-1:0] word_x;         // 0 .. LINE_WORDS-1
    reg  [Y_CW-1:0]    line_y;         // 0 .. V_ACTIVE-1
    reg  [1:0]         byte_ph;        // 0=R 1=G 2=B
    reg  [IDX_W-1:0]   px;             // current pixel column 0..H_ACTIVE-1
    reg  [31:0]        word_acc;
    reg  [1:0]         byte_in_word;   // 0..3

    reg  [3:0]         band_ch;        // 0 .. NCH-1
    reg  [BR_CW-1:0]   band_row;       // 0 .. BAND_H-1
    reg                samples_valid;  // at least one full capture has completed

    // -------------------------------------------------------------------------
    // Sample lookup (async distributed RAM read)
    // -------------------------------------------------------------------------
    wire [NCH-1:0] s_now  = samp[px];
    wire [NCH-1:0] s_prev = samp[(px == 0) ? {IDX_W{1'b0}} : (px - 1'b1)];

    // -------------------------------------------------------------------------
    // Built-in pattern generator (used when ctrl[1]=1, i.e. nothing connected)
    // -------------------------------------------------------------------------
    reg [11:0] pat_cnt;
    wire [NCH-1:0] pat_val = {
        8'hA5,                                        // ch15..ch8 fixed pattern
        pat_cnt[11], pat_cnt[9], pat_cnt[7], pat_cnt[5],
        pat_cnt[3],  pat_cnt[2], pat_cnt[1], pat_cnt[0]
    };

    wire [NCH-1:0] sample_src = ctrl[1] ? pat_val : ch_i;

    // -------------------------------------------------------------------------
    // Row / channel decode and colour selection
    // -------------------------------------------------------------------------
    wire bit_now  = s_now [band_ch];
    wire bit_prev = s_prev[band_ch];
    wire is_edge  = (px != 0) && (bit_now != bit_prev);

    wire seg_hi = (band_row >= 2)              && (band_row <= 4);
    wire seg_lo = (band_row >= (BAND_H-5))     && (band_row <= (BAND_H-3));

    // samples_valid is REQUIRED, not cosmetic. Before the first capture the
    // sample RAM is uninitialised, so bit_now/bit_prev are X and
    //     is_edge = (px != 0) && (bit_now != bit_prev)
    // evaluates to X, which propagates through draw -> byte_val -> the output
    // stream. Simulation showed the first word arriving as 0xXx303030.
    // Gating the renderer until one capture has completed removes the X and
    // also fixes line 0 drawing half-written samples.
    wire draw = ctrl[0] && samples_valid &&
                ( is_edge                       // vertical transition
               || ( bit_now && seg_hi)          // high level segment
               || (!bit_now && seg_lo) );       // low level segment

    reg [DATA_W-1:0] col_r, col_g, col_b;
    always @(*) begin
        case (band_ch)
            4'd0 : begin col_r = 8'hFF; col_g = 8'h40; col_b = 8'h40; end
            4'd1 : begin col_r = 8'hFF; col_g = 8'hA0; col_b = 8'h20; end
            4'd2 : begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'h40; end
            4'd3 : begin col_r = 8'h60; col_g = 8'hFF; col_b = 8'h60; end
            4'd4 : begin col_r = 8'h40; col_g = 8'hFF; col_b = 8'hC0; end
            4'd5 : begin col_r = 8'h40; col_g = 8'hC0; col_b = 8'hFF; end
            4'd6 : begin col_r = 8'h80; col_g = 8'hA0; col_b = 8'hFF; end
            4'd7 : begin col_r = 8'hC0; col_g = 8'h80; col_b = 8'hFF; end
            4'd8 : begin col_r = 8'hFF; col_g = 8'h60; col_b = 8'hC0; end
            4'd9 : begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'hFF; end
            4'd10: begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'hFF; end
            4'd11: begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'hFF; end
            4'd12: begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'hFF; end
            4'd13: begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'hFF; end
            4'd14: begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'hFF; end
            default: begin col_r = 8'hFF; col_g = 8'hFF; col_b = 8'hFF; end
        endcase
    end

    // background: dark, with a faint separator row on the first row of each band
    wire [DATA_W-1:0] bg = (band_row == 0) ? 8'h30 : 8'h10;

    wire [DATA_W-1:0] byte_val = draw
                                 ? ((byte_ph == 2'd0) ? col_r :
                                    (byte_ph == 2'd1) ? col_g : col_b)
                                 : bg;

    // -------------------------------------------------------------------------
    // Stream engine
    //
    // TWO THINGS THE TESTBENCH CAUGHT (do not "simplify" them back):
    //
    //  1) tvalid must assert ONE CYCLE AFTER the 4th byte is shifted in.
    //     Driving tvalid combinationally from (byte_in_word == 3) emitted the
    //     word with only 3 bytes populated -- simulation showed the first word
    //     as 0x30303000 instead of 0x30303030.
    //     So: register the completion, and hold the pipeline while valid&&!ready.
    //
    //  2) tlast marks END OF LINE, not end of frame (AXI4-Stream Video
    //     convention, and what the existing camera path does). The VDMA uses it
    //     for line boundaries. Asserting it once per frame made the testbench
    //     report a 288000-word "line".
    //     Because word_x advances on the same edge that completes the word, the
    //     last-of-line flag must be REGISTERED alongside the valid.
    // -------------------------------------------------------------------------
    reg word_valid_r;
    reg word_last_r;

    wire stall   = word_valid_r && !m_axis_tready;
    wire advance = !stall;                       // byte pipeline moves on

    assign m_axis_tdata  = word_acc;
    assign m_axis_tvalid = word_valid_r;
    assign m_axis_tlast  = word_last_r;
    assign m_axis_tkeep  = 4'hF;      // all four bytes always valid
    assign m_axis_tuser  = 1'b0;      // start-of-frame marker not used here

    wire px_last  = (px     == (H_ACTIVE-1));
    wire wx_last  = (word_x == (LINE_WORDS-1));
    wire y_last   = (line_y == (V_ACTIVE-1));

    always @(posedge aclk) begin
        if (!aresetn) begin
            word_x       <= {WORD_CW{1'b0}};
            line_y       <= {Y_CW{1'b0}};
            byte_ph      <= 2'd0;
            px           <= {IDX_W{1'b0}};
            word_acc     <= 32'd0;
            byte_in_word <= 2'd0;
            band_ch      <= 4'd0;
            band_row     <= {BR_CW{1'b0}};
            pat_cnt      <= 12'd0;
            word_valid_r <= 1'b0;
            word_last_r  <= 1'b0;
            samples_valid<= 1'b0;
        end else begin
            pat_cnt <= pat_cnt + 1'b1;

            // ---- capture one sample set per pixel column during line 0 ----
            if ((line_y == {Y_CW{1'b0}}) && advance && (byte_ph == 2'd0))
                samp[px] <= sample_src;

            // ---- byte pipeline -------------------------------------------
            if (advance) begin
                word_acc <= {byte_val, word_acc[31:8]};

                if (byte_ph == 2'd2) begin
                    byte_ph <= 2'd0;
                    px      <= px_last ? {IDX_W{1'b0}} : (px + 1'b1);
                end else begin
                    byte_ph <= byte_ph + 1'b1;
                end

                if (byte_in_word == 2'd3) begin
                    byte_in_word <= 2'd0;
                    if (wx_last) begin
                        word_x <= {WORD_CW{1'b0}};
                        if (y_last) begin
                            line_y   <= {Y_CW{1'b0}};
                            band_ch  <= 4'd0;
                            band_row <= {BR_CW{1'b0}};
                        end else begin
                            line_y <= line_y + 1'b1;
                            // first full capture is done once line 0 is left;
                            // it stays set, so later frames never see X either
                            if (line_y == {Y_CW{1'b0}}) samples_valid <= 1'b1;
                            if (band_row == (BAND_H-1)) begin
                                band_row <= {BR_CW{1'b0}};
                                band_ch  <= band_ch + 1'b1;
                            end else begin
                                band_row <= band_row + 1'b1;
                            end
                        end
                    end else begin
                        word_x <= word_x + 1'b1;
                    end
                end else begin
                    byte_in_word <= byte_in_word + 1'b1;
                end
            end

            // ---- valid / last-of-line, registered off the completion cycle ----
            if (stall) begin
                word_valid_r <= 1'b1;            // hold until accepted
                word_last_r  <= word_last_r;
            end else begin
                word_valid_r <= (byte_in_word == 2'd3);
                word_last_r  <= (byte_in_word == 2'd3) && wx_last;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Status: {14'b0, band_ch, line_y, word_x} -- readable for bring-up
    // -------------------------------------------------------------------------
    assign status = { 2'd0, band_ch, 8'd0, line_y, word_x };

endmodule
