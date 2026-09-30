// pbmarkdup works on raw reads before alignment (reference-free duplicate
// detection), unlike Illumina's position-based post-alignment dedup — so this
// runs between QC and alignment, not after it.
//
// Two behaviours verified against the tool itself, not its docs:
//  - Without --rmdup it only *marks* duplicates; a FASTQ has no flag for the
//    aligner to honor, so duplicates would flow straight through. --rmdup is
//    what makes this stage actually remove them.
//  - It writes plain-text FASTQ even when the output is named *.fq.gz or
//    *.fastq.gz, so the compression is done here rather than trusted.
process PBMARKDUP {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::pbmarkdup=1.2.0"
    container "quay.io/biocontainers/pbmarkdup:1.2.0--h9ee0642_0"
    publishDir "${params.outdir}/dedup/metrics", mode: 'copy', pattern: "*.log"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}.dedup.fastq.gz"), emit: reads
    path "*.log", emit: log

    script:
    """
    pbmarkdup --rmdup --log-level INFO --log-file ${meta.id}.pbmarkdup.log \\
        ${reads} ${meta.id}.dedup.fastq
    gzip -f ${meta.id}.dedup.fastq
    """
}
