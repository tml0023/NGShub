#!/usr/bin/env python3
"""Build a PacBio-style unaligned BAM from FASTQ, with the per-read CCS tags
(qs/qe/zm/np/rq/ec) lima/isoseq actually need.

A plain `samtools import`, even with a correct @RG DS:READTYPE=CCS header,
leaves lima stuck in an internal futex wait forever instead of erroring --
confirmed by direct trace: it opens its output files but never progresses,
regardless of thread count or --peek-guess. Adding these per-read tags (all
present on every real PacBio BAM, absent from a generic import) is what
actually unblocks it."""
import gzip
import sys

import pysam


def main():
    fastq_path, bam_path, sample = sys.argv[1], sys.argv[2], sys.argv[3]

    header = {
        "HD": {"VN": "1.6", "SO": "unknown", "pb": "3.0.1"},
        "RG": [{
            "ID": sample,
            "PL": "PACBIO",
            "DS": "READTYPE=CCS;BINDINGKIT=100-236-500;SEQUENCINGKIT=001-558-034;"
                  "BASECALLERVERSION=5.0.0;FRAMERATEHZ=100",
            "SM": sample,
        }],
    }

    opener = gzip.open if fastq_path.endswith(".gz") else open
    with pysam.AlignmentFile(bam_path, "wb", header=header) as out, \
            opener(fastq_path, "rt") as fh:
        zm = 0
        while True:
            name = fh.readline().rstrip("\n")
            if not name:
                break
            seq = fh.readline().rstrip("\n")
            fh.readline()  # '+'
            qual = fh.readline().rstrip("\n")

            a = pysam.AlignedSegment()
            a.query_name = name[1:].split()[0]
            a.query_sequence = seq
            a.query_qualities = pysam.qualitystring_to_array(qual)
            a.flag = 4
            a.set_tag("RG", sample, value_type="Z")
            a.set_tag("qs", 0, value_type="i")
            a.set_tag("qe", len(seq), value_type="i")
            a.set_tag("zm", zm, value_type="i")
            a.set_tag("np", 10, value_type="i")
            a.set_tag("rq", 0.999, value_type="f")
            a.set_tag("ec", 10.0, value_type="f")
            out.write(a)
            zm += 1


if __name__ == "__main__":
    main()
