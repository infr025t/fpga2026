# Task 4 — numerical core synthesis and resource exchanges

2026-10-26. The actual VGA numerical core passes the local resource and registered
setup/hold synthesis gates at 10 ns. The two same-function resource comparisons
pass independent scalar simulation. A bounded, additional OOC implementation
passes **internal register-to-register** timing, but fails overall boundary hold:
this is **not full-system timing closure or board validation**.

The production change is one real magnitude/sign pipeline register in
`detail_enhance`. Current `L_ENH=7`, `L_CORE=55`, and `EXTRA_ALIGN=1` gives 56.
The historical Task 3 values 6/54/55 remain documented in its original report;
the current simulation manifest is [core_timing_fix_results.json](core_timing_fix_results.json).
No formula, arithmetic width, rounding, crop, II=1, runtime interface or hardware
assumption changed. No camera, display, ingress controller or UART was implemented.

## Method and constraints

Vivado 2025.1, build 6140274, part `xc7a35tcpg236-1`, Windows; tools under
`E:/Vivado/2025.1/Vivado/bin`, Python `E:/Python/python.exe`. Source lineage is
reviewed Task 3 `a5d1b61`; exact run HEAD, source hashes, commands, parameters and
report hashes are in [core_synthesis_results.json](core_synthesis_results.json).
All synthesis inputs are W=640, H=480; production EXTRA_ALIGN=0. All alternatives
use identical 10.000 ns clock, input max/min 2.000/0.000 ns and output max/min
2.000/0.000 ns. XDC is read **before** synthesis. `HD.CLK_SRC=BUFGCTRL_X0Y0` is an
explicit local OOC timing anchor, not a future board placement decision. There
are no false paths, multicycle exceptions or algorithm clocks.

The synthesis runner rejects nonzero exit, timeout, ERROR/FATAL/CRITICAL WARNING,
missing actual completion marker, missing evidence, latches, multiple drivers,
combinational loops, unconstrained endpoints, missing clock or I/O delay,
negative registered setup/hold or overall setup, and production resource-cap
excess. The Tcl marker means tool-flow completion only. Synthesis boundary hold
is reported separately because unplaced OOC ports are not a realized surrounding
system. `--route-core` additionally checks overall routed setup/hold and correctly
returns failure for the boundary hold result below.

LUT totals are **Slice LUTs from report_utilization**, including SRLs and Vivado's
LUT combining adjustment, not simply a `REF_NAME =~ LUT*` cell count. Primitive
counts remain a separately named machine-readable diagnostic. The earliest
exploratory stdout used that incomplete primitive count; the tables here and
final acceptance checks use the complete utilization report.

## Actual local synthesis

| Design | RAMB18 | RAMB36 | BRAM36 equiv. | DSP | Slice LUT | FF | Registered setup / hold ns | Overall setup ns |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| guided_core | 5 | 5 | 7.5 | 18 | 2452 | 2609 | +1.222 / +0.204 | +1.222 |
| A current: moments5 | 5 | 0 | 2.5 | 5 | 509 | 548 | +3.261 / +0.219 | +3.226 |
| A presquare: moments_store_square | 0 | 5 | 5.0 | 1 | 621 | 724 | +3.261 / +0.219 | +3.226 |
| B current: coefficient_box5 | 0 | 5 | 5.0 | 4 | 906 | 910 | +1.222 / +0.219 | +1.222 |
| B queue: coefficient_box_queue | 1 | 5 | 5.5 | 4 | 914 | 879 | +1.222 / +0.214 | +1.222 |

All five have **0 latches, 0 multidrivers, 0 combinational loops, 0 critical
warnings**, and 0 unconstrained internal endpoints or missing clock/I/O delays.
Production caps BRAM36<=24, DSP<=24, LUT<=12000 and FF<=20000 all pass. This is
numerical-core use, not the eventual system use. Future peripherals must still
fit inside these system caps; the core's 18 DSP count supersedes the earlier
unmeasured lower estimate. Synthesis overall hold is -0.489 ns for four designs
and -0.160 ns for presquare; these boundary estimates are not represented as
closed timing.

## Timing defect and verification

The first actual synthesis had registered setup -0.391 ns. That preliminary
runner created the clock after synthesis and omitted the OOC clock anchor; both
runner defects were corrected before the next evaluation. With correct
pre-synthesis XDC and anchor, the unchanged core still failed at -0.098 ns.
The concrete path was `enh/detail0_reg` through absolute value, threshold,
limiting and signed restoration into the DSP input: 13 logic levels in the
initial report. Failure evidence is retained under `evidence/task4/failures/`.

Registering magnitude and sign separates the absolute value carry chain from
the soft-threshold/limit logic. Gain, threshold and base are delayed consistently;
metadata follows the package latency. No preservation attribute or timing
exception hides the path. The fixed core gives +1.222 ns registered setup.

The existing independent model-based **9-bench core suite** was rerun once for
this real production change, after a focused stage pass: 832 complete frames,
24 VGA frames, 7,225,548 triples including observed pre-abort prefixes, zero
differences and zero simulator warnings. Every VGA frame has 298,304 outputs.
Both EXTRA_ALIGN=0/1 test accepted-edge latency 55/56, crop/coordinates/flags,
random gaps, line blanks, runtime modes/configurations, abort/reset and early
arithmetic faults. The eight fewer compared prefix pixels than the old suite
are due to the added stage before fixed abort times, not dropped complete-frame
outputs. The package and current manifest agree exactly:

`9 + 20 + 12 + 3 + 7 + 4 + 0 = 55`.

For continuous VGA, first output is input SOF + 5183 (or 5184 with extra align);
output EOF is accepted input EOF + 55/56. Two latency configurations remain real
hardware configurations; no padding to an arbitrary budget was inserted.

An additional bounded OOC `opt_design / place_design / phys_opt_design /
route_design` run used the same constraints. Internal registered paths have
setup **+1.114 ns**, hold **+0.053 ns**. Overall setup is +0.638 ns but overall
hold is **-1.126 ns**, so the overall route gate is **FAIL**. Vivado emitted 91
`Route 35-198` messages: OOC ports lack `HD.PARTPIN_LOCS`, preventing their partial
routes and accurate boundary timing. No invented boundary floorplan or relaxed
minimum delay was added to turn this green. Full-system placement/routing must
close actual producer/consumer paths, clocking, reset, I/O and CDC; neither this
local route nor the synthesis estimate establishes that result.

## A: parallel squares versus stored square

Both designs calculate the same S1, S2, raw center and metadata from the same 5x5
window, at II=1 and the same observable 9-cycle latency. The alternative moves
the two square registers ahead of the row helper and stores `{I_squared,I}` in
five 24-bit banks. It uses one square multiplier. The current design stores
five 8-bit banks and squares their five outputs in parallel. The downstream
full-width sums, difference/accumulator and center rules are equivalent.

At W=640: current logical row storage is 5*640*8/8 = **3200 B**; presquare is
5*640*24/8 = **9600 B**. Current minus alternative is -6400 B, -2.5 BRAM36,
+4 DSP, -112 Slice LUT and -176 FF. Both reach the same worst registered setup
slack in this experiment. The physical RAM mapping is measured, not inferred
from the byte count alone.

## B: carry center in RAM versus a separate token queue

The alternative preserves the coefficient box's arithmetic and 12-cycle
latency, uses the same five banks of W-4 entries, narrows each entry from 36 to
28 bits, and adds a `2*(W-4)+2` deep 8-bit valid-token queue. Queue addresses
advance only for accepted tokens. A synchronous next-slot prefetch reads an
address different from the current write address; it avoids a same-address
read/write mode dependency. Only pointer/state is reset, never the RAM array.
Two free-running output registers match the row helper's clock latency. Window
warmup gates all stale initial queue data, including after frame restart.

For W=640, both 28-bit and 36-bit coefficient banks map to **five RAMB36**.
The 1274x8 queue maps to **one RAMB18**. Current storage is 14,310 B; queue
alternative is 11,130+1274 = 12,404 B. Current minus alternative is **+1906 logical
bytes**, **-0.5 BRAM36**, **0 DSP**, **-8 Slice LUT**, and **+31 FF**. Thus this
implementation saves a physical block and the queue pointer/prefetch machinery,
but does not minimize logical bytes or FF count. The measured FF difference is
reported without replacing it with the original budget narrative.

A and B use separate comparison baselines. Their local differences must not be
added to a single incompatible baseline or to old-demo utilization.

## Functional comparison and diagnostic tests

`tb_resource_exchange` independently computes each expected S1/S2 or coefficient
mean by scalar summation over all 25 coordinates, and checks center, coordinates,
frame ID, range-error, valid timing and complete-frame counts for **both**
implementations. Expected values do not call either DUT. Coverage includes II=1,
intermittent bubbles, long line gaps, multiple frame IDs, abort during activity,
and reset followed by restart. Results:

| Size | Compared moments tokens | Compared coefficient-box tokens |
|---|---:|---:|
| 16x16 | 600 | 272 |
| 17x19 | 806 | 414 |
| VGA | 1,212,216 | 1,194,480 |

Counts include valid prefixes of deliberately aborted frames. All three pass
without compiler/elaborator/simulator warnings. The initial RED failed with
the two absent experiment modules; logs remain saved. Full results are in
[resource_exchange_results.json](resource_exchange_results.json).

Eight diagnostics tests pass, including rejecting a Tcl echo of a completion
marker, error after marker, critical warning, missing marker, exit/timeout,
negative setup/registered hold, cap excess and unconstrained endpoints. Real
Vivado fixtures also reject an error printed after PASS despite exit 0, exit 0
without PASS, and a timeout with child cleanup. See
[synth_runner_fixtures.json](synth_runner_fixtures.json). The registered-hold gate
was strengthened after tool runs; reconstruction/hash verification proves it was
the only post-run runner change, and the final evaluator was reapplied to all
saved metrics without repeating unchanged synthesis.

The final presquare rerun first hit an installation-script read error for
`retarget_vhdl.tcl`. It was retained as a **tool failure**, and the identical RTL,
constraints and tool were rerun serially; the retry passes. No RTL change was
made to cure this tool error.

## Warning classification and reproduction

Final synthesis warning counts are core 32, moments 5, presquare 3, box 3,
queue-box 3; critical counts are zero. `Synth 8-6014` removes unused procedural
temporaries or registers absorbed in multiplier mapping; `Synth 8-3936` trims
unused partial quotient bits; `Synth 8-7129` identifies input EOL/EOF unused by
the numerical core (ingress validation is later work, as in Task 3);
`Synth 8-7080` is informational about parallel synthesis eligibility;
`DRC 23-814` states the OOC connectivity-check limit. The core's full optional
route log has 128 total warnings: the preceding 32 plus 3 additional OOC DRC
notices, 91 missing-partition-pin warnings, one tile-split warning, and one
estimated timing-not-met warning. These route warnings are not suppressed.

From `E:/Vivado_FPGA_Programs/fpga2026/stream_video_enhance`:

```powershell
E:/Python/python.exe -m unittest discover -s tests -p test_synth_runner.py -v
E:/Python/python.exe scripts/run_exchange_tests.py
E:/Python/python.exe scripts/run_core_tests.py --suite core --core-size all --extra-align both
E:/Python/python.exe scripts/run_core_synth.py
# Optional additional boundary diagnostic; expected overall hold failure is retained:
E:/Python/python.exe scripts/run_core_synth.py --route-core
# The observed transient tool failure was retried with:
E:/Python/python.exe scripts/run_core_synth.py --tops moments_store_square
```

The synthesis runner requires the current simulation latency manifest and
rejects package/manifest mismatch. Scratch is under `build/regression`; the first
exploratory outputs outside that subfolder were preserved and never staged.
Raw logs, utilization, clock/I/O constraints, timing, DRC and route evidence are
checked in under `reports/rtl/evidence/task4`. Checkpoints remain local scratch.
Exact historical invocation arrays and hashes are in the machine-readable
summaries. The model gate and old demo/reference artifacts were not rerun or
modified.
