#!/usr/bin/env python3
"""Generate a synthetic dataset with a known deletion and insertion, for
validating structural-variant callers (Manta, Delly, pbsv, Sniffles2, cuteSV).

Builds one random reference + donor genome pair, then simulates reads for
all three platforms (Illumina paired-end, PacBio HiFi-like, ONT-like) from
the same donor, so every platform's SV callers can be checked against the
same ground truth.
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


def make_illumina_reads(donor, outdir, sample, coverage, read_length, insert_size, error_rate, rng):
    n_pairs = (len(donor) * coverage) // (2 * read_length)
    r1_path = outdir / f"{sample}_R1.fastq.gz"
    r2_path = outdir / f"{sample}_R2.fastq.gz"
    qual = "I" * read_length

    def seq_errors(seq):
        out = []
        for base in seq:
            if rng.random() < error_rate:
                out.append(rng.choice([b for b in BASES if b != base]))
            else:
                out.append(base)
        return "".join(out)

    with gzip.open(r1_path, "wt") as f1, gzip.open(r2_path, "wt") as f2:
        for i in range(n_pairs):
            fragment_len = max(2 * read_length, int(rng.gauss(insert_size, 40)))
            start = rng.randint(0, len(donor) - fragment_len)
            fragment = donor[start : start + fragment_len]
            read1 = seq_errors(fragment[:read_length])
            read2 = seq_errors(revcomp(fragment[-read_length:]))
            name = f"{sample}_read{i}"
            f1.write(f"@{name}/1\n{read1}\n+\n{qual}\n")
            f2.write(f"@{name}/2\n{read2}\n+\n{qual}\n")

    with open(outdir / "illumina_samplesheet.csv", "w") as fh:
        fh.write("sample,fastq_1,fastq_2\n")
        fh.write(f"{sample},{r1_path.resolve()},{r2_path.resolve()}\n")

    return n_pairs


def make_long_reads(donor, outdir, sample, platform, coverage, mean_len, sd_len, error_rate, rng):
    fastq_path = outdir / f"{platform}.fastq.gz"
    n_reads = (len(donor) * coverage) // mean_len

    def seq_errors(seq):
        out = []
        for base in seq:
            if rng.random() < error_rate:
                out.append(rng.choice([b for b in BASES if b != base]))
            else:
                out.append(base)
        return "".join(out)

    with gzip.open(fastq_path, "wt") as fh:
        for i in range(n_reads):
            read_len = max(1000, int(rng.gauss(mean_len, sd_len)))
            read_len = min(read_len, len(donor))
            start = rng.randint(0, len(donor) - read_len)
            read = seq_errors(donor[start : start + read_len])
            qual = "I" * len(read)
            fh.write(f"@{sample}_{platform}_read{i}\n{read}\n+\n{qual}\n")

    with open(outdir / f"{platform}_samplesheet.csv", "w") as fh:
        fh.write("sample,fastq\n")
        fh.write(f"{sample},{fastq_path.resolve()}\n")

    return n_reads


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="data/validate_sv")
    ap.add_argument("--length", type=int, default=400_000)
    ap.add_argument("--del-pos", type=int, default=100_000, help="0-based start of the deleted region")
    ap.add_argument("--del-len", type=int, default=500)
    ap.add_argument("--ins-pos", type=int, default=300_000, help="0-based insertion anchor")
    ap.add_argument("--ins-len", type=int, default=400)
    ap.add_argument("--sample", default="sample1")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    if not (args.ins_pos + args.ins_len < args.del_pos or args.del_pos + args.del_len < args.ins_pos):
        raise SystemExit("insertion and deletion regions must not overlap")

    rng = random.Random(args.seed)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    contig = "chrSV"

    reference = "".join(rng.choice(BASES) for _ in range(args.length))
    inserted_seq = "".join(rng.choice(BASES) for _ in range(args.ins_len))

    # Build the donor by walking events in reference-coordinate order, so this
    # works regardless of which event (insertion or deletion) comes first.
    events = sorted(
        [
            ("DEL", args.del_pos, args.del_len),
            ("INS", args.ins_pos, 0),
        ],
        key=lambda e: e[1],
    )
    donor_parts = []
    cursor = 0
    for kind, pos, length in events:
        donor_parts.append(reference[cursor:pos])
        if kind == "DEL":
            cursor = pos + length
        else:
            donor_parts.append(inserted_seq)
            cursor = pos
    donor_parts.append(reference[cursor:])
    donor = "".join(donor_parts)

    expected_len = args.length - args.del_len + args.ins_len
    assert len(donor) == expected_len, f"donor length {len(donor)} != expected {expected_len}"

    write_fasta(outdir / "reference.fa", contig, reference)

    with open(outdir / "truth_sv.tsv", "w") as fh:
        fh.write("type\tchrom\tpos\tend\tsvlen\n")
        # 1-based, anchored at the base before the event, as VCF SV convention expects.
        fh.write(f"INS\t{contig}\t{args.ins_pos}\t{args.ins_pos}\t{args.ins_len}\n")
        fh.write(f"DEL\t{contig}\t{args.del_pos}\t{args.del_pos + args.del_len}\t{-args.del_len}\n")

    n_pairs = make_illumina_reads(
        donor, outdir, args.sample, coverage=30, read_length=150, insert_size=350,
        error_rate=0.001, rng=rng,
    )
    n_pacbio = make_long_reads(
        donor, outdir, args.sample, "pacbio", coverage=20, mean_len=10_000, sd_len=2_000,
        error_rate=0.001, rng=rng,
    )
    n_ont = make_long_reads(
        donor, outdir, args.sample, "ont", coverage=20, mean_len=10_000, sd_len=3_000,
        error_rate=0.02, rng=rng,
    )

    print(f"reference      : {outdir / 'reference.fa'} ({args.length:,} bp)")
    print(f"truth SVs      : {outdir / 'truth_sv.tsv'} (1 insertion +{args.ins_len}bp, 1 deletion -{args.del_len}bp)")
    print(f"illumina reads : {n_pairs:,} pairs -> {outdir / 'illumina_samplesheet.csv'}")
    print(f"pacbio reads   : {n_pacbio:,} reads -> {outdir / 'pacbio_samplesheet.csv'}")
    print(f"ont reads      : {n_ont:,} reads -> {outdir / 'ont_samplesheet.csv'}")


if __name__ == "__main__":
    main()
