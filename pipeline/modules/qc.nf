process FASTQC {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::fastqc=0.12.1"
    publishDir path: { "${params.outdir}/qc/fastqc_${stage}" }, mode: 'copy'

    input:
    tuple val(meta), path(reads, stageAs: 'input/*')
    val stage

    output:
    path "*.zip", emit: zip
    path "*.html", emit: html

    script:
    // FastQC names its output after the input file, so reads are symlinked to
    // sample- and stage-qualified names. Without this, two samples whose FASTQ
    // files share a basename collide when MultiQC gathers the reports.
    """
    mkdir -p renamed
    i=1
    for f in input/*; do
        base=\$(basename "\$f")
        ln -s "\$PWD/\$f" "renamed/${meta.id}_${stage}_R\${i}.\${base#*.}"
        i=\$((i + 1))
    done

    fastqc --threads ${task.cpus} --quiet --outdir . renamed/*
    """
}

process MULTIQC {
    label 'process_low'
    conda "bioconda::multiqc=1.35"
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    path '*'

    output:
    path "multiqc_report.html", emit: report
    path "multiqc_report_data", emit: data

    script:
    """
    multiqc --force --filename multiqc_report.html .
    """
}
