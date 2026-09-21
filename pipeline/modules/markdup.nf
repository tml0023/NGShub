process GATK_MARKDUPLICATES {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::gatk4=4.6.2.0"
    publishDir "${params.outdir}/alignment/metrics", mode: 'copy', pattern: "*.metrics.txt"

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.markdup.bam"), emit: bam
    path "*.metrics.txt", emit: metrics

    script:
    """
    gatk --java-options "-Xmx${task.memory.toGiga()}g" MarkDuplicates \\
        --INPUT ${bam} \\
        --OUTPUT ${meta.id}.markdup.bam \\
        --METRICS_FILE ${meta.id}.markdup.metrics.txt \\
        --VALIDATION_STRINGENCY LENIENT \\
        --TMP_DIR .
    """
}

process SAMTOOLS_MARKDUP {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::samtools=1.24"
    publishDir "${params.outdir}/alignment/metrics", mode: 'copy', pattern: "*.metrics.txt"

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.markdup.bam"), emit: bam
    path "*.metrics.txt", emit: metrics

    script:
    """
    samtools sort -n -@ ${task.cpus} -m 512M -o namesorted.bam ${bam}
    samtools fixmate -m -@ ${task.cpus} namesorted.bam fixmate.bam
    samtools sort -@ ${task.cpus} -m 512M -o positionsorted.bam fixmate.bam
    samtools markdup -@ ${task.cpus} -f ${meta.id}.markdup.metrics.txt \\
        positionsorted.bam ${meta.id}.markdup.bam
    rm -f namesorted.bam fixmate.bam positionsorted.bam
    """
}

process PUBLISH_BAM {
    tag "${meta.id}"
    label 'process_low'

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.bam"), emit: bam

    script:
    """
    cp ${bam} ${meta.id}.bam
    """
}
