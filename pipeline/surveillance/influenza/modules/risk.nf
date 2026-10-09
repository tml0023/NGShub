process RISK_SCORE {
    tag "${meta.id}"
    label 'process_low'
    conda "conda-forge::biopython=1.88"
    publishDir path: { "${params.outdir}/risk/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(segments)
    path marker_table
    path pb2_ref
    path pa_ref
    path na_n1_ref

    output:
    tuple val(meta), path("${meta.id}_risk.json"), emit: json
    tuple val(meta), path("${meta.id}_risk.tsv"), emit: tsv

    script:
    // IRMA names segments "A_PB2.fasta", "A_PA.fasta", "A_NA_<subtype>.fasta"
    // (subtype varies by sample, e.g. N1/N2) -- map to the gene names the
    // marker table and reference set use before invoking the checker.
    """
    seg_args=""
    for f in ${segments}; do
        case "\$f" in
            A_PB2*.fasta) seg_args="\${seg_args} --segment PB2=\$f" ;;
            A_PA*.fasta)  seg_args="\${seg_args} --segment PA=\$f" ;;
            A_NA_*.fasta) seg_args="\${seg_args} --segment NA=\$f" ;;
        esac
    done
    check_risk_markers.py ${marker_table} ${meta.id} \\
        --ref PB2=${pb2_ref} --ref PA=${pa_ref} --ref NA=${na_n1_ref} \\
        \${seg_args}
    """
}
