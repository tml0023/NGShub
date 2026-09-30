import gzip
import json
import re
import shutil
import subprocess
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import db, runner
from .catalog import PLATFORMS, VALID
from .config import CORS_ORIGINS, KNOWN_SITES_BY_REFERENCE, REFERENCES_DIR, REPO_ROOT, RUNS_DIR

DOCKER_HELP_URL = "https://www.docker.com/products/docker-desktop/"

SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
FASTQ_SUFFIXES = (".fastq", ".fq", ".fastq.gz", ".fq.gz")
# samtools faidx needs an uncompressed (or bgzipped) FASTA; plain .gz will fail.
FASTA_SUFFIXES = (".fa", ".fasta", ".fna")


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()
    db.reset_orphaned_runs()
    runner.start_workers()
    yield


app = FastAPI(title="ngs-web", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)


def safe_name(value: str, label: str) -> str:
    name = Path(value).name
    if not SAFE_NAME.match(name):
        raise HTTPException(400, f"Invalid {label}: {value!r}")
    return name


def resolve_within(base: Path, relative: str) -> Path:
    target = (base / relative).resolve()
    if not target.is_relative_to(base.resolve()):
        raise HTTPException(400, "Path outside of run directory")
    return target


def require_run(run_id: str) -> dict:
    run = db.get_run(safe_name(run_id, "run id"))
    if not run:
        raise HTTPException(404, "Run not found")
    return run


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/api/catalog")
def get_catalog():
    return {"platforms": PLATFORMS}


@app.get("/api/references")
def get_references():
    references = []
    for path in sorted(REFERENCES_DIR.glob("*")):
        if path.suffix.lower() in (".fa", ".fasta", ".fna") and path.is_file():
            references.append({"name": path.name, "size": path.stat().st_size})
    return references


def _docker_status() -> dict:
    docker_path = shutil.which("docker")
    if not docker_path:
        return {
            "available": False,
            "detail": "Docker isn't installed. Run ./scripts/setup_docker.sh, "
            f"or see {DOCKER_HELP_URL}.",
        }
    try:
        result = subprocess.run(
            ["docker", "info"], capture_output=True, timeout=20, text=True
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return {"available": False, "detail": f"Docker check failed: {exc}"}
    if result.returncode != 0:
        return {
            "available": False,
            "detail": "Docker is installed but not running. Open Docker Desktop "
            "and wait for it to finish starting.",
        }
    return {"available": True, "detail": None}


@app.get("/api/setup-status")
def get_setup_status():
    references = {
        name: (REFERENCES_DIR / name).is_file() for name in KNOWN_SITES_BY_REFERENCE
    }
    known_sites = {
        name: all(p.is_file() for p in paths)
        for name, paths in KNOWN_SITES_BY_REFERENCE.items()
    }
    return {
        "docker": _docker_status(),
        "references": references,
        "known_sites": known_sites,
    }


@app.post("/api/runs", status_code=201)
async def create_run(
    name: str = Form(...),
    config: str = Form(...),
    samples: str = Form(...),
    files: list[UploadFile] = File(default=[]),
    reference_file: UploadFile | None = File(default=None),
):
    try:
        cfg = json.loads(config)
        sample_rows = json.loads(samples)
    except json.JSONDecodeError as exc:
        raise HTTPException(400, f"Malformed JSON: {exc}") from exc

    if not isinstance(sample_rows, list) or not sample_rows:
        raise HTTPException(400, "At least one sample is required")

    platform = cfg.get("platform")
    if platform not in PLATFORMS:
        raise HTTPException(400, f"Invalid platform: {platform!r}. Available: {sorted(PLATFORMS)}")
    platform_def = PLATFORMS[platform]
    platform_valid = VALID[platform]

    for step in platform_def["steps"]:
        key = step["id"]
        value = cfg.get(key)
        if value not in platform_valid[key]:
            raise HTTPException(400, f"Invalid {key}: {value!r}")

    callers = cfg.get("callers") or []
    if not callers or not set(callers).issubset(platform_valid["callers"]):
        raise HTTPException(400, f"Invalid callers: {callers!r}")

    run_id = uuid.uuid4().hex[:12]
    directory = runner.run_dir(run_id)
    inputs = directory / "inputs"
    inputs.mkdir(parents=True, exist_ok=True)

    stored: dict[str, Path] = {}
    for upload in files:
        filename = safe_name(upload.filename or "", "filename")
        if not filename.lower().endswith(FASTQ_SUFFIXES):
            raise HTTPException(400, f"{filename} is not a FASTQ file")
        destination = inputs / filename
        with open(destination, "wb") as handle:
            shutil.copyfileobj(upload.file, handle, length=1024 * 1024)
        stored[filename] = destination

    if reference_file is not None and reference_file.filename:
        ref_name = safe_name(reference_file.filename, "reference filename")
        if not ref_name.lower().endswith(FASTA_SUFFIXES):
            raise HTTPException(400, "Reference must be an uncompressed FASTA file")
        reference_path = inputs / ref_name
        with open(reference_path, "wb") as handle:
            shutil.copyfileobj(reference_file.file, handle, length=1024 * 1024)
    else:
        ref_name = cfg.get("reference")
        if not ref_name:
            raise HTTPException(400, "A reference genome is required")
        reference_path = REFERENCES_DIR / safe_name(ref_name, "reference")
        if not reference_path.is_file():
            raise HTTPException(400, f"Unknown reference genome: {ref_name}")

    known_sites: list[Path] = []
    if platform == "illumina" and cfg.get("bqsr"):
        known_sites = KNOWN_SITES_BY_REFERENCE.get(ref_name, [])
        if reference_file is not None or not known_sites:
            available = ", ".join(sorted(KNOWN_SITES_BY_REFERENCE))
            raise HTTPException(
                400,
                "BQSR needs known-variant sites matched to the reference genome; "
                f"available for: {available}. Pick one of those, or turn off BQSR.",
            )
        missing = [str(p) for p in known_sites if not p.is_file()]
        if missing:
            raise HTTPException(500, f"Known-sites files missing on server: {missing}")

    normalised = []
    if platform_def["paired"]:
        samplesheet_rows = ["sample,fastq_1,fastq_2"]
        for row in sample_rows:
            sample = safe_name(str(row.get("sample", "")), "sample name")
            read1 = safe_name(str(row.get("fastq_1", "")), "fastq_1")
            if read1 not in stored:
                raise HTTPException(400, f"{read1} was not uploaded")
            read2_value = row.get("fastq_2")
            read2 = safe_name(str(read2_value), "fastq_2") if read2_value else ""
            if read2 and read2 not in stored:
                raise HTTPException(400, f"{read2} was not uploaded")
            samplesheet_rows.append(
                f"{sample},{stored[read1]},{stored[read2] if read2 else ''}"
            )
            normalised.append({"sample": sample, "fastq_1": read1, "fastq_2": read2 or None})
    else:
        # Single-end (e.g. PacBio HiFi): one read file per sample, no pairing.
        samplesheet_rows = ["sample,fastq"]
        for row in sample_rows:
            sample = safe_name(str(row.get("sample", "")), "sample name")
            read1 = safe_name(str(row.get("fastq_1", "")), "fastq_1")
            if read1 not in stored:
                raise HTTPException(400, f"{read1} was not uploaded")
            samplesheet_rows.append(f"{sample},{stored[read1]}")
            normalised.append({"sample": sample, "fastq_1": read1, "fastq_2": None})

    samplesheet = directory / "samplesheet.csv"
    samplesheet.write_text("\n".join(samplesheet_rows) + "\n")

    params = {
        "input": str(samplesheet),
        "fasta": str(reference_path.resolve()),
        "outdir": str(directory / "results"),
        "callers": ",".join(callers),
    }
    for step in platform_def["steps"]:
        params[step["id"]] = cfg[step["id"]]
    for flag in platform_def["flags"]:
        params[flag["id"]] = bool(cfg.get(flag["id"], flag["default"]))
    if known_sites:
        params["bqsr"] = True
        params["known_sites"] = ",".join(str(p) for p in known_sites)
    if cfg.get("keep_work"):
        params["keep_work"] = True

    db.create_run(run_id, name.strip() or run_id, platform, params, normalised)
    runner.write_params(run_id, params)
    runner.submit(run_id)

    return {"id": run_id, "status": "queued"}


@app.get("/api/runs")
def list_runs():
    return db.list_runs()


@app.get("/api/runs/{run_id}")
def get_run(run_id: str):
    run = require_run(run_id)
    run["tasks"] = runner.read_progress(run_id)
    return run


@app.post("/api/runs/{run_id}/cancel")
def cancel_run(run_id: str):
    require_run(run_id)
    if not runner.cancel(run_id):
        raise HTTPException(409, "Run is not active")
    return {"status": "cancelled"}


@app.get("/api/runs/{run_id}/log")
def get_log(run_id: str, offset: int = Query(0, ge=0)):
    require_run(run_id)
    log_path = runner.run_dir(run_id) / "run.log"
    if not log_path.exists():
        return {"offset": 0, "text": ""}
    with open(log_path, "r", errors="replace") as handle:
        handle.seek(offset)
        text = handle.read()
        return {"offset": handle.tell(), "text": text}


@app.get("/api/runs/{run_id}/files")
def list_files(run_id: str):
    require_run(run_id)
    results = runner.run_dir(run_id) / "results"
    if not results.exists():
        return []
    entries = []
    for path in sorted(results.rglob("*")):
        if path.is_file():
            entries.append(
                {
                    "path": str(path.relative_to(results)),
                    "size": path.stat().st_size,
                }
            )
    return entries


@app.get("/api/runs/{run_id}/download")
def download(run_id: str, path: str = Query(...)):
    require_run(run_id)
    results = runner.run_dir(run_id) / "results"
    target = resolve_within(results, path)
    if not target.is_file():
        raise HTTPException(404, "File not found")
    return FileResponse(target, filename=target.name)


@app.get("/api/runs/{run_id}/variants")
def get_variants(
    run_id: str,
    caller: str = Query(...),
    sample: str | None = Query(None),
    limit: int = Query(200, ge=1, le=5000),
):
    run = require_run(run_id)
    if caller not in VALID[run["platform"]]["callers"]:
        raise HTTPException(400, f"Unknown caller: {caller}")

    directory = runner.run_dir(run_id) / "results" / "variants" / caller
    vcfs = sorted(directory.glob("*.vcf.gz")) if directory.exists() else []
    if not vcfs:
        raise HTTPException(404, f"No VCF found for {caller}")

    by_sample = {vcf.name.split(f".{caller}.vcf.gz")[0]: vcf for vcf in vcfs}
    if sample is not None:
        if sample not in by_sample:
            raise HTTPException(
                404, f"No {caller} VCF for sample {sample!r}. Available: {sorted(by_sample)}"
            )
        target = by_sample[sample]
    elif len(vcfs) == 1:
        target = vcfs[0]
    else:
        raise HTTPException(
            400, f"Multiple samples for {caller}; pass ?sample=. Available: {sorted(by_sample)}"
        )

    variants = []
    total = 0
    with gzip.open(target, "rt", errors="replace") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            total += 1
            if len(variants) >= limit:
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 8:
                continue
            variants.append(
                {
                    "chrom": fields[0],
                    "pos": int(fields[1]),
                    "ref": fields[3],
                    "alt": fields[4],
                    "qual": fields[5],
                    "filter": fields[6],
                }
            )
    return {
        "caller": caller,
        "file": target.name,
        "sample": target.name.split(f".{caller}.vcf.gz")[0],
        "samples": sorted(by_sample),
        "total": total,
        "variants": variants,
    }


# Serve the built frontend when it exists, so production runs from one process.
_frontend = REPO_ROOT / "frontend" / "dist"
if _frontend.is_dir():
    app.mount("/", StaticFiles(directory=str(_frontend), html=True), name="frontend")
