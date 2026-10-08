// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Relational'
// deviations = [
//   'Simulink compares the real values of a and b of any two fixed-point types (different widths, binary points or mixed signed/unsigned are aligned first); the HDL requires one NBITS, an implicit common binary point and one SIGNED flag for both inputs.',
// ]
//
// [params.COMP]
// mask = 'mode'
// type = 'popup'
// [params.COMP.values]
// 0 = 'a=b'
// 1 = 'a!=b'
// 2 = 'a<b'
// 3 = 'a>b'
// 4 = 'a<=b'
// 5 = 'a>=b'
//
// [params.USE_ENABLE]
// mask = 'en'
// type = 'checkbox'
// [params.USE_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// NBITS = 'inherited width: Simulink takes it from the input signals'
// SIGNED = 'inherited signedness: Simulink takes it from the input types'
//
// [mask_missing]
// op_type = 'Bool vs Ufix_1_0 only changes the output type; the HDL bit is identical'
//
// [ports]
// order = 'Simulink: a, b, [en]; HDL: en, a, b'
// note = 'input labels a/b from the icon port_label; output name op from xlRelational.sgm (icon shows the comparison text)'
// [ports.renamed]
// out = 'op'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module relational #(
    parameter int NBITS   = 8,
    /* COMP: 0=eq, 1=ne, 2=lt, 3=gt, 4=le, 5=ge */
    parameter int COMP    = 0,
    /* SIGNED: 0 = a and b are unsigned, 1 = a and b are two's complement */
    parameter int SIGNED  = 0,
    /* LATENCY: 0 = combinational output, >=1 = pipeline stages */
    parameter int LATENCY = 1,
    /* USE_ENABLE: 1 = use the enable port en (Xilinx "Provide enable port"):
       en = 0 holds the pipeline registers; no effect when LATENCY = 0.
       en defaults to 1 and may be left unconnected when unused. */
    parameter int USE_ENABLE = 0
)(
    input  logic             clk,
    input  logic             en = 1'b1,
    input  logic [NBITS-1:0] a,
    input  logic [NBITS-1:0] b,
    output logic             out
);

    initial begin
        if (COMP < 0 || COMP > 5)
            $fatal(1, "Error: Invalid COMP = %0d. (0=eq,1=ne,2=lt,3=gt,4=le,5=ge)", COMP);
        if (SIGNED != 0 && SIGNED != 1)
            $fatal(1, "Error: Invalid SIGNED = %0d. (0=unsigned, 1=signed)", SIGNED);
    end

    logic result;

    // Sign-extend by one bit so one comparison covers both cases
    logic signed [NBITS:0] a_x, b_x;
    assign a_x = {(SIGNED != 0) & a[NBITS-1], a};
    assign b_x = {(SIGNED != 0) & b[NBITS-1], b};

    always_comb begin
        case (COMP)
            0: result = (a_x == b_x);
            1: result = (a_x != b_x);
            2: result = (a_x <  b_x);
            3: result = (a_x >  b_x);
            4: result = (a_x <= b_x);
            5: result = (a_x >= b_x);
            default: result = 1'b0;
        endcase
    end

    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign out = result;
        end else begin : GEN_PIPE
            // Power-on value is given as a declaration initializer and the loop
            // variable is local to the always_ff: newer Verilator rejects a
            // variable written by both an 'initial' process and an always_ff
            // (MULTIDRIVEN).
            logic shift_reg [0:LATENCY-1] = '{default: '0};
            always_ff @(posedge clk) if (USE_ENABLE == 0 || en) begin
                shift_reg[0] <= result;
                for (int k = 1; k < LATENCY; k = k + 1)
                    shift_reg[k] <= shift_reg[k-1];
            end
            assign out = shift_reg[LATENCY-1];
        end
    endgenerate

endmodule
