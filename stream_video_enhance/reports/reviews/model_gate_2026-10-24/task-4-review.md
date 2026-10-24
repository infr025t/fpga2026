# Task 4 scoped specification and code-quality review

Review date: 2026-10-24. Scope: Task 4 only, BASE `20d054b`, HEAD `b06e119`, using task-4-brief.md, task-4-report.md, task-4-code.diff, actual sources, committed history and generated evidence. Current checkout also contains later documentation-only commit `0c16384`; that commit is outside this verdict. Broad final review and RTL implementation are separate gates.

## Verdict

**PASS for the Task 4 controlled model gate, with one nonblocking P3 documentation correction.** No P0/P1/P2 findings or actionable implementation defects found. The evidence supports profile_id=1, epsilon=1024, T_D=2, T_E=4, G_E=428, L=16 for the registered controlled scope. This is not a hardware or universal-image-quality result.

## Actionable finding

- **[P3] Update the stale reproduction paragraph after changing the command block.** `stream_video_enhance/README.md:23` says the “first command” returns 1 and preserves a report on quality failure, but the first command is now `unittest discover` at line 16. Passing unit/numerical tests can coexist with a failing quality gate, as the preserved earlier experiments demonstrate. The same paragraph still instructs registration of `expanded-v2`, while the immediately preceding current-experiment example registers `finegain-v3`. Identify `evaluate --run` explicitly as the quality-gate exit-code command and use finegain-v3 for the current experiment, or label expanded-v2 clearly as historical replay. This does not affect the saved experiment or profile.

## Specification compliance

| Binding requirement | Review result |
|---|---|
| VGA-only 640x480 to 632x472; unchanged 5x5 arithmetic, widths and rounding | PASS. No reference.py or RTL changes in the reviewed diff. Formal dimensions remain in the specification/RTL-plan constraints; smaller numerical fixtures are still test fixtures. Actual VGA numerical evidence is recorded separately below. |
| Exact bounded 51-candidate grid and legal parameters | PASS. dataset.py validates the complete experiment-specific grid and policy; evaluate.py consumes registered values. Saved configurations exactly equal epsilon=[1024], T_D=[2,4,8], T_E=[4], G=384..448 step4, L=16, in registered product order. Fine gains remain inside reference.py's unchanged integer G=0..512 range. |
| Preregister new primary text/texture and independent noise before search | PASS on available committed evidence. Code/tests commit f1adeba precedes registration/archive/preregistration_checks commit 747c5da, which precedes result commit ab19a61. Registration and archive bytes exactly match 747c5da. Literal text, position, geometry, clean intensities, foreground and 5x5 adjacent-background masks match the brief. |
| Independence against previous rounds and current tuning | PASS. Read-only comparison found no matching primary image among old arrays/sequence frames or current tuning arrays/frames. Preregistration's 1403/1419/697 counts per primary include each sequence array itself plus its individual frames, totaling 3519; image-only comparisons also have zero matches. All 762 noisy/temporal arrays differ from both old rounds; tuning/holdout temporal arrays differ. Canonical fixtures and public photographic regions are explicitly marked reused. |
| Fixed tuning feasibility/maximin selection/ties | PASS. select_candidate uses tuning checks and the registered two-primary minimum, then lowest T_D and lowest G_E. Saved 51 outcomes contain 15 feasible candidates. Independently ranking the saved values yields index 11, margin 1.0821705143191118 and G428/T_D2. No hardcoded winning gain or report location drives selection. |
| Exactly one holdout configuration | PASS within the executable path and saved evidence. run calls assess once for holdout after selection, and finegain-v3 returns before legacy exploratory/control holdout branches. Saved holdout config equals selected/profile config and count=1. Figure generation recomputes selected-config outputs only; it does not rank or assess additional configurations. |
| All 17 frozen required checks before publishing | PASS. Loader checks the frozen primary inventory/case associations, required-check inventory and DEFERRED policies. Publication requires aggregate PASS with the explicit required list; all 17 saved checks and profile status bindings are PASS. No acceptance threshold changed. |
| Source-commit/hash binding and traceable profile | PASS. All six current execution source hashes match the bundle and git-show bytes at both f1adeba and entry commit 747c5da. Profile, metrics, registration, input archive, generator commit and entry-source identity agree. Later documentation HEAD does not replace entry identity. |
| Preserve old 24/72 FAIL and baseline bytes | PASS. All 614 snapshot entries match actual bytes. Git diff 20d054b..b06e119 has no changes under either old experiment directory, demo/stream_image_demo, or model/reference.py. Both historical FAIL conclusions remain. |
| No RTL/hardware claims; exposure/video deferred | PASS. Only model/test/profile/report/docs changed. Actual exposure, actual camera video and future RTL bit-exact checks remain DEFERRED/nonrequired in metrics and profile. Documentation states the controlled scope and missing hardware evidence. |

## Code quality and tests

The extension reuses registration, assessment, reporting and provenance logic rather than copying an evaluator. A small experiment-specific validator contains the bounded grid/policy contract; a separate selection function makes the maximin and tie behavior reviewable. Old experiments retain first-feasible selection. The tests cover all 17 gain values, literal new primary definitions/masks, both historical noise streams, maximin versus average, T_D-before-G ties, failed-check exclusion, fallback and policy/inventory/case tampering. No new production arithmetic or interfaces were introduced.

Verified actual saved output, without rerunning any suite or model search:

- Focused RED: 4 tests, 4 failures for unsupported finegain-v3 before implementation; GREEN: 4 tests in 2.326s, OK.
- Evaluation regression: 26 tests in 7.762s, OK.
- Official model numerical subprocess: 11 tests in 27.327s, OK.
- Final full suite: 37 named `... ok` entries, `Ran 37 tests in 35.273s`, `OK`; final-tests-exit.txt is 0.
- Recorded VGA numerical output: 288 cases; 0/1-LSB histogram [85812329,99223], MAE 0.001154944, RMSE 0.033984462.
- Official run stdout records PASS, 51 candidates, 15 feasible, one holdout config, profile published, no required failures; run-exit.txt is 0.
- All 11 archived log hashes match actual files. Commands in the execution report correspond to the test modules/case names and run output present in these logs.

Read-only verification also checked the archive's 907-array inventory, shape, dtype and per-array SHA256, registration/archive/profile/metrics binding, exact candidate order, selected ranking, commit ancestry and preservation hashes. No filtering, test suite, candidate search or additional holdout assessment was executed during this review. No Git/worktree mutation was performed; this review file is the only written artifact.

Key hashes independently matched: registration `4313e070de338caa2abf3e21c3370814dcbd45420c6752af92628e226cb52c34`; archive `270f74a61befab69eb8a373154d442b4e0592137c8bf93987b472e1ac829cae8`; metrics `18181b0d6144fbf17a36132de0721f3c077f5f8ac090a14312f651743d7b74af`; profile `0817488e0e5de12c1b863caa20295bb2633a973f21869e536ae23fabe461701f`.

## Limits and items not independently verifiable

Commit ordering, source control, archived inputs and logs support preregistration and the one-holdout execution path. They cannot prove that no unrecorded exploratory run ever occurred outside the repository. Saved stdout does not itself contain a full shell/process audit; exact historical invocation is corroborated by the report, source path and named output rather than an independent external execution recorder.

This review inspected recorded tests rather than repeating them, as requested. It did not visually inspect every generated figure; assessment of large generated artifacts used metrics, masks/input bytes, provenance, hashes and plotting code. The quality result is limited to the preregistered controlled inputs. ENHANCE step overshoot=2 is at the frozen maximum; sigma16 text ratio=1.036364 is below +5%, and worst line ratio=0.978669. These costs are disclosed and are not silently promoted to required-check passes.

No RTL, synthesis, placement/routing, timing, L_CORE, camera-exposure/video or board validation was performed or inferred. A passing scoped model review permits the separately authorized dependent RTL planning/implementation gate; it does not replace the broad final review.
