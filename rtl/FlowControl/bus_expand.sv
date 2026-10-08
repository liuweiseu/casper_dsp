

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
// block = 'casper_library_flow_control.slx/bus_expand'
// deviations = [
//   "Simulink slices from the MSB of bus_in: each Slice uses 'Upper Bit Location + Width', base 'MSB of Input', bit1 = -acc_bits (bus_expand_init.m:171-173). If bus_in is wider than OUTPUT_NUM*OUTPUT_WIDTH, Simulink ignores the extra LSBs. The HDL fixes the bus_in width at OUTPUT_NUM*OUTPUT_WIDTH.",
//   "Simulink's outputs are typed (outputArithmeticType 0=unsigned, 1=signed, 2=Boolean; outputBinaryPt). Type 9 discards that slice and drops its port (bus_expand_init.m:150-158). The HDL outputs raw bit slices and supports only 'divisions of equal size'; the bit values are identical.",
// ]
//
// [hdl_only]
//
// [mask_missing]
// mode = "only 'divisions of equal size' is supported"
// outputBinaryPt = 'outputs are raw bit slices (no binary point)'
// outputArithmeticType = 'outputs are raw bit slices (no arithmetic type)'
// show_format = 'display option only'
// outputToWorkspace = 'workspace option only'
// variablePrefix = 'workspace option only'
// outputToModelAsWell = 'workspace option only (with outputToWorkspace=on and this off, Simulink creates no output ports)'
//
// [ports]
// order = 'bus_out[i] is the LSB-first slice i, i.e. Simulink out{i+1} = port OUTPUT_NUM-i'
// [ports.renamed]
// bus_out = 'lsb_out1, out2, ..., msb_outN'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module bus_expand #(
    parameter int OUTPUT_NUM = 4,
    parameter int OUTPUT_WIDTH = 8
)(
    input  logic [OUTPUT_NUM*OUTPUT_WIDTH - 1:0] bus_in,
    output logic [OUTPUT_WIDTH-1:0]        bus_out [OUTPUT_NUM]
);

// genvar i;
// generate
//     for (i = 0; i < OUTPUT_NUM; i++) begin : GEN_EXPAND
//         assign bus_out[i] = bus_in[i*OUTPUT_WIDTH +: OUTPUT_WIDTH];
//     end
// endgenerate

// TODO: We need to support divisions of arbitrary size
genvar i;
generate
    for (i = 0; i < OUTPUT_NUM; i++) begin : GEN_EXPAND
        slice #(
            .NBITS(OUTPUT_NUM*OUTPUT_WIDTH),
            .START_BIT(i*OUTPUT_WIDTH),
            .WIDTH(OUTPUT_WIDTH)
        ) u_slice (
            .din(bus_in),
            .dout(bus_out[i])
        );
    end
endgenerate

endmodule