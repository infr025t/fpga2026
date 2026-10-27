# Task 3 implementation report

Status: implementation and behavioral simulation complete; ready for independent
controller review. Original task base: 393f4c7. Resumed existing implementation
and final clean 2026-10-26 simulation evidence without rewriting or rerunning
completed RTL work. No source changed during this resume.

Implemented coefficient5, reconstruct, detail_enhance, core_latency_pkg and
guided_core; added two benches and deterministic model/literal vector generation;
extended the shared runner with additive core-suite options. Measured stage
latencies 9/20/12/3/6 plus four links give L_CORE=54; EXTRA_ALIGN=1 gives55.

Final clean matrix: nine benches PASS, no tool warnings/errors; 832 complete
frames including 24 VGA, 7,225,556 compared triples with zero differences. Every
VGA frame has 298,304 outputs. Seven real simulator-runner fixtures PASS with
zero skips. Exact commands, complete captured logs, source hashes, counts,
scope/contract details and TDD RED/GREEN are durable in:

- `stream_video_enhance/reports/rtl/core.md`
- `stream_video_enhance/reports/rtl/core_results.json`

Resume verification independently regenerated 1,623 vector files byte for byte,
checked every final tool exit/diagnostic/PASS line and source modification time,
and matched all six immutable original model/test hashes to profile 1. All 11
RTL files, runner and stage bench match the earlier saved SHA256 manifest. The
vector generator and integrated bench were strengthened after that manifest but
before the final clean compile; the durable report explicitly states the limit
of the historical hash evidence. No ignored scratch fixture is a dependency of
the normal core regression command.

TDD evidence: stage RED compiled and then failed `coefficient invalid error` at
16 ns against placeholder behavior; integrated RED compiled and failed `core
valid cycle=193 got=0 expected=1 L=54` against the initial core stub. GREEN is the
complete final core CLI matrix. RED tool command arrays and full logs are in the
JSON; historical helper scripts in ignored scratch are not needed for GREEN.

Owned files: five new RTL files; scripts/core_vectors.py;
scripts/run_core_tests.py; sim/tb_core_stages.sv; sim/tb_guided_core.sv;
reports/rtl/core.md; reports/rtl/core_results.json; this report. Task 1/2 RTL,
model/profile and original tests, parent audit/status docs and historical evidence
were not edited. No push, synthesis, camera/display/runtime integration, hardware
programming or cleanup was performed.

Self-review covered arithmetic bounds/signs/ties, full Q8 base preservation,
same-cycle metadata/triple outputs, frame-held config, edge-based latency sum,
flush dominance/recovery, early uncropped faults and deterministic fresh fixture
generation. No unresolved correctness concern found. Numerical core legality
assertions do not replace future runtime config/protocol/error-counting logic.
Physical timing/resource/board behavior remains unverified by design scope.
