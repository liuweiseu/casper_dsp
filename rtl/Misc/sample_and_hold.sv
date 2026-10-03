// sample_and_hold — casper_library sample_and_hold (casper_library_misc.slx,
// SID 158; the block has no init script, the diagram is stored as is)
//
//   cnt : Counter, free running, unsigned ceil(log2(PERIOD)) bits, start 0,
//         rst = clr
//   clr = (cnt >= PERIOD-1) | sync                 (Relational / Logical, latency 0)
//   out : Register (init 0, no rst), d = in, en = Delay(clr, 1)
//
// The register loads in one cycle after clr: a sync at cycle t (or the
// counter reaching PERIOD-1 at t) makes out show in(t+1) from cycle t+2 on.
// Without sync it resamples every PERIOD cycles; a sync restarts the period.
//
// Parameters: PERIOD is the mask parameter (default 1024, the stored mask
// value). BITWIDTH is not a mask parameter: in Simulink the width of in/out
// is inherited from the input, here it must be given. PERIOD must be >= 2
// (PERIOD = 1 would give a 0-bit counter, which Sysgen rejects).

module sample_and_hold #(
    parameter int PERIOD   = 1024,
    parameter int BITWIDTH = 32
)(
    input  logic                clk,
    input  logic                sync,
    input  logic [BITWIDTH-1:0] din,
    output logic [BITWIDTH-1:0] dout
);

    initial begin
        if (PERIOD < 2)
            $fatal(1, "sample_and_hold: PERIOD must be >= 2 (got %0d)", PERIOD);
    end

    localparam int NB = $clog2(PERIOD);

    logic [NB-1:0] cnt, last_val;
    logic          at_end, clr, clr_d;

    counter #(
        .COUNTER_TYPE(0), .NBITS(NB), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0), .RST_VAL(0)
    ) u_cnt (.clk(clk), .rst(clr), .enable(1'b1), .dout(cnt));

    constant #(.NBITS(NB), .VAL(PERIOD - 1)) u_last (.out(last_val));

    relational #(.NBITS(NB), .COMP(5), .LATENCY(0), .SIGNED(0)) u_ge (
        .clk(clk), .a(cnt), .b(last_val), .out(at_end));

    logic [0:0] or_din [2];
    logic [0:0] or_dout;
    assign or_din[0] = at_end;
    assign or_din[1] = sync;
    logical #(.NBITS(1), .NINPUTS(2), .LATENCY(0), .FUNC(2)) u_or (
        .clk(clk), .din(or_din), .dout(or_dout));
    assign clr = or_dout[0];

    delay #(.LATENCY(1), .BITWIDTH(1)) u_en_dly (.clk(clk), .din(clr), .dout(clr_d));

    register #(.BITWIDTH(BITWIDTH), .USE_RST(0), .USE_ENABLE(1), .INIT_VAL(0)) u_reg (
        .clk(clk), .rst(1'b0), .en(clr_d), .d(din), .q(dout));

endmodule
