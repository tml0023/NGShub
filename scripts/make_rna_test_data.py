#!/usr/bin/env python3
"""Generate a tiny synthetic spliced-gene dataset for RNA-seq pipeline
smoke-testing: a genome with two 2-exon genes, a matching GTF, and reads
for all three platforms (Illumina paired-end, PacBio-style full-length
cDNA with primers/polyA, ONT-style full-length cDNA)."""
import argparse
import gzip
import random
from pathlib import Path

BASES = "ACGT"
COMPLEMENT = str.maketrans("ACGTN", "TGCAN")
NEB_5P = "GCAATGAAGTCGCAGGGTTGGG"
NEB_CLONTECH_3P = "GTACTCTGCGTTGATACCACTGCTT"


def revcomp(seq):
    return seq.translate(COMPLEMENT)[::-1]


def write_fasta(path, name, seq, width=60):
    with open(path, "w") as fh:
        fh.write(f">{name}\n")
        for i in range(0, len(seq), width):
            fh.write(seq[i : i + width] + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="data/validate_rna")
    ap.add_argument("--seed", type=int, default=11)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    contig = "chrR"
    length = 10_000

    genome = list("".join(rng.choice(BASES) for _ in range(length)))

    genes = {
        "geneA": {"tx": "geneA.1", "exons": [(1000, 1300), (1800, 2100)]},
        "geneB": {"tx": "geneB.1", "exons": [(5000, 5400), (5900, 6200)]},
    }

    # A uniformly random genome won't have canonical GT...AG splice-site
    # motifs at the intron boundaries, so aligners/classifiers (pigeon
    # included) correctly flag such a gene as non-canonical/novel rather
    # than a clean full-splice-match, even when every other property (exon
    # count, length, gene assignment) is exactly right. Force real motifs in.
    for info in genes.values():
        exons = info["exons"]
        for i in range(len(exons) - 1):
            intron_start, intron_end = exons[i][1], exons[i + 1][0]
            genome[intron_start : intron_start + 2] = list("GT")
            genome[intron_end - 2 : intron_end] = list("AG")

    def mature_mrna(exons):
        return "".join("".join(genome[s:e]) for s, e in exons)

    write_fasta(outdir / "reference.fa", contig, "".join(genome))

    with open(outdir / "annotation.gtf", "w") as fh:
        for gene_id, info in genes.items():
            exons = info["exons"]
            tx = info["tx"]
            gene_start, gene_end = exons[0][0] + 1, exons[-1][1]
            fh.write(
                f'{contig}\ttest\tgene\t{gene_start}\t{gene_end}\t.\t+\t.\t'
                f'gene_id "{gene_id}"; gene_name "{gene_id}";\n'
            )
            fh.write(
                f'{contig}\ttest\ttranscript\t{gene_start}\t{gene_end}\t.\t+\t.\t'
                f'gene_id "{gene_id}"; gene_name "{gene_id}"; transcript_id "{tx}";\n'
            )
            for s, e in exons:
                fh.write(
                    f'{contig}\ttest\texon\t{s + 1}\t{e}\t.\t+\t.\t'
                    f'gene_id "{gene_id}"; gene_name "{gene_id}"; transcript_id "{tx}";\n'
                )

    # ---- Illumina: paired-end reads sampled from the mature mRNA, 2
    # conditions x 2 replicates, geneA differentially expressed (high in
    # "treated", low in "control"), geneB constant as a non-DE control.
    read_len = 75
    illumina_dir = outdir / "illumina"
    illumina_dir.mkdir(exist_ok=True)
    samplesheet_rows = ["sample,fastq_1,fastq_2,condition"]

    conditions = {
        "control_1": {"geneA": 10, "geneB": 40},
        "control_2": {"geneA": 12, "geneB": 38},
        "treated_1": {"geneA": 80, "geneB": 42},
        "treated_2": {"geneA": 75, "geneB": 36},
    }
    for sample, coverage in conditions.items():
        r1_path = illumina_dir / f"{sample}_R1.fastq.gz"
        r2_path = illumina_dir / f"{sample}_R2.fastq.gz"
        qual = "I" * read_len
        with gzip.open(r1_path, "wt") as f1, gzip.open(r2_path, "wt") as f2:
            i = 0
            for gene_id, info in genes.items():
                mrna = mature_mrna(info["exons"])
                n_pairs = coverage[gene_id]
                for _ in range(n_pairs):
                    frag_len = min(len(mrna), max(2 * read_len, int(rng.gauss(180, 15))))
                    start = rng.randint(0, len(mrna) - frag_len)
                    fragment = mrna[start : start + frag_len]
                    read1 = fragment[:read_len]
                    read2 = revcomp(fragment[-read_len:])
                    name = f"{sample}_{gene_id}_read{i}"
                    f1.write(f"@{name}/1\n{read1}\n+\n{qual}\n")
                    f2.write(f"@{name}/2\n{read2}\n+\n{qual}\n")
                    i += 1
        condition = "treated" if sample.startswith("treated") else "control"
        samplesheet_rows.append(f"{sample},{r1_path.resolve()},{r2_path.resolve()},{condition}")

    (illumina_dir / "samplesheet.csv").write_text("\n".join(samplesheet_rows) + "\n")

    # ---- PacBio-style: full-length reads = primer + mRNA + polyA + primer,
    # one sample, moderate coverage per gene.
    pacbio_dir = outdir / "pacbio"
    pacbio_dir.mkdir(exist_ok=True)
    with gzip.open(pacbio_dir / "sample1.fastq.gz", "wt") as fh:
        i = 0
        for gene_id, info in genes.items():
            mrna = mature_mrna(info["exons"])
            # lima's --peek-guess needs >=100 reads sharing a primer
            # combination before it will commit to a call (GuessMinCount);
            # below that it stalls indefinitely rather than degrading
            # gracefully, so this must comfortably clear 100 total reads.
            for _ in range(75):
                read = NEB_5P + mrna + ("A" * 30) + revcomp(NEB_CLONTECH_3P)
                qual = "I" * len(read)
                fh.write(f"@pb_{gene_id}_read{i}\n{read}\n+\n{qual}\n")
                i += 1
    (pacbio_dir / "samplesheet.csv").write_text(
        f"sample,fastq\nsample1,{(pacbio_dir / 'sample1.fastq.gz').resolve()}\n"
    )

    # ---- ONT-style: full-length cDNA reads = just the mature mRNA (no
    # primers/polyA needed -- minimap2 splice alignment is what's under test).
    ont_dir = outdir / "ont"
    ont_dir.mkdir(exist_ok=True)
    with gzip.open(ont_dir / "sample1.fastq.gz", "wt") as fh:
        i = 0
        for gene_id, info in genes.items():
            mrna = mature_mrna(info["exons"])
            for _ in range(15):
                qual = "I" * len(mrna)
                fh.write(f"@ont_{gene_id}_read{i}\n{mrna}\n+\n{qual}\n")
                i += 1
    (ont_dir / "samplesheet.csv").write_text(
        f"sample,fastq\nsample1,{(ont_dir / 'sample1.fastq.gz').resolve()}\n"
    )

    print(f"reference  : {outdir / 'reference.fa'} ({length:,} bp, 2 genes)")
    print(f"annotation : {outdir / 'annotation.gtf'}")
    print(f"illumina   : {illumina_dir / 'samplesheet.csv'} (4 samples, 2 conditions)")
    print(f"pacbio     : {pacbio_dir / 'samplesheet.csv'}")
    print(f"ont        : {ont_dir / 'samplesheet.csv'}")


if __name__ == "__main__":
    main()
