// pulse_ext — extend a rising-edge trigger into a fixed-length output pulse
//
// On each rising edge of 'in', the module asserts 'out' for exactly PULSE_LEN
// clock cycles (2-cycle latency: 1 from edge_detect + 1 from counter clear).
// A new rising edge during an active pulse resets the counter to 0, re-starting
// the full PULSE_LEN-cycle pulse from that point.
//
// NOTE: With INIT_VAL=0, the counter starts at 0 on power-on and immediately
// runs to PULSE_LEN before settling into the idle state.  In designs where a
// clean initial state is required, apply a system reset to 'in' or the
// upstream logic to suppress this power-on transient.
//
// Signal flow:
//
//   in ──► edge_detect ──► trig ──► counter.rst   (clears cnt to 0)
//                                                   │
//   constant(PULSE_LEN) ─────────────► relational.b │
//                                                   │
//   counter.dout ──────────────────► relational.a  │
//          ▲                              │          │
//          │                              ▼          │
//          └────── enable ◄── relational.out ──► out
//                             (cnt != PULSE_LEN)
//
// counter counts up freely; relational stops it (enable=0) once cnt reaches
// PULSE_LEN.  The same signal drives 'out'.

module pulse_ext #(
    parameter int PULSE_LEN = 4
)(
    input  logic clk,
    input  logic in,
    output logic out
);

    // Bit width needed to represent values 0..PULSE_LEN
    localparam int NBITS_CNT = $clog2(PULSE_LEN + 1);

    logic                 trig;
    logic [NBITS_CNT-1:0] const_val;
    logic [NBITS_CNT-1:0] cnt_out;

    // ── edge_detect ───────────────────────────────────────────────────────────
    // EDGE_TYPE=0 : detect rising edges only
    // OUTPUT_POL=0: active-high output
    // 'trig' is high for exactly one cycle after each rising edge of 'in'.
    // It is connected to counter.rst to clear the counter and restart the count.
    edge_detect #(
        .EDGE_TYPE (0),
        .OUTPUT_POL(0)
    ) u_edge_detect (
        .clk(clk),
        .din(in),
        .dout(trig)
    );

    // ── constant ──────────────────────────────────────────────────────────────
    // Outputs the fixed value PULSE_LEN on 'out'.
    // Connected to relational.b as the comparison reference:
    //   relational checks whether the counter has reached PULSE_LEN.
    constant #(
        .NBITS(NBITS_CNT),
        .VAL  (PULSE_LEN)
    ) u_constant (
        .out(const_val)
    );

    // ── counter ───────────────────────────────────────────────────────────────
    // COUNTER_TYPE=0 (free_running): counts up without a built-in limit;
    //   the enable signal from relational provides the stopping condition.
    // COUNT_DIR=0 (up): counts 0 → 1 → 2 → … → PULSE_LEN, then holds.
    // INIT_VAL=0: power-on value; counter starts at 0.
    // ENABLE_SYNC_RST=1: rst (from edge_detect) synchronously clears cnt to 0,
    //   restarting the pulse on each new rising edge of 'in'.
    // ENABLE_ENABLE=1: enable (from relational) gates counting;
    //   counting stops when cnt == PULSE_LEN (relational output goes low).
    counter #(
        .COUNTER_TYPE  (0),
        .NBITS         (NBITS_CNT),
        .COUNT_DIR     (0),
        .INIT_VAL      (0),
        .STEP          (1),
        .ENABLE_SYNC_RST(1),
        .ENABLE_ENABLE  (1)
    ) u_counter (
        .clk   (clk),
        .rst   (trig),
        .enable(out),
        .dout  (cnt_out)
    );

    // ── relational ────────────────────────────────────────────────────────────
    // COMP=1 (ne): output is 1 when a != b, i.e. when cnt != PULSE_LEN.
    // LATENCY=0: combinational — output changes the same cycle the counter
    //   value changes, with no additional pipeline delay.
    // The output serves two roles:
    //   1. Drives counter.enable: counter counts while cnt != PULSE_LEN;
    //      once cnt reaches PULSE_LEN the counter is gated off and holds.
    //   2. Is the module output 'out': high during the active pulse,
    //      low when the counter has reached PULSE_LEN (pulse complete).
    relational #(
        .NBITS  (NBITS_CNT),
        .COMP   (1),
        .LATENCY(0)
    ) u_relational (
        .clk(clk),
        .a  (cnt_out),
        .b  (const_val),
        .out(out)
    );

endmodule
