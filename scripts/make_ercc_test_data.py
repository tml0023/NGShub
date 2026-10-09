#!/usr/bin/env python3
"""Simulate paired-end reads from the 92 ERCC spike-in sequences, at read
depth proportional to each transcript's known Mix 1 molar concentration
times its length (standard RNA-seq sequencing physics: a longer transcript
at the same molar concentration contributes proportionally more reads).
Salmon's length-normalized TPM output should then correlate with the known
input concentrations -- this is what validates quantification accuracy."""
import argparse
import gzip
import random
from pathlib import Path

COMPLEMENT = str.maketrans("ACGTN", "TGCAN")


def revcomp(seq):
    return seq.translate(COMPLEMENT)[::-1]


def read_fasta(path):
    seqs = {}
    name = None
    chunks = []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if name:
                    seqs[name] = "".join(chunks)
                name = line[1:].split()[0]
                chunks = []
            else:
                chunks.append(line)
    if name:
        seqs[name] = "".join(chunks)
    return seqs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fasta", default="scripts/assets/ercc/ERCC92.fa")
    ap.add_argument("--conc", default="scripts/assets/ercc/ERCC_Controls_Analysis.txt")
    ap.add_argument("--outdir", default="data/validate_ercc")
    ap.add_argument("--read-length", type=int, default=75)
    ap.add_argument("--total-reads", type=int, default=400_000)
    ap.add_argument("--error-rate", type=float, default=0.002)
    ap.add_argument("--seed", type=int, default=17)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    seqs = read_fasta(args.fasta)

    conc = {}
    with open(args.conc) as fh:
        header = fh.readline().strip().split("\t")
        idx = {name: i for i, name in enumerate(header)}
        for line in fh:
            row = line.rstrip("\n").split("\t")
            ercc_id = row[idx["ERCC.AMB.Expected"]]
            mix1 = float(row[idx["Mix1Conc.Attomoles_ul"]])
            if ercc_id in seqs and mix1 > 0:
                conc[ercc_id] = mix1

    # weight = concentration * length (molecules present * reads/molecule
    # a sequencer would produce for that length), then distributed over the
    # requested total read budget.
    weights = {eid: conc[eid] * len(seqs[eid]) for eid in conc}
    total_weight = sum(weights.values())

    read_counts = {}
    for eid, w in weights.items():
        n = round(args.total_reads * w / total_weight)
        if n > 0:
            read_counts[eid] = n

    def seq_errors(seq):
        out = []
        for base in seq:
            if rng.random() < args.error_rate:
                out.append(rng.choice([b for b in "ACGT" if b != base]))
            else:
                out.append(base)
        return "".join(out)

    r1_path = outdir / "ercc_R1.fastq.gz"
    r2_path = outdir / "ercc_R2.fastq.gz"
    qual = "I" * args.read_length

    with gzip.open(r1_path, "wt") as f1, gzip.open(r2_path, "wt") as f2:
        read_idx = 0
        for eid, n in sorted(read_counts.items()):
            seq = seqs[eid]
            for _ in range(n):
                if len(seq) <= args.read_length:
                    frag = seq
                else:
                    start = rng.randint(0, len(seq) - args.read_length)
                    frag = seq[start:]
                r1 = seq_errors(frag[: args.read_length].ljust(args.read_length, "A"))
                r2 = seq_errors(revcomp(frag)[: args.read_length].ljust(args.read_length, "A"))
                name = f"{eid}_{read_idx}"
                f1.write(f"@{name}/1\n{r1}\n+\n{qual}\n")
                f2.write(f"@{name}/2\n{r2}\n+\n{qual}\n")
                read_idx += 1

    (outdir / "truth_concentrations.tsv").write_text(
        "ercc_id\tmix1_attomoles_ul\tlength\tsimulated_reads\n"
        + "\n".join(
            f"{eid}\t{conc[eid]}\t{len(seqs[eid])}\t{read_counts.get(eid, 0)}"
            for eid in sorted(conc)
        )
        + "\n"
    )
    (outdir / "ercc_samplesheet.csv").write_text(
        f"sample,fastq_1,fastq_2\nercc_mix1,{r1_path.resolve()},{r2_path.resolve()}\n"
    )

    print(f"transcripts with reads: {len(read_counts)} / {len(conc)}")
    print(f"total reads           : {sum(read_counts.values()):,} pairs")
    print(f"truth table           : {outdir / 'truth_concentrations.tsv'}")
    print(f"samplesheet           : {outdir / 'ercc_samplesheet.csv'}")


if __name__ == "__main__":
    main()
