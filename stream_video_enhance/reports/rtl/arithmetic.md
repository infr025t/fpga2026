# Task 1 — exact arithmetic and real simulator runner

Date: 2026-10-24. Branch: `feat/stream-video-v0`. Scope: three arithmetic/token
primitives, one arithmetic bench, runner and its tests. Model prerequisite was
confirmed PASS: `profile.json` epsilon=1024, T_D=2, T_E=4, G_E=428, L=16,
17/17 required checks PASS, traced source commit `747c5da`.

## Implementation and measured timing

All RTL uses a single clock; the bench clock is 10 ns. Arithmetic advances every
clock, including bubbles. Reset/abort clear validity; data registers need no
reset. Invalid arithmetic tokens retain aligned `out_valid`, assert
`range_error`, and return defensive zero. Errors are never asserted on bubbles.

| Module | Measured edge-to-edge latency | II | Contract |
|---|---:|---:|---|
| div25_pipe | 4 | 1 | floor(n/25), no caller rounding bias |
| ratio_q12_pipe | 13 | 1 | exact RN(4096V,DEN) |
| token_pipe | 0, 1, 3 tested | 1 | payload/valid delay, L0 reset/abort masking |

An input sampled at rising edge t produces output after rising edge t+L.
`div25_pipe` captures input, computes two unsigned partial products, merges the
full U41 reciprocal product, extracts candidate quotient, then compares/corrects
it. The multiplier identity is 671089=15729+20*32768. `25*q0` is full U22.
The ratio captures V/DEN, executes twelve spatially unrolled fractional stages,
then rounds with a U13 result. Every doubled remainder/comparison/subtraction is
U25. A rounding carry to 4096 is flagged before narrowing, never reported as a
successful zero coefficient. No synthesizable variable division or frame RAM.

Parameter guards reject IN_W outside 1..21, OUT_W outside 1..16, WIDTH<1 and
LATENCY<0. Arithmetic range checking additionally rejects n>1632012 or quotient
overflow, V>10143900, DEN>10783900, DEN<=V and rounded A>4092. DEN-V is not
restricted to one epsilon offset, permitting independent literal tests.

## Test-first evidence

Commands ran from `E:/Vivado_FPGA_Programs/fpga2026` unless specified:

```text
E:/Python/python.exe -m unittest discover -s stream_video_enhance/tests -p test_core_runner.py -v
E:/Python/python.exe stream_video_enhance/scripts/run_core_tests.py --quick
E:/Python/python.exe stream_video_enhance/scripts/run_core_tests.py --timeout 240
```

Initial missing runner/DUT tests failed. A stub-only arithmetic implementation
then compiled and elaborated; functional RED was captured before implementing
the arithmetic logic:

```text
build/regression/arithmetic-29af17cc64
xvlog exit=0, xelab exit=0, xsim exit=0
Fatal: L0 pipe
Time: 46 ns
runner verdict: FAIL (xsim exit/diagnostic failure)
```

This distinguishes real assertion failure from earlier scaffolding errors:
`arithmetic-f89d94aa2b` failed xelab because stub modules lacked timescales;
`arithmetic-8b27a2c8d9` failed xsim command parsing because cmd.exe split '=' in
the unquoted plusarg. Final runner supplies plusargs through an xsim options
file. These were tool/scaffolding RED, not numerical RED.

Focused GREEN first ran in `arithmetic-dd4dd61aab`; final focused bench with
separate vector counters and pseudorandom gaps passed in `arithmetic-0f4564e39c`:
6 div tokens and 20019 ratio tokens, measured 4/13 clocks and token 0/1/3.

## Full arithmetic regression — PASS

The full regression was run once after focused checks passed. Actual result:

```text
build/regression/arithmetic-9d3a8213df
xvlog: exit 0, 0.670 s
xelab: exit 0, 1.505 s
xsim:  exit 0, 58.280 s
PASS tb_arithmetic div_checks=1632014 ratio_checks=20019
max_II1_streak=4016 latencies=4,13 token=0,1,3
Each tool's private job: ActiveProcesses=0 before return.
```

Coverage:

- All 1632013 legal n from 0 through 1632012, plus U21 maximum 2097151
  explicitly rejected. Literal boundaries 0/24/25/26/1632012 are independently
  pinned to 0/0/1/1/65280. Default 21->16 and smaller 17->12 instances run in
  parallel; the smaller instance is checked with independent bench division,
  including values exceeding its output capacity.
- 20000 seeded random 25-pixel windows plus V=0/Vmax for each epsilon
  16/64/256/1024: 20008 model-derived legal ratios. Seed=20261024.
  The committed `div25_exact` and `ratio_q12` functions generate expected files;
  none of the six existing model/test Python files were changed.
- Eleven independent ratio literals: zero, half tie 1/8192, neighbors 1/8191
  and 1/8193, U25 remainder doubling (8388608/10000000 -> 3436), zero/invalid
  denominator, V==DEN, exceeded V/DEN ledger, and rounding carry to 4096.
- Continuous initial II=1 burst followed by repeatable LFSR bubbles and line
  gaps; scoreboards verify every valid/error/payload at exact edge latency.
  Reset and abort with occupied pipelines and valid still asserted, then drains
  proving no leaked tokens. Invalid input payloads are X during random bubbles.
  Sent/checked counts must match before PASS; missing or empty vectors fail.

## Real runner fixtures — PASS

Final unittest run: **6 tests passed, 0 skipped, 37.230 s**. Illegal-parameter
test contains three subtests (negative token latency, IN_W=22, OUT_W=17).
The other five fixtures use real xvlog/xelab/xsim: successful PASS, compile
error, printed PASS followed by `$fatal`, normal completion without PASS,
and infinite simulated-time loop with an 8 s per-stage timeout. Observed
timeout is specifically xsim, not compilation; result exit is null and reason
`xsim timeout`. Fatal diagnostics are rejected even when xsim returns zero.
Machine-readable result.json and captured stage logs are retained per build.

Lifecycle debugging was separate from numerical testing. An early timeout using
taskkill /PID /T rejected timeout correctly but immediate TemporaryDirectory
deletion encountered WinError32 on xsim.xdbg. The final implementation creates
a private Windows Job, starts each wrapper suspended, assigns it before any
children can launch, resumes it, terminates only this job when done, waits for
zero active processes and closes process/job handles. Fixture artifacts remain
in ignored build directories; Windows can briefly retain mapped debug files
after the process count is zero. A subsequent process inventory found no
xsim/xsimk/xelab/xvlog/loader processes, including from the early fixture.
No process-name-wide termination or hardware operation was performed.

## Tools, self-review and limits

Tools are `E:/Vivado/2025.1/Vivado/bin/{xvlog,xelab,xsim}.bat`; Python is
`E:/Python/python.exe`. Fresh xvlog -version and xsim -version both returned 0
and printed `Vivado Simulator v2025.1.0`, from the ignored full-regression build
directory. All compile/sim commands use unique children of build/regression;
the existing root ignore rule already covers these, so no new ignore rule was
necessary. Checked-in evidence is this summary; large vectors/databases/logs
stay under ignored build/. `git diff --check` passed.

Self-review checked reciprocal split/full widths, final rounding carry before
narrowing, valid-only error propagation, bubble/flush scoreboards, actual
expected-vector counts and simulator failure exits/logs. There is no synthesis,
100 MHz routed timing or hardware claim in Task 1. The runner currently targets
this Windows/Vivado installation and can override its binary directory through
VIVADO_BIN.

Integration concern: the explicit t -> t+L convention counts acceptance stage 0.
For positive token latency, storage is indexed 0..L. A downstream module samples
an upstream NBA-updated output at the next rising edge; later integration must
derive and measure module boundary scheduling and total latency accordingly.
Do not infer end-to-end latency by counting array elements or blindly summing
standalone latencies without the boundary schedule.

## Review fix round 1 — fresh-checkout fixture bootstrap

Scoped review `.superpowers/sdd/2026-10-23-rtl-core/task-1-review.md` found one
P2: the documented unittest-first command could not allocate a fixture when
build/regression did not exist. `RunnerTests.fixture` now creates that parent
with `mkdir(parents=True, exist_ok=True)` before calling mkdtemp. The behavioral
regression redirects the actual fixture ROOT to a separate temporary checkout
whose build parent is initially absent, runs real xvlog/xelab/xsim, and requires
PASS plus all three stages and outputs under that temporary root. ROOT is
restored in finally. No existing build directory was moved or deleted.

RED command, before the bootstrap correction:

```text
E:/Python/python.exe -m unittest discover -s stream_video_enhance/tests -p test_core_runner.py -k bootstraps -v
Ran 1 test in 0.002s; FAILED (errors=1)
FileNotFoundError [WinError 3] at actual fixture mkdtemp, before any tool stage.
```

GREEN command ran once after the correction, covering the new test and all six
existing real-runner fixture methods (including three parameter subtests):

```text
E:/Python/python.exe -m unittest discover -s stream_video_enhance/tests -p test_core_runner.py -v
Ran 7 tests in 37.519s; OK; 0 skips.
```

Raw unittest RED/GREEN stdout+stderr are retained in
`build/regression/task-1-fixround1-{red,green}.txt`. Nine real fixture invocations
ran in GREEN; the fresh-checkout fixture's successful temporary tree was cleaned
by its own context, and the eight original fixture invocations retain their
usual ignored build evidence. This fix changes only fixture setup and its
regression test. Arithmetic RTL, vector generation, saved full arithmetic run,
existing model files and parent specifications/plans remain unchanged; numerical
and model regressions were not rerun. The prior arithmetic results still refer
to their original recorded run.
