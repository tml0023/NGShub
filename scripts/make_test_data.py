#!/usr/bin/env python3
"""Generate a tiny synthetic Illumina dataset for pipeline validation.

Produces a small reference, a mutated donor genome with known SNVs, and
paired-end reads sampled from the donor, so pipeline output can be checked
against a truth set.
"""
import argparse
import gzip
import random
from pathlib import Path

BASES = "ACGT"
COMPLEMENT = str.maketrans("ACGTN", "TGCAN")


def revcomp(seq):
    return seq.translate(COMPLEMENT)[::-1]


def write_fasta(path, name, seq, width=60):
    with open(path, "w") as fh:
        fh.write(f">{name}\n")
        for i in range(0, len(seq), width):
            fh.write(seq[i : i + width] + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="data/test")
    ap.add_argument("--length", type=int, default=50_000)
    ap.add_argument("--coverage", type=int, default=30)
    ap.add_argument("--read-length", type=int, default=150)
    ap.add_argument("--insert-size", type=int, default=350)
    ap.add_argument("--num-variants", type=int, default=50)
    ap.add_argument("--error-rate", type=float, default=0.001)
    ap.add_argument("--sample", default="sample1")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    contig = "chrTest"

    reference = "".join(rng.choice(BASES) for _ in range(args.length))

    # Homozygous SNVs, spaced well apart and away from the contig edges.
    margin = args.insert_size * 2
    positions = sorted(
        rng.sample(range(margin, args.length - margin), args.num_variants)
    )
    donor = list(reference)
    truth = []
    for pos in positions:
        ref_base = reference[pos]
        alt_base = rng.choice([b for b in BASES if b != ref_base])
        donor[pos] = alt_base
        truth.append((pos + 1, ref_base, alt_base))  # VCF is 1-based
    donor = "".join(donor)

    write_fasta(outdir / "reference.fa", contig, reference)

    with open(outdir / "truth.vcf", "w") as fh:
        fh.write("##fileformat=VCFv4.2\n")
        fh.write(f"##contig=<ID={contig},length={args.length}>\n")
        fh.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n")
        for pos, ref_base, alt_base in truth:
            fh.write(f"{contig}\t{pos}\t.\t{ref_base}\t{alt_base}\t.\tPASS\t.\n")

    n_pairs = (args.length * args.coverage) // (2 * args.read_length)
    r1_path = outdir / f"{args.sample}_R1.fastq.gz"
    r2_path = outdir / f"{args.sample}_R2.fastq.gz"
    qual = "I" * args.read_length

    def sequencing_errors(seq):
        if args.error_rate <= 0:
            return seq
        out = []
        for base in seq:
            if rng.random() < args.error_rate:
                out.append(rng.choice([b for b in BASES if b != base]))
            else:
                out.append(base)
        return "".join(out)

    with gzip.open(r1_path, "wt") as f1, gzip.open(r2_path, "wt") as f2:
        for i in range(n_pairs):
            fragment_len = max(
                2 * args.read_length, int(rng.gauss(args.insert_size, 40))
            )
            start = rng.randint(0, len(donor) - fragment_len)
            fragment = donor[start : start + fragment_len]

            read1 = sequencing_errors(fragment[: args.read_length])
            read2 = sequencing_errors(revcomp(fragment[-args.read_length :]))

            name = f"{args.sample}_read{i}"
            f1.write(f"@{name}/1\n{read1}\n+\n{qual}\n")
            f2.write(f"@{name}/2\n{read2}\n+\n{qual}\n")

    with open(outdir / "samplesheet.csv", "w") as fh:
        fh.write("sample,fastq_1,fastq_2\n")
        fh.write(f"{args.sample},{r1_path.resolve()},{r2_path.resolve()}\n")

    print(f"reference   : {outdir / 'reference.fa'} ({args.length:,} bp)")
    print(f"truth VCF   : {outdir / 'truth.vcf'} ({len(truth)} SNVs)")
    print(f"reads       : {n_pairs:,} pairs @ {args.coverage}x")
    print(f"samplesheet : {outdir / 'samplesheet.csv'}")


if __name__ == "__main__":
    main()
