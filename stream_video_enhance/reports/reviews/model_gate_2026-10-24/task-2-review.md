# Task 2 independent review

Reviewed range: `03b5eca..95ba7ab`. Review is read-only except this review document. The original Task 2 requirements are binding; the later expanded-v2 authorization does not retroactively change this round. No full test suite or candidate search was rerun.

## Verdicts

- **SPEC COMPLIANCE: CHANGES REQUIRED (one P2 evidence defect).** The registered experiment, numerical acceptance rules, original 24-candidate search, tuning-only choice, honest FAIL/MISSING result and publication prohibition are implemented. One of the three required edge profiles does not cross its edge.
- **CODE QUALITY: CHANGES REQUIRED (P2 below).** Metric primitives and failure aggregation are clear and use appropriate floating/signed arithmetic. The profile extraction needs direction-aware sampling. A separate P3 robustness suggestion concerns real-image class validation.
- **MODEL QUALITY GATE: correctly FAIL.** No model profile or algorithm RTL is present. The failed enhancement ratios and absent real-exposure evidence are experimental outcomes, not implementation bugs, and must remain recorded as such.

## Findings

### [P2] Horizontal edge profile samples along the edge instead of across it

**Location:** `stream_video_enhance/model/evaluate.py:201` (and output `reports/model_gate/edge_profiles.json`, horizontal section).

All three directions use the middle horizontal row. For a horizontal step, intensity varies vertically, so this samples a constant plateau and cannot show the transition, its shape, or a halo. Direct inspection of the saved JSON confirms every horizontal profile contains only `[32]` as its set of distinct values, for RAW, BASE, DENOISE and ENHANCE. Consequently `edge_profile_horizontal.png` is a set of flat coincident traces, and the delivered horizontal edge profile does not satisfy the required three-direction edge-profile evidence. The numeric far-contrast and overshoot checks operate on full images and are not invalidated by this plotting bug.

**Fix:** sample the middle column for horizontal edges, retaining the middle row for vertical edges; explicitly describe the sampling axis. Add a small independent fixture that asserts both 32 and 224 occur in each clean step profile. Keep the original registered inputs, registration and original FAIL untouched. If original result bytes are frozen, save corrected supplemental profile evidence separately and record the defect; apply the corrected extraction to subsequent experiment reports.

### [P3] Real-image class gate counts files rather than registered classes

**Location:** `stream_video_enhance/model/evaluate.py:241-242`; supporting registration code `stream_video_enhance/model/dataset.py:121-130`.

`real_image_classes` passes whenever at least three cases have category `real`. All three registered cases use this same category, and the only photographic masks are whole-image high/low quantiles. No metadata maps the photos or regions to the required flat/text/texture classes, so this check cannot establish class coverage: three images of the same class would also pass. The current photos plausibly supply those visual contents and their provenance is honest; this is a validation weakness, not a claim that the current images are fabricated or that the original overall FAIL should change.

**Recommendation:** explicitly register real-image/region class labels and corresponding fixed masks, then verify the required class set and nonempty masks, returning MISSING for absent classes. Test three same-class images and one missing class. Any changed registration belongs to a new experiment; preserve original round bytes and annotate its limited class-check semantics.

## Requirements and artifact audit

- Preregistration commit `cfe857b5fc811c283d5c317006ea5313dc3b70d7` is an ancestor of head. Its archived registration and input archive are unchanged through `95ba7ab`. The runtime also rejects absent registration, archive inventory/hash mismatch, changed array shape/dtype/bytes and an uncommitted/modified registration before search.
- Current archive validation succeeded: **801 cases, 891 arrays, eight 64-frame sequences**, tuning399 / holdout402. SHA256 of `inputs.npz`: `d208e84909b41c066e0f07428826d7e15ce7b71524db1ea80f7c4c748b7d6c4a`. SHA256 of `registration.json`: `452a24b753dad1c849cbca0a2f004326909ace511edd3904d28a56fd6d3f8280`.
- Synthetic fixed dimensions, crop4, all listed pattern classes, sigma2/4/8/16 with seeds0..4, PCG64 streams, saved input/mask bytes, independent split geometries and text/texture primary declarations are present. The original grid is exactly epsilon64/256 × TD2/4/8 × TE2/4 × GE384/448, L16, giving24 candidates.
- All candidates are assessed on tuning first. Zero feasible tuning candidates leads deterministically to preregistered candidate0 as diagnostic only; the official holdout configuration is epsilon64/TD2/TE2/GE384/L16. Original G320 control and explicitly nonqualifying post-gate G512 diagnostic are distinguished from the official search and do not alter selection or publication.
- Four modes consume the same input, output crop and fixed masks. Literal tests independently exercise PSNR/MSE, contrast, newly clipped fraction and pixelwise population temporal standard deviation. Registration, tampering, rounding and failure/missing/unknown required-state publication tests are present. Saved final test log records20 tests /36.808s /OK; no unnecessary rerun was performed.
- Saved metrics and Chinese report agree: primary holdout ratios **0.954965560565542** and **0.9375**, tuning feasible0, gate FAIL, profile_published=false. DENOISE sigma8 PSNR improvement1.7655222345dB, bias0.0806818182, clean-line mean0.9895833333, far-step1.0, overshoot0, new clipping0 and temporal ratio0.9635848206 are consistently reported. Sigma16/all seeds, worst detail cases, moving and simulated-exposure sequences are retained.
- All three registered source file SHA256 values match their present files. Actual OV7670 graphite RAW provenance is separate from the two public scikit-image photos. Photos have no fabricated clean reference or PSNR. Real exposure is required MISSING in this original round; actual camera video is separately MISSING/nonrequired, and future RTL comparison DEFERRED/nonrequired. Aggregate required FAIL/MISSING cannot publish a profile.

## Evidence and limits

Reviewed the source/test diff once using the code companion and checked relevant original-spec clauses15.A against source and artifacts. Inspected generated corpus by inventory, archive/per-array validation, source hashes, selected config/check summaries and saved profile values rather than manually reading every numeric row. The only focused experiment was a read-only artifact/hash inventory and unique-value inspection of the saved horizontal profile. No implementation edits, commits, full test reruns, external downloads or parameter searches were made.

The P2 defect affects one visualization, not the original registered numerical FAIL. Preserve the original experiment and address reporting correctness before treating Task2 evidence as fully reviewed; Task3 can implement the fix under its separate registration and policy.
