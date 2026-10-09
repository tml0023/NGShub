#!/usr/bin/env nextflow

// Targeted influenza surveillance, Oxford Nanopore: single-end FASTQ ->
// chopper filtering -> IRMA (FLU-minion, the MinION-tuned preset IRMA ships
// for exactly this platform) -> GenoFLU -> risk-marker screen -> report.
//
// Shares its risk-marker reference panel, risk table, and the risk/report
// scripts with the Illumina influenza pipeline (../influenza/) by reference
// rather than forking copies -- those are literature-sourced and
// correctness-critical (see check_risk_markers.py), so one source of truth
// is worth the cross-directory path over independent copies that could
// drift out of sync.

include { NANOPLOT; MULTIQC } from '../../modules/qc.nf'
include { CHOPPER } from './modules/filter.nf'
include { IRMA_ASSEMBLE_ONT } from './modules/irma.nf'
include { GENOFLU } from './modules/genotype.nf'
include { RISK_SCORE } from './modules/risk.nf'
include { SURVEILLANCE_REPORT } from './modules/report.nf'

def validateChoice(String name, String value, List<String> allowed) {
    if (!allowed.contains(value)) {
        error("Invalid --${name} '${value}'. Valid options: ${allowed.join(', ')}")
    }
}

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }

    validateChoice('trimmer', params.trimmer, ['chopper', 'none'])

    def influenza_dir = "${workflow.projectDir}/../influenza"
    def marker_table = file("${influenza_dir}/assets/risk_markers.tsv", checkIfExists: true)
    def pb2_ref       = file("${influenza_dir}/assets/PB2_reference.fasta", checkIfExists: true)
    def pa_ref        = file("${influenza_dir}/assets/PA_reference.fasta", checkIfExists: true)
    def na_n1_ref     = file("${influenza_dir}/assets/NA_N1_reference.fasta", checkIfExists: true)

    // Samplesheet is single-column reads: ONT is single-end, like the DNA ONT pipeline.
    def ch_reads = channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            if (!row.sample) { error("Samplesheet row is missing a 'sample' column value") }
            if (!row.fastq)  { error("Sample '${row.sample}' is missing fastq") }
            def meta = [id: row.sample.toString().trim()]
            tuple(meta, file(row.fastq, checkIfExists: true))
        }

    def ch_qc = channel.empty()

    NANOPLOT(ch_reads)
    ch_qc = ch_qc.mix(NANOPLOT.out.report)

    def ch_filtered
    if (params.trimmer == 'chopper') {
        CHOPPER(ch_reads)
        ch_filtered = CHOPPER.out.reads
    }
    else {
        ch_filtered = ch_reads
    }

    IRMA_ASSEMBLE_ONT(ch_filtered)
    ch_qc = ch_qc.mix(IRMA_ASSEMBLE_ONT.out.read_counts.map { _meta, f -> f })

    def ch_assembled = IRMA_ASSEMBLE_ONT.out.segments.filter { _meta, segs -> segs.size() > 0 }

    GENOFLU(ch_assembled)
    RISK_SCORE(ch_assembled, marker_table, pb2_ref, pa_ref, na_n1_ref)

    def ch_report_input = GENOFLU.out.genotype.join(RISK_SCORE.out.json)
    SURVEILLANCE_REPORT(ch_report_input)

    MULTIQC(ch_qc.collect())
}
