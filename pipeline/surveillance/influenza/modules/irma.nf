process IRMA_ASSEMBLE {
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
    // IRMA takes one or two FASTQ positionally depending on layout -- there's
    // no flag for it, the module reads the argument count itself.
    def reads_args = meta.single_end ? "${reads}" : "${reads[0]} ${reads[1]}"
    """
    IRMA FLU ${reads_args} ${meta.id}_irma
    """
}
