import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

DATA_DIR = Path(os.environ.get("NGSWEB_DATA_DIR", REPO_ROOT / "data")).resolve()
RUNS_DIR = DATA_DIR / "runs"
REFERENCES_DIR = Path(
    os.environ.get("NGSWEB_REFERENCES_DIR", DATA_DIR / "references")
).resolve()
PIPELINE_DIR = Path(
    os.environ.get("NGSWEB_PIPELINE_DIR", REPO_ROOT / "pipeline")
).resolve()
DB_PATH = Path(os.environ.get("NGSWEB_DB", DATA_DIR / "ngsweb.sqlite")).resolve()

NEXTFLOW_PROFILE = os.environ.get("NGSWEB_NEXTFLOW_PROFILE", "micromamba")
MAX_CONCURRENT_RUNS = int(os.environ.get("NGSWEB_MAX_CONCURRENT_RUNS", "1"))

CORS_ORIGINS = os.environ.get(
    "NGSWEB_CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173"
).split(",")


def tool_path_env() -> dict:
    """PATH that lets Nextflow find java, micromamba and itself."""
    env = os.environ.copy()
    extra = [str(Path(sys.executable).parent), str(Path.home() / ".local" / "bin")]
    env["PATH"] = os.pathsep.join(extra + [env.get("PATH", "")])
    env.setdefault("JAVA_HOME", str(Path(sys.executable).parent.parent / "lib" / "jvm"))
    env["NXF_ANSI_LOG"] = "false"
    return env


for directory in (DATA_DIR, RUNS_DIR, REFERENCES_DIR):
    directory.mkdir(parents=True, exist_ok=True)
