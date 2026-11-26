// negedge_delay — casper_library negedge_delay (casper_library_misc.slx,
// SID 77): stretches the falling edge of a level signal
//
//   bits = ceil(log2(PULSE_LEN+1))               (mask initialization)
//   ne   = edge_detect(din, Falling, Active High)
//   cnt  : Counter, free running, up, unsigned bits wide, start 0,
//          rst = ne, en = run
//   run  = (cnt <= PULSE_LEN-2)                  (Relational, latency 0)
//   dout = din | Delay(din, 1) | run             (Logical OR, latency 0)
//
// A falling edge at cycle t (din(t)=0, din(t-1)=1) keeps dout high through
// cycle t+PULSE_LEN-1: Delay(din) covers t, the restarted counter t+1 ..
// t+PULSE_LEN-1. Power-on: cnt starts at 0, so dout is high for the first
// PULSE_LEN-1 cycles whatever din does. While din stays high the counter
// sits at PULSE_LEN-1 (enable off).
//
// PULSE_LEN is the only mask parameter (stored default 5). The mask errors
// out for PULSE_LEN < 3 ("Minimum length is 3."); here that is a $fatal.
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
// block = 'casper_library_misc.slx/negedge_delay'
// deviations = []
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// din = 'in'
// dout = 'out'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module negedge_delay #(
    parameter int PULSE_LEN = 5
)(
    input  logic clk,
    input  logic din,
    output logic dout
);

    initial begin
        if (PULSE_LEN < 3)
            $fatal(1, "negedge_delay: minimum PULSE_LEN is 3 (got %0d)", PULSE_LEN);
    end

    localparam int NB = $clog2(PULSE_LEN + 1);

    logic          ne, din_d, run;
    logic [NB-1:0] cnt, run_max;

    edge_detect #(.EDGE(1), .POLARITY(0)) u_negedge (
        .clk(clk), .din(din), .dout(ne));

    counter #(
        .COUNTER_TYPE(0), .NBITS(NB), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_cnt (.clk(clk), .rst(ne), .enable(run), .dout(cnt));

    constant #(.NBITS(NB), .VAL(PULSE_LEN - 2)) u_max (.out(run_max));

    relational #(.NBITS(NB), .COMP(4), .LATENCY(0), .SIGNED(0)) u_le (
        .clk(clk), .a(cnt), .b(run_max), .out(run));

    delay #(.LATENCY(1), .BITWIDTH(1)) u_dly (.clk(clk), .din(din), .dout(din_d));

    logic [0:0] or_din [3];
    logic [0:0] or_dout;
    assign or_din[0] = din;
    assign or_din[1] = din_d;
    assign or_din[2] = run;
    logical #(.NBITS(1), .NINPUTS(3), .LATENCY(0), .FUNC(2)) u_or (
        .clk(clk), .din(or_din), .dout(or_dout));
    assign dout = or_dout[0];

endmodule
