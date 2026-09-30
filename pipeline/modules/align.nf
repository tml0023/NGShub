process BWA_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::bwa=0.7.19"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta

    output:
    path "bwa"

    script:
    """
    mkdir -p bwa
    bwa index -p bwa/${fasta.baseName} ${fasta}
    """
}

process BWAMEM2_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::bwa-mem2=2.3"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta

    output:
    path "bwamem2"

    script:
    """
    mkdir -p bwamem2
    bwa-mem2 index -p bwamem2/${fasta.baseName} ${fasta}
    """
}

process BOWTIE2_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::bowtie2=2.5.5"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta

    output:
    path "bowtie2"

    script:
    """
    mkdir -p bowtie2
    bowtie2-build --threads ${task.cpus} ${fasta} bowtie2/${fasta.baseName}
    """
}

process BWA_MEM {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::bwa=0.7.19 bioconda::samtools=1.24"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    def rg = "@RG\\tID:${meta.id}\\tSM:${meta.id}\\tPL:ILLUMINA\\tLB:${meta.id}"
    def sort_cpus = Math.max(1, (task.cpus as int).intdiv(2))
    """
    INDEX=\$(find -L ${index} -name "*.amb" | head -n1 | sed 's/\\.amb\$//')
    bwa mem -t ${task.cpus} -R '${rg}' \$INDEX ${reads} \\
        | samtools sort -@ ${sort_cpus} -m 512M -o ${meta.id}.sorted.bam -
    """
}

process BWAMEM2_MEM {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::bwa-mem2=2.3 bioconda::samtools=1.24"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    def rg = "@RG\\tID:${meta.id}\\tSM:${meta.id}\\tPL:ILLUMINA\\tLB:${meta.id}"
    def sort_cpus = Math.max(1, (task.cpus as int).intdiv(2))
    """
    INDEX=\$(find -L ${index} -name "*.amb" | head -n1 | sed 's/\\.amb\$//')
    bwa-mem2 mem -t ${task.cpus} -R '${rg}' \$INDEX ${reads} \\
        | samtools sort -@ ${sort_cpus} -m 512M -o ${meta.id}.sorted.bam -
    """
}

process BOWTIE2_ALIGN {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::bowtie2=2.5.5 bioconda::samtools=1.24"
    publishDir "${params.outdir}/alignment/logs", mode: 'copy', pattern: "*.log"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam
    path "*.log", emit: log

    script:
    def reads_arg = meta.single_end ? "-U ${reads[0]}" : "-1 ${reads[0]} -2 ${reads[1]}"
    def sort_cpus = Math.max(1, (task.cpus as int).intdiv(2))
    """
    INDEX=\$(find -L ${index} -name "*.rev.1.bt2" | head -n1 | sed 's/\\.rev\\.1\\.bt2\$//')
    bowtie2 \\
        --threads ${task.cpus} \\
        --rg-id ${meta.id} --rg SM:${meta.id} --rg PL:ILLUMINA --rg LB:${meta.id} \\
        -x \$INDEX ${reads_arg} \\
        2> ${meta.id}.bowtie2.log \\
        | samtools sort -@ ${sort_cpus} -m 512M -o ${meta.id}.sorted.bam -
    """
}

process DRAGMAP_HASHTABLE {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::dragmap=1.3.0"
    container "quay.io/biocontainers/dragmap:1.3.0--h5ca1c30_7"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta

    output:
    path "dragmap"

    script:
    """
    mkdir dragmap
    dragen-os \\
        --build-hash-table true \\
        --ht-reference ${fasta} \\
        --output-directory dragmap \\
        --ht-num-threads ${task.cpus}
    """
}

process DRAGMAP_ALIGN {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::dragmap=1.3.0 bioconda::samtools=1.24"
    // dragmap's own biocontainer doesn't bundle samtools (needed for the sort
    // this process pipes into), so use the same mulled dragmap+samtools image
    // nf-core's DRAGMAP_ALIGN module uses.
    container "quay.io/biocontainers/mulled-v2-580d344d9d4a496cd403932da8765f9e0187774d:df80ed8d23d0a2c43181a2b3dd1b39f2d00fab5c-0"

    input:
    tuple val(meta), path(reads)
    path hashtable

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    def reads_arg = meta.single_end ? "-1 ${reads[0]}" : "-1 ${reads[0]} -2 ${reads[1]}"
    def sort_cpus = Math.max(1, (task.cpus as int).intdiv(2))
    """
    dragen-os \\
        -r ${hashtable} \\
        --num-threads ${task.cpus} \\
        --RGID ${meta.id} \\
        --RGSM ${meta.id} \\
        ${reads_arg} \\
        2> ${meta.id}.dragmap.log \\
        | samtools sort -@ ${sort_cpus} -m 512M -o ${meta.id}.sorted.bam -
    """
}
