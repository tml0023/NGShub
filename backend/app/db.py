import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

from .config import DB_PATH

SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    status      TEXT NOT NULL,
    params      TEXT NOT NULL,
    samples     TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    started_at  TEXT,
    finished_at TEXT,
    exit_code   INTEGER,
    error       TEXT
);
"""


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@contextmanager
def connect():
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with connect() as conn:
        conn.executescript(SCHEMA)


def create_run(run_id: str, name: str, params: dict, samples: list) -> None:
    with connect() as conn:
        conn.execute(
            "INSERT INTO runs (id, name, status, params, samples, created_at)"
            " VALUES (?, ?, 'queued', ?, ?, ?)",
            (run_id, name, json.dumps(params), json.dumps(samples), now()),
        )


def update_run(run_id: str, **fields) -> None:
    if not fields:
        return
    assignments = ", ".join(f"{key} = ?" for key in fields)
    with connect() as conn:
        conn.execute(
            f"UPDATE runs SET {assignments} WHERE id = ?",
            (*fields.values(), run_id),
        )


def _row_to_dict(row: sqlite3.Row) -> dict:
    run = dict(row)
    run["params"] = json.loads(run["params"])
    run["samples"] = json.loads(run["samples"])
    return run


def get_run(run_id: str):
    with connect() as conn:
        row = conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
    return _row_to_dict(row) if row else None


def list_runs(limit: int = 100) -> list:
    with connect() as conn:
        rows = conn.execute(
            "SELECT * FROM runs ORDER BY created_at DESC LIMIT ?", (limit,)
        ).fetchall()
    return [_row_to_dict(row) for row in rows]


def reset_orphaned_runs() -> None:
    """Runs left mid-flight by a server restart can never be resumed by us."""
    with connect() as conn:
        conn.execute(
            "UPDATE runs SET status = 'failed', error = 'Server restarted during run',"
            " finished_at = ? WHERE status IN ('running', 'queued')",
            (now(),),
        )
