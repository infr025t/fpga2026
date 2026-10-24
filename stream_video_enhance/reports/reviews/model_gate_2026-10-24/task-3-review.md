# Task 3 expanded-v2 specification and code quality review

Reviewed range: `475f205..f4fb6af`. Review date: 2026-10-23. Binding requirements: `task-3-brief.md` plus the parent's expanded-v2 review contract. This review excludes the prospective finegain-v3 experiment and later hardware work.

## Verdict

**SPEC COMPLIANCE: CHANGES REQUIRED.** The completed official experiment follows the authorized 72-point grid, registration-before-search procedure, independent holdout selection, preservation and reporting requirements. Its measured FAIL is valid. Two implementation protections remain incomplete: required primary targets can be omitted through a self-consistent malformed registration, and published execution provenance is not bound to the code actually executed.

**CODE QUALITY: CHANGES REQUIRED.** Fix the two P2 findings before another experiment or any future profile publication. No algorithm defect or reason to rerun this completed search was found. No profile or algorithm RTL is authorized by the archived result.

## Findings

### [P2] Validate primary targets independently of the editable required inventory

- Location: `stream_video_enhance/model/dataset.py:219-222`; related `dataset.py:24-28`, `evaluate.py:165-168` and `evaluate.py:358-365`.
- The expected inventory is generated from `registration['primary_enhancement']` itself. Setting its holdout list to `[]` and removing the two corresponding required-check entries makes the weakened inventory agree with `expected`. `load_registration()` accepts it, and `assess()` then creates no primary holdout enhancement checks. Consequently the publication gate no longer requires the two frozen RAW+5% targets. A partial omission similarly removes one of the binding targets.
- Focused read-only reproduction: loaded the official registration/archive with `Path.read_text` patched in memory to return that altered JSON. All original archive/array hashes still verified; the loader accepted **15 required checks and zero primary required checks**. No file, search or test suite was changed or run.
- Fix: validate the frozen expanded-v2 primary lists independently (exactly the registered text and period4/amplitude32 targets for both splits), including their split/category/clean-case correspondence, before deriving/checking the required inventory. Keep the original-v1 replay contract unchanged. Add focused rejection tests for omitted/partial/wrong-class primary lists even when `required_checks` is edited to match. Preserve the official round2 registration and result bytes.

### [P2] Capture and verify execution source provenance before evaluation

- Location: `stream_video_enhance/model/evaluate.py:315-322` and `evaluate.py:350-364`.
- The preflight checks only committed registration/input bytes. The executable dataset/evaluator/reference/tests can have local changes, while `source_model_commit` is taken from `git rev-parse HEAD` only after numerical tests, all candidates and the holdout finish. An uncommitted model edit, or a source commit made during that long interval, can therefore produce a profile naming a commit that does not describe the executed implementation. The registration's generator commit does not establish execution provenance.
- Fix: capture execution identity and hashes of the relevant model/numerical-test sources at run entry, require those bytes to match a recorded committed revision before filtering, and verify that they have not changed before publication. Use that entry identity in metrics/profile. Allow unrelated documentation commits when source hashes remain identical. Add bounded tests that reject dirty/changed model sources and preserve the entry identity across an unrelated HEAD change; no full search is needed to test these paths.
- This is a publication-path risk, not evidence that the archived round2 run used different arithmetic: `git diff 90b8277 d36c7c2 -- stream_video_enhance/model` is empty. The existing report explicitly records the generator and later execution HEAD separately.

## Verified strengths and actual outcome

- Inspected the source/test diff and package inventory; inspected generated evidence by manifest, hashes, source provenance and parsed summaries rather than manually reading every metric row. The full package includes unrelated camera preflight and gated future RTL-plan documentation; neither introduces algorithm RTL in this task.
- `load_registration()` independently verified all **907 arrays / 802 cases**, archive SHA256 `9691656a1336738474000220f04a49703e964c1463707fb39a566a6fba8bc5d6`, and registration SHA256 `7ed05a28f3aa5a3aaeb3b5a30e179cffb28662c1f23748b40ed7c73eae41545b`.
- Generated configuration list contains exactly **72 unique candidates in declared ascending order**, matching every archived candidate configuration. The registration commit is `6b6ccc78f0d829b636a236aacc1dee80166db4eb`; implementation is `90b8277`.
- Both new primary clean arrays differ from every round1 two-dimensional U8 array and every new tuning two-dimensional U8 array. The code provides the declared independent entropy2026102302 noise/temporal streams; reused canonical fixtures are explicitly identified as non-novel evidence.
- New real-image coverage checks the actual flat/text/texture label set and nonempty cropped masks. Verified foreground/background counts: flat2745/2925, texture8227/8124, public text23034/22588, graphite text21534/21637. All three registered source-file hashes match. Photographic rows report observed region statistics without fabricated clean-reference PSNR. Original-v1's file-count limitation is explicitly historical.
- Archived result is **FAIL, zero feasible tuning candidates, exactly one holdout configuration**: first registered diagnostic epsilon16/T_D2/T_E2/G_E384/L16. Its three required failures are tuning_feasible and the two primary holdout ratios **0.9298255928 / 1.0**, versus1.05. The remaining14 controlled checks pass. The three allowed later evidence categories are nonrequired DEFERRED, not PASS.
- `model/profile.json` is absent. No new algorithm RTL is present. No holdout ranking or extra expanded-v2 exploratory configuration was found in the execution path.
- `git diff --name-only 475f205 f4fb6af -- stream_video_enhance/reports/model_gate demo/stream_image_demo stream_video_enhance/model/reference.py` is empty, consistent with the archived573-file preservation evidence. Formula/rounding/reference and original round1 bytes remain unchanged.
- Existing logs show28 tests in101.226s and embedded numerical11 tests in92.434s, bothOK. These logs were inspected, not rerun. No official search, full suite, numerical suite, git mutation or source edit was performed during this review.

## Follow-up boundary

Fix the two gate protections with focused tests, then retain this experiment as its measured failure. The 72-point numerical result does not require another evaluation because of these safeguards. Any separately authorized finegain-v3 registration/search remains a separate task; no later camera-module documentation or physical measurement is implied by this review.
