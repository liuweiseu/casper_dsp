// power — casper_library_misc/power: |c|^2 of a complex input
//
// c packs {re, im}, each a signed BIT_WIDTH-bit fraction (Fix_<BIT_WIDTH>_
// <BIT_WIDTH-1>), re in the MSBs (c_to_ri). As power_behav.m builds it:
//   re^2, im^2 : full-precision Xilinx Mults (Fix_<2*BIT_WIDTH>_<2*BIT_WIDTH-2>),
//                MULT_LATENCY registers
//   power      : AddSub re^2 + im^2, User Defined Unsigned
//                <2*BIT_WIDTH+1>_<2*BIT_WIDTH>, Truncate / Wrap, ADD_LATENCY
//                registers
// so dout (Simulink port power) is UFix_<2*BIT_WIDTH+1>_<2*BIT_WIDTH>, MULT_LATENCY + ADD_LATENCY
// cycles after c. The only value that does not fit is re = im = -1 (|c|^2 =
// 2), which wraps to 0, as in Simulink. Registers power up to 0.
//
// Built from c_to_ri, multiplier (bus_mult lane) and adder_subtractor
// (bus_addsub lane), which model the Xilinx Mult / AddSub arithmetic.
//
// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'casper_library_misc.slx/power'
// deviations = []
//
// [params.BIT_WIDTH]
// mask = 'BitWidth'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [params.ADD_LATENCY]
// mask = 'add_latency'
// type = 'edit'
//
// [params.MULT_LATENCY]
// mask = 'mult_latency'
// type = 'edit'
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// note = 'the output is dout because Verilator rejects a port named like its module'
// [ports.renamed]
// dout = 'power'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module power #(
    parameter int BIT_WIDTH    = 18,
    parameter int ADD_LATENCY  = 2,
    parameter int MULT_LATENCY = 3
)(
    input  logic                   clk,
    input  logic [2*BIT_WIDTH-1:0] c,
    output logic [2*BIT_WIDTH:0]   dout
);

    localparam int SQ_BITS = 2 * BIT_WIDTH;        // full-precision square
    localparam int SQ_BP   = 2 * (BIT_WIDTH - 1);

    logic [BIT_WIDTH-1:0] re, im;
    logic [SQ_BITS-1:0]   re_sq, im_sq;

    c_to_ri #(.N_BITS(BIT_WIDTH), .BIN_PT(BIT_WIDTH - 1)) u_c_to_ri (
        .c(c), .re(re), .im(im));

    multiplier #(
        .N_BITS_A(BIT_WIDTH), .BIN_PT_A(BIT_WIDTH - 1), .TYPE_A(1),
        .N_BITS_B(BIT_WIDTH), .BIN_PT_B(BIT_WIDTH - 1), .TYPE_B(1),
        .N_BITS_OUT(SQ_BITS), .BIN_PT_OUT(SQ_BP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
    ) u_real_square (.clk(clk), .a(re), .b(re), .dout(re_sq), .misco());

    multiplier #(
        .N_BITS_A(BIT_WIDTH), .BIN_PT_A(BIT_WIDTH - 1), .TYPE_A(1),
        .N_BITS_B(BIT_WIDTH), .BIN_PT_B(BIT_WIDTH - 1), .TYPE_B(1),
        .N_BITS_OUT(SQ_BITS), .BIN_PT_OUT(SQ_BP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
    ) u_imag_square (.clk(clk), .a(im), .b(im), .dout(im_sq), .misco());

    adder_subtractor #(
        .N_BITS_A(SQ_BITS), .BIN_PT_A(SQ_BP), .TYPE_A(1),
        .N_BITS_B(SQ_BITS), .BIN_PT_B(SQ_BP), .TYPE_B(1),
        .N_BITS_OUT(2 * BIT_WIDTH + 1), .BIN_PT_OUT(2 * BIT_WIDTH), .TYPE_OUT(0),
        .OPMODE(0), .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(ADD_LATENCY)
    ) u_power_adder (.clk(clk), .a(re_sq), .b(im_sq), .dout(dout), .misco(), .dvalid());

endmodule
