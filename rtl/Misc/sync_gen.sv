// sync_gen — casper_library_misc/sync_gen: periodic / software sync pulse
//
// The block holds three software registers (swreg, From Processor, 32 bits).
// The HDL takes their values as input ports instead of the yellow blocks:
//   sync            (yellow block <sync_gen>/sync)            bit 0 used
//   sync_period_sel (yellow block <sync_gen>/sync_period_sel) bit 0 used
//   sync_period_var (yellow block <sync_gen>/sync_period_var) all 32 bits
// The registers are named <design>_<sync_gen path>_sync etc. in software;
// the wrapper that connects the ports keeps those names.
//
// Structure of the block (sync_gen_init.m sets the constant):
//   period_const = SCALE * SIM_ACC_LEN * PFB_FIR_TAPS * FFT_SIZE *
//                  lcm(REORDER_VEC) / FFT_SIMULT_INPUTS - 2   (Signed 32-bit)
//   Mux: sync_period_sel[0] = 0 -> period_const, 1 -> sync_period_var
//        (Full precision: Fix_33_0)
//   Relational a = b: Mux == Counter, latency 1
//   restart = Relational | rising edge of sync[0]
//   Counter: 32-bit free running, synchronous reset by restart
//   sync_out = rising edge of restart
// So with sync_period_sel = 0 sync_out pulses every period_const + 2 cycles
// (sync_period_var + 2 with sync_period_sel = 1), and a rising edge on
// sync[0] restarts the period with a pulse. sync_out is one cycle wide.
//
// REORDER_VEC is a packed vector of 32-bit elements, first element in the
// MSBs (as munge ORDER): {32'd2, 32'd2, 32'd9} is the mask vector [2 2 9].
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
// block = 'casper_library_misc.slx/sync_gen'
// deviations = [
//   'The three swreg yellow blocks (sync, sync_period_sel, sync_period_var) are not implemented: their register values are the input ports of the same names. In Simulink simulation they come from the swregs sim ports, which the block ties to constants (sync = 1, sync_period_sel = 0, sync_period_var = 0).',
//   'sync_gen_init.m writes num2str(period - 2) into a Signed 32-bit Constant; the HDL stops with $fatal when the period is not an integer or period - 2 does not fit in 32 signed bits.',
// ]
//
// [params.SIM_ACC_LEN]
// mask = 'sim_acc_len'
// type = 'edit'
//
// [params.FFT_SIZE]
// mask = 'fft_size'
// type = 'edit'
//
// [params.FFT_SIMULT_INPUTS]
// mask = 'fft_simult_inputs'
// type = 'edit'
//
// [params.PFB_FIR_TAPS]
// mask = 'pfb_fir_taps'
// type = 'edit'
//
// [params.REORDER_VEC]
// mask = 'reorder_vec'
// type = 'edit'
// note = "packed 32-bit elements, first in the MSBs: {32'd2, 32'd2, 32'd9} is the mask vector [2 2 9]"
//
// [params.SCALE]
// mask = 'scale'
// type = 'edit'
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// note = 'sync, sync_period_sel and sync_period_var are the swreg values (yellow blocks of those names inside the block, From Processor, 32 bits); Simulink has no input ports'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// sync = 'value of the swreg <block>/sync (From Processor)'
// sync_period_sel = 'value of the swreg <block>/sync_period_sel (From Processor)'
// sync_period_var = 'value of the swreg <block>/sync_period_var (From Processor)'
// @simulink-mapping end

module sync_gen #(
    parameter int SIM_ACC_LEN       = 2,
    parameter int FFT_SIZE          = 1024,
    parameter int FFT_SIMULT_INPUTS = 4,
    parameter int PFB_FIR_TAPS      = 4,
    parameter     REORDER_VEC       = {32'd2, 32'd2},
    parameter int SCALE             = 1
)(
    input  logic        clk,
    input  logic [31:0] sync,
    input  logic [31:0] sync_period_sel,
    input  logic [31:0] sync_period_var,
    output logic        sync_out
);

    localparam int REORDER_LEN = $bits(REORDER_VEC) / 32;

    function automatic longint gcd(input longint a, input longint b);
        while (b != 0) begin
            longint t = a % b;
            a = b;
            b = t;
        end
        return a;
    endfunction

    function automatic longint lcm_reorder();
        longint l = 1;
        for (int i = 0; i < REORDER_LEN; i++) begin
            longint v = longint'(REORDER_VEC[32*(REORDER_LEN-1-i) +: 32]);
            l = l / gcd(l, v) * v;
        end
        return l;
    endfunction

    localparam longint PERIOD_NUM = longint'(SCALE) * SIM_ACC_LEN * PFB_FIR_TAPS * FFT_SIZE * lcm_reorder();
    localparam longint PERIOD     = PERIOD_NUM / longint'(FFT_SIMULT_INPUTS);
    localparam longint CONST_VAL  = PERIOD - 2;

    initial
    begin
        if ($bits(REORDER_VEC) % 32 != 0 || REORDER_LEN < 1)
            $fatal(1, "sync_gen: REORDER_VEC must be packed 32-bit elements");
        for (int i = 0; i < REORDER_LEN; i++)
            if (REORDER_VEC[32*(REORDER_LEN-1-i) +: 32] < 1)
                $fatal(1, "sync_gen: REORDER_VEC element %0d must be positive", i);
        if (PFB_FIR_TAPS < 1)
            $fatal(1, "sync_gen: PFB_FIR_TAPS = %0d must be >= 1", PFB_FIR_TAPS);
        if (FFT_SIMULT_INPUTS < 1 || PERIOD_NUM % longint'(FFT_SIMULT_INPUTS) != 0)
            $fatal(1, "sync_gen: the sync period %0d / %0d is not an integer", PERIOD_NUM, FFT_SIMULT_INPUTS);
        if (CONST_VAL < -(64'sd1 <<< 31) || CONST_VAL > (64'sd1 <<< 31) - 1)
            $fatal(1, "sync_gen: sync period - 2 = %0d does not fit the Signed 32-bit constant", CONST_VAL);
    end

    logic [31:0] period_const;
    logic        sync_bit, sel_bit, sync_edge, eq, restart;
    logic [31:0] count;
    logic [32:0] mux_in [2];
    logic [32:0] period;

    constant #(.NBITS(32), .VAL(int'(CONST_VAL))) u_sync_period_const (.out(period_const));

    slice #(.NBITS(32), .START_BIT(0), .WIDTH(1)) u_sync_bit (.din(sync), .dout(sync_bit));
    slice #(.NBITS(32), .START_BIT(0), .WIDTH(1)) u_sel_bit  (.din(sync_period_sel), .dout(sel_bit));

    edge_detect #(.EDGE(0), .POLARITY(0)) u_posedge3 (.clk(clk), .din(sync_bit), .dout(sync_edge));

    // Full-precision Mux of Fix_32_0 and UFix_32_0: Fix_33_0
    assign mux_in = '{{period_const[31], period_const}, {1'b0, sync_period_var}};
    multiplexer #(.NBITS(33), .NINPUTS(2), .LATENCY(0)) u_mux (
        .clk(clk), .din(mux_in), .sel(sel_bit), .dout(period));

    relational #(.NBITS(33), .COMP(0), .SIGNED(1), .LATENCY(1)) u_relational (
        .clk(clk), .a(period), .b({1'b0, count}), .out(eq));

    logic or_in [2];
    assign or_in = '{eq, sync_edge};
    logical #(.NBITS(1), .NINPUTS(2), .LATENCY(0), .FUNC(2)) u_logical (
        .clk(clk), .din(or_in), .dout(restart));

    counter #(
        .COUNTER_TYPE(0), .NBITS(32), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0)
    ) u_counter3 (.clk(clk), .rst(restart), .enable(1'b1), .dout(count));

    edge_detect #(.EDGE(0), .POLARITY(0)) u_posedge1 (.clk(clk), .din(restart), .dout(sync_out));

endmodule
