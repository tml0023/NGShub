process CLAIR3 {
    tag "${meta.id}"
    label 'process_high'
    container "hkubal/clair3:v2.0.3"
    publishDir "${params.outdir}/variants/clair3", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('clair3'), path("${meta.id}.clair3.vcf.gz"), path("${meta.id}.clair3.vcf.gz.tbi"), emit: vcf

    script:
    // r1041_e82_400bps_sup_v520 targets R10.4.1 flow cells basecalled with
    // Dorado's "super accuracy" model, the current standard ONT chemistry.
    // Older R9.4.1 runs need a different bundled model -- see ont_model.
    def model = params.ont_clair3_model ?: 'r1041_e82_400bps_sup_v520'
    """
    /opt/bin/run_clair3.sh \\
        --bam_fn=${bam} \\
        --ref_fn=${fasta} \\
        --threads=${task.cpus} \\
        --platform=ont \\
        --model_path=/opt/models/${model} \\
        --output=. \\
        ${params.clair3_args ?: ''}
    mv merge_output.vcf.gz ${meta.id}.clair3.vcf.gz
    mv merge_output.vcf.gz.tbi ${meta.id}.clair3.vcf.gz.tbi
    """
}

process DEEPVARIANT {
    tag "${meta.id}"
    label 'process_high'
    container "google/deepvariant:1.10.0"
    publishDir "${params.outdir}/variants/deepvariant", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('deepvariant'), path("*.vcf.gz"), path("*.vcf.gz.tbi"), emit: vcf
    path "*.g.vcf.gz", emit: gvcf

    script:
    def shards = params.deepvariant_num_shards ?: task.cpus
    """
    /opt/deepvariant/bin/run_deepvariant \\
        --model_type=ONT_R104 \\
        --ref=${fasta} \\
        --reads=${bam} \\
        --output_vcf=${meta.id}.deepvariant.vcf.gz \\
        --output_gvcf=${meta.id}.deepvariant.g.vcf.gz \\
        --num_shards=${shards} \\
        ${params.deepvariant_args ?: ''}
    """
}
