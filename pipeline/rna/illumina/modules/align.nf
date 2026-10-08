process STAR_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::star=2.7.11b"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta
    path gtf

    output:
    path "star_index"

    script:
    """
    mkdir star_index
    STAR --runMode genomeGenerate --genomeDir star_index \\
        --genomeFastaFiles ${fasta} --sjdbGTFfile ${gtf} \\
        --sjdbOverhang 99 --runThreadN ${task.cpus} \\
        --genomeSAindexNbases ${params.star_sa_index_nbases}
    """
}

process STAR_ALIGN {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::star=2.7.11b bioconda::samtools=1.24"

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), path("${meta.id}.sorted.bam.bai"), emit: bam
    path "${meta.id}.Log.final.out", emit: log

    script:
    // Decompressing here and skipping --readFilesCommand avoids STAR's own
    // subprocess spawn for "zcat", which can't find it on a micromamba env's
    // PATH (no system dirs inherited) and fails with EXITING/exit 102.
    def reads_args = meta.single_end ? "r1.fastq" : "r1.fastq r2.fastq"
    def decompress = meta.single_end
        ? "gunzip -c ${reads} > r1.fastq"
        : "gunzip -c ${reads[0]} > r1.fastq\n    gunzip -c ${reads[1]} > r2.fastq"
    """
    ${decompress}
    STAR --runMode alignReads --genomeDir ${index} \\
        --readFilesIn ${reads_args} \\
        --runThreadN ${task.cpus} \\
        --outSAMtype BAM SortedByCoordinate \\
        --outFileNamePrefix ${meta.id}. \\
        --outSAMattrRGline ID:${meta.id} SM:${meta.id}
    mv ${meta.id}.Aligned.sortedByCoord.out.bam ${meta.id}.sorted.bam
    samtools index ${meta.id}.sorted.bam
    """
}
