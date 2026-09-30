process PBMM2_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::pbmm2=1.7.0"
    storeDir "${params.reference_cache}/${fasta.baseName}"

    input:
    path fasta

    output:
    path "${fasta.baseName}.mmi"

    script:
    """
    pbmm2 index --preset HIFI ${fasta} ${fasta.baseName}.mmi
    """
}

process PBMM2_ALIGN {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::pbmm2=1.7.0"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    def rg = "@RG\\tID:${meta.id}\\tSM:${meta.id}"
    """
    pbmm2 align --preset HIFI --sort -j ${task.cpus} \\
        --rg '${rg}' \\
        ${index} ${reads} ${meta.id}.sorted.bam
    """
}

process MINIMAP2_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::minimap2=2.31"
    storeDir "${params.reference_cache}/${fasta.baseName}"

    input:
    path fasta

    output:
    path "${fasta.baseName}.hifi.mmi"

    script:
    // minimap2 indices are preset-specific -- suffixed so this doesn't collide
    // with the ONT pipeline's map-ont index for the same reference, which is
    // cached in the same directory.
    """
    minimap2 -x map-hifi -d ${fasta.baseName}.hifi.mmi ${fasta}
    """
}

process MINIMAP2_ALIGN {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::minimap2=2.31 bioconda::samtools=1.24"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    def rg = "@RG\\tID:${meta.id}\\tSM:${meta.id}"
    def sort_cpus = Math.max(1, (task.cpus as int).intdiv(2))
    """
    minimap2 -a -x map-hifi -t ${task.cpus} -R '${rg}' ${index} ${reads} \\
        | samtools sort -@ ${sort_cpus} -m 512M -o ${meta.id}.sorted.bam -
    """
}
