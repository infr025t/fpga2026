# Blue-background white-character change review

Reviewed candidate: `E:/FPGA_Test_Work/plate_blue_polarity_v1_1/project`

Compared baseline: `E:/Vivado_FPGA_Programs/fpga_plate_vision_v1_0/project`

Review scope: read-only source audit of polarity ownership, reset/abort, raw-image preservation, UART flags, and manual-mode isolation. No board, COM port, bitstream generation, or simulation was run by this reviewer. The implementation team is separately adding and running regression tests.

## Findings

No blocking correctness defect found in the reviewed changes. No requested code changes.

## Checked reasoning

- A recursive RTL content-hash comparison found exactly two changed RTL files: `rtl/top/lcd_top.sv` and `rtl/recognition/plate_recognition_subsystem.sv`. The locator, segmenter, normalizer, controller, and CNN RTL remain identical to the baseline.
- The top-level source of `white_characters` is `ss[5]`, behind the existing two-stage switch synchronization. SW5 does not alter camera capture or the display pixel path.
- `active_white_characters` is sampled on `source_start && !auto_busy` only when `auto_rst` is false. This is the same accepted-frame condition as the controller's IDLE/source_start transition. Busy source starts cannot change the selected polarity. A malformed accepted start may latch a polarity but is then rejected by the existing controller; it never completes recognition.
- The mode vector includes the polarity bit only while automatic recognition owns the workers. A polarity transition therefore resets the automatic controller, observer and workers using the established mode-change mechanism, gates RAM/core writes, suppresses result/ROI events, and clears pending display state through `display_enabled`. Display overlays keep the established frame-boundary update behavior. A simultaneous mode transition and source start is discarded; the next complete source frame can be accepted.
- `a_flags={active_white_characters,1'b0}` sends one stable frame setting to both recognition workers and the observer. Registered `cap_begin` reaches the observer one clock after the accepting edge, when the newly latched flags are already available. The observer snapshots `cap_flags` and clears queued data on a mode reset, so a completed frame cannot silently combine the old payload with new polarity metadata.
- Original pixels are still stored unmodified. The normalizer exposes raw RAM data to the shared scan port; the locator sees that raw scan data. The segmenter and normalizer alone use the already-supported `flags[1]` inversion. Thus the changed behavior is local to character extraction and normalization.
- In manual mode the new mode-vector bit is zero regardless of SW5, and worker flags remain `m_flags`. The manual UART command's own polarity and rotation semantics are unchanged. Existing subsystem testbench instances explicitly bind the new input low.
- The PC verifier now accepts automatic flags 0 and 2 while retaining the full-frame search-ROI check. It still locates on raw pixels and passes the reported flags to segmentation and normalization, matching the RTL contract.

## Evidence boundary

This review supports the implementation structure and minimal scope. It does not establish synthesis/timing closure, a newly programmed board result, or broad blue-plate recognition accuracy. The reported five-frame software result belongs to the separate experiment evidence, not to an independent hardware verification by this reviewer.
