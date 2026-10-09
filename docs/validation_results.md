# Validation results

Real external-benchmark validation, run against the project plan's
performance targets (Oct 2026 merged plan). Three of the four targets that
map to pipelines which existed at the time are met. The pathogen
surveillance family (Phase 5) has since had its first real-data validation
too — see below.

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

Not yet done: Kraken2 taxonomic screening, host depletion, Nextclade/UShER
lineage placement, POD5/Dorado ingest, and the formal sensitivity/
specificity validation run against the plan's named datasets.

## Remaining listed targets

Not started: metagenomic/bacterial runtime, AMR gene concordance. Both
depend on the bacterial/AMR pipeline family (Phase 6 — Flye/metaFlye,
AMRFinderPlus, RGI, MOB-suite), which doesn't exist in this codebase yet.

## Reproducing this

- `scripts/make_ercc_test_data.py` — regenerates the ERCC synthetic dataset
  from `scripts/assets/ercc/` (checked in; see that directory's README for
  provenance).
- GIAB chr20 data was pulled live from NCBI/NHGRI's public FTP each time;
  no script is checked in for this one since it's mostly `curl`/`samtools`
  one-liners against stable public URLs (see this file's own commands
  above) rather than a generator worth maintaining as code.
