// ts_stats_axi.v -- ts_stats + a small AXI4-Lite slave so the PS can read the numbers.
//
// WHY A WRAPPER INSTEAD OF AN AXI-LITE ts_stats
//   The statistics logic has no business knowing about AXI.  Keeping the register interface in a thin
//   wrapper means the streaming logic can be simulated and reviewed on its own, and the address map
//   is in one obvious place.
//
// THE STREAM IS TAPPED, NOT INSERTED
//   In the block design the camera stream forks through an axis_broadcaster: M00 still feeds the
//   capture VDMA exactly as before, M01 feeds this module.  This module never asserts back-pressure,
//   so a bug here cannot stall the camera path -- which matters, because the camera path is the one
//   thing that has been reliable all along.
//
// REGISTER MAP (one 4 KB AXI-Lite window)
//   0x00 CHANTOT      channels examined in the last complete frame
//   0x04 CLIPLONG     channels at or above CLIP_THRESHOLD
//   0x08 BBOX         x0[31:16] | y0[15:0]
//   0x0C BBOX         x1[31:16] | y1[15:0]
//   0x10 FRAME_COUNT  completed frames seen on the stream
//   0x14 STATUS       bit0 = a frame has completed since reset
//
// ASCII ONLY.

module ts_stats_axi #(
    parameter integer CLIP_THRESHOLD = 248,
    parameter integer HACTIVE        = 1280,
    parameter integer VACTIVE        = 720
) (
    // AXI4-Lite slave
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    // awprot/arprot exist only so Vivado infers a full AXI4-Lite interface on these ports; without
    // them the module shows up as loose signal pins and cannot be joined to the interconnect.
    input  wire [2:0]  s_axi_awprot,
    // 32-bit address: an inferred AXI4-Lite interface carries a 32-bit address, and
    // declaring only the low 6 bits left the rest unconnected -- the slave then saw two
    // address bits and the whole register file repeated every four words.
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [2:0]  s_axi_arprot,
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // AXI4-Stream tap (from the broadcaster's M01)
    // tready is present ONLY so Vivado infers an AXI4-Stream interface on these ports: the
    // broadcaster exposes M01_AXIS as an interface and does not publish its individual signals as
    // pins, so a module without tready appears as loose ports and cannot be joined with
    // connect_bd_intf_net.  This block never back-pressures, so tready is tied high.
    input  wire        m_axis_aclk,
    input  wire        m_axis_aresetn,
    input  wire [23:0] m_axis_tdata,
    input  wire        m_axis_tvalid,
    input  wire        m_axis_tlast,
    output wire        m_axis_tready
);

    // never back-pressures: always ready, so tapping cannot slow the capture path
    assign m_axis_tready = 1'b1;

    wire [31:0] st_chantot;
    wire [31:0] st_cliplong;
    wire [15:0] st_x0, st_y0, st_x1, st_y1;
    wire [31:0] st_frames;
    wire [31:0] st_beats;
    wire [31:0] st_lines;
    wire        st_valid;

    ts_stats #(
        .CLIP_THRESHOLD (CLIP_THRESHOLD),
        .HACTIVE        (HACTIVE),
        .VACTIVE        (VACTIVE)
    ) u_stats (
        .aclk        (m_axis_aclk),
        .aresetn     (m_axis_aresetn),
        .s_tdata     (m_axis_tdata),
        .s_tvalid    (m_axis_tvalid),
        .s_tlast     (m_axis_tlast),
        .chantot     (st_chantot),
        .cliplong    (st_cliplong),
        .bbox_x0     (st_x0),
        .bbox_y0     (st_y0),
        .bbox_x1     (st_x1),
        .bbox_y1     (st_y1),
        .frame_count (st_frames),
        .frame_valid (st_valid),
        .beat_count  (st_beats),
        .line_count  (st_lines)
    );

    // ---------------------------------------------------------------- read side
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
        end else begin
            s_axi_arready <= 1'b1;
            if (s_axi_arvalid && s_axi_arready) begin
                case (s_axi_araddr[5:2])
                    4'd0: s_axi_rdata <= st_chantot;
                    4'd1: s_axi_rdata <= st_cliplong;
                    4'd2: s_axi_rdata <= {st_x0, st_y0};
                    4'd3: s_axi_rdata <= {st_x1, st_y1};
                    4'd4: s_axi_rdata <= st_frames;
                    4'd5: s_axi_rdata <= {31'd0, st_valid};
                    4'd6: s_axi_rdata <= st_beats;
                    4'd7: s_axi_rdata <= st_lines;
                    default: s_axi_rdata <= 32'hDEADBEEF;
                endcase
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------- write side (accepted, ignored)
    // Nothing here is writable today.  The response is still a proper OKAY so a stray write from the
    // PS does not hang the interconnect waiting for a response that never comes.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
        end else begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule
