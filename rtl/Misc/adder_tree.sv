// adder_tree — pipelined sum of N_INPUTS values
//
// Corresponds to casper_library's adder_tree (adder_tree_init.m, fixed
// point, dvalid_en off). The inputs are reduced pairwise, stage by stage,
// as adder_tree_init.m builds it:
//
//   cur_n = N_INPUTS
//   while cur_n > 1:
//       n_adds = floor(cur_n / 2), n_dlys = cur_n mod 2
//       node j < n_adds  = node 2j + node 2j+1 of the previous stage  (AddSub)
//       node n_adds      = node cur_n-1, delayed LATENCY           (if odd)
//       cur_n = n_adds + n_dlys
//
// STAGES = ceil(log2(N_INPUTS)) stages, each LATENCY cycles (csp_latency),
// so dout and sync_out come STAGES·LATENCY cycles after din / sync (a plain
// Delay for sync, as in casper). N_INPUTS = 1 wires din[0] to dout.
//
// Adder precision:
//   PRECISION = 0: Full — casper's AddSub default, which adder_tree_init.m
//                  does not change: every add grows one integer bit
//                  (binary point BIN_PT, type TYPE). dout has
//                  DATA_WIDTH + STAGES bits.
//   PRECISION = 1: User defined — every adder outputs N_BITS_OUT bits,
//                  binary point BIN_PT_OUT, signed, with QUANTIZATION /
//                  OVERFLOW, as pfb_fir_real_init.m sets the tree's addr*
//                  blocks (Truncate, Wrap there). Carried odd values keep
//                  their format until their next add. dout has N_BITS_OUT
//                  bits (DATA_WIDTH for N_INPUTS = 1).
//   N_BITS_OUT_EFF is dout's width.
//
// Declared for traceability only: FIRST_STAGE_HDL and ADDER_IMP (adder
// implementation choices) are ignored; DVALID_EN and FLOATING_POINT must be 0.

module adder_tree #(
    parameter int N_INPUTS        = 3,
    parameter int DATA_WIDTH      = 18,
    parameter int BIN_PT          = 0,
    parameter int TYPE            = 1,
    parameter int LATENCY         = 1,
    parameter int PRECISION       = 0,
    parameter int N_BITS_OUT      = 18,
    parameter int BIN_PT_OUT      = 0,
    parameter int QUANTIZATION    = 0,
    parameter int OVERFLOW        = 0,
    // declared, not implemented (see header)
    parameter int FIRST_STAGE_HDL = 0,
    parameter int ADDER_IMP       = 0,
    parameter int DVALID_EN       = 0,
    parameter int FLOATING_POINT  = 0,
    // derived (not meant to be overridden)
    parameter int N_BITS_OUT_EFF  = node_width(n_stages(N_INPUTS), 0)
)(
    input  logic                      clk,
    input  logic                      sync,
    input  logic [DATA_WIDTH-1:0]     din [N_INPUTS],
    output logic                      sync_out,
    output logic [N_BITS_OUT_EFF-1:0] dout
);

    // ── elaboration-time tree description ───────────────────────────────────
    function automatic int n_stages(int n);
        int s = 0;
        while ((1 << s) < n) s++;
        return s;
    endfunction

    // number of nodes after stage s (stage 0 = the inputs)
    function automatic int stage_n(int s);
        int c = N_INPUTS;
        for (int k = 0; k < s; k++) c = c / 2 + c % 2;
        return c;
    endfunction

    // node j of stage s: is it an input carried only through delays?
    function automatic bit is_leaf(int s, int j);
        int c, jj;
        jj = j;
        for (int k = s; k > 0; k--) begin
            c = stage_n(k - 1);
            if (jj < c / 2) return 0;     // an adder
            jj = c - 1;                   // the carried odd value
        end
        return 1;
    endfunction

    // integer bits of node j of stage s (PRECISION = 0)
    function automatic int full_int_bits(int s, int j);
        int a, b;
        if (s == 0) return DATA_WIDTH - BIN_PT;
        if (j < stage_n(s - 1) / 2) begin
            a = full_int_bits(s - 1, 2 * j);
            b = full_int_bits(s - 1, 2 * j + 1);
            return ((a > b) ? a : b) + 1;
        end
        return full_int_bits(s - 1, stage_n(s - 1) - 1);
    endfunction

    function automatic int node_width(int s, int j);
        if (PRECISION == 0) return full_int_bits(s, j) + BIN_PT;
        return is_leaf(s, j) ? DATA_WIDTH : N_BITS_OUT;
    endfunction

    function automatic int node_bin_pt(int s, int j);
        if (PRECISION == 0) return BIN_PT;
        return is_leaf(s, j) ? BIN_PT : BIN_PT_OUT;
    endfunction

    function automatic int node_type(int s, int j);
        if (PRECISION == 0) return TYPE;
        return is_leaf(s, j) ? TYPE : 1;
    endfunction

    localparam int STAGES = n_stages(N_INPUTS);
    localparam int WMAX   = DATA_WIDTH + N_BITS_OUT + STAGES;   // >= any node width

    if (DVALID_EN != 0)      $fatal(1, "adder_tree: DVALID_EN is not implemented");
    if (FLOATING_POINT != 0) $fatal(1, "adder_tree: FLOATING_POINT is not implemented");
    if (N_INPUTS < 1)        $fatal(1, "adder_tree: N_INPUTS must be >= 1");

    // sync: casper's sync_delay is a plain Delay of STAGES·LATENCY
    pipeline #(.BITWIDTH(1), .LATENCY(STAGES * LATENCY)) u_sync_delay (
        .clk(clk), .din(sync), .dout(sync_out));

    // node values, zero-extended to WMAX; each stage reads the previous one
    // by hierarchical reference
    for (genvar s = 0; s <= STAGES; s++) begin : GEN_STAGE
        localparam int CUR = stage_n(s);
        logic [WMAX-1:0] node [CUR];

        if (s == 0) begin : GEN_INPUTS
            for (genvar j = 0; j < CUR; j++) begin : GEN_IN
                assign node[j] = WMAX'(din[j]);
            end
        end else begin : GEN_REDUCE
            localparam int PREV   = stage_n(s - 1);
            localparam int N_ADDS = PREV / 2;

            for (genvar j = 0; j < CUR; j++) begin : GEN_NODE
                localparam int W  = node_width(s, j);
                logic [W-1:0] value;
                assign node[j] = WMAX'(value);

                if (j < N_ADDS) begin : GEN_ADD
                    localparam int WA = node_width(s - 1, 2 * j);
                    localparam int WB = node_width(s - 1, 2 * j + 1);
                    adder_subtractor #(
                        .N_BITS_A(WA), .BIN_PT_A(node_bin_pt(s - 1, 2 * j)),
                        .TYPE_A(node_type(s - 1, 2 * j)),
                        .N_BITS_B(WB), .BIN_PT_B(node_bin_pt(s - 1, 2 * j + 1)),
                        .TYPE_B(node_type(s - 1, 2 * j + 1)),
                        .N_BITS_OUT(W), .BIN_PT_OUT(node_bin_pt(s, j)), .TYPE_OUT(node_type(s, j)),
                        .OPMODE(0),
                        .QUANTIZATION((PRECISION == 0) ? 0 : QUANTIZATION),
                        .OVERFLOW((PRECISION == 0) ? 0 : OVERFLOW),
                        .LATENCY(LATENCY)
                    ) u_addr (
                        .clk(clk),
                        .a(GEN_STAGE[s-1].node[2 * j][WA-1:0]),
                        .b(GEN_STAGE[s-1].node[2 * j + 1][WB-1:0]),
                        .dout(value));
                end else begin : GEN_DLY
                    // the odd value of the previous stage, delayed
                    pipeline #(.BITWIDTH(W), .LATENCY(LATENCY)) u_dly (
                        .clk(clk), .din(GEN_STAGE[s-1].node[PREV - 1][W-1:0]), .dout(value));
                end
            end
        end
    end

    assign dout = GEN_STAGE[STAGES].node[0][N_BITS_OUT_EFF-1:0];

endmodule
