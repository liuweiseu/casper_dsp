# constant test data

No CSV files are needed. The testbench derives the expected output directly
from the DUT parameters `NBITS` and `VAL`.

Parameter sets exercised via `simulation.toml`:

| NBITS | VAL  | Description |
|-------|------|-------------|
| 8     | 0    | Zero output |
| 8     | 170  | 0xAA — alternating bits |
| 8     | 255  | Maximum value for 8-bit width |
| 4     | 7    | Non-power-of-two value, 4-bit width |
| 12    | 4095 | Maximum value for 12-bit width |
