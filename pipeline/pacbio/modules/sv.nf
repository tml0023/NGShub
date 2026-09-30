process PBSV_CALL {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::pbsv=2.2.2"
    // pbsv's bioconda package ships Linux-only ELF binaries, and its own
    // biocontainer doesn't bundle htslib -- bgzip/tabix run as a separate
    // conda-based step (PBSV_INDEX) that works natively on macOS.
    container "quay.io/biocontainers/pbsv:2.2.2--2"

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), path("${meta.id}.pbsv.vcf"), emit: vcf

    script:
    """
    pbsv discover ${bam} ${meta.id}.svsig.gz
    pbsv call --ccs -j ${task.cpus} ${fasta} ${meta.id}.svsig.gz ${meta.id}.pbsv.vcf
    """
}

process PBSV_INDEX {
    tag "${meta.id}"
    label 'process_low'
    conda "bioconda::htslib=1.24"
    publishDir "${params.outdir}/variants/sv/pbsv", mode: 'copy'

    input:
    tuple val(meta), path(vcf)

    output:
    tuple val(meta), val('pbsv'), path("${meta.id}.pbsv.vcf.gz"), path("${meta.id}.pbsv.vcf.gz.tbi"), emit: vcf

    script:
    """
    bgzip ${vcf}
    tabix -p vcf ${meta.id}.pbsv.vcf.gz
    """
}
