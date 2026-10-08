process PBMM2_INDEX_ISOSEQ {
    tag "${fasta.name}"
    label 'process_high'
    conda "bioconda::pbmm2=1.7.0"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path fasta

    output:
    path "${fasta.baseName}.isoseq.mmi"

    script:
    """
    pbmm2 index --preset ISOSEQ ${fasta} ${fasta.baseName}.isoseq.mmi
    """
}

process PBMM2_ALIGN_ISOSEQ {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::pbmm2=1.7.0"

    input:
    tuple val(meta), path(clustered_bam)
    path index

    output:
    tuple val(meta), path("${meta.id}.mapped.bam"), emit: bam

    script:
    """
    pbmm2 align --preset ISOSEQ --sort -j ${task.cpus} ${index} ${clustered_bam} ${meta.id}.mapped.bam
    """
}

// isoseq, lima, and pbpigeon all ship Linux-only bioconda binaries -- run in
// containers.

process ISOSEQ_COLLAPSE {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::isoseq=4.3.0"
    container "quay.io/biocontainers/isoseq:4.3.0--h9ee0642_0"
    publishDir path: { "${params.outdir}/isoforms/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(mapped_bam)
    tuple val(meta2), path(flnc_bam), path(flnc_pbi)

    output:
    tuple val(meta), path("${meta.id}.collapsed.gff"), emit: gff
    tuple val(meta), path("${meta.id}.collapsed.flnc_count.txt"), emit: flnc_count

    script:
    """
    isoseq collapse --do-not-collapse-extra-5exons ${mapped_bam} ${flnc_bam} ${meta.id}.collapsed.gff
    """
}

process PIGEON_PREPARE_REFERENCE {
    tag "${gtf.name}"
    label 'process_medium'
    conda "bioconda::pbpigeon=1.4.0"
    container "quay.io/biocontainers/pbpigeon:1.4.0--h9948957_0"
    storeDir "${params.reference_cache}/${fasta.baseName}-${fasta.size()}"

    input:
    path gtf
    path fasta

    output:
    path "${gtf.baseName}.sorted.gtf", emit: gtf
    path "${gtf.baseName}.sorted.gtf.pgi", emit: gtf_index
    path fasta, emit: fasta
    path "${fasta}.fai", emit: fai

    script:
    // pigeon prepare strips the GTF's own extension before appending
    // ".sorted.gtf" (annotation.gtf -> annotation.sorted.gtf, not
    // annotation.gtf.sorted.gtf).
    """
    pigeon prepare ${gtf} ${fasta}
    """
}

process PIGEON_CLASSIFY {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::pbpigeon=1.4.0"
    container "quay.io/biocontainers/pbpigeon:1.4.0--h9948957_0"
    publishDir path: { "${params.outdir}/isoforms/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(collapsed_gff), path(flnc_count)
    path sorted_gtf
    path gtf_index
    path ref_fasta
    path ref_fai

    output:
    tuple val(meta), path("${meta.id}.collapsed.sorted.gff"), path("${meta.id}_classification.txt"), path("${meta.id}_junctions.txt"), emit: classification

    script:
    // pigeon classify writes several files from the -o prefix; filter needs
    // the junctions.txt sidecar present even though it's not on its own
    // command line -- it looks it up by the classification file's own name.
    """
    pigeon prepare ${collapsed_gff}
    pigeon classify ${meta.id}.collapsed.sorted.gff ${sorted_gtf} ${ref_fasta} --fl ${flnc_count} -o ${meta.id}
    """
}

process PIGEON_FILTER {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::pbpigeon=1.4.0"
    container "quay.io/biocontainers/pbpigeon:1.4.0--h9948957_0"
    publishDir path: { "${params.outdir}/isoforms/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(sorted_gff), path(classification), path(junctions)

    output:
    tuple val(meta), val('pigeon'), path("${meta.id}_classification.filtered_lite_classification.txt"), emit: classification
    tuple val(meta), path("${meta.id}.collapsed.sorted.filtered_lite.gff"), emit: gff

    script:
    // pigeon filter names its filtered classification from the
    // classification file's own prefix, but its filtered GFF from the
    // --isoforms GFF's prefix -- two different input files, two different
    // output-naming conventions.
    """
    pigeon filter ${classification} --isoforms ${sorted_gff}
    """
}
