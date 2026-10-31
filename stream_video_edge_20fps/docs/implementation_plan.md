# Video20fps Implementation Plan
**Goal:** Native VGA RAW/EDGE above20fps, same wiring.
**Architecture:** Faster sensor profile; continuous credit-based FIFO; matched LCD words; unchanged numerical core.
**Spec:** docs/spec.md
## Global Constraints
No COM15, no rewiring, no main changes. Preserve baseline. Stop if physical debug requires user action.
- [x] Test/implement fast LCD word handshakes and final completion.
- [x] Test/implement continuous FIFO credit, wrap and frame ownership.
- [x] Add sensor profile, constrained input capture and latched metrics.
- [x] Test complete path; build and route.
- [ ] Validate hardware references and frame rate before scene observation.

Hardware in progress: internal100+100frames reference PASS; actual sensor22.5077fps. Byte phase corrected to even Y with prefetched pixel0; FIFO model VGA wrap/pause PASS. Initial continuous known bars passed84frames then failed frame85; freeze evidence preserved, no stability claim. Add whole-frame diagnostic first/last mismatch locator to distinguish phase discontinuity from sparse bit errors.
