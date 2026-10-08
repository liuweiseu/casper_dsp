// cross_multiplier — casper_library cross multiplier (casper_library_correlator
// .slx, Block SID 71; cross_multiplier_init.m, whose function is misnamed
// refactor_storage_init)
//
// Multiplies every pair of input streams x <= y, conjugating the second,
// for each of the AGGREGATION complex samples packed in a stream word:
//
//   din[x] ─ bus_expand ─ c_to_ri ─┐  (per sub-stream s; sub-stream 0 = MSBs)
//   din[y] ─ bus_expand ─ c_to_ri ─┤
//        4 x Delay(1) (operand fan-out registers)
//        cmult_4bit_hdl* : real = ac + bd, imag = bc - ad  (a,b = x re,im;
//                          c,d = y re,im) = x * conj(y), Mult / AddSub Full
//                          precision, latency MULT + ADD -> Fix(2W+1, 2P)
//        convert_of (re, im) -> Fix(BIT_WIDTH_OUT, BINARY_POINT_OUT), QUANTISATION /
//                          OVERFLOW, latency CONV_LATENCY (overflow flag unused)
//        ri_to_c, bus_create ─ dout[k]
//   sync_out = Delay(sync_in, 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY)
//
// cmult_4bit_hdl* is implemented by cmult with CONJUGATED = 1 at full
// precision (N_BITS_AB = 2W+1, BIN_PT_AB = 2P, no input/convert latency),
// which is bit- and cycle-equivalent (see cmult.sv).
//
// Output k enumerates x = 0..STREAMS-1, y = x..STREAMS-1 in that order; in
// Simulink output "din{x}_x_din{y}*" is port sum_{j<x}(STREAMS-j) + (y-x) + 2
// (port 1 is sync_out), i.e. port k+2.
//
// Packing: din[x] holds AGGREGATION complex samples, sub-stream s at
// din[x][(AGGREGATION-s)*2W-1 -: 2W] (sub-stream 0 in the MSBs: bus_expand
// output 1 and bus_create input 1 are the MSB slice), each {re, im} with
// re in the upper W bits; dout[k] likewise with BIT_WIDTH_OUT-bit parts.
// The ports are packed arrays: din[x] is stream x, dout[k] output k.
//
// Parameters (mask names; defaults are the stored mask values except
// STREAMS): STREAMS, AGGREGATION 2, BIT_WIDTH_IN 4, BINARY_POINT_IN 3,
// BIT_WIDTH_OUT 9, BINARY_POINT_OUT 6, MULT_LATENCY 2, ADD_LATENCY 1,
// OVERFLOW 0 (Wrap; 1 Saturate, 2 Error = wrap in HDL), QUANTISATION 0
// (Truncate; 1 Round (unbiased: +/- Inf) = half away from zero, 2 Round
// (unbiased: even values) = half to even), CONV_LATENCY 0.
// The library stores streams = 0 (the init loops then build nothing but the
// sync delay) and cross_multiplier_init.m has no defaults, so STREAMS
// defaults to 2, the smallest value with a cross product; STREAMS < 1 is a
// $fatal.
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
// block = 'casper_library_correlator.slx/cross_multiplier'
// deviations = [
//   "OVERFLOW = 2 ('Error') wraps silently in the HDL. In Simulink cross_multiplier_init.m:161/166 passes 'Error' through convert_of (convert_of_init.m:108-127, USE_XILINX = 1) to a Xilinx Convert. Its overflow options are 'Wrap', 'Saturate' and 'Flag as error' (xbsIndex_r4.slx blockdiagram.xml), so Simulink either rejects the setting or flags each overflow as a simulation error. Neither one produces wrapped data.",
//   'Default STREAMS = 2, not the stored mask value 0 (empty shell). cross_multiplier_init.m has defaults = {}, and with streams = 0 Simulink builds only the sync delay. The HDL stops with a $fatal for STREAMS < 1.',
// ]
//
// [params.OVERFLOW]
// mask = 'overflow'
// type = 'popup'
// note = "HDL treats 2 ('Error') as Wrap; Simulink passes the text 'Error' verbatim through convert_of to an xbsIndex_r4 Convert whose options are only Wrap/Saturate/Flag as error"
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Error'
//
// [params.QUANTISATION]
// mask = 'quantisation'
// type = 'popup'
// [params.QUANTISATION.values]
// 0 = 'Truncate'
// 1 = 'Round  (unbiased: +/- Inf)'
// 2 = 'Round  (unbiased: even values)'
//
// [hdl_only]
// NOUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// note = 'dout[k] enumerates x = 0..STREAMS-1, y = x..STREAMS-1; Simulink port k+2'
// [ports.renamed]
// din = 'din0..din<STREAMS-1>'
// dout = 'din<x>_x_din<y>* (x <= y)'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module cross_multiplier #(
    parameter int STREAMS          = 2,
    parameter int AGGREGATION      = 2,
    parameter int BIT_WIDTH_IN     = 4,
    parameter int BINARY_POINT_IN  = 3,
    parameter int BIT_WIDTH_OUT    = 9,
    parameter int BINARY_POINT_OUT = 6,
    parameter int MULT_LATENCY     = 2,
    parameter int ADD_LATENCY      = 1,
    parameter int OVERFLOW         = 0,
    parameter int QUANTISATION     = 0,
    parameter int CONV_LATENCY     = 0,
    // derived; not to be overridden
    parameter int NOUT             = STREAMS * (STREAMS + 1) / 2
)(
    input  logic                                            clk,
    input  logic                                            sync_in,
    input  logic [STREAMS-1:0][AGGREGATION*2*BIT_WIDTH_IN-1:0]  din,
    output logic                                            sync_out,
    output logic [NOUT-1:0][AGGREGATION*2*BIT_WIDTH_OUT-1:0]    dout
);

    localparam int W  = BIT_WIDTH_IN;
    localparam int WO = BIT_WIDTH_OUT;
    localparam int A  = AGGREGATION;

    initial begin
        if (STREAMS < 1)
            $fatal(1, "cross_multiplier: STREAMS must be >= 1 (the library's stored 0 builds no multipliers)");
        if (AGGREGATION < 1)
            $fatal(1, "cross_multiplier: AGGREGATION must be >= 1");
        if (NOUT != STREAMS * (STREAMS + 1) / 2)
            $fatal(1, "cross_multiplier: NOUT is derived, do not override");
        if (QUANTISATION < 0 || QUANTISATION > 2 || OVERFLOW < 0 || OVERFLOW > 2)
            $fatal(1, "cross_multiplier: invalid QUANTISATION %0d / OVERFLOW %0d", QUANTISATION, OVERFLOW);
    end

    // ── sync ─────────────────────────────────────────────────────────────────
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY)) u_sync (
        .clk(clk), .din(sync_in), .dout(sync_out));

    // ── one conjugating multiplier per (x, y, sub-stream) ────────────────────
    for (genvar x = 0; x < STREAMS; x++) begin : GEN_X
        for (genvar y = x; y < STREAMS; y++) begin : GEN_Y
            // output index: sum_{j<x} (STREAMS - j) + (y - x)
            localparam int K = x * STREAMS - x * (x - 1) / 2 + (y - x);

            for (genvar s = 0; s < A; s++) begin : GEN_SUB
                logic [W-1:0]      xr, xi, yr, yi, xr_d, xi_d, yr_d, yi_d;
                logic [2*W:0]      p_re, p_im;
                logic [4*W+1:0]    prod;
                logic [WO-1:0]     o_re, o_im;

                c_to_ri #(.N_BITS(W), .BIN_PT(BINARY_POINT_IN)) u_c_to_ri_x (
                    .c(din[x][(A - s) * 2 * W - 1 -: 2 * W]), .re(xr), .im(xi));
                c_to_ri #(.N_BITS(W), .BIN_PT(BINARY_POINT_IN)) u_c_to_ri_y (
                    .c(din[y][(A - s) * 2 * W - 1 -: 2 * W]), .re(yr), .im(yi));

                // operand fan-out registers
                delay #(.LATENCY(1), .BITWIDTH(W)) u_d0 (.clk(clk), .din(xr), .dout(xr_d));
                delay #(.LATENCY(1), .BITWIDTH(W)) u_d1 (.clk(clk), .din(xi), .dout(xi_d));
                delay #(.LATENCY(1), .BITWIDTH(W)) u_d2 (.clk(clk), .din(yr), .dout(yr_d));
                delay #(.LATENCY(1), .BITWIDTH(W)) u_d3 (.clk(clk), .din(yi), .dout(yi_d));

                // cmult_4bit_hdl*: x * conj(y), full precision
                cmult #(
                    .N_BITS_A(W), .BIN_PT_A(BINARY_POINT_IN), .N_BITS_B(W), .BIN_PT_B(BINARY_POINT_IN),
                    .N_BITS_AB(2 * W + 1), .BIN_PT_AB(2 * BINARY_POINT_IN), .QUANTIZATION(0),
                    .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
                    .CONV_LATENCY(0), .IN_LATENCY(0), .CONJUGATED(1)
                ) u_cmult (.clk(clk), .a({xr_d, xi_d}), .b({yr_d, yi_d}), .ab(prod));

                assign {p_re, p_im} = prod;

                convert_of #(
                    .BIT_WIDTH_I(2 * W + 1), .BINARY_POINT_I(2 * BINARY_POINT_IN), .BIT_WIDTH_O(WO),
                    .BINARY_POINT_O(BINARY_POINT_OUT), .QUANTIZATION(QUANTISATION),
                    .OVERFLOW((OVERFLOW == 1) ? 1 : 0), .CSP_LATENCY(CONV_LATENCY)
                ) u_cvrt_real (.clk(clk), .din(p_re), .dout(o_re), .of());

                convert_of #(
                    .BIT_WIDTH_I(2 * W + 1), .BINARY_POINT_I(2 * BINARY_POINT_IN), .BIT_WIDTH_O(WO),
                    .BINARY_POINT_O(BINARY_POINT_OUT), .QUANTIZATION(QUANTISATION),
                    .OVERFLOW((OVERFLOW == 1) ? 1 : 0), .CSP_LATENCY(CONV_LATENCY)
                ) u_cvrt_imag (.clk(clk), .din(p_im), .dout(o_im), .of());

                ri_to_c #(.NBITS(WO)) u_ri_to_c (
                    .re(o_re), .im(o_im), .c(dout[K][(A - s) * 2 * WO - 1 -: 2 * WO]));
            end
        end
    end

endmodule
