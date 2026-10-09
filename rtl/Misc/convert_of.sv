// convert_of — fixed-point convert with an overflow indication
//
// dout is exactly rtl/Bus/convert's output (signed in, signed out). of flags
// that the integer part of din does not fit the output format, using
// casper_library's convert_of rule (convert_of_init.m): with
//
//   wb_lost = (BIT_WIDTH_I - BINARY_POINT_I) - (BIT_WIDTH_O - BINARY_POINT_O)
//
// integer bits dropped, of = 1 when the top wb_lost+1 bits of din are not
// all equal (neither all 0 nor all 1), i.e. din is not a sign extension of a
// value that fits. The check looks at din only: a carry out of the rounding
// step (e.g. rounding the largest value up) is not flagged, as in
// casper_library. wb_lost <= 0 means overflow is impossible: of = 0.
// of and dout have the same CSP_LATENCY (pipeline stages power up to 0).
//
// Encodings as rtl/Bus/convert: QUANTIZATION 0=truncate, 1=round half away
// from zero, 2=round half to even; OVERFLOW 0=wrap, 1=saturate.
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
// block = 'casper_library_misc.slx/convert_of'
// deviations = [
//   "OVERFLOW=2: convert_of_init.m:124 passes the popup text 'Error' to xbsIndex_r4/Convert, whose options are Wrap/Saturate/'Flag as error', so the Simulink block cannot be built with it. The HDL treats 2 as wrap.",
//   "QUANTIZATION=2: the popup text 'Round  (unbiased: even values)' is passed verbatim to xbsIndex_r4/Convert, whose option is 'Round  (unbiased: Even Values)' (convert_of_init.m:123). Whether set_param accepts the case mismatch is unverified. The HDL rounds half to even.",
//   "The HDL assumes a signed input (TYPE_IN=1 on the inner convert). Simulink's Convert uses the input signal's actual type, so an unsigned din is zero-extended there, but the HDL sign-extends it. The of check treats the MSB as a sign bit in both.",
//   'When wb_lost+1 > BIT_WIDTH_I, the HDL clips the checked bit count to BIT_WIDTH_I. Simulink would create Slice blocks reaching above the MSB and fail to elaborate.',
// ]
//
// [params.QUANTIZATION]
// mask = 'quantization'
// type = 'popup'
// note = "option 2's case differs from xbsIndex_r4/Convert's 'Round  (unbiased: Even Values)', to which convert_of_init.m:123 passes it verbatim"
// [params.QUANTIZATION.values]
// 0 = 'Truncate'
// 1 = 'Round  (unbiased: +/- Inf)'
// 2 = 'Round  (unbiased: even values)'
//
// [params.OVERFLOW]
// mask = 'overflow'
// type = 'popup'
// note = "HDL OVERFLOW = 2 wraps (rtl/Bus/convert.sv:137 saturates only for 1), so it is exported as 'Wrap'; the mask's 'Error'/'Flag as error' option does not build or would flag instead of wrapping"
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Wrap'
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module convert_of #(
    parameter int BIT_WIDTH_I    = 16,
    parameter int BINARY_POINT_I = 8,
    parameter int BIT_WIDTH_O    = 8,
    parameter int BINARY_POINT_O = 4,
    parameter int QUANTIZATION   = 0,
    parameter int OVERFLOW       = 0,
    parameter int CSP_LATENCY    = 0
)(
    input  logic                  clk,
    input  logic [BIT_WIDTH_I-1:0]  din,
    output logic [BIT_WIDTH_O-1:0] dout,
    output logic                  of
);

    localparam int WB_LOST = (BIT_WIDTH_I - BINARY_POINT_I) - (BIT_WIDTH_O - BINARY_POINT_O);
    // number of top bits checked, clipped to the input width
    localparam int N_TOP   = (WB_LOST + 1 > BIT_WIDTH_I) ? BIT_WIDTH_I : WB_LOST + 1;

    convert #(
        .N_BITS_IN (BIT_WIDTH_I),  .BIN_PT_IN (BINARY_POINT_I),  .TYPE_IN (1),
        .N_BITS_OUT(BIT_WIDTH_O), .BIN_PT_OUT(BINARY_POINT_O), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CSP_LATENCY)
    ) u_convert (
        .clk (clk),
        .din (din),
        .dout(dout)
    );

    logic of_raw;

    generate
        if (WB_LOST <= 0) begin : GEN_NEVER
            assign of_raw = 1'b0;
        end else begin : GEN_CHECK
            logic [N_TOP-1:0] top;
            assign top    = din[BIT_WIDTH_I-1 -: N_TOP];
            assign of_raw = !((&top) || !(|top));
        end
    endgenerate

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(CSP_LATENCY)) u_of_dly (
        .clk(clk), .din(of_raw), .dout(of));

endmodule
