

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
// block = 'casper_library_flow_control.slx/bus_create'
// deviations = [
//   'Simulink reinterprets each input as unsigned with binary point 0 at its own width and concatenates them, so inputs may differ in width (bus_create_init.m Reinterpret + xbsIndex_r4/Concat). The HDL requires every input to be NBITS wide.',
// ]
//
// [hdl_only]
// NBITS = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
//
// [ports]
// order = 'din[i] is Simulink in{INPUT_NUM-i}: Simulink in1 is the MSB slot, HDL din[0] the LSB'
// [ports.renamed]
// din = 'in1..inN'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module bus_create #(
    parameter int NBITS     = 8,
    parameter int INPUT_NUM = 4
)(
    input  logic [NBITS-1:0] din [INPUT_NUM],
    output logic [(NBITS * INPUT_NUM)-1 : 0] bus_out
);

    always_comb begin
        for (int i = 0; i < INPUT_NUM; i++) begin
            bus_out[i * NBITS +: NBITS] = din[i];
        end
    end

endmodule