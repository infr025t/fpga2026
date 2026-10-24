"""Run real Vivado simulator stages in isolated ignored build directories."""
import argparse
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get("VIVADO_BIN", "E:/Vivado/2025.1/Vivado/bin"))
ERROR = re.compile(r"(?im)^\s*(?:ERROR:|FATAL:|Fatal:|Error:)")


def _run_tool(command, cwd, log, timeout):
    """A suspended wrapper joins a private Windows job before spawning children.

    taskkill /T alone races asynchronous child handle closure. Wait for the job
    to contain zero active processes before returning a timeout to the caller.
    """
    from ctypes import wintypes
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    kernel.CreateJobObjectW.restype = wintypes.HANDLE
    kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    kernel.TerminateJobObject.argtypes = [wintypes.HANDLE, wintypes.UINT]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.QueryInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                                wintypes.DWORD, ctypes.c_void_p]
    job = kernel.CreateJobObjectW(None, None)
    if not job:
        raise ctypes.WinError(ctypes.get_last_error())
    proc = None
    timed_out = False
    try:
        proc = subprocess.Popen(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                creationflags=0x4)  # CREATE_SUSPENDED
        if not kernel.AssignProcessToJobObject(job, int(proc._handle)):
            proc.kill()
            proc.wait()
            raise ctypes.WinError(ctypes.get_last_error())
        resume = ctypes.WinDLL("ntdll").NtResumeProcess
        resume.argtypes = [wintypes.HANDLE]
        if resume(int(proc._handle)) != 0:
            raise OSError("cannot resume tool wrapper")
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            code = None
    finally:
        # Also clear a descendant unexpectedly left after a successful wrapper.
        if not kernel.TerminateJobObject(job, 1):
            raise ctypes.WinError(ctypes.get_last_error())
        if proc is not None:
            proc.wait(timeout=15)
        accounting = ctypes.create_string_buffer(48)
        deadline = time.monotonic() + 15
        while True:
            if not kernel.QueryInformationJobObject(job, 1, accounting, 48, None):
                raise ctypes.WinError(ctypes.get_last_error())
            active = int.from_bytes(accounting.raw[40:44], "little")
            if active == 0:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("tool job failed to release descendants")
            time.sleep(0.02)
        kernel.CloseHandle(job)
        if proc is not None:
            proc._handle.Close()
    return code, timed_out


def run_bench(sources, top, work_dir, timeout=180, pass_marker=None, plusargs=()):
    work_dir = Path(work_dir).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    result = {"top": top, "passed": False, "stages": [], "work_dir": str(work_dir)}
    # Options file avoids cmd.exe treating '=' in a plusarg as an argument separator.
    (work_dir / "xsim-options.txt").write_text("\n".join('-testplusarg "'+str(a)+'"' for a in plusargs))
    stages = [("xvlog", ["-sv", *map(lambda p: str(Path(p).resolve()), sources)]),
              ("xelab", [top, "-s", "snapshot"]),
              ("xsim", ["snapshot", "-runall", "-f", "xsim-options.txt"])]
    for tool, args in stages:
        command = [str(BIN / (tool + ".bat")), *args]
        log_path = work_dir / (tool + "-captured.log")
        start = time.monotonic()
        with log_path.open("w", encoding="utf-8") as log:
            code, timed_out = _run_tool(command, work_dir, log, timeout)
            if timed_out:
                result["reason"] = tool + " timeout"
        output = log_path.read_text(encoding="utf-8", errors="replace")
        result["stages"].append({"tool": tool, "command": command, "exit": code,
                                 "seconds": round(time.monotonic() - start, 3), "log": str(log_path),
                                 "private_job_active_processes": 0})
        if code is None or code != 0 or ERROR.search(output):
            result.setdefault("reason", tool + " exit/diagnostic failure")
            break
    else:
        if (pass_marker or "PASS " + top) not in output:
            result["reason"] = "missing PASS marker"
        else:
            result["passed"] = True
            result["reason"] = "PASS"
            result["simulation_summary"] = [s for s in output.splitlines() if "PASS " in s]
    (work_dir / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def generate_vectors(path, quick=False):
    import numpy as np
    spec = importlib.util.spec_from_file_location("reference", ROOT / "model/reference.py")
    reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reference)
    ns = np.arange(1632013, dtype=np.int64) if not quick else np.array([0,24,25,26,1632012], dtype=np.int64)
    qs = reference.div25_exact(ns)
    assert tuple(map(int, reference.div25_exact(np.array([0,24,25,26,1632012],dtype=np.int64)))) == (0,0,1,1,65280)
    with (path / "div.txt").open("w") as f:
        for n, q in zip(ns, qs):
            f.write(f"{n} {q} 0\n")
        f.write("2097151 0 1\n")
    rng = np.random.default_rng(20261024)
    count = 0
    with (path / "ratio.txt").open("w") as f:
        # Independently hand-derived generic denominators: half/neighbor, U25 double,
        # invalid zero denominator, V>=DEN, excessive coefficient and range.
        literals = [(0,10000,0,0),(1,8192,1,0),(1,8193,0,0),(1,8191,1,0),
                    (8388608,10000000,3436,0),(9999,10000,0,1),
                    (0,0,0,1),(7,7,0,1),(10143901,10783900,0,1),
                    (100,10783901,0,1),(10000,10001,0,1)]
        for row in literals:
            f.write("%d %d %d %d\n" % row)
        for epsilon in reference.EPSILONS:
            # Each V is generated from a real 25-pixel window, including extrema.
            pixels = rng.integers(0,256,(5000,25),dtype=np.int64)
            v = 25*(pixels*pixels).sum(axis=1)-pixels.sum(axis=1)**2
            v = np.concatenate((np.array([0,10143900], dtype=np.int64),v))
            a = reference.ratio_q12(v, epsilon)
            assert np.all(a <= 4092)
            for vv, aa in zip(v,a):
                f.write(f"{vv} {vv+625*epsilon} {aa} 0\n")
            count += len(v)
    return {"div_legal": len(ns), "div_invalid":1,"ratio_windows":count,"ratio_literals":len(literals)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--timeout", type=float, default=240)
    args = parser.parse_args()
    path = ROOT / "build/regression" / ("arithmetic-" + uuid.uuid4().hex[:10])
    path.mkdir(parents=True)
    counts = generate_vectors(path,args.quick)
    result = run_bench([*(ROOT / "rtl" / s for s in ("token_pipe.sv","div25_pipe.sv","ratio_q12_pipe.sv")),
                        ROOT / "sim/tb_arithmetic.sv"], "tb_arithmetic", path,
                       timeout=args.timeout, plusargs=["VECTORS="+path.as_posix()])
    result["vectors"] = counts
    (path / "result.json").write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
