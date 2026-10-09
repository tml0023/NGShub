# Validation results

Real external-benchmark validation, run against the project plan's
performance targets (Oct 2026 merged plan). Three of the four targets that
map to pipelines which existed at the time are met. The pathogen
surveillance family (Phase 5) has since had its first real-data validation
too — on both Illumina and, as of this update, Oxford Nanopore — see below.

## GIAB concordance (SNP / indel), Illumina pipeline

**Met — SNP F1 = 99.29% (target ≥ 99%), indel F1 = 99.18% (target ≥ 95%)**

- **Truth set**: GIAB HG001/NA12878, NISTv4.2.1, GRCh38, chr20 only.
- **Reads**: Real HG001 Illumina HiSeq data, extracted via remote region
  query (`samtools view <region>`) from NHGRI's public 300x GRCh38 BAM, then
  subsampled to ~30x (`samtools view -s 42.1`) — standard WGS depth, not the
  raw 300x.
- **Reference**: chr20 slice of the app's bundled `hg38.fa`.
- **Pipeline**: `pipeline/main.nf` (Illumina), default tool choices —
  fastp → BWA-MEM2 → GATK MarkDuplicates → GATK HaplotypeCaller. No BQSR
  (the bundled known-sites VCFs are genome-wide; scoping them to a
  single-contig chr20 reference risks a sequence-dictionary mismatch, and
  BQSR isn't required for a baseline concordance benchmark).
- **Scoring**: `rtg vcfeval` (GA4GH-standard, the plan's own named
  alternative to hap.py), restricted to the high-confidence BED,
  `--squash-ploidy`.
- **Result**: 125,535 variants called; 78,680/78,680 truth variants
  compared, 681 false positives, 469 false negatives overall.
  SNP-only: precision 0.9908, sensitivity 0.9949, F1 0.9929.
  Indel-only: precision 0.9955, sensitivity 0.9883, F1 0.9918.

Chosen scope: chr20 only, not full-genome. GIAB's own validation guidance
treats a single chromosome as a legitimate quick-validation scope; full
hg38 needs a ~100GB+ FASTQ download and multi-hour runtime this machine
hasn't been tested against (see the runtime entry below).

## RNA-seq quantification accuracy vs ERCC spike-ins, Illumina RNA-seq

**Met — Spearman r = 0.9942 (target ≥ 0.95)**

- **Reference material**: NIST/Thermo Fisher's ERCC92 control sequences and
  their official Mix 1 molar-concentration table (`ERCCMix1and2` from NIST's
  `erccdashboard` package) — the actual external synthetic-RNA standard the
  field uses for this exact purpose, not an in-house stand-in.
- **Simulated reads**: paired-end reads sampled per ERCC transcript at depth
  proportional to (Mix 1 concentration × transcript length) — standard
  RNA-seq sequencing physics, so that Salmon's length-normalized TPM output
  is the correct quantity to correlate against molar concentration.
  400,000 read pairs total across 83/92 transcripts (9 lowest-concentration
  transcripts rounded to 0 simulated reads, consistent with real assay
  detection limits at that end of the ~10^6-fold concentration range).
- **Pipeline**: `pipeline/rna/illumina/main.nf`, default tool choices —
  Trim Galore → STAR (QC) → Salmon.
- **Result**: Spearman r = 0.9942 (p = 8.1e-89) between Salmon TPM and known
  Mix 1 concentration, across all 92 transcripts; 83/92 detected (TPM > 0).

## Full hg38 WGS runtime, Illumina, trim-align-call

**Not met as stated — chr20-scale data point only**

The GIAB validation run above gives real per-process timing on this
machine's default 6 CPU / 6 GB config, at chr20 scale (64 Mb, ~2.1% of the
genome):

| Stage | Wall time |
| --- | --- |
| fastp | 5m 17s |
| BWA-MEM2 index (chr20 only) | 1m 0s |
| BWA-MEM2 align | 14m 15s |
| GATK MarkDuplicates | 2m 35s |
| GATK HaplotypeCaller | 44m 13s |
| **Core trim→align→call total** | **~66m** |
| Full run incl. QC, reference prep, reporting | ~71m |

This is **not** extrapolated to a full-genome number. Runtime at this scale
doesn't scale linearly with genome size — index build, per-process
overhead, and I/O don't scale the same way variant-calling compute does —
and this machine's 6 GB default ceiling is already documented as
insufficient for full-genome BWA-MEM2/DragMap indexing (see the README).
A real full-hg38 number needs an actual full-genome run on adequate
hardware, which hasn't been done.

## Targeted influenza surveillance (Phase 5 MVP), first real-data run

**Not a completed target — a first correctness check on real data, not yet
the formal validation run the plan specifies (82-sample inoculation
dataset, then 100-200 runs from PRJNA1102327)**

- **Sample**: SRR40955955, real USDA-NVSL Illumina WGS of Influenza A, from
  the exact BioProject the plan names (PRJNA1102327), pulled live via
  `prefetch`/`fasterq-dump`. ~512K read pairs, no subsampling.
- **Pipeline**: `pipeline/surveillance/influenza/main.nf` — FastQC → IRMA
  (segment assembly + subtyping) → GenoFLU (genotype assignment) →
  rule-based risk-marker screen → plain-language HTML report.
- **Result**: IRMA correctly assembled all 8 segments and called the
  subtype **H5N1** (HA: H5, NA: N1). GenoFLU assigned genotype **B3.13** —
  the actual documented genotype of the 2024 US dairy cattle H5N1
  outbreak, and the specific genotype the plan itself names as a target
  ("check that cattle B3.13 and D1.1 samples land in the right clades").
  Risk screen: all 4 markers (PB2 E627K, PB2 D701N, PA I38T, NA H275Y)
  correctly read as wildtype — consistent with published reporting that
  this lineage is predominantly avian-adapted at these positions — giving
  an overall "low" risk call.
- **Negative control**: a synthetic 500-read-pair random-sequence sample
  produced zero assembled segments and correctly stopped there — no
  genotype, no risk score, no fabricated report. Confirms the pipeline
  doesn't manufacture a result when there's no real signal, though this is
  a synthetic negative, not the ZymoBIOMICS/CAMI benchmark the plan
  specifies for the real false-positive-rate target.
- **A correctness issue found and fixed along the way**: risk-marker amino
  acid positions can't be read off a raw translated open reading frame.
  IRMA's assembled segments include the vRNA UTRs, so position 1 isn't the
  CDS start, and naively picking "the first ATG that gives a long ORF"
  found the *wrong* start codon (10 residues downstream of the true one) —
  confirmed directly by comparing against a reference protein sequence.
  Fixed by aligning each segment's translation against a reference protein
  with known literature-standard numbering (BLOSUM62, global alignment)
  and reading marker positions off the alignment, not raw sequence offset.

Not yet done at the time: Kraken2 taxonomic screening, host depletion,
Nextclade/UShER lineage placement, POD5/Dorado ingest, and the formal
sensitivity/specificity validation run against the plan's named datasets.
Kraken2 taxonomic screening has since been added — see below.

## Targeted influenza surveillance, Oxford Nanopore MVP, first real-data run

**Not a completed target — a first correctness check on real data, same
caveat as the Illumina MVP above**

- **Sample**: SRR26182435, a real Oxford Nanopore MinION run from BioProject
  PRJNA1021187 (USDA's Exotic and Emerging Avian Viral Diseases Research
  Unit, U.S. National Poultry Research Center) — a genuine avian influenza
  field surveillance dataset, not the same BioProject as the Illumina run
  above but the same real-world category the plan targets. 175,692 single-end
  reads, mean length 338bp (consistent with amplicon-tiled or
  segment-targeted sequencing, not whole-genome shotgun), pulled live via
  `prefetch`/`fasterq-dump`.
- **Pipeline**: `pipeline/surveillance/influenza_ont/main.nf` — NanoPlot →
  `chopper` filtering → IRMA (`FLU-minion` config — IRMA's own MinION-tuned
  preset for the same FLU module used on Illumina, not a separate tool) →
  GenoFLU → the same risk-marker screen and report scripts as the Illumina
  pipeline, called directly from `pipeline/surveillance/influenza/bin/`
  rather than duplicated, since the marker table and reference proteins are
  literature-sourced and correctness-critical.
- **Result**: IRMA correctly assembled all 8 segments from real ONT reads and
  called subtype **H5N1** (HA: H5, NA: N1) — again landing on H5N1 by pure
  biological signal, not a coincidence of the test data. GenoFLU assigned
  genotype **A1** (wholly Eurasian avian lineage across all 8 segments,
  99.69–100% identity), distinct from the Illumina run's B3.13 — the correct,
  biologically sensible result for a wild/poultry avian-surveillance sample
  as opposed to the North American dairy-cattle outbreak lineage, and a
  useful sign the pipeline isn't just reproducing one memorized answer. Risk
  screen: all 4 markers correctly read as wildtype, giving a "low" risk call.
  Verified twice — once by running IRMA/GenoFLU/the risk script directly by
  hand, and once through the actual Nextflow pipeline end-to-end — with
  identical results both times.
- **Negative control**: the same synthetic random-sequence negative control
  used for the Illumina MVP, run through the ONT pipeline. IRMA correctly
  assembled zero segments; GenoFLU, the risk screen, and the report stage
  were all correctly skipped — only `NANOPLOT`, `IRMA_ASSEMBLE_ONT`, and
  `MULTIQC` ran, confirmed by inspecting the run's process list and result
  directory (no `genotype/`, `risk/`, or `report/` output at all).
- **A real bug found and fixed before it shipped**: the DNA ONT pipeline's
  `chopper` filtering step defaults to a 500bp minimum read length — correct
  for whole-genome shotgun long reads, but on this real amplicon-style
  influenza dataset (mean length 338bp) it would have discarded roughly 87%
  of reads (only ~12.5% of reads in SRR26182435 are ≥500bp; ~96% are
  ≥150bp) before IRMA ever saw them. Confirmed directly by computing the
  read-length distribution before wiring the pipeline up. Fixed with a
  pipeline-local `chopper` module (100bp floor — enough to strip genuinely
  unusable fragments without discarding the bulk of real reads) instead of
  reusing the DNA ONT pipeline's module, and a distinct parameter name
  (`influenza_chopper_min_length`) so it can't silently inherit the shared
  `nextflow.config`'s 500bp default for the other platform.

Not yet done at the time: the same list as the Illumina MVP (Kraken2, host
depletion, Nextclade/UShER, POD5/Dorado ingest, formal sensitivity/
specificity validation), plus PacBio support for this mode. Kraken2
taxonomic screening has since been added — see below.

## Taxonomic composition screening (Kraken2), both influenza platforms

**Not a completed target — a new diagnostic capability, correctly working,
but not the formal ZymoBIOMICS/CAMI false-positive-rate benchmark the plan
specifies**

- **What it is**: Kraken2 against the prebuilt "Viral" database (RefSeq
  viral, ~0.5 GB — not the full standard database, which is 100+ GB and
  impractical on a single dev machine). Runs on every sample unconditionally
  in both influenza pipelines, regardless of whether IRMA assembles
  anything, reporting percent unclassified and percent Influenza A virus
  (NCBI taxid 11320, confirmed present in this DB build's `inspect.txt`
  before relying on it). This screens composition *among viruses*, not true
  host-genome depletion — the viral DB has no host genomes in it.
- **Illumina negative control**: the same synthetic random-sequence negative
  control used for the IRMA validation above, run through the
  Kraken2-enabled pipeline. Result: 100% unclassified, 0% Influenza A —
  exactly the expected result for pure random sequence.
- **ONT real-data result** (SRR26182435, the same real H5N1 avian MinION
  sample validated above): **98.48% unclassified, 1.15% Influenza A virus**.
  This is itself informative, not just a sanity check: it confirms this is
  raw, unenriched whole-genome sequencing (not a targeted influenza
  amplicon library), with influenza present at low relative abundance in a
  mostly non-viral background — yet IRMA still correctly assembled all 8
  segments from that minority signal. A composition result like this is
  exactly the kind of context a pass/fail assembly outcome alone can't give:
  it tells a user *why* a borderline sample looks the way it does.
- **Both results verified by running the actual Nextflow pipelines
  end-to-end**, not a standalone Kraken2 invocation outside the app.
- **A real cross-platform gap caught during design, before any test ran**:
  the shared Kraken2 process picks single- vs paired-end CLI flags off
  `meta.single_end`. That key is only ever set by the Illumina influenza
  pipeline (the one pipeline that supports both read layouts); the ONT
  pipeline's samplesheet-parsing code, read directly rather than assumed,
  never set it at all. Left alone, `meta.single_end` would have been `null`
  for every ONT sample — and a naive `!meta.single_end` "is this paired"
  check would have evaluated `true` (Groovy's `null` is falsy, so its
  negation is `true`), silently treating single-end ONT reads as paired.
  Fixed by setting `single_end: true` explicitly in the ONT pipeline's
  metadata instead of relying on that inversion.

Not yet done: true host depletion (needs host reference genomes, not just
the viral DB), Nextclade/UShER lineage placement, POD5/Dorado ingest, and
the formal ZymoBIOMICS/CAMI false-positive-rate benchmark. The composition
result also isn't surfaced in the main HTML report yet — Files tab only
(`taxonomy/<sample>/`), consistent with this app's existing "no dedicated
viewer for X" pattern for other outputs.

## Remaining listed targets

Not started: metagenomic/bacterial runtime, AMR gene concordance. Both
depend on the bacterial/AMR pipeline family (Phase 7 — Flye/metaFlye,
AMRFinderPlus, RGI, MOB-suite), which doesn't exist in this codebase yet.

## Reproducing this

- `scripts/make_ercc_test_data.py` — regenerates the ERCC synthetic dataset
  from `scripts/assets/ercc/` (checked in; see that directory's README for
  provenance).
- GIAB chr20 data was pulled live from NCBI/NHGRI's public FTP each time;
  no script is checked in for this one since it's mostly `curl`/`samtools`
  one-liners against stable public URLs (see this file's own commands
  above) rather than a generator worth maintaining as code.
