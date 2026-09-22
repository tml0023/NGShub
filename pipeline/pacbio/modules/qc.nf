process NANOPLOT {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::nanoplot=1.48.0"
    publishDir "${params.outdir}/qc/nanoplot", mode: 'copy'

    input:
    tuple val(meta), path(reads)

    output:
    path "${meta.id}", emit: report

    script:
    """
    NanoPlot --threads ${task.cpus} --fastq ${reads} --prefix "" --outdir ${meta.id}
    """
}
