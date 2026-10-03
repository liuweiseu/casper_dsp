# read_ctrl

## Description

The read-side controller of `xeng_descramble` (`system_456`; identical copy `system_973` in `xeng_descramble_4ant`). It is not a library block.

```
dly    free running, DEL_BITS bits,  rst = start | pace
pace   = dly >= DEL
enable = pace & ~done
rd     free running, RD_BITS bits,  rst = start, en = enable    -> read_addr
done   register (power-on 0, rst = start, priority), d = en = (rd >= CNT)
```

After `start`, the read address steps 0, 1, … one every `DEL+1` cycles (every cycle when `DEL = 0`) until `done` stops it. That is `D·E` enabled words in both cases.

The `done` register needs reset priority. After a read pass it sits with `en = 1`, and only the reset lets the next `start` through.

At power-on `done = 0`, so a read pass runs without any `start`.

Built from `constant` ×2, `relational` ×2, `counter` ×2 and `register`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEL` | 2 | `ship_el_del` |
| `CNT` | 288 | `ship_el_cnt` |
| `DEL_BITS` | 2 | `max(1, ceil(log2(DEL+1)))` |
| `RD_BITS` | 9 | `ceil(log2(CNT+1))` |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `start` | input | 1 | Start of a read pass |
| `read_addr` | output | `RD_BITS` | Narrow read address |
| `enable` | output | 1 | Read valid |
