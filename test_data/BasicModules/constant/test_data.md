# constant test data

No CSV files are needed. The testbench derives the expected output directly
from the DUT parameters `NBITS` and `VAL`.

Parameter sets exercised via `simulation.toml`:

| Test # | NBITS | VAL  | Description |
|--------|-------|------|-------------|
| 0 | 8     | 0    | Zero output |
| 1 | 8     | 170  | 0xAA — alternating bits |
| 2 | 8     | 255  | Maximum value for 8-bit width |
| 3 | 4     | 7    | Non-power-of-two value, 4-bit width |
| 4 | 12    | 4095 | Maximum value for 12-bit width |
