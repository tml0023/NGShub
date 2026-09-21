#!/usr/bin/env python3
"""Compare a called VCF against the synthetic truth set from make_test_data.py.

Callers legitimately disagree on representation: FreeBayes in particular emits
multi-nucleotide haplotype alleles (CAGAT->CAGAC) where bcftools and GATK emit
the equivalent single SNV. Comparing raw POS/REF/ALT would score those as both
a false positive and a false negative, so MNPs are decomposed before matching.
"""
import argparse
import gzip
import sys
from pathlib import Path


def decompose(pos: int, ref: str, alt: str):
    """Split an equal-length multi-nucleotide allele into per-base SNVs."""
    if len(ref) == len(alt) and len(ref) > 1:
        for offset, (ref_base, alt_base) in enumerate(zip(ref, alt)):
            if ref_base != alt_base:
                yield pos + offset, ref_base, alt_base
    else:
        yield pos, ref, alt


def load(path: Path, min_qual: float = 0.0) -> dict:
    opener = gzip.open if path.suffix == ".gz" else open
    variants = {}
    with opener(path, "rt", errors="replace") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 6:
                continue
            qual = fields[5]
            if qual not in (".", "") and float(qual) < min_qual:
                continue
            for alt in fields[4].split(","):
                for pos, ref_base, alt_base in decompose(
                    int(fields[1]), fields[3], alt
                ):
                    variants[(fields[0], pos)] = (ref_base, alt_base)
    return variants


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("truth")
    parser.add_argument("called")
    parser.add_argument("--label", default="")
    parser.add_argument(
        "--min-qual",
        type=float,
        default=20.0,
        help="drop calls below this QUAL (FreeBayes emits QUAL=0 candidates)",
    )
    parser.add_argument("--min-recall", type=float, default=0.95)
    parser.add_argument("--min-precision", type=float, default=0.95)
    args = parser.parse_args()

    truth = load(Path(args.truth))
    called = load(Path(args.called), min_qual=args.min_qual)

    matched = {k for k in truth if k in called and called[k] == truth[k]}
    recall = len(matched) / len(truth) if truth else 0.0
    precision = len(matched) / len(called) if called else 0.0

    ok = recall >= args.min_recall and precision >= args.min_precision
    print(
        f"{'PASS' if ok else 'FAIL'}  {args.label:<48}"
        f" truth={len(truth):>4} called={len(called):>4}"
        f" recall={recall:.3f} precision={precision:.3f}"
    )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
