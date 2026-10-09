// FLU-minion is IRMA's own MinION-tuned config for the FLU module (lower
// base quality thresholds, BLAT-based alignment) -- not a separate tool,
// just a different preset of the same assembler used by the Illumina
// influenza pipeline. Output layout is identical (per-segment FASTAs named
// e.g. A_PB2.fasta directly in the output dir root), so GenoFLU, the risk
// screen, and the report stage are unchanged from the Illumina version.
process IRMA_ASSEMBLE_ONT {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::irma=1.4.0"
    publishDir path: { "${params.outdir}/assembly/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}_irma/*.fasta"), emit: segments, optional: true
    tuple val(meta), path("${meta.id}_irma/tables/READ_COUNTS.txt"), emit: read_counts, optional: true
    path "${meta.id}_irma", emit: full_output

    script:
    """
    IRMA FLU-minion ${reads} ${meta.id}_irma
    """
}
