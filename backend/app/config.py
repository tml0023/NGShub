import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

DATA_DIR = Path(os.environ.get("NGSWEB_DATA_DIR", REPO_ROOT / "data")).resolve()
RUNS_DIR = DATA_DIR / "runs"
REFERENCES_DIR = Path(
    os.environ.get("NGSWEB_REFERENCES_DIR", DATA_DIR / "references")
).resolve()
KNOWN_SITES_DIR = Path(
    os.environ.get("NGSWEB_KNOWN_SITES_DIR", DATA_DIR / "known_sites")
).resolve()
KRAKEN2_DB_DIR = Path(
    os.environ.get("NGSWEB_KRAKEN2_DB_DIR", DATA_DIR / "kraken2_db")
).resolve()

# BQSR needs known-variant sites matched to the reference build. Resolvable
# only for the references this mapping knows about; a custom-uploaded
# reference has no known-sites data, so BQSR isn't offered for it.
KNOWN_SITES_BY_REFERENCE = {
    "hg38.fa": [
        KNOWN_SITES_DIR / "hg38" / "dbsnp138.vcf.gz",
        KNOWN_SITES_DIR / "hg38" / "mills_indels.vcf.gz",
    ],
    "hg19.fa": [
        KNOWN_SITES_DIR / "hg19" / "dbsnp138.vcf.gz",
        KNOWN_SITES_DIR / "hg19" / "mills_indels.vcf.gz",
    ],
}

# RNA-seq platforms need a gene annotation (GTF) matched to the reference's
# contig naming -- resolvable only for the references this mapping knows
# about; a custom-uploaded reference needs its own GTF uploaded alongside it.
ANNOTATION_BY_REFERENCE = {
    "hg38.fa": REFERENCES_DIR / "hg38.gtf",
    "hg19.fa": REFERENCES_DIR / "hg19.gtf",
}
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
