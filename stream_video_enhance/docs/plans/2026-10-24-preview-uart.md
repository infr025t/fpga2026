# Snapshot and VEF0 diagnostic implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Implement sequentially with independent task reviews.

**Goal:** Export bounded overview or same-frame RAW/result ROI diagnostics while the verified core continues independently.

**Architecture:** One 9600x16 logical snapshot, physically five2048x18 block RAM banks, with exclusive capture/scan/read ownership. A single UART consumer sends VEF0v2 image packets or immutable latest STATUS reports. It never feeds the calculation or stalls its input.

**Tech Stack:** SystemVerilog/Vivado2025.1 xsim, Python unittest/zlib/struct/Pillow. Physical serial access and board programming are excluded from these tasks.

**Spec:** `stream_video_enhance/docs/spec.md` sections10,12.3,15.B. Requires completion of numerical core and `2026-10-24-stream-runtime.md`. Actual latency comes from core_latency_pkg, never an estimate.

## Global Constraints

- Same feature branch and checkout; preserve model/profile/historical evidence/demo/reference. Tool scratch remains under ignored build/regression. No push, hardware or LCD implementation.
- Formal640x480 input and632x472 cropped output. Overview158x118=18644bytes, original origin(4,4), sample_step4. ROI_PAIR96x96x2=18432bytes; default original origin(272,192), sample_step1. One shared19200byte logical capacity, no extra image/frame RAM.
- On outputSOF choose whether to capture and freeze frame configuration/layout. If notEMPTY skip the entire preview frame; core valid/CRC/accepted/completed must not change. Switches are not read live during capture or send.
- ROI RAM wordk is {selected[7:0],raw[7:0]}; serialize lowbytefirst RAW0,PROC0,... . Overview packs two consecutive samples into one word, lowbytefirst, pads a final odd highbyte0 without including padding in payload/CRC.
- Consumer byte-address rd_en/rd_addr[14:0] returns rd_valid/rd_data one clock later. Byte lane/bank selects align with the RAM output. No unannounced extra output register.
- CRC-32/ISO-HDLC with standard123456789 vector; payloadCRC covers actual ordered exported bytes only. Full-core CRC remains from runtime and covers every cropped pixel.
- VEF0 magic, version2, 88byte header, littleendian fields and all offsets exactly spec10.2. Only kinds0OVERVIEW/layout0,1ROI_PAIR/layout1,2STATUS/layout2. No old FPG1/version1 compatibility layer.
- UART1000000baud8N1 from100MHz,100clockcycles/bit. TXidle1. There is no PC command/register-write protocol or normal PC algorithm dependency.
- Write failing behavioral benches before logic, preserve actual RED/GREEN. Reference/golden packets use Pythonzlib plus independently checked literal offsets, not RTL serialization copied into a second model.

## File/API map

Create rtl/preview_pkg.sv importing video_runtime_pkg. `snapshot_desc_t` contains core_report_t core, width/height/origin_x/origin_y[15:0], sample_step/kind/layout[7:0], payload_bytes/payload_crc[31:0]. Magic/version/headerlen/buildL are serialization constants, not per-pixel fields. Every snapshot holds its own core report and commit counters even when runtime latest changes.

preview_snapshot #(W,H,ROI_X,ROI_Y) consumes aligned raw/selected/outputmetadata, frame_config_t active_config valid for the in-flight frame, frame_success/invalid, and matching published core_report. It emits snapshot_valid/desc, accepts claim,byte read and release, and emits cfg_error, captured/skipped/timeout counters, busy. A request/matching acknowledgment pair cancels its sole consumer before timeout release. Output write/read ownership is local to this module.

uart_snapshot consumes snapshot offer/read interface and runtime latest/claim interface plus running reason/counters for STATUS. It emits TX and consumer_cancel_ack; accepts cancel and reset. Header fields are frozen in local registers before CRC calculation or transmission. No read access after cancellation acknowledgment.

## Task 1: Single snapshot, packing, commit and CRC scan

**Files:** Create rtl/preview_pkg.sv, preview_snapshot.sv, sim/tb_preview.sv, scripts/preview_vectors.py, reports/rtl/preview.md. Extend run_core_tests.py suite selection without changing existing arithmetic/windows behavior.

- [ ] Write RED bench using output-raster tokens and literal per-coordinate RAW/selected values. Check allROI bytes, overview samples and CRC against independent expected byte arrays; no real core is needed for this component bench.
- [ ] Implement EMPTY→CAPTURE→WAIT_COMMIT→CRC_SCAN→READY→READOUT→EMPTY. Capture starts only onoutSOF when enabled andEMPTY; freeze config/id/geometry. Reject ROI origin outside4..W-100/4..H-100 withcfg_error and no capture; small dimensions lacking96x96 cannot requestROI. Do not silently clamp an invalid origin.
- [ ] Map five independent2048x18 RAMs with16usedbits into a single9600word logical space. ROI writes once pervalid pixel atII1. Overview uses one pending-lowbyte register; only matching sample tokens advance packing. Reset/abort clearcontrol/valid, never RAM contents.
- [ ] Require exact captured count, matching validEOF, frame_success and core_report id/config beforecommit. Core report may arrive after frame_success: retain pending snapshot until it arrives. An invalid/abort discards uncommitted data; stale/unrelated reports never commit it.
- [ ] CRC_SCAN uses the same one-cycle byte read path. ForNbytes it takesN+1 cycles to obtain the last read response, then onecycle to latchCRC/READY. Check first/lastbyte and exactscan completion edges, including odd overview payload in generic small tests. No bank writes inWAIT_COMMIT/CRC_SCAN/READY/READOUT.
- [ ] Exercise default and four extreme legalROI origins, invalid origins, changing shadowlayout midframe, intermittentvalid, abort at first/last capture pixel and status-before/afterEOF. Check that FRAMEid, config and full-coreCRC remain the captured frame after hundreds of runtime publications.
- [ ] With a consumer permanentlybusy/neverclaiming, capture one snapshot and skip subsequent wholeframes. WithNONEconsumer configuration, preview can be disabled, core remains active. On5second timeout cancelconsumer first, await cancellationack, thenrelease; an old reader cannot read newly reused RAM. Use scaled CLK_HZ for timeout bench and test stale read-return on cancellation.
- [ ] Save actual bytecount/RAMorganization/readlatency/CRC logs and commit scoped files. No physical display claim.

## Task 2: UART transmitter, atomic packet headers and host decoder

**Files:** Create rtl/uart_tx_byte.sv, uart_snapshot.sv, sim/tb_vef_uart.sv, scripts/vef_protocol.py, scripts/receive_vef.py, tests/test_vef_protocol.py, reports/rtl/uart.md. Add an explicitly documented optional serial-host dependency if required; no serial port is opened during automated tests.

- [ ] Define pure Python encode/decode APIs for88byte headers and threepayloadlayouts. Tests use literal offset checks for everyfield, standardCRCvector, exact kinds/lengths and packetgoldens. Corrupt one headerbyte, onepayloadbyte, truncate at every header boundary, prepend garbage and embed magic in payload; streamparser mustresynchronize without accepting badCRC/invalidlengths.
- [ ] Write RED serial bench sampling the physicalTX line at bit centers; verify start/dataLSBfirst/stop,100cycles/bit and all payload bytes. A DUT merely printingPASS without correctTX bytes cannot satisfy the scoreboard.
- [ ] Implement TX byte driver and serializer. Latch header/sourcecfg/frameCRC/counters once atpacketconstruction; build first84bytes, compute headerCRC, append4littleendianCRCbytes, then transmit. Metadata changes during transmission never change the current header. CRCflags0 gives invalidCRC STATUS withframeid/corecount/CRCs0 rather than fabricated success.
- [ ] Image packets consume their snapshot's descriptor/commitcountercopies. STATUS uses one claimed last_good frame/config/CRC copy and atomically samples current reason/runningcounters. With no readyimage, send latest not-yet-sent report at mostonce per100ms; no queued perframe reports. Empty STATUS payloadCRC0. Use actualL_CORE in offset56, not51/55/64.
- [ ] Prioritize an available image at idlepacketboundaries; STATUS may finish before a newlyreadyimage. Respect one-cycleRAMreads and UARTbusy; do not underrun/duplicate lastbyte. Consumer cancel stops packet/readrequests, restoresidleTX and acknowledges before RAM reuse.
- [ ] Verify completeOVERVIEW/ROI_PAIR/STATUS packets through both SV serialscoreboard and purePythondecoder; repeated latest overwrites whileTXbusy mustnot alter sent bytes. Check reset/cancel at header and payload boundaries, then recovery to a correct nextpacket. Preserve raw TX bytes, goldenpacket hashes and actual timing.
- [ ] Host receive CLI deinterleaves ROI and writes images/logs only. Optional explicitly invoked offline ROI88x88 and internalpatternCRC checks call the existing fixedmodel; they are development validation, not required normal calculation. Unit tests use byte streams, not a liveCOMport. Provide usage and commit scoped files.

## Task 3: Actual runtime/core integration and consumer independence

**Files:** Create sim/tb_preview_system.sv; extend vector/harness selection, tests/test_vef_protocol.py and reports/rtl/preview_integration.md. No physical camera/top-level pin routing yet.

- [ ] Connect actual pattern/ingress/core/fullCRC monitor/snapshot/UART using completed stages. For the same predeclared inputframes/configs, run previewOFF, normaloverview, ROI, permanentconsumerbusy and randomslowconsumer. Accepted/completed/invalid and bothfullCRCs must match across cases; onlypreview/mailboxexport counters may differ.
- [ ] Run10VGAframes of the actual numerical chain with at leastRAW/DENOISE/ENHANCE cases. Receive a complete158x118overview and96x96RAW/resultpair from actualTX and compare everydecodedbyte to fixedreference. FullcoreCRC includespixelsnotexported: mutate a non-ROI coreoutput byte and demonstrate changedfullCRC while ROI payload remainsunchanged.
- [ ] For each ROI, apply existing fixedmodel to its96x96RAWplane and compare central88x88 to selectedprocessingplane[4:92,4:92]. Do not pad missing external support. Also compare whole expectedROIpair to the full-frame fixedresult; this distinguishes valid localrecomputation from a wrongcrop.
- [ ] Inject invalidsource/abort after a previewprefix was captured; it must never becomeREADY or a successfulpacket. Test sourceOK early/late, packet stalls beyond watchdog, latest fastoverwrite, layout changes and resume. No completed badframe or torn descriptor is acceptable.
- [ ] Report calculation throughput, simulation clock, preview completion rate and UART line time separately. Update README/status with exact available diagnostics and remaining localcontrol/camera/boardroute/hardware milestones. Commit fresh evidence; no board performance claim.

## Preflight dependencies

| Tasks | Producer / consumer | Check |
|---|---|---|
| 1 self | one RAM, two packing layouts, one-cycle reads | same physicalfivebanks, no hidden extraROI RAM |
| 2 self | frozen descriptor→headerCRC→serialbytes→decoder | explicitall88offsets, kinds/payloadchecked independently |
| 1→2 | snapshot offer/claim/read/release/cancel | soleconsumer; cancellation precedes RAM reuse |
| runtime→1/2 | committedreport and config/countercopies | snapshotframe remains immutable; STATUS claim samplesrunningcounters |
| all→3 | actual numerical core output and serial transport | fixed-reference pixels+complete CRCs, no PC runtime algorithm |

The later board integration plan must still implement debounced switches/LED pages, source selection and camera diagnostics, create separate constraints/project and perform resource/timing/CDC/DRC/bit generation. Screen and Flash milestones remain as specified; this plan does not silently add a physical VGA/LCD driver.
