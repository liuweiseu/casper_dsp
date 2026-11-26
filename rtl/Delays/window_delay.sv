// window_delay — casper_library window_delay (casper_library_delays.slx,
// SID 240; no init script): delays a window (level) signal by DELAY cycles
// using two sync_delays instead of a DELAY-deep shift register
//
//   rise = edge_detect(din, Rising,  Active High)
//   fall = edge_detect(din, Falling, Active High)
//   r_d  = sync_delay(rise, DELAY-1)
//   f_d  = sync_delay(fall, DELAY-1)
//   dout : Register (init 0), d = r_d, en = r_d, rst = f_d
//
// A rising edge at cycle t sets dout from t+DELAY, a falling edge clears it
// from t+DELAY, so dout(t) = din(t-DELAY) as long as edges of the same kind
// are at least DELAY-1 cycles apart (each sync_delay pulse restarts its
// counter, only the last pulse in a window comes out). r_d and f_d are
// never high together (a rising and a falling edge cannot coincide), so the
// rst/en priority of the Xilinx Register does not matter.
//
// Power-on: the edge detectors' previous value is 0 (Simulink Delay init),
// so din = 1 from cycle 0 counts as a rising edge at cycle 0 and dout goes
// high at cycle DELAY.
//
// DELAY is the only mask parameter (stored default 10). The mask does not
// check it; DELAY < 1 would give sync_delay a negative length, so it is a
// $fatal here.
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
// block = 'casper_library_delays.slx/window_delay'
// deviations = [
//   "The library block contains four Gateway Out blocks with hdl_port = 'on' (240:2-240:5, on in, rise_d, fall_d and out) plus a Scope; in a Sysgen netlist these become extra top-level outputs, which the HDL does not have.",
//   "DELAY < 1 is a $fatal in the HDL; the mask prompt says 'desired delay (>2)' but nothing checks it.",
// ]
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// note = 'system_240.xml also contains 4 debug Gateway Out blocks (hdl_port = on) and a Scope; they are not modelled'
// [ports.renamed]
// din = 'in'
// dout = 'out'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module window_delay #(
    parameter int DELAY = 10
)(
    input  logic clk,
    input  logic din,
    output logic dout
);

    initial begin
        if (DELAY < 1)
            $fatal(1, "window_delay: DELAY must be >= 1 (got %0d)", DELAY);
    end

    logic rise, fall, rise_d, fall_d;

    edge_detect #(.EDGE(0), .POLARITY(0)) u_posedge (
        .clk(clk), .din(din), .dout(rise));
    edge_detect #(.EDGE(1), .POLARITY(0)) u_negedge (
        .clk(clk), .din(din), .dout(fall));

    sync_delay #(.DELAY_LEN(DELAY - 1)) u_rise_dly (.clk(clk), .din(rise), .dout(rise_d));
    sync_delay #(.DELAY_LEN(DELAY - 1)) u_fall_dly (.clk(clk), .din(fall), .dout(fall_d));

    register #(.BITWIDTH(1), .USE_RST(1), .USE_ENABLE(1), .INIT_VAL(0)) u_reg (
        .clk(clk), .rst(fall_d), .en(rise_d), .d(rise_d), .q(dout));

endmodule
