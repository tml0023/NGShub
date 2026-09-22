process GATK_BASERECALIBRATOR {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::gatk4=4.6.2.0"
    publishDir "${params.outdir}/alignment/bqsr", mode: 'copy', pattern: "*.table"

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai
    path dict
    path known_sites
    path known_sites_tbi

    output:
    tuple val(meta), path("${meta.id}.recal.table"), emit: table

    script:
    def known_args = known_sites.collect { path -> "--known-sites ${path}" }.join(' ')
    """
    gatk --java-options "-Xmx${task.memory.toGiga()}g" BaseRecalibrator \\
        --input ${bam} \\
        --reference ${fasta} \\
        ${known_args} \\
        --output ${meta.id}.recal.table
    """
}

process GATK_APPLYBQSR {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::gatk4=4.6.2.0"
    publishDir "${params.outdir}/alignment", mode: 'copy', pattern: "*.bam"

    input:
    tuple val(meta), path(bam), path(bai), path(table)
    path fasta
    path fai
    path dict

    output:
    tuple val(meta), path("${meta.id}.bqsr.bam"), emit: bam

    script:
    """
    gatk --java-options "-Xmx${task.memory.toGiga()}g" ApplyBQSR \\
        --input ${bam} \\
        --reference ${fasta} \\
        --bqsr-recal-file ${table} \\
        --output ${meta.id}.bqsr.bam
    """
}
