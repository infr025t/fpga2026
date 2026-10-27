# Task 1 report: independent numerical references

Status: DONE. Commit: `1e1e6fd` (`feat: add independent V0 integer and float numerical references`). Dispatch base was `07a4b16`; main's documentation commit `5df26d3` landed before this scoped commit. No mathematical incompatibility with the specified filter was found.

## Scoped changes

Only these four files were included in the commit:

- `stream_video_enhance/model/__init__.py`: public numerical API exports.
- `stream_video_enhance/model/reference.py`: exact integer and independent float64 paths, checkpoint layers, legal-input/configuration guards, source patterns.
- `stream_video_enhance/model/requirements.txt`: NumPy 2.4.6 and Pillow 12.3.0 pins.
- `stream_video_enhance/tests/test_reference.py`: 11 numerical gate tests.

No RTL, old demo, reference material, or project docs were changed by this task. This report and saved RED/GREEN logs are local orchestration artifacts outside the scoped source commit.

`gain` means encoded integer Q8 G, inclusive 0..512; the floating path converts it to real gain G/256. DENOISE requires G=256. Legal modes are uppercase RAW/BASE/DENOISE/ENHANCE. L is fixed at 16. Images must be nonempty 2D uint8 arrays within width16..640/height16..480; the small sizes support numerical/ROI tests and do not add formal hardware builds. Formal hardware delivery remains VGA-only. All filter outputs crop four pixels per side; VGA output shape is (472,632).

The integer path retains full int64 intermediates, including variance, coefficients, exact rounded means, signed enhancement products, and clip-before-final-Q8-rounding. `div25_exact` implements the mandated reciprocal/correction recipe and has the unrounded floor-division public contract; callers explicitly add12. `ratio_q12` uses full exact integer arithmetic. The float path independently computes float64 integral sums, unquantized coefficients/means/base/detail, and rounds only the final clipped pixel. It does not call fixed-layer, integer division, enhancement, or Q8 rounding helpers. Shared code only validates configuration/input.

`fixed_layers` documents each plane's original coordinate origin and exposes s1, s2, variance_numerator, denominator, a_q12, mean_q8, b_q8, center, sum_a, sum_b, abar_q12, bbar_q8, base_q8, and raw.

## TDD evidence and commands

Environment: Windows PowerShell, cwd `E:/Vivado_FPGA_Programs/fpga2026`, Python `E:/Python/python.exe` 3.14.5, NumPy2.4.6, Pillow12.3.0.

Tests were written before any model implementation. Initial command:

```powershell
E:/Python/python.exe -m unittest discover -s stream_video_enhance/tests -p test_reference.py -v
```

Output was saved to `.superpowers/sdd/2026-10-23-model-gate/task-1-red.txt`:

```text
Ran 11 tests in 0.010s
FAILED (failures=11)
```

Each failure was the deliberate assertion `Task 1 numerical reference API has not been implemented`, via a lazy import in setUp; unittest discovery itself completed. Model implementation followed this observed RED run.

Focused command after implementation:

```powershell
E:/Python/python.exe -m unittest stream_video_enhance.tests.test_reference.ReferenceTests.test_crop_and_original_center_not_window_corner stream_video_enhance.tests.test_reference.ReferenceTests.test_independent_brute_force_small_images_and_checkpoints stream_video_enhance.tests.test_reference.ReferenceTests.test_signed_ties_unsigned_gain_and_clamp stream_video_enhance.tests.test_reference.ReferenceTests.test_inclusive_configuration_guards stream_video_enhance.tests.test_reference.ReferenceTests.test_patterns_frame_wrap_and_block_edges stream_video_enhance.tests.test_reference.ReferenceTests.test_ratio_bounds_random_windows_and_rounding stream_video_enhance.tests.test_reference.ReferenceTests.test_div25_exhaustive_unrounded_and_correction stream_video_enhance.tests.test_reference.ReferenceTests.test_intermediate_ledger_extrema_and_exact_coefficient_center -v
```

The first focused run passed seven tests but exposed an incorrect test assumption that q0 must overestimate somewhere in the legal range. Exhaustive evidence showed this never happens; see the proof below. The implementation already produced correct floor division everywhere. The false branch-reachability assertion was replaced by an exhaustive assertion of the actual legal-domain property. The focused rerun passed all8 tests in0.227s; its output is in `task-1-focused.txt`.

The initial full GREEN run passed11 tests in32.351s. Tests were then strengthened with exact rational ratio-half ties and aggregate VGA error reporting. Focused tie command:

```powershell
E:/Python/python.exe -m unittest stream_video_enhance.tests.test_reference.ReferenceTests.test_ratio_bounds_random_windows_and_rounding -v
```

Passed1 test in0.123s, saved to `task-1-ratio-ties.txt`.

The final full Task1 suite used the same discovery command as RED and saved its complete output to `task-1-green.txt`:

```text
test_all_constants_eps_modes_and_parameter_extrema ... ok
test_crop_and_original_center_not_window_corner ... ok
test_div25_exhaustive_unrounded_and_correction ... ok
test_inclusive_configuration_guards ... ok
test_independent_brute_force_small_images_and_checkpoints ... ok
test_intermediate_ledger_extrema_and_exact_coefficient_center ... ok
test_local_raw_96_produces_same_central_88 ... ok
test_patterns_frame_wrap_and_block_edges ... ok
test_ratio_bounds_random_windows_and_rounding ... ok
test_signed_ties_unsigned_gain_and_clamp ... ok
VGA numerical gate: 288 cases; error histogram 0/1 LSB=[85812329, 99223]; MAE=0.001154944; RMSE=0.033984462
test_vga_structured_random_final_error_one_lsb ... ok

Ran 11 tests in 32.430s
OK
```

`git diff --check` and `git diff --cached --check` produced no diagnostics before committing. Only the four owned files were staged and committed.

## Numerical coverage

- Independent Python scalar oracle uses 25 separate coefficient-center loops, each with a25-point raw window, without invoking production sum/division helpers. Tests compare exact base_q8 and rounded float base at three selected positions in each16x16/17x19 image for every epsilon. First-round statistics and original-pixel centers are also checked independently.
- Every constant0..255, every epsilon16/64/256/1024, every mode, threshold extrema0/16 and gain extrema0/512 is tested in both paths (DENOISE uses its mandatory256). The loop executes32,768 filter calls; DENOISE gains repeat the legal256 case. All preserve the exact constant.
- div25 exhausts all1,632,013 legal integers against floor(n/25), with explicit unrounded boundary fixtures and no hidden+12.
- ratio checks20,000 independently generated legal25-pixel windows plus V=0/1/10,143,900 for each epsilon against Python-int rational rounding. Exact half ties use V=7567epsilon, giving Q12 ratio3783.5, which must round to3784; the immediate integer neighbors give3783 and3784. A reaches4092 at the maximum variance/epsilon16 as specified.
- Direct enhancement fixtures cover positive/negative half ties away from zero, final Q8 half-up ties, G=512 positive signed multiplication, threshold0/16, residual limiting at16 and output saturation.
- Guard tests reject wrong image dtype/shape/size, non-integer/bool parameters, invalid epsilon/mode, DENOISE gains other than256, variable L, negative/out-of-range divider/variance operands, and invalid aligned base arrays.
- Patterns cover frame counter wrap at2^32, the ramp's modulo256,16-pixel checker boundaries, odd-width x<W/2 step behavior, constant128 and illegal arguments.
- Checkpoint tests inspect min/max/dtype/shape against the ledger for black, white and0/255 checker images for every epsilon. Maximum variance10,143,900 is actually attained.
- VGA gate uses nine640x480 images: the four source patterns, seeded full-range random image, diagonal step, two-pixel lines, seeded sigma8 flat noise, and isolated impulse. Every epsilon is checked with RAW, BASE, two DENOISE threshold extremes, and four ENHANCE threshold/gain corners. There are288 image/config comparisons and85,911,552 output-pixel comparisons. Observed maximum absolute final difference is1LSB;85,812,329 pixels match exactly and99,223 differ by1. Aggregate MAE0.001154944 and RMSE0.033984462.
-96x96 raw input crops at three legal positions, including opposite extremes, produce88x88 outputs exactly equal to the full VGA result at corresponding coordinates for every epsilon/mode and both fixed/float paths.

## Correctness observations and limits

The div25 correction branch is unreachable for the specified legal n range, although the mandated correction is retained unchanged. Since671089*25=2^24+9,

```text
n*671089/2^24 = n/25 + 9n/(25*2^24).
```

For n<=1,632,012,9n/2^24<1. The excess is therefore less than1/25, smaller than the minimum distance of a nonintegral n/25 to the next integer. Thus q0 already equals floor(n/25) everywhere in this domain. This agrees with exhaustive execution. The specification's statement "at most one high" remains true; this does not require changing its algorithm or range.

No other correctness concerns remain in this task. This is numerical-model evidence only. It does not freeze a visual-quality profile, satisfy the later image-quality/holdout gate, demonstrate streaming II=1/timing/resource use, or validate RTL/board behavior. Those remain separate work.
