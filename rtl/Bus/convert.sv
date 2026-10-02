// convert — fixed-point format converter (requantize / bit growth / overflow)
//
// Reinterprets 'din' as a fixed-point number of format
// (N_BITS_IN, BIN_PT_IN, TYPE_IN) and converts it to the output format
// (N_BITS_OUT, BIN_PT_OUT, TYPE_OUT). No arithmetic is performed other than
// the binary-point alignment, quantization of dropped LSBs and overflow
// handling of dropped MSBs. Corresponds to the Xilinx System Generator
// "Convert" block used by casper_library's bus_convert.
//
// Value of a word x with binary point B: real = int(x) * 2^-B, where int(x)
// is the two's-complement (TYPE=1) or unsigned (TYPE=0) interpretation.
//
// Encodings (shared by every fixed-point module in rtl/Bus/ and
// rtl/Multipliers/, and identical to the casper_library mask encodings):
//   TYPE_*       : 0 = unsigned, 1 = signed (two's complement)
//   QUANTIZATION : 0 = truncate (round toward -Inf, i.e. drop LSBs)
//                  1 = round half away from zero ("Round (unbiased: +/- Inf)")
//                  2 = round half to even        ("Round (unbiased: Even Values)")
//   OVERFLOW     : 0 = wrap (keep the low N_BITS_OUT bits)
//                  1 = saturate to the output range
//                  2 = "flag as error" in Simulink; not meaningful in HDL,
//                      treated as wrap
//
// BIN_PT_IN / BIN_PT_OUT may be negative or exceed the word width; only
// their difference matters for alignment.
//
// LATENCY: 0 = combinational, N > 0 = N pipeline stages built from
// BasicModules/register. Pipeline stages power up to 0.

module convert #(
    parameter int N_BITS_IN    = 16,
    parameter int BIN_PT_IN    = 8,
    parameter int TYPE_IN      = 1,
    parameter int N_BITS_OUT   = 8,
    parameter int BIN_PT_OUT   = 4,
    parameter int TYPE_OUT     = 1,
    parameter int QUANTIZATION = 0,
    parameter int OVERFLOW     = 0,
    parameter int LATENCY      = 0
)(
    input  logic                  clk,
    input  logic [N_BITS_IN-1:0]  din,
    output logic [N_BITS_OUT-1:0] dout
);

    // SHIFT > 0: drop SHIFT fractional LSBs (quantize)
    // SHIFT < 0: append -SHIFT zero LSBs (exact)
    localparam int SHIFT = BIN_PT_IN - BIN_PT_OUT;
    localparam int LSH   = (SHIFT < 0) ? -SHIFT : 0;
    localparam int RSH   = (SHIFT > 0) ?  SHIFT : 0;

    // Internal signed working width: holds the aligned input, the rounding
    // carry, the output range limits and the bit indexed at RSH, with guard
    // bits for the sign and the rounding carry.
    localparam int W0 = (N_BITS_IN + LSH > N_BITS_OUT) ? N_BITS_IN + LSH : N_BITS_OUT;
    localparam int W1 = (W0 > RSH) ? W0 : RSH;
    localparam int W  = W1 + 3;

    localparam logic signed [W-1:0] ONE  = 1;
    localparam logic signed [W-1:0] MAXV = (TYPE_OUT != 0) ? (ONE <<< (N_BITS_OUT - 1)) - ONE
                                                           : (ONE <<< N_BITS_OUT) - ONE;
    localparam logic signed [W-1:0] MINV = (TYPE_OUT != 0) ? -(ONE <<< (N_BITS_OUT - 1))
                                                           : '0;

    logic signed [W-1:0] x_ext;    // input, sign/zero extended
    logic signed [W-1:0] aligned;  // input with LSH zero LSBs appended
    logic signed [W-1:0] rnd;      // rounding offset added before the right shift
    logic signed [W-1:0] sum;
    logic signed [W-1:0] q;        // quantized value in output LSB units
    logic [N_BITS_OUT-1:0] result;

    // ── sign / zero extension ─────────────────────────────────────────────────
    generate
        if (TYPE_IN != 0) begin : GEN_SEXT
            assign x_ext = {{(W - N_BITS_IN){din[N_BITS_IN-1]}}, din};
        end else begin : GEN_ZEXT
            assign x_ext = {{(W - N_BITS_IN){1'b0}}, din};
        end
    endgenerate

    assign aligned = x_ext <<< LSH;

    // ── quantization ──────────────────────────────────────────────────────────
    // Arithmetic right shift is floor(); a rounding offset turns it into:
    //   round-to-inf  : floor(x/2^s + 1/2) for x >= 0, ceil(x/2^s - 1/2) for x < 0
    //                   -> offset = 2^(s-1) - (x < 0)
    //   round-to-even : offset = 2^(s-1) - 1 + (bit s of x)
    generate
        if (RSH == 0 || QUANTIZATION == 0) begin : GEN_TRUNC
            assign rnd = '0;
        end else if (QUANTIZATION == 1) begin : GEN_ROUND_INF
            assign rnd = (ONE <<< (RSH - 1)) - (aligned[W-1] ? ONE : '0);
        end else begin : GEN_ROUND_EVEN
            assign rnd = (ONE <<< (RSH - 1)) - ONE + (aligned[RSH] ? ONE : '0);
        end
    endgenerate

    assign sum = aligned + rnd;
    assign q   = sum >>> RSH;

    // ── overflow ──────────────────────────────────────────────────────────────
    generate
        if (OVERFLOW == 1) begin : GEN_SAT
            always_comb begin
                if      (q > MAXV) result = MAXV[N_BITS_OUT-1:0];
                else if (q < MINV) result = MINV[N_BITS_OUT-1:0];
                else               result = q[N_BITS_OUT-1:0];
            end
        end else begin : GEN_WRAP
            assign result = q[N_BITS_OUT-1:0];
        end
    endgenerate

    // ── optional output pipeline ──────────────────────────────────────────────
    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign dout = result;
        end else begin : GEN_PIPE
            logic [N_BITS_OUT-1:0] stage [0:LATENCY];
            assign stage[0] = result;
            for (genvar i = 0; i < LATENCY; i++) begin : GEN_STAGE
                register #(
                    .BITWIDTH  (N_BITS_OUT),
                    .USE_RST   (0),
                    .USE_ENABLE(0),
                    .INIT_VAL  (0)
                ) u_register (
                    .clk(clk),
                    .rst(1'b0),
                    .en (1'b1),
                    .d  (stage[i]),
                    .q  (stage[i+1])
                );
            end
            assign dout = stage[LATENCY];
        end
    endgenerate

endmodule
