process SAMTOOLS_INDEX {
    tag "${meta.id}"
    label 'process_low'
    conda "bioconda::samtools=1.24"
    publishDir "${params.outdir}/alignment", mode: 'copy'

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path(bam), path("*.bai"), emit: bam

    script:
    """
    samtools index -@ ${task.cpus} ${bam}
    """
}

process SAMTOOLS_STATS {
    tag "${meta.id}"
    label 'process_low'
    conda "bioconda::samtools=1.24"
    publishDir "${params.outdir}/alignment/stats", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    path "*.{stats,flagstat}", emit: stats

    script:
    """
    samtools stats -@ ${task.cpus} ${bam} > ${meta.id}.stats
    samtools flagstat -@ ${task.cpus} ${bam} > ${meta.id}.flagstat
    """
}
