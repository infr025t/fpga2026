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


def missing_simulator_tools(directory=None):
    directory = BIN if directory is None else Path(directory)
    return [str(directory / (tool + ".bat")) for tool in ("xvlog", "xelab", "xsim")
            if not (directory / (tool + ".bat")).is_file()]


def simulator_unavailable_message(missing):
    return ("Vivado simulator tools are unavailable: " + ", ".join(missing)
            + ". Set VIVADO_BIN to a Vivado bin directory containing xvlog, xelab and xsim.")


def has_pass_marker(output, marker):
    """Accept a complete PASS line, optionally followed by measured values."""
    return re.search(r"(?m)^" + re.escape(marker) + r"(?:[ \t].*)?$", output) is not None


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
    missing = missing_simulator_tools()
    if missing:
        result["reason"] = simulator_unavailable_message(missing)
        (work_dir / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        return result
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
        if not has_pass_marker(output, pass_marker or "PASS " + top):
            result["reason"] = "missing PASS marker"
        else:
            result["passed"] = True
            result["reason"] = "PASS"
            result["simulation_summary"] = [s for s in output.splitlines() if "PASS " in s]
    (work_dir / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result

