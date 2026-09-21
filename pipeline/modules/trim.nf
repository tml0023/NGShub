process FASTP {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::fastp=1.3.7"
    publishDir "${params.outdir}/trimming/fastp", mode: 'copy', pattern: "*.{json,html}"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.trim.fastq.gz", arity: '1..2'), emit: reads
    path "*.fastp.json", emit: json
    path "*.fastp.html", emit: html

    script:
    def args = params.fastp_args ?: ''
    if (meta.single_end) {
        """
        fastp \\
            --in1 ${reads[0]} \\
            --out1 ${meta.id}_1.trim.fastq.gz \\
            --json ${meta.id}.fastp.json \\
            --html ${meta.id}.fastp.html \\
            --thread ${task.cpus} \\
            ${args}
        """
    } else {
        """
        fastp \\
            --in1 ${reads[0]} --in2 ${reads[1]} \\
            --out1 ${meta.id}_1.trim.fastq.gz \\
            --out2 ${meta.id}_2.trim.fastq.gz \\
            --detect_adapter_for_pe \\
            --json ${meta.id}.fastp.json \\
            --html ${meta.id}.fastp.html \\
            --thread ${task.cpus} \\
            ${args}
        """
    }
}

process TRIMGALORE {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::trim-galore=0.6.11 bioconda::cutadapt=5.2"
    publishDir "${params.outdir}/trimming/trimgalore", mode: 'copy', pattern: "*report.txt"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.trim.fastq.gz", arity: '1..2'), emit: reads
    path "*report.txt", emit: report

    script:
    def args = params.trimgalore_args ?: ''
    // trim_galore parallelises poorly above 4 cores (it forks cutadapt + pigz)
    def cores = Math.min(task.cpus as int, 4)
    if (meta.single_end) {
        """
        trim_galore --gzip --cores ${cores} ${args} ${reads[0]}
        mv *_trimmed.fq.gz ${meta.id}_1.trim.fastq.gz
        """
    } else {
        """
        trim_galore --paired --gzip --cores ${cores} ${args} ${reads[0]} ${reads[1]}
        mv *_val_1.fq.gz ${meta.id}_1.trim.fastq.gz
        mv *_val_2.fq.gz ${meta.id}_2.trim.fastq.gz
        """
    }
}
