// tb_xilinx_equiv — PLATFORM="XILINX" vs PLATFORM="GENERIC" equivalence check
//
// Instantiates single_port_ram, dual_port_ram, rom and delay_bram twice —
// once with the GENERIC (behavioral) implementation, which the Verilator /
// cocotb flow verifies against golden data, and once with the XILINX (XPM)
// implementation — drives both copies with the same random stimulus and
// compares every output on every clock cycle.
//
// Needs Vivado's simulator (xsim) and the XPM sources; see
// run_xsim_equiv.sh. Not part of the Docker / cocotb test matrix.
//
// dual_port_ram stimulus never creates a cross-port collision (same address
// on both ports with a write), which the dual_port_ram contract leaves
// undefined. Same-port read-during-write happens on every write.

`timescale 1ns / 1ps

module tb_xilinx_equiv #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter int    DELAY_LEN  = 16,
    parameter int    CYCLES     = 2000,
    parameter string INIT_FILE  = ""
);

    localparam int AW = ADDR_WIDTH;
    localparam int DW = DATA_WIDTH;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    // ── stimulus ─────────────────────────────────────────────────────────────
    logic          we   = 1'b0, we_a = 1'b0, we_b = 1'b0;
    logic [AW-1:0] addr = '0, addr_a = '0, addr_b = '0, rom_addr = '0;
    logic [DW-1:0] din  = '0, din_a = '0, din_b = '0, dly_din = '0;

    // ── DUT pairs ────────────────────────────────────────────────────────────
    logic [DW-1:0] sp_g, sp_x, dpa_g, dpa_x, dpb_g, dpb_x, rom_g, rom_x, dly_g, dly_x;

    single_port_ram #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .PLATFORM("GENERIC")) u_sp_g
        (.clk(clk), .we(we), .addr(addr), .din(din), .dout(sp_g));
    single_port_ram #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .PLATFORM("XILINX")) u_sp_x
        (.clk(clk), .we(we), .addr(addr), .din(din), .dout(sp_x));

    dual_port_ram #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .PLATFORM("GENERIC")) u_dp_g
        (.clk(clk), .we_a(we_a), .addr_a(addr_a), .din_a(din_a), .dout_a(dpa_g),
                    .we_b(we_b), .addr_b(addr_b), .din_b(din_b), .dout_b(dpb_g));
    dual_port_ram #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .PLATFORM("XILINX")) u_dp_x
        (.clk(clk), .we_a(we_a), .addr_a(addr_a), .din_a(din_a), .dout_a(dpa_x),
                    .we_b(we_b), .addr_b(addr_b), .din_b(din_b), .dout_b(dpb_x));

    rom #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .INIT_FILE(INIT_FILE), .PLATFORM("GENERIC")) u_rom_g
        (.clk(clk), .addr(rom_addr), .dout(rom_g));
    rom #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .INIT_FILE(INIT_FILE), .PLATFORM("XILINX")) u_rom_x
        (.clk(clk), .addr(rom_addr), .dout(rom_x));

    delay_bram #(.BITWIDTH(DW), .DELAY_LEN(DELAY_LEN), .PLATFORM("GENERIC")) u_dly_g
        (.clk(clk), .din(dly_din), .dout(dly_g));
    delay_bram #(.BITWIDTH(DW), .DELAY_LEN(DELAY_LEN), .PLATFORM("XILINX")) u_dly_x
        (.clk(clk), .din(dly_din), .dout(dly_x));

    // ── compare / drive ─────────────────────────────────────────────────────
    int errors = 0;
    int writes_sp = 0, writes_dp = 0;

    function automatic logic [DW-1:0] rand_word();
        return DW'({$urandom, $urandom});
    endfunction

    task automatic check(string name, logic [DW-1:0] g, logic [DW-1:0] x, int cyc);
        if (g !== x) begin
            errors++;
            if (errors <= 20)
                $display("MISMATCH cycle %0d %s: GENERIC=%h XILINX=%h", cyc, name, g, x);
        end
    endtask

    initial begin
        for (int cyc = 0; cyc < CYCLES; cyc++) begin
            @(negedge clk);
            // outputs changed at the previous posedge; compare before driving
            check("single_port_ram.dout", sp_g,  sp_x,  cyc);
            check("dual_port_ram.dout_a", dpa_g, dpa_x, cyc);
            check("dual_port_ram.dout_b", dpb_g, dpb_x, cyc);
            check("rom.dout",             rom_g, rom_x, cyc);
            check("delay_bram.dout",      dly_g, dly_x, cyc);

            // single_port_ram: write-heavy first half, then 25 % writes
            we   = (cyc < CYCLES / 2) ? ($urandom_range(3) != 0) : ($urandom_range(3) == 0);
            addr = AW'($urandom);
            din  = rand_word();
            writes_sp += we;

            // dual_port_ram: independent random ports, no cross-port collision
            we_a   = $urandom_range(1);
            we_b   = $urandom_range(1);
            addr_a = AW'($urandom);
            addr_b = AW'($urandom);
            if (addr_a == addr_b && (we_a || we_b)) addr_b = addr_a + 1'b1;
            din_a  = rand_word();
            din_b  = rand_word();
            writes_dp += we_a + we_b;

            rom_addr = AW'($urandom);
            dly_din  = rand_word();
        end
        $display("RESULT DATA_WIDTH=%0d ADDR_WIDTH=%0d DELAY_LEN=%0d CYCLES=%0d writes(sp=%0d dp=%0d) errors=%0d",
                 DW, AW, DELAY_LEN, CYCLES, writes_sp, writes_dp, errors);
        if (errors == 0) $display("EQUIV_PASS");
        else             $display("EQUIV_FAIL");
        $finish;
    end

endmodule
