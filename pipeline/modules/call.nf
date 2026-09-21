process GATK_HAPLOTYPECALLER {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::gatk4=4.6.2.0"
    publishDir "${params.outdir}/variants/haplotypecaller", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai
    path dict

    output:
    tuple val(meta), val('haplotypecaller'), path("*.vcf.gz"), path("*.vcf.gz.tbi"), emit: vcf

    script:
    """
    gatk --java-options "-Xmx${task.memory.toGiga()}g" HaplotypeCaller \\
        --reference ${fasta} \\
        --input ${bam} \\
        --output ${meta.id}.haplotypecaller.vcf.gz \\
        --native-pair-hmm-threads ${task.cpus} \\
        ${params.haplotypecaller_args ?: ''}
    """
}

process BCFTOOLS_CALL {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::bcftools=1.24"
    publishDir "${params.outdir}/variants/bcftools", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('bcftools'), path("*.vcf.gz"), path("*.vcf.gz.tbi"), emit: vcf

    script:
    """
    bcftools mpileup \\
        --fasta-ref ${fasta} \\
        --threads ${task.cpus} \\
        --annotate FORMAT/AD,FORMAT/DP \\
        --output-type u ${bam} \\
        | bcftools call --multiallelic-caller --variants-only \\
            --threads ${task.cpus} \\
            --output-type z --output ${meta.id}.bcftools.vcf.gz \\
            ${params.bcftools_args ?: ''}
    bcftools index --tbi ${meta.id}.bcftools.vcf.gz
    """
}

process FREEBAYES {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::freebayes=1.3.10 bioconda::bcftools=1.24"
    publishDir "${params.outdir}/variants/freebayes", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('freebayes'), path("*.vcf.gz"), path("*.vcf.gz.tbi"), emit: vcf

    script:
    """
    freebayes --fasta-reference ${fasta} ${params.freebayes_args ?: ''} ${bam} > raw.vcf
    bcftools sort --output-type z --output ${meta.id}.freebayes.vcf.gz raw.vcf
    bcftools index --tbi ${meta.id}.freebayes.vcf.gz
    rm -f raw.vcf
    """
}

process BCFTOOLS_STATS {
    tag "${meta.id}:${caller}"
    label 'process_low'
    conda "bioconda::bcftools=1.24"
    publishDir "${params.outdir}/variants/stats", mode: 'copy'

    input:
    tuple val(meta), val(caller), path(vcf), path(tbi)

    output:
    path "*.bcftools_stats.txt", emit: stats

    script:
    """
    bcftools stats ${vcf} > ${meta.id}.${caller}.bcftools_stats.txt
    """
}
