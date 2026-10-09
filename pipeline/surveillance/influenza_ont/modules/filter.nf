// A local copy of the DNA ONT pipeline's chopper process (../../ont/modules/trim.nf),
// not a shared include, because its default length floor doesn't transfer: that
// pipeline's 500bp default assumes whole-genome shotgun long reads, but targeted
// influenza sequencing (amplicon-tiled or segment-targeted) produces much shorter
// reads -- confirmed on a real MinION surveillance run (SRR26182435, USDA avian
// H5N1), where the 500bp floor would have discarded ~87% of reads (mean length
// 338bp) before IRMA ever saw them. 100bp here only strips reads too short to be
// biologically meaningful; IRMA's own FLU-minion config applies its own stricter
// 150bp quality-read threshold downstream during consensus building.
process CHOPPER {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::chopper=0.14.1"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}.filtered.fastq.gz"), emit: reads

    script:
    // Deliberately NOT params.chopper_min_length: the shared pipeline/nextflow.config
    // sets that to 500 for the whole-genome ONT pipeline, and since it's always
    // explicitly set (not null), a `?:` fallback here would never fire -- Nextflow's
    // params namespace is shared across every pipeline loaded with that config file.
    def min_qual = params.chopper_min_quality ?: 10
    def min_length = params.influenza_chopper_min_length ?: 100
    """
    gunzip -c ${reads} | chopper -q ${min_qual} -l ${min_length} --threads ${task.cpus} \\
        | gzip > ${meta.id}.filtered.fastq.gz
    """
}
