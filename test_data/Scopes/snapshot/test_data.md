# snapshot test data

Each subdirectory corresponds to one parameter set. These are bitfield_snapshot sets 1 to 4 seen from the snapshot inside: `din`, `we` and `trig` are the bitfield_snapshot inputs delayed by its `SNAP_DELAY` pipelines (what the snapshot received in Simulink), the other signals are the same. Signals: `sim_din.csv`, `sim_we.csv`, `sim_trig.csv` and `sim_ctrl.csv` (the value of the snapshot's ctrl swreg); expected outputs: `sim_status.csv` (the value written into the status swreg), `sim_bram_addr.csv`, `sim_bram_data_in.csv`, `sim_bram_we.csv` (the snapshot's shared_bram inputs) and `sim_arm_out.csv`, one value per cycle. `din` and `we` (70 % high) are random. `ctrl` arms a capture again and again, cycling through the settings `0b111` (trigger and write at once), `0b001` (wait for `trig`, write on `we`), `0b011`, `0b101` and `0b1001` (circular bit, no effect without circap): each arm clears bit 0 for 3 cycles, then sets it for long enough to fill the buffer or not; `trig` pulses before and during each arm.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: exported on 2026-10-28 in this repository's session from Simulink models of `casper_library_scopes/bitfield_snapshot` (MATLAB R2021a, System Generator 2021.1, SNAP platform; `io_names = [d]`, BRAM storage, offset / circap / value / ext_arm / ext_circ off, provide_outputs and use_dsp48 on). In each model the links were broken and the mask initializations of the bitsnap and its snapshot frozen; the ctrl swreg's sim port was turned on and driven by a Repeating Sequence Stair playing `sim_ctrl.csv`; Slice / Gateway Out / To Workspace probes logged the shared_bram inputs (outputs of add_del, dat_del, we_del), the status swreg input (add_gen output 5) and arm_or. The input CSVs are the source values, the output CSVs the logged Simulink signals.

| Test # | Directory | NSAMPLES | DATA_WIDTH | IN_WIDTH | Cycles | Description |
|--------|-----------|----------|------------|----------|--------|-------------|
| 0 | `simdata0` | 4 | 128 | 128 | 1500 | 16 x 128-bit (bitfield_snapshot set 1) |
| 1 | `simdata1` | 5 | 32 | 32 | 1500 | 32 x 32-bit (bitfield_snapshot set 2) |
| 2 | `simdata2` | 3 | 8 | 6 | 1200 | 8 x 8-bit, 6-bit input (zero-extended) (bitfield_snapshot set 3) |
| 3 | `simdata3` | 4 | 64 | 64 | 1500 | 16 x 64-bit (bitfield_snapshot set 4) |
