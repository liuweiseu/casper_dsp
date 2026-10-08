// complex_multiplier — fixed-point complex multiply built from multiplier and
// adder_subtractor instances
//
// (dout_re + j*dout_im) = convert( (a_re + j*a_im) * (b_re + j*b_im) )
//
// a_re/a_im share one fixed-point format (N_BITS_A, BIN_PT_A, TYPE_A),
// b_re/b_im share (N_BITS_B, BIN_PT_B, TYPE_B), and dout_re/dout_im share the
// output format. All intermediate products and sums are kept at full
// precision (exact); the only requantization happens in the final
// adder_subtractor stage. MULT_SPEC=0 and MULT_SPEC=1 are therefore
// bit-identical and differ only in latency and resource usage.
//
// MULT_SPEC = 0 : 4-multiply form
//     re = a_re*b_re - a_im*b_im
//     im = a_re*b_im + a_im*b_re
//     latency = MULT_LATENCY + ADD_LATENCY
//
//     a_re,b_re ─► mult ─┐
//     a_im,b_im ─► mult ─┴► sub ─► dout_re
//     a_re,b_im ─► mult ─┐
//     a_im,b_re ─► mult ─┴► add ─► dout_im
//
// MULT_SPEC = 1 : 3-multiply (Karatsuba-style) form
//     k1 = b_re * (a_re + a_im)
//     k2 = a_re * (b_im - b_re)
//     k3 = a_im * (b_re + b_im)
//     re = k1 - k3
//     im = k1 + k2
//     latency = ADD_LATENCY + MULT_LATENCY + ADD_LATENCY
//     (the pre-adders use ADD_LATENCY; the operands bypassing them are
//      delay-matched with BasicModules/delay)
//
// Encodings (common to all fixed-point modules in rtl/Bus/ and
// rtl/Multipliers/):
//   TYPE_*       : 0 = unsigned, 1 = signed
//   QUANTIZATION : 0 = truncate, 1 = round half away from zero,
//                  2 = round half to even
//   OVERFLOW     : 0 = wrap, 1 = saturate (2 = flag as error -> wrap)
//   *_LATENCY    : 0 = combinational, N > 0 = N register stages
//
// The two latency parameters follow casper_library bus_mult's
// mult_latency / add_latency.
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
// block = 'xbsIndex_r4.slx/Complex Multiplier 6.0 '
// deviations = [
//   "No Simulink block is bit/cycle-equivalent: xbsIndex_r4/CMult is a constant multiplier (xlCmult.sgm: cmult(a, en, coef, ...)), and the closest complex block, 'Complex Multiplier 6.0 ' (cmpy IP, note the trailing space in the block name), is an AXI4-Stream core with a single latency setting. The HDL structure follows casper twiddle_general_4mult/3mult (docs/Multipliers/complex_multiplier.md) instead.",
//   'The IP truncates (or random-rounds) to the MSBs of the full-precision result and cannot overflow; the HDL requantizes in the final adder_subtractor to N_BITS_OUT/BIN_PT_OUT/TYPE_OUT with truncate/round-half-away/round-half-even and wrap/saturate (default QUANTIZATION = 2, OVERFLOW = 1).',
//   "OVERFLOW = 2 ('flag as error') is silently treated as wrap, not rejected (complex_multiplier.sv:38).",
//   'Latency is MULT_LATENCY + ADD_LATENCY (MULT_SPEC 0) or MULT_LATENCY + 2*ADD_LATENCY (MULT_SPEC 1), with power-on zero outputs; the IP latency is set by latencyconfig/minimumlatency and its output is qualified by dout_tvalid.',
// ]
//
// [params.MULT_SPEC]
// mask = 'optimizegoal'
// type = 'popup'
// note = 'closest analogue only: cmpy v6.0 with Use_Mults builds 4 multipliers for Performance and 3 for Resources'
// [params.MULT_SPEC.values]
// 0 = 'Performance'
// 1 = 'Resources'
//
// [params.N_BITS_OUT]
// mask = 'outputwidth'
// type = 'edit'
// note = 'the IP keeps the MSBs of the full-precision result; the HDL converts to N_BITS_OUT/BIN_PT_OUT with QUANTIZATION/OVERFLOW'
//
// [params.QUANTIZATION]
// mask = 'roundmode'
// type = 'popup'
// hdl_unsupported = [1, 2]
// note = "HDL 1 (round half away from zero) and 2 (round half to even) have no IP option; the IP's Random_Rounding has no HDL value"
// [params.QUANTIZATION.values]
// 0 = 'Truncate'
//
// [hdl_only]
// N_BITS_A = 'inherited from the a_tdata_real/imag input type in the IP'
// BIN_PT_A = 'inherited from the a_tdata_real/imag input type in the IP'
// TYPE_A = 'IP inputs are always signed'
// N_BITS_B = 'inherited from the b_tdata_real/imag input type in the IP'
// BIN_PT_B = 'inherited from the b_tdata_real/imag input type in the IP'
// TYPE_B = 'IP inputs are always signed'
// BIN_PT_OUT = 'IP output binary point follows from the MSB-aligned output width'
// TYPE_OUT = 'IP output is always signed'
// OVERFLOW = 'IP has no overflow handling (output is MSB-aligned, never overflows)'
// MULT_LATENCY = 'IP latency is a single value (latencyconfig / minimumlatency)'
// ADD_LATENCY = 'IP latency is a single value (latencyconfig / minimumlatency)'
//
// [mask_missing]
// hasatlast = 'AXI4-Stream side channels not implemented'
// hasatuser = 'AXI4-Stream side channels not implemented'
// atuserwidth = 'AXI4-Stream side channels not implemented'
// hasbtlast = 'AXI4-Stream side channels not implemented'
// hasbtuser = 'AXI4-Stream side channels not implemented'
// btuserwidth = 'AXI4-Stream side channels not implemented'
// hasctrltlast = 'AXI4-Stream side channels not implemented'
// hasctrltuser = 'AXI4-Stream side channels not implemented'
// ctrltuserwidth = 'AXI4-Stream side channels not implemented'
// outtlastbehv = 'AXI4-Stream side channels not implemented'
// multtype = 'resource choice only (HDL always uses multipliers)'
// flowcontrol = 'no AXI handshake: the HDL is always non-blocking'
// latencyconfig = 'latency is MULT_LATENCY/ADD_LATENCY in the HDL'
// minimumlatency = 'latency is MULT_LATENCY/ADD_LATENCY in the HDL'
// aclken = 'clock enable not implemented'
// aresetn = 'reset not implemented'
// trim_axipin_name = 'port naming only'
//
// [ports]
// order = 'Simulink (icon port_label): a_tvalid, a_tdata_imag, a_tdata_real, b_tvalid, b_tdata_imag, b_tdata_real -> dout_tvalid, dout_tdata_imag, dout_tdata_real (imag before real); HDL: a_re, a_im, b_re, b_im -> dout_re, dout_im'
// [ports.renamed]
// a_re = 'a_tdata_real'
// a_im = 'a_tdata_imag'
// b_re = 'b_tdata_real'
// b_im = 'b_tdata_imag'
// dout_re = 'dout_tdata_real'
// dout_im = 'dout_tdata_imag'
// [ports.missing]
// a_tvalid = 'AXI4-Stream handshake not implemented'
// b_tvalid = 'AXI4-Stream handshake not implemented'
// dout_tvalid = 'AXI4-Stream handshake not implemented'
// [ports.extra]
// @simulink-mapping end

module complex_multiplier #(
    parameter int N_BITS_A     = 18,
    parameter int BIN_PT_A     = 17,
    parameter int TYPE_A       = 1,
    parameter int N_BITS_B     = 18,
    parameter int BIN_PT_B     = 17,
    parameter int TYPE_B       = 1,
    parameter int N_BITS_OUT   = 18,
    parameter int BIN_PT_OUT   = 17,
    parameter int TYPE_OUT     = 1,
    parameter int QUANTIZATION = 2,
    parameter int OVERFLOW     = 1,
    parameter int MULT_SPEC    = 0,
    parameter int MULT_LATENCY = 3,
    parameter int ADD_LATENCY  = 2
)(
    input  logic                  clk,
    input  logic [N_BITS_A-1:0]   a_re,
    input  logic [N_BITS_A-1:0]   a_im,
    input  logic [N_BITS_B-1:0]   b_re,
    input  logic [N_BITS_B-1:0]   b_im,
    output logic [N_BITS_OUT-1:0] dout_re,
    output logic [N_BITS_OUT-1:0] dout_im
);

    // Total pipeline latency from inputs to outputs.
    localparam int LATENCY = (MULT_SPEC == 0) ? MULT_LATENCY + ADD_LATENCY
                                              : 2 * ADD_LATENCY + MULT_LATENCY;

    generate
        if (MULT_SPEC == 0) begin : GEN_4MULT

            // Full-precision product format of multiplier (A x B)
            localparam int N_BITS_P = N_BITS_A + N_BITS_B + 2;
            localparam int BIN_PT_P = BIN_PT_A + BIN_PT_B;

            logic [N_BITS_P-1:0] p_rr, p_ii, p_ri, p_ir;

            multiplier #(
                .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(TYPE_A),
                .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(TYPE_B),
                .N_BITS_OUT(N_BITS_P), .BIN_PT_OUT(BIN_PT_P), .TYPE_OUT(1),
                .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
            ) u_mult_rr (.clk(clk), .a(a_re), .b(b_re), .dout(p_rr));

            multiplier #(
                .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(TYPE_A),
                .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(TYPE_B),
                .N_BITS_OUT(N_BITS_P), .BIN_PT_OUT(BIN_PT_P), .TYPE_OUT(1),
                .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
            ) u_mult_ii (.clk(clk), .a(a_im), .b(b_im), .dout(p_ii));

            multiplier #(
                .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(TYPE_A),
                .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(TYPE_B),
                .N_BITS_OUT(N_BITS_P), .BIN_PT_OUT(BIN_PT_P), .TYPE_OUT(1),
                .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
            ) u_mult_ri (.clk(clk), .a(a_re), .b(b_im), .dout(p_ri));

            multiplier #(
                .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(TYPE_A),
                .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(TYPE_B),
                .N_BITS_OUT(N_BITS_P), .BIN_PT_OUT(BIN_PT_P), .TYPE_OUT(1),
                .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
            ) u_mult_ir (.clk(clk), .a(a_im), .b(b_re), .dout(p_ir));

            // re = p_rr - p_ii
            adder_subtractor #(
                .N_BITS_A(N_BITS_P), .BIN_PT_A(BIN_PT_P), .TYPE_A(1),
                .N_BITS_B(N_BITS_P), .BIN_PT_B(BIN_PT_P), .TYPE_B(1),
                .N_BITS_OUT(N_BITS_OUT), .BIN_PT_OUT(BIN_PT_OUT), .TYPE_OUT(TYPE_OUT),
                .OPMODE(1), .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
                .CSP_LATENCY(ADD_LATENCY)
            ) u_sub_re (.clk(clk), .a(p_rr), .b(p_ii), .dout(dout_re));

            // im = p_ri + p_ir
            adder_subtractor #(
                .N_BITS_A(N_BITS_P), .BIN_PT_A(BIN_PT_P), .TYPE_A(1),
                .N_BITS_B(N_BITS_P), .BIN_PT_B(BIN_PT_P), .TYPE_B(1),
                .N_BITS_OUT(N_BITS_OUT), .BIN_PT_OUT(BIN_PT_OUT), .TYPE_OUT(TYPE_OUT),
                .OPMODE(0), .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
                .CSP_LATENCY(ADD_LATENCY)
            ) u_add_im (.clk(clk), .a(p_ri), .b(p_ir), .dout(dout_im));

        end else begin : GEN_3MULT

            // Full-precision pre-adder formats (adder_subtractor full precision)
            localparam int N_BITS_SA = N_BITS_A + 2;   // a_re + a_im
            localparam int N_BITS_SB = N_BITS_B + 2;   // b_im - b_re, b_re + b_im
            // Full-precision product format: (N_BITS_B x N_BITS_SA) and
            // (N_BITS_A x N_BITS_SB) are both N_BITS_A + N_BITS_B + 4 bits
            localparam int N_BITS_K  = N_BITS_A + N_BITS_B + 4;
            localparam int BIN_PT_K  = BIN_PT_A + BIN_PT_B;

            logic [N_BITS_SA-1:0] s_a;       // a_re + a_im
            logic [N_BITS_SB-1:0] d_b;       // b_im - b_re
            logic [N_BITS_SB-1:0] s_b;       // b_re + b_im
            logic [N_BITS_A-1:0]  a_re_d, a_im_d;
            logic [N_BITS_B-1:0]  b_re_d;
            logic [N_BITS_K-1:0]  k1, k2, k3;

            // ── pre-adders (exact) ──────────────────────────────────────────
            adder_subtractor #(
                .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(TYPE_A),
                .N_BITS_B(N_BITS_A), .BIN_PT_B(BIN_PT_A), .TYPE_B(TYPE_A),
                .N_BITS_OUT(N_BITS_SA), .BIN_PT_OUT(BIN_PT_A), .TYPE_OUT(1),
                .OPMODE(0), .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(ADD_LATENCY)
            ) u_pre_sa (.clk(clk), .a(a_re), .b(a_im), .dout(s_a));

            adder_subtractor #(
                .N_BITS_A(N_BITS_B), .BIN_PT_A(BIN_PT_B), .TYPE_A(TYPE_B),
                .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(TYPE_B),
                .N_BITS_OUT(N_BITS_SB), .BIN_PT_OUT(BIN_PT_B), .TYPE_OUT(1),
                .OPMODE(1), .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(ADD_LATENCY)
            ) u_pre_db (.clk(clk), .a(b_im), .b(b_re), .dout(d_b));

            adder_subtractor #(
                .N_BITS_A(N_BITS_B), .BIN_PT_A(BIN_PT_B), .TYPE_A(TYPE_B),
                .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(TYPE_B),
                .N_BITS_OUT(N_BITS_SB), .BIN_PT_OUT(BIN_PT_B), .TYPE_OUT(1),
                .OPMODE(0), .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(ADD_LATENCY)
            ) u_pre_sb (.clk(clk), .a(b_re), .b(b_im), .dout(s_b));

            // ── delay-match the operands that bypass the pre-adders ─────────
            if (ADD_LATENCY == 0) begin : GEN_NO_DLY
                assign a_re_d = a_re;
                assign a_im_d = a_im;
                assign b_re_d = b_re;
            end else begin : GEN_DLY
                delay #(.LATENCY(ADD_LATENCY), .BITWIDTH(N_BITS_A))
                    u_dly_a_re (.clk(clk), .din(a_re), .dout(a_re_d));
                delay #(.LATENCY(ADD_LATENCY), .BITWIDTH(N_BITS_A))
                    u_dly_a_im (.clk(clk), .din(a_im), .dout(a_im_d));
                delay #(.LATENCY(ADD_LATENCY), .BITWIDTH(N_BITS_B))
                    u_dly_b_re (.clk(clk), .din(b_re), .dout(b_re_d));
            end

            // ── three full-precision multiplies ─────────────────────────────
            multiplier #(
                .N_BITS_A(N_BITS_B),  .BIN_PT_A(BIN_PT_B), .TYPE_A(TYPE_B),
                .N_BITS_B(N_BITS_SA), .BIN_PT_B(BIN_PT_A), .TYPE_B(1),
                .N_BITS_OUT(N_BITS_K), .BIN_PT_OUT(BIN_PT_K), .TYPE_OUT(1),
                .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
            ) u_mult_k1 (.clk(clk), .a(b_re_d), .b(s_a), .dout(k1));

            multiplier #(
                .N_BITS_A(N_BITS_A),  .BIN_PT_A(BIN_PT_A), .TYPE_A(TYPE_A),
                .N_BITS_B(N_BITS_SB), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
                .N_BITS_OUT(N_BITS_K), .BIN_PT_OUT(BIN_PT_K), .TYPE_OUT(1),
                .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
            ) u_mult_k2 (.clk(clk), .a(a_re_d), .b(d_b), .dout(k2));

            multiplier #(
                .N_BITS_A(N_BITS_A),  .BIN_PT_A(BIN_PT_A), .TYPE_A(TYPE_A),
                .N_BITS_B(N_BITS_SB), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
                .N_BITS_OUT(N_BITS_K), .BIN_PT_OUT(BIN_PT_K), .TYPE_OUT(1),
                .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
            ) u_mult_k3 (.clk(clk), .a(a_im_d), .b(s_b), .dout(k3));

            // ── post-adders with output requantization ──────────────────────
            // re = k1 - k3
            adder_subtractor #(
                .N_BITS_A(N_BITS_K), .BIN_PT_A(BIN_PT_K), .TYPE_A(1),
                .N_BITS_B(N_BITS_K), .BIN_PT_B(BIN_PT_K), .TYPE_B(1),
                .N_BITS_OUT(N_BITS_OUT), .BIN_PT_OUT(BIN_PT_OUT), .TYPE_OUT(TYPE_OUT),
                .OPMODE(1), .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
                .CSP_LATENCY(ADD_LATENCY)
            ) u_sub_re (.clk(clk), .a(k1), .b(k3), .dout(dout_re));

            // im = k1 + k2
            adder_subtractor #(
                .N_BITS_A(N_BITS_K), .BIN_PT_A(BIN_PT_K), .TYPE_A(1),
                .N_BITS_B(N_BITS_K), .BIN_PT_B(BIN_PT_K), .TYPE_B(1),
                .N_BITS_OUT(N_BITS_OUT), .BIN_PT_OUT(BIN_PT_OUT), .TYPE_OUT(TYPE_OUT),
                .OPMODE(0), .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
                .CSP_LATENCY(ADD_LATENCY)
            ) u_add_im (.clk(clk), .a(k1), .b(k2), .dout(dout_im));

        end
    endgenerate

endmodule
