process GENOFLU {
    tag "${meta.id}"
    label 'process_medium'
    conda "bioconda::genoflu=1.08"
    publishDir path: { "${params.outdir}/genotype/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(segments)

    output:
    tuple val(meta), path("${meta.id}.genotype.tsv"), emit: genotype

    script:
    // GenoFLU names its own output with an embedded run timestamp
    // (<sample>_<YYYY-MM-DD_HH-MM-SS>_stats.tsv), so the exact filename
    // can't be declared up front -- glob for it and normalize the name.
    // genoflu.py exits non-zero when no genotype can be assigned (e.g. an
    // incomplete or non-influenza sample), which is a valid outcome here,
    // not a pipeline failure.
    """
    cat ${segments} > ${meta.id}.all_segments.fasta
    genoflu.py -f ${meta.id}.all_segments.fasta -n ${meta.id} || true
    stats_file=\$(ls ${meta.id}_*_stats.tsv 2>/dev/null | head -n1)
    if [ -n "\${stats_file}" ]; then
        cp "\${stats_file}" ${meta.id}.genotype.tsv
    else
        printf 'sample\\tdate\\tFile Name\\tGenotype\\n%s\\tNA\\tNA\\tunassigned\\n' ${meta.id} > ${meta.id}.genotype.tsv
    fi
    """
}
