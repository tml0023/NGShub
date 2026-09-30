import json
import os
import queue
import shutil
import signal
import subprocess
import threading
from pathlib import Path

from . import db
from .catalog import PLATFORMS, needs_docker
from .config import (
    MAX_CONCURRENT_RUNS,
    NEXTFLOW_PROFILE,
    PIPELINE_DIR,
    RUNS_DIR,
    tool_path_env,
)

_queue: "queue.Queue[str]" = queue.Queue()
_processes: dict[str, subprocess.Popen] = {}
_processes_lock = threading.Lock()
_workers_started = False


def run_dir(run_id: str) -> Path:
    return RUNS_DIR / run_id


def submit(run_id: str) -> None:
    _queue.put(run_id)


def start_workers() -> None:
    global _workers_started
    if _workers_started:
        return
    _workers_started = True
    for index in range(MAX_CONCURRENT_RUNS):
        thread = threading.Thread(target=_worker, name=f"ngsweb-worker-{index}", daemon=True)
        thread.start()


def _worker() -> None:
    while True:
        run_id = _queue.get()
        try:
            _execute(run_id)
        except Exception as exc:  # a crashed worker must not strand the run
            db.update_run(
                run_id, status="failed", error=str(exc), finished_at=db.now()
            )
        finally:
            _queue.task_done()


def _execute(run_id: str) -> None:
    run = db.get_run(run_id)
    if not run or run["status"] == "cancelled":
        return

    directory = run_dir(run_id)
    log_path = directory / "run.log"
    params = run["params"]
    pipeline_script = PLATFORMS[run["platform"]]["pipeline"]
    # The docker profile is conda + docker, so it's a strict superset of the
    # default: switch to it whenever a selected tool only exists as a container,
    # instead of letting the run fail at that step with a bare "No such file".
    profile = NEXTFLOW_PROFILE
    if profile == "micromamba" and needs_docker(run["platform"], params):
        profile = "docker"

    command = [
        "nextflow",
        "-log",
        str(directory / "nextflow.log"),
        # Runs launch from the run's own directory, so Nextflow only finds a
        # nextflow.config next to the script itself. That covers Illumina
        # (pipeline/main.nf) but not pacbio/ or ont/, which would silently run
        # with no conda, no profiles, and no defaults. Pass it explicitly.
        "-c",
        str(PIPELINE_DIR / "nextflow.config"),
        "run",
        str(PIPELINE_DIR / pipeline_script),
        "-profile",
        profile,
        "-ansi-log",
        "false",
        "-work-dir",
        str(directory / "work"),
        "-params-file",
        str(directory / "params.json"),
    ]

    db.update_run(run_id, status="running", started_at=db.now())

    with open(log_path, "w", buffering=1) as log_file:
        log_file.write(f"$ {' '.join(command)}\n\n")
        log_file.flush()
        process = subprocess.Popen(
            command,
            cwd=str(directory),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            env=tool_path_env(),
            start_new_session=True,
        )
        with _processes_lock:
            _processes[run_id] = process
        exit_code = process.wait()

    with _processes_lock:
        _processes.pop(run_id, None)

    current = db.get_run(run_id)
    if current and current["status"] == "cancelled":
        return

    if exit_code == 0:
        if not params.get("keep_work", False):
            shutil.rmtree(directory / "work", ignore_errors=True)
        db.update_run(
            run_id, status="succeeded", exit_code=0, finished_at=db.now()
        )
    else:
        db.update_run(
            run_id,
            status="failed",
            exit_code=exit_code,
            error=_last_error(log_path),
            finished_at=db.now(),
        )


def _last_error(log_path: Path, max_chars: int = 2000) -> str:
    try:
        text = log_path.read_text(errors="replace")
    except OSError:
        return "Pipeline failed (no log available)"
    marker = text.rfind("ERROR ~")
    snippet = text[marker:] if marker != -1 else text[-max_chars:]
    return snippet[:max_chars].strip()


def cancel(run_id: str) -> bool:
    with _processes_lock:
        process = _processes.get(run_id)
    if process is None:
        run = db.get_run(run_id)
        if run and run["status"] == "queued":
            db.update_run(run_id, status="cancelled", finished_at=db.now())
            return True
        return False

    db.update_run(run_id, status="cancelled", finished_at=db.now())
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except ProcessLookupError:
        pass
    return True


BACKEND_ONLY_PARAMS = {"keep_work"}


def write_params(run_id: str, params: dict) -> None:
    pipeline_params = {k: v for k, v in params.items() if k not in BACKEND_ONLY_PARAMS}
    (run_dir(run_id) / "params.json").write_text(json.dumps(pipeline_params, indent=2))


def read_progress(run_id: str) -> list:
    """Per-task state, parsed from the Nextflow trace file."""
    trace = run_dir(run_id) / "results" / "pipeline_info" / "trace.txt"
    if not trace.exists():
        return []
    try:
        lines = trace.read_text(errors="replace").splitlines()
    except OSError:
        return []
    if len(lines) < 2:
        return []

    header = lines[0].split("\t")
    tasks = []
    for line in lines[1:]:
        fields = line.split("\t")
        if len(fields) != len(header):
            continue
        row = dict(zip(header, fields))
        tasks.append(
            {
                "name": row.get("name", ""),
                "process": row.get("process", ""),
                "status": row.get("status", ""),
                "duration": row.get("duration", ""),
                "exit": row.get("exit", ""),
            }
        )
    return tasks
