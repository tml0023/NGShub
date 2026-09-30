// Unlike PacBio HiFi (already ~99.9% accurate CCS consensus), raw Oxford
// Nanopore reads benefit from quality/length filtering before alignment --
// this is chopper, the actively-maintained successor to NanoFilt.
process CHOPPER {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::chopper=0.14.1"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}.filtered.fastq.gz"), emit: reads

    script:
    def min_qual = params.chopper_min_quality ?: 10
    def min_length = params.chopper_min_length ?: 500
    """
    gunzip -c ${reads} | chopper -q ${min_qual} -l ${min_length} --threads ${task.cpus} \\
        | gzip > ${meta.id}.filtered.fastq.gz
    """
}
