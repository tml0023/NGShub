process CUTESV {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::cutesv=2.1.4 bioconda::htslib=1.24"
    publishDir "${params.outdir}/variants/sv/cutesv", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('cutesv'), path("${meta.id}.cutesv.vcf.gz"), path("${meta.id}.cutesv.vcf.gz.tbi"), emit: vcf

    script:
    // ONT preset from cuteSV's own documented recommendations -- distinct
    // from its PacBio CLR/HiFi presets, tuned for ONT's higher indel error rate.
    """
    mkdir -p work
    cuteSV ${bam} ${fasta} ${meta.id}.cutesv.vcf work \\
        --threads ${task.cpus} \\
        --max_cluster_bias_INS 100 --diff_ratio_merging_INS 0.3 \\
        --max_cluster_bias_DEL 100 --diff_ratio_merging_DEL 0.3
    bgzip ${meta.id}.cutesv.vcf
    tabix -p vcf ${meta.id}.cutesv.vcf.gz
    """
}
