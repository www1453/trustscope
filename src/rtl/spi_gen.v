//=============================================================================
// spi_gen.v
//
// PL-side SPI master used as a KNOWN-GOOD signal source for the protocol
// decoder. It exists because the board has no external SPI peripheral to
// measure: the camera is an SCCB/I2C device and the AN5642 module is faulty,
// so without this the SPI decode path could only ever be tested against a
// synthetic array in software -- which proves nothing about the sampler, the
// capture buffer or the run-length decoder.
//
// The UART demo already proves the EXTERNAL path (CPU bit-bang -> B20 ->
// jumper -> cmos_d_0[0] -> sampler). This generator proves the DECODE path on
// a signal that was really sampled through the same hardware, without needing
// any more wires: its outputs are routed by the block design straight into the
// sampler's probe bus.
//
//   probe bus mapping (see bd_add_spi_gen.tcl):
//     bit0 = cmos_d_0[0]   external probe, B20 jumper  (UART + calibration)
//     bit1 = spi_sck       \
//     bit2 = spi_mosi       > this module
//     bit3 = spi_cs_n      /
//     bit4..8 = cmos_d_0[8:4]  external, kept
//
// Timing: SCK half period = DIV aclk cycles. At 50 MHz and DIV = 250 that is
// 5 us, i.e. SCK = 100 kHz and one 8-bit transfer = 80 us. That matters: the
// capture window is 176 us at 220 ns per sample, so a fast SPI clock would
// leave only a handful of samples per bit and the decoder's edge-to-edge
// estimate would be quantised to uselessness. At 100 kHz each SCK half period
// spans about 23 samples.
//
// Protocol: SPI mode 0 (CPOL=0, CPHA=0), MSB first, 8 bits.
//   - SCK idles low, CS idles high
//   - MOSI is set up while SCK is low and is sampled by the slave on the
//     RISING edge; it changes on the FALLING edge
//
// ASCII ONLY.
//=============================================================================

`timescale 1ns / 1ps

module spi_gen #(
    parameter integer DIV = 250        // aclk cycles per SCK half period
)(
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] ctrl_i,         // [24] = start (rising edge), [23:16] = data

    output reg         sck,
    output reg         mosi,
    output reg         cs_n
);

    reg [15:0] div;
    reg [3:0]  bitn;                   // 7 down to 0
    reg [7:0]  sh;
    reg        run;
    reg        start_d;

    // Bit-selecting an integer parameter is not portable (some tools reject
    // DIV[15:0]), so take a proper vector copy once.
    localparam [15:0] DIVV = DIV[15:0];

    wire start_edge = ctrl_i[24] & ~start_d;

    always @(posedge aclk) begin
        if (!aresetn) begin
            div     <= 16'd0;
            bitn    <= 4'd0;
            sh      <= 8'd0;
            run     <= 1'b0;
            start_d <= 1'b0;
            sck     <= 1'b0;
            mosi    <= 1'b0;
            cs_n    <= 1'b1;
        end else begin
            start_d <= ctrl_i[24];

            if (!run) begin
                // Idle. A rising edge on ctrl_i[24] starts one byte.
                sck  <= 1'b0;
                cs_n <= 1'b1;
                mosi <= 1'b0;
                div  <= 16'd0;

                if (start_edge) begin
                    sh   <= ctrl_i[23:16];
                    bitn <= 4'd7;
                    mosi <= ctrl_i[23];   // MSB first, valid before the first rising edge
                    cs_n <= 1'b0;
                    sck  <= 1'b0;
                    run  <= 1'b1;
                end
            end else begin
                if (div != DIVV - 16'd1) begin
                    div <= div + 16'd1;
                end else begin
                    div <= 16'd0;
                    sck <= ~sck;

                    // `sck` still holds its OLD value here: 0 means we are
                    // driving it high (the rising edge the slave samples on),
                    // 1 means the falling edge, where the master advances.
                    if (sck) begin
                        if (bitn == 4'd0) begin
                            run  <= 1'b0;      // 8 bits done
                            cs_n <= 1'b1;
                            mosi <= 1'b0;
                        end else begin
                            bitn <= bitn - 4'd1;
                            sh   <= {sh[6:0], 1'b0};
                            mosi <= sh[6];     // next bit, set up while SCK is low
                        end
                    end
                end
            end
        end
    end

endmodule
