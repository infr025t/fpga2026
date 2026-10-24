# Task 2 scoped rereview

Range: `95ba7ab..475f205`. Scope: disposition of prior P2 horizontal edge-profile defect and new P2-or-higher regressions introduced by this fix. P3 real-image class coverage remains explicitly deferred to Task3.

**Disposition: ADDRESSED. Scoped review passes. No new P2-or-higher findings.**

The implementation now extracts a middle-column trace for horizontal edges and retains middle-row traces for vertical/diagonal edges. Captions state output y/x axes and clarify that the diagonal axis is not perpendicular distance. This corrects the original sampling direction without altering numerical model or gate calculations.

The added independent fixture defines literal32/224 plateaus for all three directions and checks both profile endpoints in every mode. Saved RED log records four horizontal-mode failures before the fix; focused GREEN records one test /0.072s /OK. The saved final full log records21 tests /99.883s /OK. No tests or searches were rerun for this rereview.

Read-only inspection of the committed corrected profiles confirms all12 direction/mode pairs start32 and end224. Horizontal traces have88 samples (output height), while vertical/diagonal traces have120 (output width), matching the registered96x128 inputs and crop4. Visual inspection of the corrected horizontal PNG confirms it crosses the edge and its axis caption is accurate.

Byte comparisons between the two reviewed commits confirm registration.json, inputs.npz and metrics.json are identical. Their SHA256 values are respectively452a24b753dad1c849cbca0a2f004326909ace511edd3904d28a56fd6d3f8280, d208e84909b41c066e0f07428826d7e15ce7b71524db1ea80f7c4c748b7d6c4a and9668c6f5e2678bc2cd109188710de979577381eb9c4fe659bdf81c29869d7eee. Original quality FAIL, candidate selection and absence of a published profile remain unchanged.

The appended report honestly identifies the original plotting defect, distinguishes regenerated visual evidence from unchanged registered numerical results, and explicitly limits the old real_image_classes PASS to a file-count check. It does not claim P3 has been fixed. The included Task3 plan clarification concerns later independent primary inputs versus reusable canonical stress fixtures and does not change the original experiment.

Only this rereview document was written. No implementation changes, commits, subagents, full-suite reruns or candidate searches were performed.
