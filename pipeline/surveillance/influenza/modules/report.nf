process SURVEILLANCE_REPORT {
    tag "${meta.id}"
    label 'process_low'
    conda "conda-forge::python=3.11"
    publishDir path: { "${params.outdir}/report/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(genotype_tsv), path(risk_json)

    output:
    tuple val(meta), path("${meta.id}_report.html"), emit: html

    script:
    """
    build_surveillance_report.py ${meta.id} ${genotype_tsv} ${risk_json} ${meta.id}_report.html
    """
}
