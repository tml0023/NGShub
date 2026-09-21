process BWA_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::bwa=0.7.19"
    storeDir "${params.reference_cache}/${fasta.baseName}"

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
    storeDir "${params.reference_cache}/${fasta.baseName}"

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
    storeDir "${params.reference_cache}/${fasta.baseName}"

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
