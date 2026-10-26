# Task 3 — integrated numerical core

Simulation completed 2026-10-26, with the final clean matrix ending at 17:39:58
local time. Resume audit verified the saved results and current sources. All nine
benches passed without compiler, elaborator, or simulator warnings. Across 832
completed frames (24 VGA), 7,225,556 `{raw,base,selected}` triples matched the
unchanged fixed model, including prefixes observed before explicit aborts.
Each VGA frame produced exactly 298,304 outputs. This is behavioral simulation
evidence; synthesis, routed timing, runtime controllers, camera, display, and
board validation remain outside this task.

## Implementation and interfaces

The core composes the reviewed `moments5` and `coefficient_box5` with three new
registered arithmetic modules. All data travels with original coordinates,
frame ID and valid; RAW, BASE and selected mode share the output cycle. There is
no ready or backpressure and no full-frame intermediate image buffer.

| Module | Data interface | Operation |
|---|---|---|
| `coefficient5` | S1 U13, S2 U21, epsilon U11, center U8 → A U12 Q12, b U16 Q8, center | Full products, signed variance check, exact ratio, exact mean, rounded b |
| `reconstruct` | Abar U12 Q12, bbar U16 Q8, aligned I U8 → base U16 Q8, aligned I | Full U20 product, round by 16, U17 sum, clip to 65280 |
| `detail_enhance` | base U16 Q8, I U8, T U5, G U10, mode U2 → selected/raw/base U8 | Signed soft threshold and limit, full gain product, ties away from zero, final clip/round |
| `guided_core #(W,H,EXTRA_ALIGN)` | Original raster and frame configuration → cropped triple and markers | Two windows, three arithmetic stages, optional one physical output register |

The three arithmetic modules accept `clk,rst,abort,in_valid`, x U10, y U9 and
frame_id U32, and return the matching valid/metadata and `range_error`.
Each error is valid aligned. Invalid input ranges return a defensive value and
an error; they are not successful pixels. Full-width intermediate guards are
retained before narrowing. In particular G=512 remains positive in the signed
multiplication, and BASE is kept in Q8 until the detail computation is finished.

`guided_core` accepts legal W/H from 16 through 640/480 and EXTRA_ALIGN 0 or 1.
Configuration is captured on accepted SOF and held through drain; DENOISE forces
G=256. Request pins may change later without affecting the active frame. The
caller supplies a legal raster and legal SOF configuration, waits L_CORE empty
cycles after input EOF, and handles errors by invalidating/aborting the frame.
The core's simulation assertions reject overlapping frames and illegal SOF
configuration. Runtime cfg_error counting and protocol validation belong to the
later ingress/controller work; input EOL/EOF are interface markers, not a second
validator inside this numerical core. Output markers are regenerated from valid
and original cropped coordinates.

Top-level `arithmetic_error` is an OR of valid-aligned stage error events, masked
by reset/abort. It can precede final out_valid: a bad early coefficient outside
the final crop must still invalidate the frame. The core does not silently discard
such a fault or autonomously declare frame success.

## Measured latency

The convention is accepted rising edge t → output observed after NBA at t+L.
The package is the single latency manifest; the benches derive schedules from
it, and core assertions check stage parameters against it.

| Term | Cycles |
|---|---:|
| L_MOM | 9 |
| L_COEF | 20 |
| L_BOX | 12 |
| L_REC | 3 |
| L_ENH | 6 |
| L_LINK | 4 |
| L_ALIGN | 0 |
| L_CORE | **54** |
| L_CORE with EXTRA_ALIGN=1 | **55** |

Each of four registered module boundaries contributes one sampling edge. The
optional alignment path uses exactly one physical register. For continuous VGA,
first output (4,4) follows first input by 8W+8+L = 5182/5183 cycles; a center pixel
has latency 4W+4+L = 2618/2619 cycles. EOF is input EOF+L. With bubbles, output
center (c,d) is due L cycles after accepted input (c+4,d+4). The scoreboard checks
every cycle against that relation, including last output and all markers.
Contiguous output runs of 632 pixels demonstrate II=1 within each VGA row;
100 MHz physical timing has not been measured.

## Regression matrix

| Bench | Completed frames | Compared triples | Other evidence |
|---|---:|---:|---|
| 16×16, align 0 | 202 | 12,996 | 196 configs, 6 post-flush recovery frames |
| 16×16, align 1 | 202 | 12,994 | Same matrix, L=55 |
| 17×19, align 0 | 202 | 20,136 | 196 configs, 6 post-flush recovery frames |
| 17×19, align 1 | 202 | 20,134 | Same matrix, L=55 |
| VGA, align 0 | 12 | 3,579,648 | II=1, L=54 frame gaps, 298,304/frame |
| VGA, align 1 | 12 | 3,579,648 | II=1, L=55 frame gaps, 298,304/frame |

Small frames cover every epsilon, T=0/16, G=0/256/512, all modes, continuous input
and deterministic random gaps plus 113-cycle line blanking. Additional cases
cover published profile 1 and old G=320 partial restoration. Patterns include
the four specified internal patterns, structured arithmetic texture, random
pixels, an impulse, horizontal ramp, constant 0/255 and noisy texture. VGA cycles
all four modes with 12 deterministic image/configuration combinations per align.

Stage vectors contain 1,032 coefficient fixtures, 1,006 reconstruction fixtures
and 2,477 enhancement fixtures. Two passes, with bubbles and reset/abort, checked
4,891/4,944/4,935 valid outputs respectively. Literal fixtures independently cover
positive and negative observable half ties, maximum variance, maximum gain,
dead-zone/limit neighbors, zero/255 saturation, constants, old parameters and
the published profile. Expected frame triples come from the unchanged model.

Reset and abort each occur at first pixel, with division occupied, and at frame
tail on both small sizes and both alignments. Valid remains asserted on the
flush edge to test priority. The scoreboards discard pending tokens only at an
explicit flush, check silence through the drained pipeline and compare complete
subsequent frames. Prefix pixels already emitted before abort are still checked
but the aborted frames do not enter the completed-frame count. Two fault benches
inject negative moments and negative variance before the first final-crop pixel;
both early errors remain visible and abort masks/flushes them.

Seven real-tool runner tests also passed, with zero skips: missing-parent
bootstrap, illegal parameters, compile failure, fatal despite PASS text, missing
PASS, actual PASS and timeout. The shared primitive runner implementation was
not changed; core suite routing is additive and rejects warnings.

## Reproduction and durable evidence

From `stream_video_enhance`, with Python/numpy installed and Vivado available:

```powershell
E:/Python/python.exe scripts/run_core_tests.py --suite core --core-size all --extra-align both
E:/Python/python.exe -m unittest discover -s tests -p test_core_runner.py -v
```

`VIVADO_BIN` can override the default `E:/Vivado/2025.1/Vivado/bin`. The core CLI
creates fresh unique directories including missing parents and generates all
input/expected fixtures from committed `core_vectors.py` and `model/reference.py`.
No ignored scaffold, old hex file, or preexisting build directory is required.
The `--quick` option is for smoke tests only and was not used for the final matrix.

[core_results.json](core_results.json) preserves source hashes, per-vector hashes,
all final tool commands/exit codes/full captured logs, RED logs, runner output and
the measured manifest. Original local scratch paths are provenance, not runtime
dependencies. Full logs are embedded so removing ignored scratch later would
not erase the durable evidence.

Resume checks found all 11 RTL files, runner and stage bench identical to the
17:34 saved SHA256 list. Only the strengthened vector generator and integrated
bench differ from that earlier list; both were last written at 17:36:07, before
every final clean compile. Regenerating all vectors into independent new
directories reproduced all 1,623 fixture files byte for byte. Current source
hashes are captured on resume, not misrepresented as pre-run hashes for those
two test files. All six original model/test source hashes still match profile 1.
No source changed during this resume; the verified final simulations were reused.

## TDD and self-review

The saved stage RED command was `E:/Python/python.exe
build/regression/task3-scaffolding/run_stage_red.py`; xvlog/xelab succeeded and
xsim emitted `Fatal: coefficient invalid error` at 16 ns against the placeholder
stage behavior. Integrated RED used `run_integrated_red.py` from the same
scaffolding folder against the initial core stub: compilation succeeded and
`Fatal: core valid cycle=193 got=0 expected=1 L=54` detected the missing output.
These are historical commands, not required reproduction scripts. Their full
tool commands and failing output are retained in the JSON. The final normal CLI
above is GREEN for all nine benches.

Self-review checked full arithmetic widths/signs, parallel metadata alignment,
frame-locked settings, reset/abort priority, early error observability, crop and
original-coordinate semantics, actual latency sum and fresh-directory fixture
generation. Existing Task 1/2 files and immutable model/test sources are unchanged.
No unresolved implementation concern was identified; independent controller
review is still required before treating Task 3 as reviewed complete.
