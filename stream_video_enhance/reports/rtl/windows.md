# Task 2 — independent row banks and two window statistics

Simulation executed 2026-10-24; evidence and source hashes rechecked 2026-10-25.
Scope: `row_window5`, `moments5`, `coefficient_box5`, window vectors/benches and
the additive windows runner option. All four windows benches passed; the seven
existing real-tool runner tests passed. This is simulation evidence, without
synthesis, routed timing, camera or board claims.

The controlled model prerequisite remains profile 1, finegain-v3, with all 17
required checks PASS. The six model/test file hashes were checked against the
profile's recorded execution sources and match. Those files, profile, demo,
reference sources and historical results were not modified or rerun.

## Public API for Task 3

All ports below are unsigned unless stated otherwise. Shared inputs are
`clk`, `rst`, `abort`, `in_valid`, `in_sof`, `in_x[9:0]`, `in_y[8:0]`,
`in_frame_id[31:0]`. Shared outputs are `out_valid`, `out_x[9:0]`,
`out_y[8:0]`, `out_frame_id[31:0]`. Reset and abort are active high,
synchronously flush state, immediately mask valid/error outputs, and prevent RAM
access while asserted. There is no ready/backpressure.

| Module and parameters | Additional inputs | Additional outputs | Coordinates |
|---|---|---|---|
| `row_window5 #(W=640,H=480,DATA_W=8)` | `in_data[DATA_W-1:0]` | `out_rows[5*DATA_W-1:0]` | Local raster in/out; output is bottom-right column position |
| `moments5 #(W=640,H=480)` | `in_pixel[7:0]` | `out_s1[12:0]`, `out_s2[20:0]`, `out_center[7:0]`, `range_error` | Input original 0..W-1/0..H-1; output original 2..W-3/2..H-3 |
| `coefficient_box5 #(W=640,H=480)` | `in_a[11:0]`, `in_b[15:0]`, `in_center[7:0]` | `out_abar[11:0]`, `out_bbar[15:0]`, `out_align[7:0]`, `range_error` | Input original 2..W-3/2..H-3; output original 4..W-5/4..H-5 |

The row helper's generic payload port is **`in_data`**, not `in_pixel`.
It accepts W/H >=5 (bounded above by 640/480); the two image stages require
W/H >=16. The coefficient row helper is instantiated at `(W-4,H-4,36)`, so the
16x16 case exercises 12x12 local RAMs. Coefficient layout is exactly
`{in_a[11:0],in_b[15:0],in_center[7:0]}`. A/Abar are Q12; b/bbar are Q8.

For row output, bits `[0+:DATA_W]` contain row y-4 and bits
`[4*DATA_W+:DATA_W]` contain current row y. Every accepted row token appears,
including warmup; nonexistent earlier rows are explicitly zero masked.
Moments and box only expose complete 5x5 windows. They do not average the center
pixel: the middle-row byte is delayed by two **local valid columns**.

The box subtracts 2 from both input coordinates before accessing local RAM.
Supply its `in_sof` on the first coefficient at original `(2,2)`, derived as
`in_valid && in_x==2 && in_y==2`. Its output coordinates equal local
bottom-right coordinates because local-to-original +2 and center offset -2
cancel. SOF/EOL/EOF are not separate output ports in these window modules;
the next stage can derive them from valid and the stated original-coordinate
bounds. Preserve the global original-coordinate convention.

`range_error` is aligned with, and only asserted for, its `out_valid` token.
Both stages retain signed 23-bit feedback sums and check negative or excessive
totals before narrowing. Moments checks S1 <=6375 and S2 <=1625625; box checks
SA <=102300 and SB <=1632000. Bad moments return zero sums while retaining the
error. Bad box sums feed defensive zero to the dividers and retain the delayed
sum error; box also ORs the two divider errors and parallel valid mismatch.
An error is not a successful pixel; the subsequent frame controller must
invalidate the frame. No error flag is inferred from startup X on bubbles.

## Measured edge timing and architecture

An input accepted at rising edge t produces its output after NBA at edge t+L.
Each module declares its checked `localparam integer LATENCY`:

| Module | Measured L | Register schedule relative to acceptance |
|---|---:|---|
| row_window5 | 2 | RAM read/current bypass t; delayed bank-role selection t+1; row output t+2 |
| moments5 | 9 | row output t+2; square stages t+3/t+4; three-level vertical tree t+5..7; difference t+8; accumulator t+9 |
| coefficient_box5 | 12 | row output t+2; tree t+3..5; difference t+6; accumulator t+7; div25 accepts t+8 and produces t+12 |

Box's internal sampling boundary into div25 is already included in 12. Do not
add it again to the top-level L_LINK=4, or use the unmeasured initial box=11.
Task 3 must derive its total from these values and the remaining measured
stages. No padding to a presumed 64-cycle core latency was introduced.

Five generate scopes each own one independent synchronous single-port RAM.
Every valid input writes one bank and reads four other banks; each bank has
mutually exclusive write/read enables. RAM arrays/read data have no reset.
The current row bypass, role selector, coordinates and frame ID are delayed
with the read. Missing rows are masked before arithmetic, and each horizontal
recurrence resets at its local x=0. `bank_index` changes only on accepted line
ends or SOF; malformed raster recovery belongs to the future ingress guard.

Moments has five parallel 8x8 squares with DSP inference attributes and full
16-bit products. Both paths have registered vertical adder trees. Horizontal
differences use S12/S20 for raw and S16/S20 for coefficients; feedback uses one
register stage and signed 23-bit addition. Histories and two-column center taps
advance only on their own local valid. Arithmetic/metadata pipelines continue
through bubbles. The box adds exactly 12 before each unchanged Task 1 div25.
Actual DSP/BRAM inference and 100 MHz timing remain Task 4 measurements.

## Commands and observed RED/GREEN

Commands were run from `E:/Vivado_FPGA_Programs/fpga2026/stream_video_enhance`:

```text
E:/Python/python.exe scripts/run_core_tests.py --suite windows --windows-size 16 --quick
E:/Python/python.exe scripts/run_core_tests.py --suite windows --windows-size vga
E:/Python/python.exe scripts/run_core_tests.py --suite windows
E:/Python/python.exe -m unittest discover -s tests -p test_core_runner.py -v
```

Existing arithmetic CLI remains the default, including `--quick` and
`--timeout`; `run_bench`, `generate_vectors`, Windows Job cleanup and fixture
behavior are unchanged. Windows adds `--windows-size all|16|17|vga|ranges`.
An additional `scripts/window_vectors.py` keeps the independent 25-point oracle
separate and auditable without restructuring the arithmetic generator/API.
There is no additional RTL helper.

Functional RED preceded working window logic. All paths below are under
`build/regression/`; each has captured tool logs and result.json:

| Run directory | Observation |
|---|---|
| windows-16-92cd1b0920 | All three stubs compile/elaborate; xsim reports `Fatal: row valid latency cycle=7`, 66 ns |
| windows-16-5c12b627b5 | With row/moments implemented, box stub fails `box valid latency cycle=119`, 1186 ns |
| windows-16-7b145d7e88 | First structured GREEN: 6 complete frames, 4 reset/abort flushes, L=2/9/12 |
| windows-vga-3981105309 | Initial one-frame VGA smoke GREEN, 302736 moments / 298304 box outputs |
| windows-range-red | Build-only mutant disabling the full-width sum guard fails first invalid-A output: frame2 A=4095, error=0 instead of 1, 2456 ns |

The guard mutation was made only in an ignored build copy; production source
was not replaced. One intermediate compile failed because `xp` was referenced
before declaration (`windows-16-63157ae2e6`); declaration order was corrected.
This compile diagnostic is separate from functional RED evidence.

Final full suite:

| Run directory | Full frames | Flushes | Checked moments | Checked box | Checked rows | Bank checks |
|---|---:|---:|---:|---:|---:|---:|
| windows-16-07d6cc5461 | 18 | 4 | 2712 | 1199 | 4976 | 37587 |
| windows-17-c00f94bd42 | 18 | 4 | 3640 | 1835 | 6204 | 45192 |
| windows-vga-425a98a7c7 | 1 | 0 | 302736 | 298304 | 307200 | 921708 |

Counts include valid outputs observed before aborted partial frames. Each full
frame independently checks exact `(W-4)*(H-4)` and `(W-8)*(H-8)` output counts.
The VGA final crop is 632x472, from original (4,4) through (635,475).
`windows-ranges-e61b71a2bd` additionally passes 192 literal outputs: 64 legal
joint maxima A=4092/b=65280, 64 invalid-A outputs flagged, 64 invalid-b outputs
flagged. All four benches have all three tool exits zero and PASS markers.

The seven unchanged real-tool runner tests passed, zero skips, 37.204 s.
Retained fixture directories (prefix `runner-fixture-`) are `lytojcnk`,
`wf0qu9b_`, `y8g1l35o` (three illegal-parameter subtests), `oif232v5`
(compile error), `q66lhmb2` (PASS followed by fatal), `rewpi0xc` (missing PASS),
`v1b5f62o` (success), and `09v7bq7t` (timeout). The bootstrap fixture's temporary
checkout was removed by its context as designed. Unittest's aggregate result
was captured in the task tool output and recorded in windows_results.json;
each retained real-tool fixture has its own logs/result. No aggregate stdout
file is claimed. Every tool invocation reported private Job active processes=0.

## Coverage, traceability and self-review

`window_vectors.py` adds all 25 spatial samples directly and uses integer
division to form coefficient/mean expectations. It does not copy the RTL
horizontal recurrence or the model's integral-image implementation. Every S1,
S2, A, b, Abar and bbar plane is cross-checked against unchanged `fixed_layers`.
Small dimensions each cover structured nonconstant data, impulse, row ramp,
seeded random, zero, maximum and checkerboard, with epsilon 16/64/256/1024
across cases. Zero/maximum also have independent literals. Each small pattern
runs both continuous and random-gap schedules with 41-cycle line gaps.

The cycle scoreboard checks missing/extra valid, all numeric outputs, exact
original centers, coordinates and frame IDs at t+LATENCY. The standalone row
instance additionally checks all five rows, including zeroed unavailable rows
against uninitialized/stale physical RAM contents. Port-mask assertions run
for it and both stage row instances on every clock, including bubbles and
flushes. Reset and abort each occur in warmup and after complete windows have
started; new frames then pass without clearing RAM. Input payloads become X
during idle gaps. The queue is drained and per-frame counts checked before PASS.

`windows_results.json` retains exact commands, summaries, source SHA256,
result/log SHA256, all three RED outcomes and the timing convention. On
2026-10-25 all recorded source, result and log hashes matched the saved files;
the passed suites were not rerun. Recorded base 611e8d0 was HEAD when evidence
was assembled; controller-only documentation subsequently advanced to e0c13a1.
The manifest's hashes identify the actual tested source independently of that
concurrent documentation history.

Self-review checked bank-role/current-data alignment at line transitions,
old-RAM masking, local-valid center taps, local coordinate conversion, field
packing, every adder/product width, signed difference extension, one-stage
feedback, +12 normalization, metadata/error alignment, output crop, occupied
flushes and additive runner behavior. No functional concern remains from these
checks. Negative-sum guards are implemented but not separately fault-injected;
legal unsigned inputs cannot cause a negative mathematical window sum. No
formal proof or code-coverage percentage is claimed. Illegal-raster recovery,
whole-core integration, synthesis/resource inference and timing remain later
milestones. Task 2 is complete for its stated simulation scope.
