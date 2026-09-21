process SAMTOOLS_FAIDX {
    tag "${fasta.name}"
    label 'process_low'
    conda "bioconda::samtools=1.24"
    storeDir "${params.reference_cache}/${fasta.baseName}"

    input:
    path fasta

    output:
    path "${fasta.name}.fai"

    script:
    """
    samtools faidx ${fasta}
    """
}

// GATK accepts a samtools-generated sequence dictionary, which avoids pulling
// the (large) gatk4 environment for runs that use other callers.
process SAMTOOLS_DICT {
    tag "${fasta.name}"
    label 'process_low'
    conda "bioconda::samtools=1.24"
    storeDir "${params.reference_cache}/${fasta.baseName}"

    input:
    path fasta

    output:
    path "${fasta.baseName}.dict"

    script:
    """
    samtools dict ${fasta} --output ${fasta.baseName}.dict
    """
}
