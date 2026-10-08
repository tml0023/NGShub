#!/usr/bin/env python3
"""Extract a transcript_id -> gene_id mapping from a GTF, for tximport."""
import re
import sys


def main():
    gtf_path, out_path = sys.argv[1], sys.argv[2]
    with open(gtf_path) as src, open(out_path, "w") as dst:
        for line in src:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9 or fields[2] != "transcript":
                continue
            attrs = fields[8]
            tx = re.search(r'transcript_id "([^"]+)"', attrs)
            gene = re.search(r'gene_id "([^"]+)"', attrs)
            if tx and gene:
                dst.write(f"{tx.group(1)}\t{gene.group(1)}\n")


if __name__ == "__main__":
    main()
