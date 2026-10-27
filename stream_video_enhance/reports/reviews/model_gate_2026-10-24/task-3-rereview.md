# Task 3 fix round1: scoped rereview

Reviewed range: `f4fb6af..20d054b`. Corrective implementation: `dfce26a`; corrective evidence: `20d054b`. Reviewed the original brief, original review, appended implementation report, fix diff, added tests and preserved evidence. This is a scoped rereview of the two original P2 findings and breakage introduced by their fixes.

## Verdict

**SPEC COMPLIANCE: PASS for the Task3 correction.** Both original P2 findings are **ADDRESSED**. The official expanded-v2 quality result remains **FAIL**, with no feasible candidate, no published profile and no algorithm RTL authorization.

**CODE QUALITY: PASS for this fix range.** No new actionable issue or fix-induced regression was found. No remaining P0/P1/P2 finding blocks the correction.

## Original P2: editable primary inventory — ADDRESSED

- `stream_video_enhance/model/dataset.py:222-225` independently fixes both tuning and holdout primary lists to the text and period4/amplitude32 clean targets. The loader no longer derives the primary contract from editable metadata.
- `dataset.py:226-233` requires exactly one case for each target and checks its split, category, clean self-reference, sigma0, seed and expected mask identifiers. `dataset.py:234-237` checks the complete required inventory against those independently fixed targets.
- Added tests cover empty, partial, duplicate, reversed and wrong-class primary lists across both splits, including matching edits to the required inventory; association tests cover missing/duplicate/wrong split/category/clean/sigma cases. The archived meaningful RED has16 failing subtests before the fix; GREEN contains the corrected tests.
- Independently repeated the original omission reproduction using only an in-memory patched registration. The loader now raises `Expanded primary targets must exactly match the frozen two-class contract` before reading the archive. No registered file was changed.
- The validation remains specific to expanded-v2 and leaves original-v1 primary/replay validation semantics intact. Archived inventory evidence confirms the original expanded-v2 registration remains valid with17 required checks and907 arrays.

## Original P2: late execution HEAD/source binding — ADDRESSED

- `stream_video_enhance/model/evaluate.py:16-28` hashes the required six model/test Python files plus any additional Python sources beneath those source directories; missing required files are rejected.
- `evaluate.py:31-50` captures entry HEAD, rejects dirty/staged/untracked source paths, compares current source hashes to that commit's Git blobs, and returns an entry identity bundle. `evaluate.py:53-59` rejects changed source bytes or inventories while allowing unrelated HEAD changes.
- `evaluate.py:360` captures the bundle before registration loading, numerical regression or any filtering. `evaluate.py:396` revalidates it after evaluation and before the expanded publication path. `evaluate.py:398-415` uses the entry commit and full bundle in metrics/profile, replacing the former end-of-run HEAD lookup.
- Added tests use actual temporary Git repositories and independent source fixtures. They reject dirty/staged/untracked/missing entry sources and modified/new/committed-changed sources during execution; they accept a documentation-only commit without replacing the entry identity. This exercises the actual Git/hash checks rather than mocking their success.
- Independently verified the saved `dfce26a31ef007f9320eb9fc21c47ea063787825` source bundle in the current repository after evidence-only HEAD advanced to `20d054b9e2c3185285dd467b28fea963fbf613c0`. A fresh capture also passes, covers six files, and has identical source hashes. No search or filtering was performed.

## Fix breakage and verification evidence

- No formula, rounding, metric threshold, candidate enumeration or holdout-selection changes occur in this correction. The new validation runs before expensive computation; final source validation precedes profile publication. The legacy publication path also rechecks source identity.
- Inspected `reports/model_gate_review_fix/green.txt`:22 tests in17.898s,OK. Inspected `full_suite.txt`:33 tests in110.771s,OK. These are existing implementation evidence, not suites rerun by the reviewer. The report retains the288 VGA cases and unchanged numerical error evidence.
- `git diff --name-only f4fb6af 20d054b` scoped to both official model-gate report directories, `model/reference.py` and `demo/stream_image_demo` is empty. The preservation artifact records62 unchanged archived files. `model/profile.json` is absent and the tracked working tree is clean.
- Only the in-memory rejection reproduction and read-only source-guard APIs were executed during rereview. No official search, suite, source edit or git mutation was performed. This review file is the sole written output.

## Out-of-scope observations

- The range contains an added future finegain-v3 plan. Its authorization interpretation, proposed grid, new holdout and selection policy are not evaluated by this correction review; no such experiment was performed here.
- A future known experiment must explicitly enter the frozen-primary/required-inventory validation and strict real-class/publication paths. Merely changing an experiment label must not be treated as extending expanded-v2 validation. This is a dependency for future work, not a newly introduced Task3 defect.
- Existing physical exposure/camera-video gaps remain DEFERRED. Missing camera-module documentation and later hardware implementation are separate work and do not alter the scoped verdict or the preserved measured FAIL.
