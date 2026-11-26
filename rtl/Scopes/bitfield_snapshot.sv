// bitfield_snapshot — casper_library_scopes/bitfield_snapshot (mask type
// bitsnap): a snapshot with typed input fields and input delays
//
// bitsnap_init.m builds: one Assert per io field (type check only), a
// bus_create of the fields, then pipelines of SNAP_DELAY registers on the
// data, we and trig, into a snapshot (casper_library_scopes/snapshot, here
// snapshot.sv) whose provide_outputs bitsnap_init.m always sets to 'off'.
// The block output arm_out is the snapshot's arm_out (ctrl bit 0).
//
// The HDL implements one io field (din, IO_WIDTH bits; Simulink port
// in_<io_name>). The snapshot's yellow blocks are ports, as in snapshot.sv:
// ctrl (swreg ctrl value), status (value into swreg status) and the
// shared_bram ports bram_addr / bram_data_in / bram_we / bram_data_out.
// Software names: <design>_<block>_ss_ctrl, _ss_status, _ss_bram (the
// snapshot inside is named ss).
//
// Latency from din / we / trig to the shared_bram ports: SNAP_DELAY + 2 for
// bram_data_in, SNAP_DELAY + 3 for a write (bram_we / bram_addr) caused by
// we, see snapshot.sv.
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
// block = 'casper_library_scopes.slx/bitfield_snapshot'
// deviations = [
//   'One io field only (io_names / io_widths / io_bps / io_types of length 1); the HDL takes its width as IO_WIDTH. Several fields would be concatenated by bus_create (first field in the MSBs) into the same data word.',
//   'The ctrl / status swregs and the bram shared_bram inside the snapshot are ports (see snapshot.sv). Only BRAM storage with snap_offset, snap_circap, snap_value, snap_ext_arm and snap_ext_circ off is implemented; the other options stop elaboration with $fatal (the mask defaults turn offset, circap and value on).',
//   'snap_provide_outputs has no effect: bitsnap_init.m always builds the snapshot with provide_outputs off.',
// ]
//
// [params.IO_WIDTH]
// mask = 'io_widths'
// type = 'edit'
// template = '[{IO_WIDTH}]'
//
// [params.SNAP_STORAGE]
// mask = 'snap_storage'
// type = 'popup'
// hdl_unsupported = [1]
// [params.SNAP_STORAGE.values]
// 0 = 'bram'
// 1 = 'dram'
//
// [params.SNAP_NSAMPLES]
// mask = 'snap_nsamples'
// type = 'edit'
//
// [params.SNAP_DATA_WIDTH]
// mask = 'snap_data_width'
// type = 'popup'
// [params.SNAP_DATA_WIDTH.values]
// 8 = '8'
// 16 = '16'
// 32 = '32'
// 64 = '64'
// 128 = '128'
//
// [params.SNAP_OFFSET]
// mask = 'snap_offset'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.SNAP_OFFSET.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SNAP_CIRCAP]
// mask = 'snap_circap'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.SNAP_CIRCAP.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SNAP_VALUE]
// mask = 'snap_value'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.SNAP_VALUE.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SNAP_EXT_ARM]
// mask = 'snap_ext_arm'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.SNAP_EXT_ARM.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SNAP_EXT_CIRC]
// mask = 'snap_ext_circ'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.SNAP_EXT_CIRC.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SNAP_PROVIDE_OUTPUTS]
// mask = 'snap_provide_outputs'
// type = 'checkbox'
// note = 'no effect (bitsnap_init.m builds the snapshot with provide_outputs off)'
// [params.SNAP_PROVIDE_OUTPUTS.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SNAP_USE_DSP48]
// mask = 'snap_use_dsp48'
// type = 'checkbox'
// note = 'implementation only; no effect on the behaviour'
// [params.SNAP_USE_DSP48.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SNAP_DELAY]
// mask = 'snap_delay'
// type = 'edit'
//
// [mask_set.io_names]
// value = '[d]'
//
// [mask_set.io_bps]
// value = '[0]'
//
// [mask_set.io_types]
// value = '[0]'
//
// [hdl_only]
//
// [mask_missing]
// show_format = 'display option only'
// snap_dram_dimm = 'DRAM storage not implemented'
// snap_dram_clock = 'DRAM storage not implemented'
// extra_names = 'used only with snap_value on (not implemented)'
// extra_widths = 'used only with snap_value on (not implemented)'
// extra_bps = 'used only with snap_value on (not implemented)'
// extra_types = 'used only with snap_value on (not implemented)'
//
// [ports]
// order = 'Simulink: in_<io_name>, we, trig -> arm_out; HDL: clk, din, we, trig, ctrl, bram_data_out -> status, bram_addr, bram_data_in, bram_we, arm_out'
// note = 'io_bps / io_types only set the Assert type check; the bits are the same'
// [ports.renamed]
// din = 'in_<io_name> (in_d for io_names = [d])'
// [ports.missing]
// [ports.extra]
// ctrl = 'value of the swreg <block>/ss/ctrl (From Processor, 32 bits)'
// status = 'value into the swreg <block>/ss/status (To Processor, 32 bits)'
// bram_addr = 'shared_bram <block>/ss/bram addr input'
// bram_data_in = 'shared_bram <block>/ss/bram data_in input'
// bram_we = 'shared_bram <block>/ss/bram we input'
// bram_data_out = 'shared_bram <block>/ss/bram data_out (unused)'
// @simulink-mapping end

module bitfield_snapshot #(
    parameter int IO_WIDTH             = 32,
    parameter int SNAP_STORAGE         = 0,     // 0 bram, 1 dram (not implemented)
    parameter int SNAP_NSAMPLES        = 10,
    parameter int SNAP_DATA_WIDTH      = 32,
    parameter int SNAP_OFFSET          = 0,
    parameter int SNAP_CIRCAP          = 0,
    parameter int SNAP_VALUE           = 0,
    parameter int SNAP_EXT_ARM         = 0,
    parameter int SNAP_EXT_CIRC        = 0,
    parameter int SNAP_PROVIDE_OUTPUTS = 0,
    parameter int SNAP_USE_DSP48       = 1,
    parameter int SNAP_DELAY           = 2
)(
    input  logic                       clk,
    input  logic [IO_WIDTH-1:0]        din,
    input  logic                       we,
    input  logic                       trig,
    input  logic [31:0]                ctrl,
    input  logic [SNAP_DATA_WIDTH-1:0] bram_data_out = '0,
    output logic [31:0]                status,
    output logic [SNAP_NSAMPLES-1:0]   bram_addr,
    output logic [SNAP_DATA_WIDTH-1:0] bram_data_in,
    output logic                       bram_we,
    output logic                       arm_out
);

    initial
        if (SNAP_DELAY < 0)
            $fatal(1, "bitfield_snapshot: SNAP_DELAY = %0d must not be negative", SNAP_DELAY);

    logic [IO_WIDTH-1:0] din_d;
    logic                we_d, trig_d;

    // io_delay / we_delay / trig_delay (bus_create of one field is the field)
    pipeline #(.BITWIDTH(IO_WIDTH), .CSP_LATENCY(SNAP_DELAY)) u_io_delay   (.clk(clk), .din(din),  .dout(din_d));
    pipeline #(.BITWIDTH(1),        .CSP_LATENCY(SNAP_DELAY)) u_we_delay   (.clk(clk), .din(we),   .dout(we_d));
    pipeline #(.BITWIDTH(1),        .CSP_LATENCY(SNAP_DELAY)) u_trig_delay (.clk(clk), .din(trig), .dout(trig_d));

    snapshot #(
        .STORAGE(SNAP_STORAGE), .NSAMPLES(SNAP_NSAMPLES), .DATA_WIDTH(SNAP_DATA_WIDTH),
        .OFFSET(SNAP_OFFSET), .CIRCAP(SNAP_CIRCAP), .VALUE(SNAP_VALUE), .EXT_ARM(SNAP_EXT_ARM),
        .EXT_CIRC(SNAP_EXT_CIRC), .PROVIDE_OUTPUTS(0), .USE_DSP48(SNAP_USE_DSP48), .IN_WIDTH(IO_WIDTH)
    ) u_ss (
        .clk(clk), .din(din_d), .we(we_d), .trig(trig_d), .ctrl(ctrl), .bram_data_out(bram_data_out),
        .status(status), .bram_addr(bram_addr), .bram_data_in(bram_data_in), .bram_we(bram_we),
        .arm_out(arm_out)
    );

endmodule
