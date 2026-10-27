# Task 4 execution report — finegain-v3

Completed 2026-10-24 after an account usage-limit interruption. The official run completed on disk; recovery verified its outputs without repeating candidate search or holdout evaluation. Directory E:/Vivado_FPGA_Programs/fpga2026, branch feat/stream-video-v0. No subagents/reviewers were spawned for Task4. TDD and verification-before-completion skills applied. No algorithm RTL was written.

## Outcome and ordered commits

- Parent preflight documentation HEAD: 5c474edbbdbabd0d6e242527ac656fd1a3ab4bfb (Task3 review basis20d054b retained).
- Code/tests BEFORE registration/search: f1adeba54c925ccf453141dbec8b2807ec6ee81c.
- Registration/archive BEFORE evaluation: 747c5da2ef8054748e8ac01ebb1fb9d64d9c3d47.
- Results/profile/test evidence: ab19a61; full identity via git rev-parse ab19a61.
- This report and spec/status/README follow in the documentation commit; resolve via git log -1 --format=%H -- .superpowers/sdd/2026-10-23-model-gate/task-4-report.md.

Controlled PASS, CLI exit0:51 complete tuning outcomes,15 feasible, exactly one selected config assessed on new holdout. profile_id=1:epsilon1024,T_D2,T_E4,G_E428,L16. All17 frozen required checks PASS. No formula/rounding/bitwidth/threshold/VGA-dimension/interface changes. Fixed_layers/filter_fixed/filter_float API and reference.py bytes unchanged.

## Implementation and RED/GREEN

Shared registration/evaluation extended without copying a full evaluator. Original-v1/expanded-v2 retain first-feasible replay. Finegain-v3 alone admits the exact epsilon[1024]/TD[2,4,8]/TE[4]/G=list(range(384,449,4))/L16 grid; other grids are rejected. Loader explicitly enforces the independently frozen two-primary IDs in each split, case/split/class/clean/sigma/seed/mask associations, all17 required checks, DEFERRED/nonrequired camera/RTL policy, and registered selection policy.

Four tests preceded implementation. Initial unsupported-experiment errors were converted to explicit assertions; final RED rerun before production edits:4 tests,4 expected FAIL (Unknown registered experiment:finegain-v3). GREEN:4 PASS in2.326s; broader evaluation regression:26 PASS in7.762s. Tests cover literal geometry/text/masks, all17 gains, disjoint streams versus both rounds, maximin score/TD-before-G ties/failed-check exclusion/diagnostic fallback, old first-feasible selection, policy/grid tampering, and omitted/replaced/reordered/duplicate primary IDs plus corrupted case bindings/inventory. Logs preserve actual outputs.

Commands from repo root (the same focused command was used for RED and GREEN):

```powershell
python -m unittest stream_video_enhance.tests.test_evaluation.EvaluationTests.test_finegain_grid_is_exactly_51_legal_candidates stream_video_enhance.tests.test_evaluation.EvaluationTests.test_finegain_primary_and_random_streams_are_new_against_both_rounds stream_video_enhance.tests.test_evaluation.EvaluationTests.test_finegain_selection_maximizes_worst_primary_then_lowest_td_gain stream_video_enhance.tests.test_evaluation.EvaluationTests.test_finegain_loader_preserves_17_checks_primary_binding_and_selection -v
python -m unittest stream_video_enhance.tests.test_evaluation -v
python -m stream_video_enhance.model.evaluate --experiment finegain-v3 --register --report-dir stream_video_enhance/reports/model_gate_round3
# Commit registration/archive/generator BEFORE evaluation
python -m stream_video_enhance.model.evaluate --run --report-dir stream_video_enhance/reports/model_gate_round3
python -m unittest discover -s stream_video_enhance/tests -v
```

Register exit0:802 cases/907 arrays. Official model exit0, recorded in logs/run-exit.txt. Model subprocess numerical regression:11 PASS in27.327s. Final full suite executed once on recovery:37 PASS in35.273s,exit0.288 VGA cases maximum fixed/float error<=1 LSB; histogram[85812329,99223],MAE0.001154944,RMSE0.033984462. No source changes after final tests.

## Preregistration and selection

New text BRAM 2026 / Smooth Gain / Video Core at(17,9); adjacent-background mask remains5x5 dilation minus strokes. Texture(2*x+y+3)%period<period/2; same classes and period4/amplitude32 primary. Noise/temporal entropy2026102303, split/pattern/sigma/seed separation. BEFORE registration commit, each new primary was compared to all old round1/round2 arrays (including every sequence frame) and all current tuning arrays/frames:3519 comparisons each,zero matches.762 noisy/temporal arrays differ from both old rounds; temporal split streams differ. Canonical stress and public photographic regions explicitly reused. preregistration_checks.json committed with inputs before filtering.

Selection was fixed before search:among candidates passing ALL tuning checks maximize the minimum of the two primary ENHANCE/RAW contrast ratios; ties lowestTD then lowestG; if none feasible first only diagnostic. Recovery reselected from saved tuning outcomes and matched index11,margin1.0821705143191118. Each TD has feasible G412/416/420/424/428. G408 misses text(1.040473),G412 passes(1.050523),G428 highest feasible margin,G432 overshoots3(limit2). All51 outcomes and full failure inventory/frontier are saved in metrics.json; report.md tabulates all. No holdout ranking or exploratory configs were used.

## Required-check evidence

- flat_sigma8_psnr: PASS; value=1.9056098408504318.
- flat_mean_bias: PASS; value=0.19640151515150706.
- clean_line_retention: PASS; value=0.9507639244711875.
- clean_step_far: PASS; value=1.0.
- default_step_overshoot: PASS; value=0.0.
- enhance_step_overshoot: PASS; value=2.0.
- primary_holdout_text_low_clean: PASS; value=1.0879719748601553.
- primary_holdout_texture_p4_a32_clean: PASS; value=1.125.
- flat_noise_sigma2: PASS; value=0.23120994673173179.
- flat_noise_sigma4: PASS; value=0.6474112762156886.
- flat_noise_sigma8: PASS; value=1.018570952149521.
- new_clipping: PASS; value=0.0001893939393939394.
- repeated64_exact: PASS; value={"RAW": true, "BASE": true, "DENOISE": true, "ENHANCE": true}.
- temporal64_noise: PASS; value=1.0124511359950088.
- tuning_feasible: PASS; value=15.
- numerical_model: PASS; value=null.
- real_image_classes: PASS; value=null.

Real exposure, actual camera video, future RTL bit-exact evidence remain DEFERRED/nonrequired. Real-image class check uses registered flat/text/texture regions and nonempty masks; no clean photographic reference/PSNR invented. Public photos and OV7670 graphite have separate provenance.

## Conditions, costs and remaining work

PASS supports registered controlled primary clean text/texture plus frozen noise/halo/clipping/stability gates. It does not establish universal enhancement or actual camera/hardware performance. Worst registered line ratio0.9786685511; sigma16 text1.0363643801(below+5%); worst texture1.0555030223. ENHANCE step overshoot2 is exactly at limit. Sigma8 spatial/temporal noise ratios1.0185709521/1.0124511360; new clipping0.00018939394=0.018939%,below0.1%. Review this traceable profile before the subsequent section16 RTL plan, key-module simulation/local synthesis/L_CORE freeze/integration/route. Actual exposure/camera-video evidence stays for camera integration. No synthesized resource/timing/board claim.

## Preservation and source provenance

614 tracked files under both old experiment dirs, numerical evidence, demo/stream_image_demo and reference.py were hashed before edits and verified unchanged before registration and on recovery. preservation-before.json archives the snapshot; historical FAIL conclusions and every prior input/report byte remain unchanged.

capture_execution_sources bound committed sources at entry before numeric work; verify_execution_sources checked stable bytes/inventory and clean execution sources before publication. Existing dirty/staged/untracked/missing/change-during-run tests PASS. Recovery compared all6 current source hashes with bundle and git show at entry commit, and verified profile/config/check/registration/archive bindings. Execution source commit747c5da2ef8054748e8ac01ebb1fb9d64d9c3d47; registered generatorf1adeba54c925ccf453141dbec8b2807ec6ee81c. Later documentation HEAD does not replace entry identity.

Actual-byte SHA256 values (original Windows CRLF retained where emitted):

- registration: 4313e070de338caa2abf3e21c3370814dcbd45420c6752af92628e226cb52c34
- archive: 270f74a61befab69eb8a373154d442b4e0592137c8bf93987b472e1ac829cae8
- metrics: 18181b0d6144fbf17a36132de0721f3c077f5f8ac090a14312f651743d7b74af
- profile: 0817488e0e5de12c1b863caa20295bb2633a973f21869e536ae23fabe461701f

Execution source hashes:

- stream_video_enhance/model/__init__.py: e5350052deba5eeadf6db512180a81103214e31b734e92ca51eee25716ad7798
- stream_video_enhance/model/dataset.py: e10f68548f4f86357b5f970394c98452d4aa0046cdfd1ae521e01c2fb11616b9
- stream_video_enhance/model/evaluate.py: 978aaec4bf1ec208657ccc42c8ba9e7703365880e64bc29a7aa6e75325f94b1a
- stream_video_enhance/model/reference.py: 71d90bd1ce2889f36f3b750e469a4d48bdc46f318533c7c2132ff8f7176bef33
- stream_video_enhance/tests/test_evaluation.py: cf899659ddd14e1bfe7d88cf59669e37b5d8c86800b91291995bd2a8887b8e5e
- stream_video_enhance/tests/test_reference.py: e5b57453383ad2c5eea33e9615a18f50383a1c0f6035323c22e56642bed10feb

Log hashes (also log_hashes.json):

- stream_video_enhance/reports/model_gate_round3/logs/final-tests-exit.txt: 13bf7b3039c63bf5a50491fa3cfd8eb4e699d1ba1436315aef9cbe5711530354
- stream_video_enhance/reports/model_gate_round3/logs/final-tests.txt: 893a13dafff7c4693f9c8a6947c7bcdaf3bb8e0c11c0e53e7114d997ed04f042
- stream_video_enhance/reports/model_gate_round3/logs/preregistration_checks.txt: ff57ed29dcb39b99ef06ee7240a5fc2cb37c2b5f67205b43fe78ecd627b00aba
- stream_video_enhance/reports/model_gate_round3/logs/register.txt: ed11d537ada66bea4de15991e86c57fa5e8311317f2e74753cacc4913b48da47
- stream_video_enhance/reports/model_gate_round3/logs/run-exit.txt: 13bf7b3039c63bf5a50491fa3cfd8eb4e699d1ba1436315aef9cbe5711530354
- stream_video_enhance/reports/model_gate_round3/logs/run.txt: 128b246dd97b51f87aa2775dc803426c1e20480c326f0890c83f5b29283aee49
- stream_video_enhance/reports/model_gate_round3/logs/tdd-green-evaluation.txt: 09db2a75c4f0ea05443d58963b9a2a4bff3deec66da85ed1fb59dd205408a388
- stream_video_enhance/reports/model_gate_round3/logs/tdd-green-focused.txt: 4c01908a01cef7521e51b12a4950447883723c807bfc34c04bb6e39f7ef27857
- stream_video_enhance/reports/model_gate_round3/logs/tdd-red.txt: ec45a30035bdf68e83fe0f6ca42b0cb1303eca75c3897d91f9fd483992c14781
- stream_video_enhance/reports/model_gate_round3/logs/verification.txt: 3dd75b260b4da2569715f2a34da214d01369e0eb6d2cd777aafd118ec6479d2d
- stream_video_enhance/reports/model_gate_round3/numerical_tests.txt: 0d1220a44cb757dde137f06c494e3bb3548390a0dd76a485b84a4c5260bd8ac3

Plain git diff --cached --check flags generated CRLF evidence lines as trailing whitespace; original profile/log/snapshot bytes were retained for stable hashes and stdout. Validation uses core.whitespace=cr-at-eol to distinguish Windows line endings. No rerun, evidence normalization, threshold relaxation, RTL edit, remote push or memory update on recovery.


## 2026-10-24 final documentation review fix

Whole-branch review found no P0–P2 issues and one P3 README ambiguity. README now explicitly distinguishes evaluate --run exit0(PASS), exit1(FAIL/MISSING), exit2(invalid input/registration) from the independent unittest result. The current example and prose both identify finegain-v3 and require committed execution code, a new empty registration directory, committed registration/archive/sources, then --run. Default original-v1 replay remains documented.

This fix changes prose only. No tests, model search or holdout evaluations were rerun; the previously recorded 37-test PASS remains the validation evidence. Git diff/check and byte verification confirm all tracked model sources, profile, dataset inputs and existing results/evidence retain their committed bytes. No thresholds, formulas or RTL changed.
