process MINIMAP2_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::minimap2=2.31"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta

    output:
    path "${fasta.baseName}.ont.mmi"

    script:
    """
    minimap2 -x map-ont -d ${fasta.baseName}.ont.mmi ${fasta}
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
    minimap2 -a -x map-ont -t ${task.cpus} -R '${rg}' ${index} ${reads} \\
        | samtools sort -@ ${sort_cpus} -m 512M -o ${meta.id}.sorted.bam -
    """
}
