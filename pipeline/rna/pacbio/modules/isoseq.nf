// lima, isoseq refine, and isoseq cluster2 all ship Linux-only bioconda
// binaries (no macOS build at all) -- run in containers.

process FASTQ_TO_BAM {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::pysam=0.24.1"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}.unaligned.bam"), emit: bam

    script:
    // A plain `samtools import`, even with a correct @RG DS:READTYPE=CCS
    // header, leaves lima stuck in an internal futex wait forever instead of
    // erroring -- confirmed by direct trace (opens its output files, never
    // progresses, regardless of thread count or --peek-guess). lima/isoseq
    // need the per-read CCS tags (qs/qe/zm/np/rq/ec) every real PacBio BAM
    // carries; fastq_to_pacbio_bam.py adds them directly via pysam.
    """
    fastq_to_pacbio_bam.py ${reads} ${meta.id}.unaligned.bam ${meta.id}
    """
}

process LIMA {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::lima=2.13.0"
    container "quay.io/biocontainers/lima:2.13.0--h9ee0642_0"

    input:
    tuple val(meta), path(bam)
    path primers

    output:
    tuple val(meta), path("${meta.id}.renamed.fl.bam"), emit: bam

    script:
    """
    lima ${bam} ${primers} ${meta.id}.fl.bam --isoseq --peek-guess
    # lima renames its output to embed the matched primer-pair name, which
    # varies with whatever is in the primers FASTA -- normalize it so
    # downstream steps have a fixed filename to depend on.
    mv \$(ls ${meta.id}.fl.*.bam | head -n1) ${meta.id}.renamed.fl.bam
    """
}

process ISOSEQ_REFINE {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::isoseq=4.3.0"
    container "quay.io/biocontainers/isoseq:4.3.0--h9ee0642_0"

    input:
    tuple val(meta), path(bam)
    path primers

    output:
    tuple val(meta), path("${meta.id}.flnc.bam"), path("${meta.id}.flnc.bam.pbi"), emit: bam

    script:
    """
    isoseq refine ${bam} ${primers} ${meta.id}.flnc.bam --require-polya
    """
}

process ISOSEQ_CLUSTER2 {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::isoseq=4.3.0"
    container "quay.io/biocontainers/isoseq:4.3.0--h9ee0642_0"

    input:
    tuple val(meta), path(flnc_bam), path(flnc_pbi)

    output:
    tuple val(meta), path("${meta.id}.clustered.bam"), emit: bam

    script:
    """
    echo ${flnc_bam} > flnc.fofn
    isoseq cluster2 flnc.fofn ${meta.id}.clustered.bam
    """
}
