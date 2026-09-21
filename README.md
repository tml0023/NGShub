# ngs-web

A web application for running Illumina short-read NGS analysis: upload FASTQ
files, choose your tools, and get VCFs.

The application is an orchestration layer. It does not reimplement alignment or
variant calling — it drives a Nextflow pipeline that calls established tools
(BWA-MEM2, GATK, bcftools, FreeBayes, …), each provisioned in its own pinned
conda environment.

```
 Browser (React)  ──HTTP──>  FastAPI  ──subprocess──>  Nextflow  ──conda──>  bioinformatics tools
   upload, tool                job queue,               DAG, retries,          fastp, bwa-mem2,
   selection, results          run state (SQLite)       resource limits        GATK, bcftools…
```

## Pipeline

Each step offers a choice of tool. Every combination is exercised by the test
matrix in `scripts/`.

| Stage | Options |
| --- | --- |
| Read QC | FastQC (per sample) + MultiQC (aggregate) |
| Trimming | `fastp`, `Trim Galore`, or none |
| Alignment | `BWA-MEM2`, `BWA-MEM`, `Bowtie2` |
| Pre-processing | `GATK MarkDuplicates`, `samtools markdup`, or none |
| Variant calling | `GATK HaplotypeCaller`, `bcftools call`, `FreeBayes` — one or more |

Callers run in parallel on the same BAM, so you can compare their output on
identical input. Reference indices are cached in `~/.ngs-web/reference_cache`
and shared across runs; conda environments are cached in `~/.ngs-web/conda`.

## Requirements

- macOS or Linux
- conda (Miniconda or Miniforge)
- ~10 GB disk for tool environments, plus space for your data

Everything else — Nextflow, Java, Node, Python — is installed by the setup
script into a single conda environment.

## Setup

```bash
./scripts/setup.sh
conda activate ngsweb
```

## Running

```bash
./scripts/dev.sh
```

- Frontend: http://127.0.0.1:5173
- API: http://127.0.0.1:8000 (interactive docs at `/docs`)

For a single-process deployment, build the frontend first — the API then serves
it at `/`:

```bash
cd frontend && npm run build && cd ..
uvicorn backend.app.main:app --port 8000
```

### Reference genomes

Drop FASTA files into `data/references/` and they appear in the reference
dropdown. Users can also upload a FASTA with a run. The reference must be
uncompressed (`.fa`, `.fasta`, `.fna`).

## Validating the install

Generate a small synthetic dataset with known variants and run the pipeline
against it:

```bash
python scripts/make_test_data.py --outdir data/test

cd pipeline
nextflow run main.nf -profile test,micromamba \
  --input ../data/test/samplesheet.csv \
  --fasta ../data/test/reference.fa \
  --outdir ../data/test/results \
  --trimmer fastp --aligner bwa --markduplicates samtools --callers bcftools
```

`data/test/truth.vcf` holds the 50 SNVs that were spiked into the donor genome,
so the output VCF can be compared directly against it. `scripts/validate.sh`
runs a matrix of tool combinations and scores each VCF automatically.

Callers are compared after decomposing multi-nucleotide alleles and dropping
`QUAL < 20`. Both matter for FreeBayes, which emits `QUAL=0` candidates and
represents adjacent variants as haplotype alleles (`CAGAT->CAGAC`) where
bcftools and GATK emit separate SNVs. Raw caller output is published unchanged
— filtering and normalisation are left to you.

## Running the pipeline without the web app

The pipeline is a standalone Nextflow workflow and is usable on its own:

```bash
cd pipeline
nextflow run main.nf \
  --input samplesheet.csv \
  --fasta /path/to/GRCh38.fa \
  --outdir results \
  --aligner bwamem2 \
  --markduplicates gatk \
  --callers haplotypecaller,bcftools
```

The samplesheet is CSV with a header; leave `fastq_2` empty for single-end data:

```csv
sample,fastq_1,fastq_2
NA12878,/data/NA12878_R1.fastq.gz,/data/NA12878_R2.fastq.gz
```

## Layout

```
pipeline/     Nextflow workflow (main.nf, modules/, nextflow.config)
backend/app/  FastAPI service: catalog, run submission, job runner, results
frontend/src/ React UI: run builder, run list, live progress, VCF browser
scripts/      setup, dev server, synthetic test data
data/         runs, uploaded inputs, reference genomes (gitignored)
```

## Extending

**Adding a tool** to an existing stage takes three coordinated edits:

1. `pipeline/modules/<stage>.nf` — add the process, pinning the conda package.
2. `pipeline/main.nf` — add a branch and extend the `validateChoice` list.
3. `backend/app/catalog.py` — add the option so the UI offers it.

The catalog is the single source of truth for the UI, and `VALID` in the same
file is what the API validates against, so those stay in sync automatically.

**Adding a sequencing platform** (PacBio, Oxford Nanopore) is a larger change:
long reads need different aligners (`minimap2`, `pbmm2`) and callers tuned to
their error profiles (`Clair3`, DeepVariant-PacBio). The intended shape is a
separate workflow per platform selected at the top level, rather than more
branches inside the Illumina workflow.

## Running on HPC or cloud

Nextflow abstracts the executor, so the pipeline code does not change. Add or
adjust a profile in `pipeline/nextflow.config` and point the backend at it with
`NGSWEB_NEXTFLOW_PROFILE`:

```bash
NGSWEB_NEXTFLOW_PROFILE=slurm uvicorn backend.app.main:app
```

A `slurm` profile is included as a starting point. What still needs work per
target: shared filesystem paths for HPC, and object storage plus credentials
and cost controls for cloud. Container images (Docker/Singularity) are not yet
defined per process — that is the prerequisite for cloud execution.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `NGSWEB_DATA_DIR` | `./data` | Runs, uploads, SQLite database |
| `NGSWEB_REFERENCES_DIR` | `./data/references` | Reference genomes offered in the UI |
| `NGSWEB_NEXTFLOW_PROFILE` | `micromamba` | Nextflow profile used for runs |
| `NGSWEB_MAX_CONCURRENT_RUNS` | `1` | Pipeline runs executed in parallel |
| `NGSWEB_CORS_ORIGINS` | Vite dev server | Allowed browser origins |

Per-run resource ceilings live in `pipeline/nextflow.config` (`max_cpus`,
`max_memory`). They default to 6 CPUs / 6 GB, suitable for a laptop.

## Current limitations

- Single-user: no authentication or per-user data isolation.
- Germline calling only; no BQSR, VQSR, or joint genotyping across samples.
- No container images yet, so cloud executors are not usable as-is.
- Work directories are deleted after a successful run, so `-resume` only helps
  for failed runs.
