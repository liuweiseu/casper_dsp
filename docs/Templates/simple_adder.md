# simple_adder

## Description

A reference template module implementing a simple registered adder. On each rising clock edge, the sum of inputs `a` and `b` is computed and stored in the output register. When reset is asserted, the output is cleared to zero. This module serves as a minimal example for the project's RTL and testbench conventions.

## Parameters

None.

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `rst` | input | 1 | Synchronous reset (active high); clears `sum` to zero |
| `clk` | input | 1 | Clock signal |
| `a` | input | 8 | First operand |
| `b` | input | 8 | Second operand |
| `sum` | output | 9 | Registered sum of `a` and `b` (extra bit prevents overflow) |
