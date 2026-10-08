process DESEQ2 {
    label 'process_medium'
    conda "bioconda::bioconductor-deseq2=1.50.2 bioconda::bioconductor-tximport=1.38.2"
    publishDir "${params.outdir}/differential_expression", mode: 'copy'

    input:
    path quant_dirs
    path samplesheet
    path tx2gene

    output:
    path "deseq2_results.csv", optional: true
    path "pca.pdf", optional: true
    path "sample_distance_heatmap.pdf", optional: true

    script:
    """
    run_deseq2.R ${samplesheet} ${tx2gene}
    """
}
