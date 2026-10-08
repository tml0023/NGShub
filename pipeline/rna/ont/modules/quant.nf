process BAMBU {
    label 'process_high'
    // r-biocmanager isn't a direct bambu dependency, but bambu's own
    // annotation-type-detection code unconditionally calls into it (even for
    // a plain GTF file path) and fails outright if it's missing.
    conda "bioconda::bioconductor-bambu=3.12.1 conda-forge::r-biocmanager=1.30.27"
    publishDir "${params.outdir}/quant/bambu", mode: 'copy'

    input:
    path bams
    path bais
    path fasta
    path gtf

    output:
    path "*.gtf", emit: gtf
    path "*gene*.txt", emit: gene_counts
    path "*transcript*.txt", emit: transcript_counts

    script:
    """
    run_bambu.R ${fasta} ${gtf} ${bams.join(' ')}
    """
}

process STRINGTIE_ASSEMBLE {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::stringtie=3.0.3"

    input:
    tuple val(meta), path(bam), path(bai)
    path gtf

    output:
    path "${meta.id}.gtf"

    script:
    """
    stringtie ${bam} -G ${gtf} -L -o ${meta.id}.gtf
    """
}

process STRINGTIE_MERGE {
    label 'process_medium'
    conda "bioconda::stringtie=3.0.3"
    publishDir "${params.outdir}/quant/stringtie2", mode: 'copy'

    input:
    path sample_gtfs
    path ref_gtf

    output:
    path "merged.gtf"

    script:
    """
    stringtie --merge -G ${ref_gtf} -o merged.gtf ${sample_gtfs}
    """
}

process FEATURECOUNTS {
    label 'process_high'
    conda "bioconda::subread=2.1.1"
    publishDir "${params.outdir}/quant/stringtie2", mode: 'copy'

    input:
    path bams
    path merged_gtf

    output:
    path "counts_gene.txt"

    script:
    """
    featureCounts -L -T 1 --primary -a ${merged_gtf} -o counts_gene.txt ${bams.join(' ')}
    """
}
