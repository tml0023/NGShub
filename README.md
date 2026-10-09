# NGShub

A web application for running NGS analysis across platforms: upload reads,
choose your tools, and get VCFs — or, for RNA-seq, gene/transcript counts,
differential expression, and isoform classification.

The application is an orchestration layer. It does not reimplement alignment or
variant calling — it drives Nextflow pipelines that call established tools
(BWA-MEM2, GATK, pbmm2, DeepVariant, …), each provisioned in its own pinned
conda environment or container.

```
 Browser (React)  ──HTTP──>  FastAPI  ──subprocess──>  Nextflow  ──conda/docker──>  bioinformatics tools
   upload, tool                job queue,               DAG, retries,                fastp, bwa-mem2,
   selection, results          run state (SQLite)       resource limits              GATK, DeepVariant…
```

## Platforms

Picking a platform in the UI selects an entirely separate Nextflow workflow —
the tools genuinely don't overlap between short and long reads, so this isn't
just a parameter change.

### Illumina (short read) — `pipeline/main.nf`

Paired- or single-end. Every step offers a choice of tool; callers run in
parallel on the same BAM, so you can compare their output on identical input.

| Stage | Options |
| --- | --- |
| Read QC | FastQC (per sample) + MultiQC (aggregate) |
| Trimming | `fastp`, `Trim Galore`, or none |
| Alignment | `BWA-MEM2`, `BWA-MEM`, `Bowtie2`, `DragMap` |
| Pre-processing | `GATK MarkDuplicates`, `samtools markdup`, or none, then optionally **BQSR** |
| Variant calling | `GATK HaplotypeCaller`, `bcftools call`, `FreeBayes`, `DeepVariant` — one or more |
| Structural variant calling (optional) | `Manta`, `Delly` — zero or more |

Structural variant calling is opt-in and off by default — it targets larger
rearrangements (deletions, insertions, duplications) that the SNV/indel
callers above miss. Delly doesn't reliably call insertions from short reads
(a well-known limitation of read-pair/split-read evidence at that size), so
pair it with Manta if insertions matter. SV output uses breakend/SVTYPE VCF
notation, not the simple REF/ALT the built-in variant browser expects — see
[Current limitations](#current-limitations).

BQSR (`GATK BaseRecalibrator` + `ApplyBQSR`) needs known-variant sites
(dbSNP, Mills indels) matched to the reference genome's exact contig naming —
only wired up for the built-in `hg38.fa` and `hg19.fa` right now (see
[Reference genomes](#reference-genomes)).

### PacBio HiFi (long read) — `pipeline/pacbio/main.nf`

Single-end — HiFi is single-molecule consensus sequencing, so there's no
R1/R2 pairing. No trimming stage: HiFi reads are already ~99.9% accurate
CCS consensus sequences, so adapter/quality trimming isn't a standard step
the way it is for raw Illumina reads. Duplicate marking, when used, runs
*before* alignment on raw reads — `pbmarkdup` uses reference-free sequence
comparison, not alignment position — unlike Illumina's post-alignment dedup.

| Stage | Options |
| --- | --- |
| Read QC | NanoPlot (long-read QC; FastQC isn't built for this) + MultiQC |
| Pre-processing | `pbmarkdup` (run with `--rmdup`, so duplicates are actually removed — without it the tool only marks them, and a FASTQ has nothing for the aligner to honor), or none (the typical default — HiFi library prep makes PCR duplication far less common) |
| Alignment | `pbmm2` (PacBio's official minimap2 wrapper, HiFi-tuned presets), `minimap2` directly |
| Variant calling | `DeepVariant` (`--model_type=PACBIO`, most benchmarked for HiFi germline calling), `Clair3` — one or more |
| Structural variant calling (optional) | `pbsv` (PacBio's own SV caller, HiFi/CCS-tuned), `Sniffles2` — zero or more |

### Oxford Nanopore (long read) — `pipeline/ont/main.nf`

Single-end, like PacBio. Unlike HiFi, raw ONT reads are noisier (~99% for
current R10.4.1 chemistry with super-accuracy basecalling), so this workflow
has a quality/length filtering stage that PacBio's doesn't. Alignment has one
option on purpose: `minimap2` (`-x map-ont`) is the field standard, and a
second choice would just be there for symmetry.

| Stage | Options |
| --- | --- |
| Read QC | NanoPlot + MultiQC |
| Filtering | `chopper` (Q≥10, ≥500 bp by default — `--chopper_min_quality` / `--chopper_min_length`), or none |
| Alignment | `minimap2` (`-x map-ont`) |
| Pre-processing | none (the typical default — ONT libraries are usually PCR-free), or `samtools markdup` |
| Variant calling | `Clair3` (`--platform=ont`, R10.4.1 SUP model; the most benchmarked ONT caller), `DeepVariant` (`--model_type=ONT_R104`) — one or more |
| Structural variant calling (optional) | `Sniffles2`, `cuteSV` (ONT-tuned preset) — zero or more |

The bundled Clair3 model targets R10.4.1 flow cells. Older R9.4.1 data needs a
different model — set `--ont_clair3_model` (see the model names in the
`hkubal/clair3` image under `/opt/models/`).

### Containerized tools

`DragMap`, `DeepVariant`, `pbmarkdup`, `Clair3`, `Manta`, and `pbsv` run in
containers rather than conda environments — marked with a `DOCKER` badge in
the UI. DragMap, pbmarkdup, Manta, and pbsv have no macOS build at all (their
bioconda packages ship Linux-only binaries); DeepVariant's and Clair3's conda
packages pull in TensorFlow builds that don't reliably resolve. All of these
work the same way they do in production pipelines like nf-core/sarek — via Docker.
Selecting any of them requires Docker Desktop running locally and
`-profile docker` (see [Using containerized tools](#using-containerized-tools));
every other tool resolves through conda and needs nothing extra. Both long-read
platforms have *only* containerized callers, so they need Docker for any run
that produces a VCF.

Reference indices are cached in `~/.ngs-web/reference_cache` and shared across
runs; conda environments are cached in `~/.ngs-web/conda`.

## RNA-seq platforms

These three are a different task from the DNA platforms above — quantifying
or discovering transcripts, not calling variants — so they produce count
matrices and GTFs, not VCFs. All three need a gene annotation (GTF) matched
to the reference genome, in addition to the FASTA (see
[Reference genomes](#reference-genomes)).

### Illumina (RNA-seq) — `pipeline/rna/illumina/main.nf`

Paired- or single-end. STAR aligns to the genome for QC purposes only
(MultiQC mapping stats); Salmon quantifies independently, straight from the
trimmed reads against a transcriptome index (no genome decoys — a possible
future refinement, not required for Salmon to work correctly). Differential
expression is automatic, not a toggle: assign samples to 2+ conditions in the
sample table and DESeq2 runs via tximport; leave conditions blank and the
pipeline stops at per-sample quantification.

| Stage | Options |
| --- | --- |
| Read QC | FastQC + MultiQC |
| Trimming | `Trim Galore`, or none |
| Alignment | `STAR` (QC only — not fed into quantification) |
| Quantification | `Salmon` |
| Differential expression | DESeq2 + tximport, automatic when 2+ conditions are assigned |

### PacBio Iso-Seq (long read) — `pipeline/rna/pacbio/main.nf`

Single-end full-length cDNA. Fixed canonical workflow, not a tool-choice menu
— `lima` (primer removal) → `isoseq refine` (polyA/concatemer trimming) →
`isoseq cluster2` (isoform clustering) → `pbmm2` (`--preset ISOSEQ`) →
`isoseq collapse` → `pigeon classify`/`filter` (PacBio's official classifier,
built on SQANTI3) against the reference annotation. `lima`, `isoseq`, and
`pbpigeon` all ship Linux-only bioconda binaries, so this entire platform
needs Docker regardless of which options are picked — `pbmm2` is the only
step that would otherwise run on conda. Defaults to the standard NEB Iso-Seq
primers; upload your own primers FASTA if your library prep used a different
kit (e.g. Kinnex barcoded primers). No differential expression — isoform-level
comparison across samples isn't as standardized as DESeq2 is for short-read
gene counts.

Uploaded FASTQ is converted to BAM internally, since the Iso-Seq toolkit is
BAM-native — but not via a plain `samtools import`. The Iso-Seq tools expect
the per-read CCS tags every real PacBio BAM carries (`qs`/`qe`/`zm`/`np`/`rq`/
`ec`); without them, `lima` doesn't error, it hangs indefinitely in an
internal thread wait, regardless of thread count or `--peek-guess`. A small
script (`pipeline/rna/pacbio/bin/fastq_to_pacbio_bam.py`, via `pysam`)
builds a BAM with those tags populated instead.

### Oxford Nanopore (RNA-seq) — `pipeline/rna/ont/main.nf`

Single-end cDNA/direct RNA. `minimap2 -x splice` aligns all samples, then
Bambu or StringTie2 reconstructs and quantifies transcripts — jointly across
every sample at once (unlike the per-sample processing everywhere else in
this app), since novel-isoform discovery benefits from pooled evidence.
Bambu does reconstruction and quantification in one step; StringTie2 assembles
per-sample, merges across samples, then quantifies with featureCounts. No
differential expression, for the same reason as PacBio.

| Stage | Options |
| --- | --- |
| Read QC | NanoPlot + MultiQC |
| Filtering | `chopper`, or none |
| Alignment | `minimap2` (`-x splice`) |
| Quantification | `Bambu`, `StringTie2 + featureCounts` — one or more |

## Pathogen surveillance

A third mode family, separate from DNA variant calling and RNA-seq: instead
of calling variants against a reference you choose, this identifies *what
pathogen is present* and screens it for known risk markers, with no
reference genome input at all. The first mode — targeted influenza — is an
MVP, not a finished product; see [Current limitations](#current-limitations)
for what's not built yet.

### Targeted Influenza Surveillance — `pipeline/surveillance/influenza/main.nf`

Paired-end Illumina only for now. No reference genome or annotation needed
— IRMA carries its own curated influenza reference modules internally, so
this platform doesn't show the reference-genome picker at all.

| Stage | Tool |
| --- | --- |
| Read QC | FastQC + MultiQC |
| Segment assembly & subtyping | `IRMA` (CDC's Iterative Refinement Meta-Assembler, FLU module) |
| Genotype assignment | `GenoFLU` (USDA; H5Nx clade 2.3.4.4b genotyping) |
| Risk-marker screen | in-house, rule-based (see below) |
| Report | plain-language HTML summary + technical appendix |

A sample that assembles zero segments (no influenza detected, or an
incomplete genome) is a real, reportable outcome, not a pipeline error —
genotyping, risk-scoring, and reporting are skipped for it rather than
producing a fabricated result.

**Risk-marker screening (v1, rule-based).** Checks the assembled PB2, PA,
and NA segments against four literature-established markers: PB2 E627K and
D701N (mammalian adaptation), PA I38T (baloxavir resistance), NA H275Y
(oseltamivir resistance, N1 numbering). Marker positions are read off a
BLOSUM62 global alignment against a reference protein with known
literature-standard numbering, not a raw translated sequence offset — IRMA's
assembled segments include the untranslated vRNA ends, so position 1 isn't
the CDS start, and naively scanning for the first long open reading frame
can land on the wrong start codon (confirmed directly during validation; see
`docs/validation_results.md`). The result is decision support, not a
diagnosis — see the disclaimer every generated report carries.

## Requirements

- macOS or Linux
- conda (Miniconda or Miniforge)
- ~10 GB disk for tool environments, plus space for your data
- Docker Desktop (or another container runtime) — only if you plan to use a
  containerized tool (see above); everything else works without it

Everything else — Nextflow, Java, Node, Python — is installed by the setup
script into a single conda environment.

## Setup

```bash
./scripts/setup.sh
conda activate ngsweb
```

That's enough to run everything except the containerized tools and BQSR. Two
more, both optional and both safe to skip if you don't need them yet — the
app tells you when you do, with a warning right on the New Run form (see
[Setup status](#setup-status)) rather than letting a run fail minutes in:

```bash
./scripts/setup_docker.sh       # Docker Desktop -- for DragMap, DeepVariant, pbmarkdup, Clair3
./scripts/setup_references.sh   # hg38/hg19 genomes + BQSR known-sites, ~9 GB, resumable
```

`setup_docker.sh` automates what it can (installs via Homebrew, launches the
app) but one step is unavoidably manual: macOS will prompt you to grant
Docker privileged network access on first launch — accept that dialog, then
wait for the whale icon in the menu bar before using a containerized tool.
On Intel Macs, Homebrew sometimes can't write to a few `/usr/local`
subdirectories left root-owned by an old system install; the script detects
this up front and prints the exact `chown` fix rather than failing partway
through a cask install with a confusing permission error.

`setup_references.sh` is idempotent — safe to re-run after a network
interruption, it skips whatever's already downloaded.

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

`./scripts/setup_references.sh` downloads `hg38.fa` (GRCh38, UCSC
chr-prefixed contigs) and `hg19.fa` (GRCh37, Broad's b37-style bare contig
naming — `1` not `chr1`, chosen specifically because it matches the
known-sites bundle below), matching BQSR known-sites resources into
`data/known_sites/{hg38,hg19}/` (dbSNP138 + Mills gold-standard indels, from
Broad's public reference bucket), and matching gene annotations into
`data/references/{hg38,hg19}.gtf` for the RNA-seq platforms (GENCODE for
hg38, chr-prefixed; Ensembl GRCh37 release 87 for hg19, bare contig names —
same contig-naming reasoning as the FASTA/known-sites pairing) — ~10 GB
total, nothing here ships in the repo itself. A custom-uploaded reference
needs its own matching GTF uploaded alongside it for the RNA-seq platforms,
the same way BQSR needs its own known-sites. Building an aligner index against either genome is a real
workload: `bwa-mem2 index` in particular wants well over the 6 GB RAM this
pipeline is configured for on a laptop, and `DragMap`'s hash table build
officially wants 32 GB+. `BWA-MEM` and `Bowtie2` are the realistic choices
for full-genome Illumina runs on modest hardware; index once and it's cached
in `~/.ngs-web/reference_cache` for every run after. STAR's genome index for
the RNA-seq platform has the same problem, worse: STAR's own documentation
wants ~30 GB RAM for a full human genome index, well beyond this pipeline's
6 GB default ceiling — raise `--max_memory` (and have the RAM to back it up)
before running Illumina RNA-seq against hg38/hg19 for real.

Mixing genome builds breaks things in a way that's easy to miss: a reference
and a known-sites VCF with the same contig name but different declared
lengths (e.g. a chr20 slice vs. the real 64Mb chr20) fails GATK's sequence
dictionary validation outright — this is a real safety check, not a bug to
work around.

### Setup status

The New Run form checks `GET /api/setup-status` (Docker availability, plus
which references have their known-sites resources present) and warns inline
— right next to the option you picked — if what you've selected won't
actually work, instead of letting you find out from a failed run:

- Pick a `DOCKER`-badged tool without Docker running → a warning names the
  tool and points at `./scripts/setup_docker.sh`.
- Turn on BQSR for a reference with no known-sites downloaded → a warning
  points at `./scripts/setup_references.sh`.

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

## Running a pipeline without the web app

All three workflows are standalone Nextflow pipelines and usable on their own.

**Illumina:**

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

**PacBio HiFi:**

```bash
cd pipeline
nextflow run pacbio/main.nf -profile docker \
  --input samplesheet.csv \
  --fasta /path/to/GRCh38.fa \
  --outdir results \
  --aligner pbmm2 \
  --markduplicates none \
  --callers deepvariant
```

The samplesheet is single-column — one FASTQ per sample, no pairing:

```csv
sample,fastq
sample1,/data/sample1.hifi_reads.fastq.gz
```

**Oxford Nanopore:**

```bash
cd pipeline
nextflow run ont/main.nf -profile docker \
  --input samplesheet.csv \
  --fasta /path/to/GRCh38.fa \
  --outdir results \
  --trimmer chopper \
  --markduplicates none \
  --callers clair3
```

Same single-column samplesheet as PacBio. Run these from `pipeline/` (or pass
`-c pipeline/nextflow.config`): Nextflow only finds `nextflow.config` next to
the script or in the directory you launch from, and `ont/` and `pacbio/` have
none of their own — from anywhere else they run with no conda, no profiles,
and no defaults. The web app passes it explicitly.

Each workflow validates its own `--aligner`/`--markduplicates`/`--callers`
values and will error clearly if you pass one meant for the other platform —
there's no shared default, since the two share few of the same values.

## Layout

```
pipeline/main.nf         Illumina workflow
pipeline/modules/        Illumina processes
pipeline/pacbio/main.nf  PacBio HiFi workflow
pipeline/pacbio/modules/ PacBio-specific processes (reuses generic ones from pipeline/modules/)
pipeline/ont/main.nf     Oxford Nanopore workflow
pipeline/ont/modules/    ONT-specific processes (reuses generic ones, incl. NanoPlot, from pipeline/modules/)
pipeline/rna/illumina/   Illumina RNA-seq workflow (STAR, Salmon, DESeq2)
pipeline/rna/pacbio/     PacBio Iso-Seq workflow (lima, isoseq, pbmm2, pigeon)
pipeline/rna/ont/        ONT RNA-seq workflow (minimap2, Bambu/StringTie2)
pipeline/surveillance/influenza/  Targeted influenza workflow (IRMA, GenoFLU, risk scoring)
pipeline/nextflow.config Shared: profiles, resource limits, conda/docker config
backend/app/              FastAPI service: catalog, run submission, job runner, results
frontend/src/             React UI: platform + run builder, run list, live progress, VCF browser
scripts/                  setup, dev server, synthetic test data
docs/                     validation results and methodology
data/                     runs, uploaded inputs, reference genomes, known-sites (gitignored)
```

## Extending

**Adding a tool** to an existing stage takes three coordinated edits:

1. `pipeline/{,pacbio/}modules/<stage>.nf` — add the process, pinning the
   conda package (or `container` if no conda build exists — check
   `micromamba repoquery search -c bioconda -c conda-forge --platform osx-64
   <package>` before assuming; several tools here needed one).
2. The platform's `main.nf` — add a branch and extend the `validateChoice` list.
3. `backend/app/catalog.py` — add the option under that platform's entry in
   `PLATFORMS` so the UI offers it. `VALID` is derived from `PLATFORMS`
   automatically, so it stays in sync.

**Adding a sequencing platform** (Oxford Nanopore is the natural next one):
add `pipeline/<platform>/main.nf` + `modules/`, a `PLATFORMS["<platform>"]`
entry in `catalog.py` (set `"paired": false` for single-end long-read data,
`"pipeline": "<platform>/main.nf"`), and extend `main.py`'s samplesheet
branch if the new platform needs yet another sample-sheet shape beyond
paired/single-end.

## Using containerized tools

DragMap, DeepVariant, pbmarkdup, and Clair3 need Docker Desktop running.
Point the backend at the `docker` profile instead of the default
`micromamba` one:

```bash
NGSWEB_NEXTFLOW_PROFILE=docker ./scripts/dev.sh
```

Every other tool still resolves through conda under this profile — only
processes with a `container` directive run through Docker. From the CLI:

```bash
nextflow run main.nf -profile docker \
  --input samplesheet.csv --fasta reference.fa \
  --aligner dragmap --callers deepvariant

nextflow run pacbio/main.nf -profile docker \
  --input samplesheet.csv --fasta reference.fa \
  --markduplicates pbmarkdup --callers clair3
```

The web app switches to the `docker` profile by itself whenever a selected
tool needs a container, so `NGSWEB_NEXTFLOW_PROFILE` only matters for CLI runs
or for forcing a different profile.

**Keep the machine awake on a laptop.** macOS sleep freezes Docker's VM while
the container's clock keeps counting, so a run looks hung (0% CPU, "process
hasn't exited") and then fails hours later. `caffeinate -i -s <command>` blocks
idle sleep, but only on AC power — it can't stop a lid-close sleep on battery.
For long DeepVariant or Clair3 runs, stay plugged in with the lid open (or use
clamshell mode with a display attached).

Docker Desktop's default VM memory allocation (often ~4 GB) is tight for
DeepVariant even on small regions — increase it in Docker Desktop's settings
if a containerized caller runs very slowly or gets OOM-killed on real data.

## Running on HPC or cloud

Nextflow abstracts the executor, so the pipeline code does not change. Add or
adjust a profile in `pipeline/nextflow.config` and point the backend at it with
`NGSWEB_NEXTFLOW_PROFILE`:

```bash
NGSWEB_NEXTFLOW_PROFILE=slurm uvicorn backend.app.main:app
```

A `slurm` profile is included as a starting point. What still needs work per
target: shared filesystem paths for HPC, and object storage plus credentials
and cost controls for cloud. Only DragMap, DeepVariant, pbmarkdup, and Clair3
have container images defined; every other process still needs conda, so a
from-scratch containerized run of the whole pipeline isn't possible yet —
that's the remaining prerequisite for a clean cloud/Kubernetes deployment (HPC
with conda support works today via the `slurm` profile).

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `NGSWEB_DATA_DIR` | `./data` | Runs, uploads, SQLite database |
| `NGSWEB_REFERENCES_DIR` | `./data/references` | Reference genomes offered in the UI |
| `NGSWEB_KNOWN_SITES_DIR` | `./data/known_sites` | BQSR known-variant-sites resources |
| `NGSWEB_NEXTFLOW_PROFILE` | `micromamba` | Nextflow profile used for runs |
| `NGSWEB_MAX_CONCURRENT_RUNS` | `1` | Pipeline runs executed in parallel |
| `NGSWEB_CORS_ORIGINS` | Vite dev server | Allowed browser origins |

Per-run resource ceilings live in `pipeline/nextflow.config` (`max_cpus`,
`max_memory`). They default to 6 CPUs / 6 GB, suitable for a laptop.

## Current limitations

- Single-user: no authentication or per-user data isolation.
- Germline calling only; no VQSR or joint genotyping across samples.
- BQSR's known-sites lookup only covers the two built-in reference genomes;
  a custom-uploaded reference can't use BQSR without adding it to
  `KNOWN_SITES_BY_REFERENCE` in `backend/app/config.py`.
- Work directories are deleted after a successful run, so `-resume` only helps
  for failed runs.
- No dedicated viewer for structural variants: the built-in variant browser
  assumes simple REF/ALT records and doesn't understand breakend/SVTYPE VCF
  notation. SV output is only reachable via the Files tab (download and view
  in IGV, bcftools, etc.), under `variants/sv/<caller>/` in the run's results.
- No dedicated viewer for RNA-seq output either, for the same reason: count
  matrices, GTFs, and DESeq2's PCA/heatmap PDFs are only reachable via the
  Files tab, not rendered in-app.
- Salmon's transcriptome index isn't decoy-aware (no full-genome decoy
  sequence) — a standard accuracy refinement, not required for correct
  operation, but a possible improvement.
- No differential expression for the long-read RNA-seq platforms (PacBio
  Iso-Seq, ONT) — isoform-level cross-sample comparison isn't as
  standardized as DESeq2 is for short-read gene counts, so both platforms
  stop at quantification.
- Pathogen surveillance is an MVP: only targeted influenza (Illumina) exists.
  No ONT/PacBio support yet despite ONT being the plan's stated priority
  platform. No Kraken2 taxonomic screening or host depletion — a sample is
  assumed to already be enriched for influenza, not raw metagenomic input.
  No Nextclade/UShER lineage placement. No POD5/Dorado basecalling ingest —
  FASTQ only. The risk-marker table has 4 markers (PB2 E627K/D701N, PA I38T,
  NA H275Y); the plan's broader "receptor-binding changes in HA" category
  isn't implemented. No dedicated viewer beyond the one generated HTML
  report per sample.
- Every surveillance report is a screening result, not a diagnosis — see the
  disclaimer rendered into each one. No CLIA/CAP pathway exists or is
  planned without a separate, deliberate validation and regulatory effort.
