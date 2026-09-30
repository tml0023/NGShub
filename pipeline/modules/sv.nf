process MANTA {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::manta=1.6.0"
    // Manta's bioconda package ships Linux-only ELF binaries (Illumina never
    // built it for macOS) -- runs in a container on macOS, same as DragMap.
    container "quay.io/biocontainers/manta:1.6.0--py27h9948957_6"
    publishDir "${params.outdir}/variants/sv/manta", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('manta'), path("${meta.id}.manta.vcf.gz"), path("${meta.id}.manta.vcf.gz.tbi"), emit: vcf

    script:
    // -g declares available memory explicitly -- Manta's own auto-detection
    // reads the Docker Desktop VM's tight memory ceiling and undercounts,
    // failing even tiny test runs with "exceeds full available resources".
    """
    configManta.py --bam ${bam} --referenceFasta ${fasta} --runDir manta_run
    manta_run/runWorkflow.py -j ${task.cpus} -g ${task.memory.toGiga()}
    cp manta_run/results/variants/diploidSV.vcf.gz ${meta.id}.manta.vcf.gz
    cp manta_run/results/variants/diploidSV.vcf.gz.tbi ${meta.id}.manta.vcf.gz.tbi
    """
}

// Shared by PacBio HiFi and Oxford Nanopore -- Sniffles2 is genuinely
// platform-agnostic, no ONT/PacBio-specific flags in its own documentation.
process SNIFFLES2 {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::sniffles=2.8.1"
    publishDir "${params.outdir}/variants/sv/sniffles2", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('sniffles2'), path("${meta.id}.sniffles2.vcf.gz"), path("${meta.id}.sniffles2.vcf.gz.tbi"), emit: vcf

    script:
    // --all-contigs: Sniffles2 silently skips any contig under 1Mb by
    // default, which would zero out calls on small/custom references.
    """
    sniffles --input ${bam} --vcf ${meta.id}.sniffles2.vcf.gz \\
        --reference ${fasta} --threads ${task.cpus} --all-contigs
    """
}

process DELLY {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::delly=2.6.0 bioconda::bcftools=1.24"
    publishDir "${params.outdir}/variants/sv/delly", mode: 'copy'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai

    output:
    tuple val(meta), val('delly'), path("${meta.id}.delly.vcf.gz"), path("${meta.id}.delly.vcf.gz.tbi"), emit: vcf

    script:
    """
    delly sr -g ${fasta} -o ${meta.id}.delly.bcf ${bam}
    bcftools sort --output-type z --output ${meta.id}.delly.vcf.gz ${meta.id}.delly.bcf
    bcftools index --tbi ${meta.id}.delly.vcf.gz
    """
}
