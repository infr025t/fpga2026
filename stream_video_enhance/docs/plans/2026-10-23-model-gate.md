# V0 model acceptance implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Implement and execute spec section 15.A before any algorithm RTL, freezing a profile only if the registered acceptance checks pass.

**Architecture:** Independent float64 and integer image models implement two valid 5x5 windows. Saved deterministic fixtures and fixed masks drive tuning and independent holdout evaluation. This is the first dependency of the complete V0 implementation; a failing gate requires a documented discussion under spec section 17.

**Tech Stack:** Python 3.14, NumPy 2.4.6, Pillow 12.3.0, unittest; Windows PowerShell.

**Spec:** `stream_video_enhance/docs/spec.md` version 1.1-review, especially sections 4, 5, 10.1, 15.A, 16.

## Global Constraints

- Work in `E:/Vivado_FPGA_Programs/fpga2026`, branch `feat/stream-video-v0`, as explicitly requested by the user. Existing clean cloned checkout and a feature branch provide the requested working location; do not create a different checkout.
- User authorized latest design and implementation on 2026-10-23: “确认最新设计，开始实现”. This supersedes the stale waiting-for-authorization text in the design documents.
- Do not modify `demo/` or `docs/reference/`; do not push or access hardware.
- Single-scale self guided filter r=2, two 5x5 valid windows; input U8; final crop 4 on each side; W/H from 16 through 640/480.
- Float model follows section 4.1; fixed model follows all rounding steps in section 5.1, with integer intermediates and range assertions. No hidden clipping of arithmetic defects.
- Modes RAW, BASE, DENOISE, ENHANCE share the same input and crop; legal epsilon 16/64/256/1024, T 0..16, gain G 0..512 and L=16.
- Final 8-bit max absolute error versus identically rounded float output <=1 LSB. RTL later must equal fixed exactly.
- Register dataset split, noise seeds, fixed masks and two primary enhancement cases before any parameter search. Save input bytes and SHA256 plus software versions. Do not call synthetic UART/RTL evidence a real image.
- Candidate set: shared epsilon in {64,256}, T_D in {2,4,8}, G_D=256, T_E in {2,4}, G_E in {384,448}, L=16. Old G=320,T=4 is comparison only.
- All section 15.A quality thresholds remain binding. If none passes or real image evidence is missing, report the specific gap; never silently relax thresholds or claim a published profile.
- New reports distinguish actual model evidence from future simulation, synthesis, route and board evidence. No algorithm RTL before the gate passes.
- TDD for numerical behavior; record an expected failing test before implementation and passing result afterward. Use independently derived scalar/brute-force expectations, not implementation self-comparison.

## Task 1: Independent numerical references and tests

**Files:** Create `stream_video_enhance/model/__init__.py`, `model/reference.py`, `tests/test_reference.py`, `model/requirements.txt`.

**Interfaces:** `filter_fixed(image, epsilon, threshold, gain, mode, limit=16)` and `filter_float(...)` return uint8 cropped arrays; `fixed_layers(image, epsilon)` returns a dict with `raw` U8, `base_q8` int64, and coefficient/statistic checkpoints; `pattern(width,height,frame_id,pattern_id=0)` returns U8 input. `div25_exact(n)` accepts int64 array/nonnegative integer over section 5.3 range. `ratio_q12(v, epsilon)` returns rounded Q12 using exact integer math. `enhance_fixed(raw, base_q8, threshold, gain, limit=16)` returns uint8; float path must not reuse fixed rounding.

- [ ] Write focused failing unittest cases catching wrong crop, coefficient centering, ties, signed rounding, gain signedness, constant behavior, illegal input/config, div25 correction and pattern frame wrap. Use lazy imports if needed so missing behavior is an assertion failure, not discovery crash.
- [ ] Run `python -m unittest discover -s stream_video_enhance/tests -p test_reference.py -v`; record expected RED.
- [ ] Implement independent float/integer paths, inclusive range guards, 5x5 sums using int64/float64 integral sums. Do not introduce a streaming cycle model at this step.
- [ ] Test small 16x16/17x19 arbitrary images against independent brute-force 25-point loops at selected locations; test all 256 constants at each epsilon/mode and gain/threshold extrema; structured/random QVGA and VGA final max error <=1; compare 96x96 local raw run central 88x88 against full-image result.
- [ ] Exhaust n=0..1,632,012 comparing div25_exact to floor(n/25); its public contract is unrounded division (callers add 12); ratio checks compare to exact RN(4096V,V+625epsilon) at bounds and randomized valid windows. Check intermediate maxima.
- [ ] Run the full new test suite once, report exact command/output and time; commit scoped Task 1 files only. Return status and report with any mathematical mismatch rather than changing spec.

## Task 2: Registered dataset, four-mode quality evaluation and gate report

**Files:** Create `model/dataset.py`, `model/evaluate.py`, `tests/test_evaluation.py`, `reports/model_gate/registration.json`, saved fixtures, `reports/model_gate/metrics.json`, `reports/model_gate/report.md`, four-mode comparisons and edge profiles. Modify README/status/spec only to record authorization, commands and true results; create `model/profile.json` only if the gate really passes.

**Interfaces:** consume Task 1 model API. CLI `python -m stream_video_enhance.model.evaluate --register` writes a registration and immutable final input bytes without running parameter search; `python -m stream_video_enhance.model.evaluate --run` requires the existing registration, validates hashes and generates metrics/report. Expose `psnr(reference,actual)`, `contrast(image,foreground_mask,background_mask)`, `new_clipping(raw,out,mask)`, `temporal_noise(frames,mask)` for independent unit tests. JSON report carries per-check PASS/FAIL/MISSING, selected tuning candidate, all holdout values and aggregate gate status. A failed quality gate returns nonzero exit code while preserving reports.

- [ ] Write and run failing tests using literal MSE/contrast/clipping/temporal fixtures. Test missing registration and altered bytes are rejected, and one failing required check prevents publication.
- [ ] Implement registration with fixed dimensions and masks covering all specified image classes. Noise generation uses NumPy PCG64, normal noise then ties-away nonnegative gray rounding, clip to U8; seed0..4 per sigma2/4/8/16. Distinguish tuning patterns/positions from holdout patterns/positions; declare two independent primary enhancement cases before running search. Save all final input bytes and hash them. Include repeated64frame, independent-noise64frame and moving/exposure sequences.
- [ ] Inspect original single-frame camera evidence and provenance in `demo/stream_image_demo/evidence/`; other generated regression frames are synthetic. Include verifiable real images with masks/paths/hashes; if the required flat/text/texture and exposure classes cannot be supported, mark the gap MISSING rather than fabricate or label an internet/synthetic image as camera evidence. This can block the full gate even when synthetic checks pass.
- [ ] Implement per-section15.A four-mode checks, worst-case and all seeds, line1/2/4, clean steps32/224, details around128 amplitude16/32 with periods4/8, text, gradients, impulse, checker/highlights. Denoise PSNR>=+1dB at sigma8 mean of5, bias<=1; line contrast mean>=80%; step far contrast>=95%/overshoot<=2; enhance>=+5%RAW on both declared holdout cases, flat noise<=1.1RAW at sigma2/4/8, new clipping<=0.001, temporal<=1.1RAW, identical frames exact. Report sigma16 degradation and moving/exposure behavior. No metric based only on BASE can qualify enhancement.
- [ ] Run register and commit registration before `--run` search, then tune only tuning set, evaluate a single selected shared-epsilon profile on holdout and save all candidate summaries. If no tuning candidate meets conditions, evaluate representative failures transparently without postselecting a holdout winner.
- [ ] Run focused and then full tests, execute evaluation, write Chinese report with reproducible commands, image hashes, quantitative results, failures and minimal proposed remedies. Do not publish profile or write algorithm RTL if FAIL/MISSING.
- [ ] Update status/README with implementation progress and exact remaining blockers. Commit scoped files and provide full report.

## Dependency and preflight review

| Tasks | Producer/consumer | Finding |
|---|---|---|
| 1 internally | float and fixed paths, tests with independent loop oracle | compatible; float must retain continuous B until final rounding |
| 2 internally | registration before search, one tuning choice before holdout | compatible; missing camera classes remain visible |
| 1 -> 2 | filter APIs, crop, legal parameter range | compatible; fixed final dimensions W-8/H-8 |
| 2 -> future RTL | only a passing published profile permits algorithm RTL | binding gate; future RTL plan follows only on PASS |

## After the model gate

On PASS, create and execute the RTL implementation plan for the section16 modules, key-module simulation/local synthesis and L_CORE freeze, QVGA/VGA full regressions, protocol integration and route. On FAIL/MISSING, preserve executable evidence and ask the user about the specific required adjustment under spec section17; continue independent verification without writing algorithm RTL.
