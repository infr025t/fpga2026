# VGA stream runtime implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Execute sequentially with task review gates.

**Goal:** Surround the verified numerical core with a bounded input queue, explicit frame validation and independently readable full-output CRC reports.

**Architecture:** One 100 MHz clock, one accepted frame in flight, a synchronous 1024x64 input FIFO and independently latched source-end status. Output CRCs observe every cropped pixel before preview selection. The report mailbox never backpressures calculation.

**Tech Stack:** SystemVerilog, Vivado2025.1 xsim, Python fixed reference and zlib.crc32.

**Spec:** `stream_video_enhance/docs/spec.md` sections7–9,10.3,12.3,15.B; numerical core plan `2026-10-23-rtl-core.md` must complete first. This plan does not implement preview, UART, physical camera, display or final board routing.

## Global Constraints

- Work in E:/Vivado_FPGA_Programs/fpga2026 on feat/stream-video-v0. Preserve demo/, reference/, profile, numerical model and existing result bytes. No hardware access, push or merge.
- Formal input640x480; output632x472. Small16x16/17x19 configurations are simulations only. One100MHz clock; no ready/backpressure at source/core interfaces; no full-frame algorithm RAM.
- Consume the actual core latency package produced by the preceding plan. L_CORE is never literal51/64. Drain L_CORE cycles after inputEOF; earliest nextSOF is EOF+L_CORE+1. S_FRAME=max(128,L_CORE+64), normal external highwater budget ceil(S_FRAME/4)+8.
- Source token64 layout: pixel[7:0], x[17:8], y[26:18], SOF27, EOL28, EOF29, frame_id[61:30], source_error62, reserved63=0. No per-pixel configuration storage.
- Status reasons0..8 and counter meanings follow spec8.3/12.3 exactly. Frame ids wrap; diagnostic sequence wraps; operational counters saturate32bits.
- Source-end OK and core-output EOF/count must both be confirmed before frame_success and CRC publication. Prefix output from a subsequently invalid frame is not a successful frame.
- All CRCs are CRC-32/ISO-HDLC: reflected0xEDB88320, initial/final XOR0xFFFFFFFF. Include first/last byte, exclude bubbles/metadata. Test123456789=0xCBF43926. One byte per cycle, II=1.
- RAM contents are not reset. Only FIFO indices/valid/control reset. All consumers may remain unavailable indefinitely without stalling the numerical core.
- Write meaningful failing benches before DUT logic; expected images/CRC come from the fixed reference and Python zlib, not a second copy of the DUT algorithm. Save commands, actual RED/GREEN and observed results under reports/rtl/runtime/; tool scratch under build/.

## Shared interface definitions

Create `rtl/video_runtime_pkg.sv`. Packed types, in declaration order:

```systemverilog
typedef struct packed {
 logic [10:0] epsilon;
 logic [4:0] threshold;
 logic [9:0] gain;
 logic [1:0] view_mode;
 logic [15:0] cfg_id, profile_id;
 logic [1:0] source_kind;
 logic [7:0] pattern_id;
 logic legacy_validation;
 logic preview_enable, roi_pair;
} frame_config_t;
typedef struct packed {
 logic [31:0] frame_id;
 logic ok;
 logic [3:0] reason;
} source_end_t;
typedef struct packed {
 logic [31:0] frame_id;
 frame_config_t config;
 logic [31:0] pixel_count, raw_crc, selected_crc;
 logic [31:0] diagnostic_seq, report_overwrite_count;
 logic [31:0] completed_frames, invalid_frames, accepted_frames;
} core_report_t;
```

`frame_config_t.threshold/gain` are the actual selected-mode parameters: RAW/BASE gain0, DENOISE gain256/T_D, ENHANCE gainG_E/T_E. Preview enable/layout travel with the frame configuration and cfg_id; the later snapshot decides at outputSOF from that frame's configuration, never an independently changing switch bus. Existing `guided_core` port/API remains unchanged. A source-end event has separate valid plus source_end_t payload; it is not inserted into a potentially full pixel FIFO. `core_done_valid/core_done_frame_id/core_done_ok` is an observation event after the last core output, before successful commit; it must not depend on frame_success, which prevents a circular wait.

Completion timing is part of the interface: core_done is a combinational preview of the currently presented valid outputEOF and final count/coordinate checks. The guard can qualify frame_success from current or saved core_done and current or saved source-end events, without registering two successive completion pulses. The accepting edge increments completed and schedules CRC publication; the monitor publishes at the next edge using its stored final CRC/config and the updated registered counters. Thus publication occurs at most one control cycle after EOF or a later sourceOK, as spec10.3 requires. Guard abort is registered; no combinational core-output→abort→core-output loop is allowed. Explicitly test simultaneous EOF/OK and both arrival orders with edge-index assertions, not only eventual report contents.

## Task 1: Internal source, synchronous queue and frame guard

**Files:** Create rtl/video_runtime_pkg.sv, source_pattern.sv, ingress_fifo.sv, ingress_guard.sv, sim/tb_runtime_ingress.sv and scripts/runtime_vectors.py. Extend scripts/run_core_tests.py to select runtime benches; add reports/rtl/runtime/ingress.md. Do not modify numerical core interfaces.

**Interfaces:** source_pattern #(W,H,PATTERN_ID,L_CORE) consumes clk,rst,enable and emits token_valid/token[63:0], end_valid/end_status. It emits complete frames atII1, then L_CORE empty cycles. enable is acted on between complete frames. Frame0 begins at reset release when enabled; id increments per emitted physicalSOF. Patterns0..3 exactly match reference.pattern.

ingress_fifo #(DEPTH=1024) consumes wr_en/wr_data and rd_en and returns registered rd_valid/rd_data, empty/full, level[10:0]. Simultaneous read/write is supported, no read while empty. Output read latency is one cycle and must be included in the guard prefetch accounting; never require asynchronous RAM read.

ingress_guard #(W,H,L_CORE,CLK_HZ=100000000) consumes source token+end event, shadow frame_config_t, stop_request, arithmetic_error, and core_done event. It emits core pixel/coordinates/flags/id ports, core_abort, active_config, frame_start_valid/id, frame_success_valid/id, frame_invalid_valid/id/reason, source_ready, and seen/accepted/completed/invalid/dropped/overflow counters plus FIFO highwater. It owns the1024 FIFO instance. Source_ready reports usability, it does not pause a physical camera.

- [ ] Build a failing bench whose success conditions include exact first/last accepted tokens, legal fullraster counts, cfg/frame association, two consecutive frames and parameter changes duringRUN. Use literal invalid traces: missingEOL, earlyEOF, extraSOF, wrongframeid, nonzero reservedbit, and flags withvalid0. Require one invalid event for each accepted badframe.
- [ ] Implement synchronous queue with inferred block RAM, a bounded read prefetch register and explicitWAIT_SOF/RUN/DRAIN/RECOVER control. Count every prefetched token in capacity/flush reasoning. Full rejects writes, latches overflow and causes independent recovery; never enqueue a synthetic error marker into full RAM.
- [ ] InRUN check all640x480 positions and inputmarkers. Lock active config only on acceptedSOF. OninputEOF drain actualL_CORE and await source status plus core_done; save either arrival order. Reason6 arithmeticerror aborts; error priorities spec8.1 apply. Recover by clearingvalid/control/FIFO and discarding through a new complete source synchronization point; no tail-to-next-frame stitching.
- [ ] Cover endOK early/late, endERROR, missingend with no queued nextframe (100ms timeout), queued nextframe delayed beyondS_FRAME, reset/stop duringframe, invalid config, FIFO full and almostfull896. Use smaller CLK_HZ in timeout benches while retaining the same cycle formula. Cover overflow recovery with full FIFO rather than mocked overflow only.
- [ ] For100MHz internal source, run at least10 fullVGAframes with actualL_CORE gaps and prove bounded stable FIFO occupancy. For the external25MPixel/s envelope, sweep phase and bounded S_FRAME pauses, verify highwater against ceil(S_FRAME/4)+8 when its assumptions hold. Report the measured internal and external cases separately.
- [ ] Check unsaturated quiescent identities accepted=completed+invalid and seen=accepted+dropped, plus directed saturation and frame_id wrap. Use package parameters for timeout/latency assertions. Save fresh results and commit scoped files.

## Task 2: Full output CRC and immutable latest mailbox

**Files:** Create rtl/crc32_byte.sv, core_crc_monitor.sv, sim/tb_core_crc.sv; extend runtime vector/harness selection and reports/rtl/runtime/crc.md.

**Interfaces:** crc32_byte is a combinational fixed byte XOR network next_state=f(state,data). core_crc_monitor #(W,H) consumes aligned out_pixel/out_raw/out_valid/x/y/sof/eol/eof/frame_id, frame_start_valid/id/config, frame_success_valid/id, frame_invalid_valid/id/reason, running completed/invalid/accepted counter buses, rst/abort. It emits core_done event with id/ok, latest_valid/core_report_t latest, claim, claimed_valid/claimed_report and overwrite_count. claim copies the complete latest report atomically; a later publication must never mutate claimed_report. Pending/output-success reports must likewise remain independent. Publication samples the three registered counter buses at that edge (normal pre-edge sampling); the successful-frame count update has already occurred at the preceding frame_success edge. Store publication diagnostic_seq and post-increment overwrite_count in the report. Future image descriptors retain these commit-time counter copies; STATUS instead takes its running counter snapshot when claimed, as required by spec10.3.

- [ ] Write RED benches for the standard CRC vector and literal singlebyte/empty cases, then image vectors from zlib.crc32. Require RAW-mode equality of both complete CRCs and outcount(W-8)*(H-8), not inputWH.
- [ ] Implement unfolded8bit CRC updates. Onout_sof process its byte frominitialstate; onout_eof include finalbyte beforefinalXOR. Flag malformed coordinates/count/frame as core_done_ok0. No preview sampling/enable enters this logic.
- [ ] Retain pendingEOF record untilmatchingframe_success. Source/guard confirmation may arrive before or afterEOF; publish no later than one controlcycle after both are present. An invalid/abort dropspending without clearinglast_good. Initialreset yields no valid report.
- [ ] Test first/lastbyte mutations, ROI-externalpixel mutation, randomvalid gaps, wrongcount, early/lateendOK, abort/reset atEOF, and framewrap. Latest reports overwritten while unclaimed increment saturated overwrite_count; claims acknowledge the current report but do not stall later publications. On claim/publication samecycle define claim of the pre-edge latest, preserving new report as unclaimed, and test that ordering explicitly.
- [ ] Verify sourcecfg/id fields remain from the same frame during later shadowupdates; claimed copy remains identical while100 new reports publish. Check publication counter copies, including publication concurrent with next-frame acceptance, and ensure later counter changes do not mutate the committed image descriptor. Save command/log/CRC table, commit scoped files.

## Task 3: Actual-core runtime integration and stream evidence

**Files:** Create sim/tb_runtime_core.sv; extend runtime_vectors.py/run_core_tests.py and reports/rtl/runtime/integration.md. No preview or UART implementation in this task.

- [ ] Connect actual source_pattern→ingress_guard→guided_core→core_crc_monitor. Connect core_done toguard and guardframe_success/invalid backtomonitor; no combinational ready loop and no dependency of core_done on frame_success.
- [ ] Expected for each frame: generate full640x480 input using reference.pattern(frame_id,PATTERN_ID), run fixed model at actualprofile config, compute croppedRAW/selected CRC withzlib. Check every coreoutput pixel against fixed results, coords/markers/frame_id, core_done and publishedreport. Cover all4patterns and all4modes over at least10VGAframes; predeclare exact matrix in the bench/vector manifest.
- [ ] Inject malformedsource traces/abort/arithmetic_error in warmup, activeoutput and lastpixel windows. Check only explicitlyinvalid frames are absent from successfulmailbox, recovery nextcompleteframe matchesreference, and counter identitiesholdwhenquiescent.
- [ ] Repeat selectedmatrix with two alreadyverified legal corelatencyconfigurations, deriving drain, sourcegap and expectedEOF from packageconstants. Reject hardcoded51/64. Compare report/accepted/completed counts with consumer claimnever, slowrandom, alwaysavailable; onlyoverwrite/claim counters may change.
- [ ] Report actual II1/simulatedacceptedthroughput and measuredlatencies separately from the100MHztarget. Preserve vector hashes, sourcecommit and logs. Commit evidence and update status with remainingpreview/UART/localcontrol/camera/boardroute work. This stage is not wholeV0 completion or boardvalidation.

## Preflight dependency table

| Tasks | Producer / consumer | Check |
|---|---|---|
| 1 self | sourcegap, FIFOlatency and guarddrain | same actualL_CORE; FIFOreadlatency explicitlycounted |
| 2 self | pendingEOF, frame_success, latest and claimed copies | independent registers; no preview dependency |
| 1→2 | frame_start/config, success/invalid ↔ core_done | core_done precedes success; no circular wait |
| 1+2→3 | actual source/guard/monitor with numericcore | identical port contracts, model-derived vectors |
| all→futurepreview | immutable perframeCRC/config association | future snapshot retains its owndescriptor, not live latest |

This plan freezes only synchronous runtime behavior already required by the specification. A physical OV7670 FIFO adapter still requires separate cache/reset/clock validation using reports/camera_vga_preflight.md; neither this plan nor an internal test source proves real camera throughput.
