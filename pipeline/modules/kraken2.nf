// Taxonomic composition screen -- not a filter, just a diagnostic: runs on
// every sample unconditionally (not gated on any downstream assembly
// result), so a sample that assembles nothing still tells you *why* --
// mostly unclassified junk, a different virus entirely, or genuinely
// influenza at too low an abundance/quality to assemble. Uses Kraken2's
// prebuilt "Viral" database (RefSeq viral, ~0.5GB) rather than the full
// standard database (100+GB, not practical on a single dev machine) -- see
// scripts/setup_kraken2_db.sh. That means this screens composition among
// viruses, not true host-genome depletion (no host genomes in this DB).
process KRAKEN2 {
    tag "${meta.id}"
    label 'process_high'
    conda "bioconda::kraken2=2.17.2"
    publishDir path: { "${params.outdir}/taxonomy/${meta.id}" }, mode: 'copy'

    input:
    tuple val(meta), path(reads)
    path db_dir

    output:
    tuple val(meta), path("${meta.id}.kraken2.report.txt"), emit: report
    tuple val(meta), path("${meta.id}.composition.json"), emit: composition

    script:
    def reads_args = meta.single_end ? "${reads}" : "--paired ${reads[0]} ${reads[1]}"
    """
    kraken2 --db ${db_dir} --threads ${task.cpus} \\
        --report ${meta.id}.kraken2.report.txt --output /dev/null ${reads_args}

    # Column 1 = cumulative % of reads at/under this clade; column 5 = taxid.
    # Taxid 0 is Kraken2's fixed "unclassified" bucket; 11320 is the stable,
    # long-established NCBI taxid for the "Influenza A virus" species node
    # (confirmed present in this DB's inspect.txt before relying on it here).
    unclassified_pct=\$(awk -F'\\t' '\$5==0{print \$1; exit}' ${meta.id}.kraken2.report.txt)
    influenza_a_pct=\$(awk -F'\\t' '\$5==11320{print \$1; exit}' ${meta.id}.kraken2.report.txt)
    printf '{"unclassified_pct": %s, "influenza_a_pct": %s}\\n' \\
        "\${unclassified_pct:-0}" "\${influenza_a_pct:-0}" > ${meta.id}.composition.json
    """
}
