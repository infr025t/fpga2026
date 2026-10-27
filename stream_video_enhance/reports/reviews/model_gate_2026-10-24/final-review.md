# Final whole-branch model-gate review

Date: 2026-10-24. Reviewed range: `f327861..0c16384`, branch `feat/stream-video-v0`, checkout `E:/Vivado_FPGA_Programs/fpga2026`.

## Verdict

**SPEC COMPLIANCE: PASS. CODE QUALITY: PASS with one nonblocking P3 documentation correction.** No actionable P0/P1/P2 finding was identified. The completed numerical/model-gate work is ready for the dependent section16 RTL implementation plan. This verdict does not declare the FPGA project complete, implement RTL, freeze L_CORE, or establish synthesis, timing, camera or board performance.

The supported published configuration is profile_id=1: epsilon1024, T_D2, T_E4, G_E428, L16. The controlled finegain-v3 result is 17 required checks PASS after 51 tuning candidates, 15 feasible candidates and one selected holdout configuration. The historical 24- and 72-candidate experiments remain FAIL.

## Actionable issues and deferred-minor disposition

- **[P3] Correct the command explanation at `stream_video_enhance/README.md:23`.** The paragraph says the first command returns1 and preserves the quality report on quality failure, but the first command in the preceding block is now `unittest discover` (line16). Unit/numerical success and quality-gate failure are distinct. The same paragraph switches to expanded-v2 while the current example registers finegain-v3. Name `evaluate --run` explicitly for quality exit1/report retention, and use finegain-v3 for the current reproduction or clearly label expanded-v2 historical replay. **Disposition: carry forward as a nonblocking documentation correction for the controller; no model rerun is necessary.** It does not undermine the saved PASS or permission to start the dependent RTL plan.
- Prior Task2 P3 concerning real classes is **closed for current controlled acceptance**: explicit flat/text/texture region labels and fixed masks replace file counting in expanded-v2/finegain-v3. The old file-count result survives only as explicitly identified historical original-v1 behavior, not current evidence.
- Prior horizontal-profile P2 and Task3 primary-inventory/source-provenance P2 findings remain **closed** in the integrated source. No new P0/P1/P2 issue was found.

## Cross-task integration and strengths

1. **Numerical contract and centering agree.** Both independent paths implement first-round self-guided coefficients followed by another valid5x5 coefficient mean and reconstruction with the original aligned pixel. First coefficient origin is(2,2), final origin(4,4); formal640x480 returns632x472. No accidental first-round filtered-pixel substitution or extra crop appears. The96x96 raw ROI test maps its88x88 output to the correct full-output indices and supports section10.1's same-input neighborhood claim.
2. **Fixed arithmetic follows the specification.** U8 input is promoted before squaring and multiplication; int64 also safely holds full-image prefix sums. Exact variance, reciprocal divide25 with caller-provided +12, Q12 ratio rounding, Q8 mean/intercept and reconstruction, signed deadzone/limit and gain ties-away rounding, then final saturation/rounding occur in the stated order. The float path shares validation but does not call fixed rounding or coefficient helpers. Its coefficients and reconstruction remain float64 until final output. The legal gain semantics consistently mean integer Q8, including428 and the unsigned512 boundary.
3. **The quality evaluator consumes the model coherently.** All four modes use identical raw/base alignment; masks and known clean references receive the same crop. PSNR uses clean synthetic data only; clipping counts new endpoint saturation over the fixed mask denominator. Temporal noise computes per-pixel temporal population standard deviation before spatial averaging. Horizontal profiles now cross the edge along the middle column. Public photographs and actual OV7670 evidence have separate provenance, and photographic PSNR is not invented.
4. **Experimental integration preserves the gate.** Known expanded/finegain registrations independently enforce both primary lists and their case associations, complete17-check inventory and explicit nonrequired DEFERRED policy. Finegain validates the exact51 grid and tuning-only maximin/tie rule. The current execution path evaluates holdout once after tuning selection and returns before legacy exploratory/control branches. Figures reuse the selected configuration without introducing a holdout ranking. Publication requires every required check to be PASS; unknown, absent or DEFERRED required statuses cannot qualify.
5. **Traceability is substantive.** Entry execution source hashes are bound to committed bytes before filtering and checked again before publication. Registration, arrays, source identity, required statuses and profile are cross-linked. Later documentation commits cannot replace the entry identity. Code/tests commit f1adeba precedes registration747c5da, which precedes results ab19a61. The later docs commit0c16384 does not modify arithmetic or execution sources.
6. **Tests target meaningful failure modes.** Independent scalar25-by25 loop expectations complement vectorized code; legal divide25 is exhausted. Exact-rational boundaries, signed half ties, unsigned gain, constants, crop/checkpoints, invalid types/ranges, VGA errors and ROI equivalence cover numerical behavior. Evaluation tests use literal metric fixtures and actual temporary Git repositories for source integrity. They cover failed-check exclusion, maximin versus average, tie ordering, grid/policy tampering, omitted/reordered/duplicate primary IDs and case bindings, and new input/stream definitions. Shared evaluator/registration logic avoids three independent implementations, while the experiment-specific policy remains explicit.

## Independently checked evidence

This review read the supplied complete code/test diff and relevant actual files, spec1.4 sections4/5/10.1/15A, plan/authorization ledger, prior task reviews and execution reports. Truncated tool output was supplemented with targeted actual-source reads. The6MB generated report was parsed as structured data rather than printed wholesale.

Read-only artifact verification during this review established:

- All614 preservation-snapshot files and all11 recorded log hashes match current bytes.
- All six execution source hashes match both current files and Git blobs at the recorded entry commit747c5da.
- Registration/archive hashes agree between actual bytes, metrics and profile; selected config, profile and saved holdout config agree.
- Independently ranking the saved tuning values gives index11,15 feasible candidates, epsilon1024/T_D2/T_E4/G_E428/L16. All17 required checks are PASS; exposure/video/RTL remain DEFERRED/nonrequired.
- Current historical metrics remain FAIL with24 and72 candidates respectively. The whole-range diff has no demo/reference-document changes or Verilog/SystemVerilog/XDC changes. Numerical reference.py has no changes after its original implementation commit1e1e6fd.
- Saved final log contains37 tests,35.273s,OK; saved VGA result contains288 cases, max error<=1LSB, histogram[85812329,99223], MAE0.001154944, RMSE0.033984462. These are checked implementation-run records, not tests executed again by this reviewer.

Verified hashes:

- registration: `4313e070de338caa2abf3e21c3370814dcbd45420c6752af92628e226cb52c34`
- inputs: `270f74a61befab69eb8a373154d442b4e0592137c8bf93987b472e1ac829cae8`
- metrics: `18181b0d6144fbf17a36132de0721f3c077f5f8ac090a14312f651743d7b74af`
- profile: `0817488e0e5de12c1b863caa20295bb2633a973f21869e536ae23fabe461701f`

No full suite, parameter search, filtering or holdout evaluation was rerun. No checkout, index, HEAD or implementation file was mutated. This report is the only written artifact.

## Readiness boundaries

PASS covers the registered controlled gate, not arbitrary-image improvement. Step overshoot2 is at its allowed limit; worst registered line ratio0.978669 and sigma16 text ratio1.036364 remain disclosed costs. TheVGA numerical matrix is sampled evidence, not exhaustive proof across every possible image/configuration. Saved provenance supports the recorded experiment sequence; repository artifacts cannot prove the absence of unrecorded outside experiments.

The next dependency can consume the stable numerical API, published profile and formalVGA dimensions for RTL planning, key-module simulation/local synthesis and eventualL_CORE freeze. Actual cameraVGA capture reliability, exposure/video checks, RTL bit-exactness, integrated timing/route and board validation remain separate outstanding milestones. No claim about those is inferred from this model review.
