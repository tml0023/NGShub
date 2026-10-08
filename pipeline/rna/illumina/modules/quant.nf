process GFFREAD_EXTRACT_TRANSCRIPTS {
    tag "${fasta.name}"
    label 'process_medium'
    conda "bioconda::gffread=0.12.9"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta
    path gtf

    output:
    path "transcripts.fa"

    script:
    """
    gffread -w transcripts.fa -g ${fasta} ${gtf}
    """
}

process GTF_TO_TX2GENE {
    tag "${gtf.name}"
    label 'process_low'
    conda "conda-forge::python=3.11"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path gtf
    path fasta

    output:
    path "tx2gene.tsv"

    script:
    """
    gtf_to_tx2gene.py ${gtf} tx2gene.tsv
    """
}

process SALMON_INDEX {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::salmon=2.8.0"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path transcripts
    path fasta

    output:
    path "salmon_index"

    script:
    """
    salmon index -t ${transcripts} -i salmon_index -k ${params.salmon_kmer_len} -p ${task.cpus}
    """
}

process SALMON_QUANT {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::salmon=2.8.0"
    publishDir "${params.outdir}/quant/salmon", mode: 'copy'

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}"), emit: quant_dir
    tuple val(meta), path("${meta.id}/quant.sf"), emit: quant_sf

    script:
    def reads_args = meta.single_end ? "-r ${reads}" : "-1 ${reads[0]} -2 ${reads[1]}"
    """
    salmon quant -i ${index} -l A ${reads_args} -p ${task.cpus} --validateMappings -o ${meta.id}
    """
}
