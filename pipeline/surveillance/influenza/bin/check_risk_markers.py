#!/usr/bin/env python3
"""Risk scoring v1 (rule-based): check an IRMA-assembled influenza sample's
segments against a curated marker table of known mammalian-adaptation and
antiviral-resistance substitutions.

Numbering is alignment-based, not raw sequence position: IRMA's assembled
segment FASTAs include the vRNA UTRs, so the true CDS start isn't position 1
and can't be found reliably by just scanning for the first long open reading
frame (verified directly: PB2's first long-looking ORF from a naively-found
ATG turned out to start 10 residues after the real start codon). Each
segment's three forward reading frames are translated and aligned (global,
BLOSUM62) against a reference protein with known, literature-standard
numbering; the best-scoring frame's alignment is used to map each marker's
reference position to the sample's actual sequence.

Usage: check_risk_markers.py <marker_table.tsv> <output_prefix> \\
           --ref GENE=ref.fasta [--ref GENE=ref.fasta ...] \\
           --segment GENE=segment.fasta [--segment GENE=segment.fasta ...]
"""
import argparse
import csv
import json
import sys

from Bio import Align
from Bio.Align import substitution_matrices

CODON_TABLE = {
    'TTT': 'F', 'TTC': 'F', 'TTA': 'L', 'TTG': 'L', 'CTT': 'L', 'CTC': 'L', 'CTA': 'L', 'CTG': 'L',
    'ATT': 'I', 'ATC': 'I', 'ATA': 'I', 'ATG': 'M', 'GTT': 'V', 'GTC': 'V', 'GTA': 'V', 'GTG': 'V',
    'TCT': 'S', 'TCC': 'S', 'TCA': 'S', 'TCG': 'S', 'CCT': 'P', 'CCC': 'P', 'CCA': 'P', 'CCG': 'P',
    'ACT': 'T', 'ACC': 'T', 'ACA': 'T', 'ACG': 'T', 'GCT': 'A', 'GCC': 'A', 'GCA': 'A', 'GCG': 'A',
    'TAT': 'Y', 'TAC': 'Y', 'TAA': '*', 'TAG': '*', 'CAT': 'H', 'CAC': 'H', 'CAA': 'Q', 'CAG': 'Q',
    'AAT': 'N', 'AAC': 'N', 'AAA': 'K', 'AAG': 'K', 'GAT': 'D', 'GAC': 'D', 'GAA': 'E', 'GAG': 'E',
    'TGT': 'C', 'TGC': 'C', 'TGA': '*', 'TGG': 'W', 'CGT': 'R', 'CGC': 'R', 'CGA': 'R', 'CGG': 'R',
    'AGT': 'S', 'AGC': 'S', 'AGA': 'R', 'AGG': 'R', 'GGT': 'G', 'GGC': 'G', 'GGA': 'G', 'GGG': 'G',
}


def read_fasta(path):
    name, chunks = None, []
    seqs = {}
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


def first_seq(path):
    seqs = read_fasta(path)
    return next(iter(seqs.values()))


def translate_frame(nt_seq, frame):
    seq = nt_seq[frame:]
    aas = []
    for i in range(0, len(seq) - 2, 3):
        codon = seq[i:i + 3]
        aas.append(CODON_TABLE.get(codon, 'X'))
    # Stop codons mid-sequence just become 'X' for alignment purposes (a
    # wrong frame will be full of these and score poorly; the true CDS
    # frame should have none before its own natural stop, which we strip).
    return "".join('X' if a == '*' else a for a in aas)


def best_frame_alignment(nt_seq, ref_protein, aligner):
    best = None
    for frame in range(3):
        query = translate_frame(nt_seq, frame)
        if not query:
            continue
        aln = aligner.align(ref_protein, query)[0]
        if best is None or aln.score > best[0]:
            best = (aln.score, aln, frame)
    return best


def map_ref_to_query(alignment):
    """Reference (1-based) position -> query residue, or None if gapped."""
    ref_aligned, query_aligned = alignment[0], alignment[1]
    mapping = {}
    ref_pos = 0
    for r, q in zip(ref_aligned, query_aligned):
        if r != '-':
            ref_pos += 1
            mapping[ref_pos] = None if q == '-' else q
    return mapping


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("marker_table")
    ap.add_argument("output_prefix")
    ap.add_argument("--ref", action="append", default=[], help="GENE=ref_protein.fasta")
    ap.add_argument("--segment", action="append", default=[], help="GENE=irma_segment.fasta")
    args = ap.parse_args()

    refs = {k: first_seq(v) for k, v in (kv.split("=", 1) for kv in args.ref)}
    segments = {k: first_seq(v) for k, v in (kv.split("=", 1) for kv in args.segment)}

    markers = []
    with open(args.marker_table) as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            markers.append(row)

    aligner = Align.PairwiseAligner()
    aligner.substitution_matrix = substitution_matrices.load("BLOSUM62")
    aligner.open_gap_score = -10
    aligner.extend_gap_score = -0.5
    aligner.mode = "global"

    results = []
    genes_checked = {}
    for gene in {m["gene"] for m in markers}:
        if gene not in segments:
            genes_checked[gene] = "segment not assembled"
            continue
        if gene not in refs:
            genes_checked[gene] = "no reference available"
            continue
        best = best_frame_alignment(segments[gene], refs[gene], aligner)
        if best is None:
            genes_checked[gene] = "translation failed"
            continue
        _score, alignment, frame = best
        genes_checked[gene] = f"aligned (frame {frame})"
        pos_map = map_ref_to_query(alignment)
        for m in [m for m in markers if m["gene"] == gene]:
            ref_pos = int(m["ref_position"])
            observed = pos_map.get(ref_pos)
            if observed is None:
                status = "not_covered"
                flagged = False
            elif observed == m["mutant_aa"]:
                status = "mutant"
                flagged = True
            elif observed == m["wildtype_aa"]:
                status = "wildtype"
                flagged = False
            else:
                status = "other"
                flagged = False
            results.append({
                **m,
                "observed_aa": observed or "-",
                "status": status,
                "flagged": flagged,
            })

    n_flagged = sum(1 for r in results if r["flagged"])
    if any(r["status"] == "not_covered" for r in results) and n_flagged == 0:
        risk_level = "unknown"
    elif n_flagged == 0:
        risk_level = "low"
    elif n_flagged == 1:
        risk_level = "moderate"
    else:
        risk_level = "high"

    report = {
        "risk_level": risk_level,
        "flagged_markers": n_flagged,
        "total_markers": len(results),
        "genes_checked": genes_checked,
        "markers": results,
    }

    with open(f"{args.output_prefix}_risk.json", "w") as fh:
        json.dump(report, fh, indent=2)

    with open(f"{args.output_prefix}_risk.tsv", "w") as fh:
        fh.write("gene\tname\tref_position\twildtype_aa\tmutant_aa\tobserved_aa\tstatus\tflagged\tcategory\tsignificance\tcitation\n")
        for r in results:
            fh.write("\t".join([
                r["gene"], r["name"], r["ref_position"], r["wildtype_aa"], r["mutant_aa"],
                r["observed_aa"], r["status"], str(r["flagged"]), r["category"],
                r["significance"], r["citation"],
            ]) + "\n")

    print(f"risk level: {risk_level} ({n_flagged}/{len(results)} markers flagged)", file=sys.stderr)
    for gene, status in genes_checked.items():
        print(f"  {gene}: {status}", file=sys.stderr)


if __name__ == "__main__":
    main()
