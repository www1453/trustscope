// tb_ts_stats.v -- drive ts_stats with a synthetic 1280x720 stream and check its counters.
//
// WHY A TESTBENCH INSTEAD OF ANOTHER BUILD
//   The block is already in the bitstream and its registers read back, and they read 3 where 691200 is
//   expected.  A build costs 25 minutes and tells me only pass/fail; a simulation tells me exactly
//   which cycle a box failed to complete.  With the frame boundary already fixed once by reading a
//   number back from hardware, the next step should be one that reports where, not just that.
//
// WHAT IT DRIVES
//   One beat per clock, 24-bit BGR where B=G=R=0x40 (below the clip threshold, so CLIPLONG must be 0),
//   tlast asserted at the end of every LINE -- which is what this video stream actually does, and what
//   the first version of the RTL got wrong by treating it as end-of-frame.
//
// WHAT IT CHECKS
//   chantot == (1280/2)*(720/2)*3 == 691200, cliplong == 0, frame_count >= 1, bbox untouched (FFFF).
//
// ASCII ONLY.


module tb_ts_stats;

    localparam integer HACTIVE = 1280;
    localparam integer VACTIVE = 720;
    localparam integer CLIP     = 248;

    reg clk = 1'b0;
    reg rstn = 1'b0;

    reg  [23:0] s_tdata = 24'h402040;   // B=0x40 G=0x20 R=0x40, all below CLIP
    reg         s_tvalid = 1'b0;
    reg         s_tlast = 1'b0;

    wire [31:0] chantot, cliplong, frame_count;
    wire [15:0] bx0, by0, bx1, by1;
    wire        fvalid;

    ts_stats #(
        .CLIP_THRESHOLD (CLIP),
        .HACTIVE        (HACTIVE),
        .VACTIVE        (VACTIVE)
    ) dut (
        .aclk        (clk),
        .aresetn     (rstn),
        .s_tdata     (s_tdata),
        .s_tvalid    (s_tvalid),
        .s_tlast     (s_tlast),
        .chantot     (chantot),
        .cliplong    (cliplong),
        .bbox_x0     (bx0),
        .bbox_y0     (by0),
        .bbox_x1     (bx1),
        .bbox_y1     (by1),
        .frame_count (frame_count),
        .frame_valid (fvalid)
    );

    always #5 clk = ~clk;

    integer x, y;
    integer errors = 0;

    initial begin
        $display("=== tb_ts_stats: one full %0dx%0d frame, tlast per LINE ===", HACTIVE, VACTIVE);
        repeat (4) @(posedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);

        for (y = 0; y < VACTIVE; y = y + 1) begin
            for (x = 0; x < HACTIVE; x = x + 1) begin
                s_tvalid <= 1'b1;
                s_tdata  <= {8'h40, 8'h20, 8'h40};
                s_tlast  <= (x == HACTIVE - 1);   // end of LINE, as the real stream does
                @(posedge clk);
            end
        end
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
        repeat (10) @(posedge clk);

        $display("  chantot    = %0d   (expected %0d)", chantot, (HACTIVE/2)*(VACTIVE/2)*3);
        $display("  cliplong   = %0d   (expected 0)", cliplong);
        $display("  frame_count= %0d   (expected >= 1)", frame_count);
        $display("  bbox       = %0d,%0d .. %0d,%0d  (expected all FFFF/0: no clipped pixel)",
                 bx0, by0, bx1, by1);

        if (chantot !== (HACTIVE/2)*(VACTIVE/2)*3) begin
            $display("*** FAIL: chantot is wrong -> the 2x2 gather or the frame boundary is broken");
            errors = errors + 1;
        end
        if (cliplong !== 0) begin
            $display("*** FAIL: cliplong should be 0 for an all-sub-threshold frame");
            errors = errors + 1;
        end
        if (frame_count < 1) begin
            $display("*** FAIL: no frame was latched");
            errors = errors + 1;
        end
        if (bx0 !== 16'hFFFF) begin
            $display("*** FAIL: bbox was touched even though nothing was clipped");
            errors = errors + 1;
        end

        if (errors == 0) $display("=== PASS ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $finish;
    end

endmodule
