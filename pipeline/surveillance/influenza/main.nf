#!/usr/bin/env nextflow

// Targeted influenza surveillance: FASTQ -> IRMA segment assembly ->
// GenoFLU genotype assignment -> risk-marker screen -> plain-language
// report. Phase 5 of the project plan ("Influenza surveillance MVP") --
// the first mode in the pathogen-surveillance family, built on the same
// ingest/QC/reporting core as the DNA and RNA-seq pipelines.
//
// Unlike those pipelines, a sample can legitimately produce *no* assembled
// segments (no influenza detected, or an incomplete/low-coverage genome) --
// that's a real, reportable outcome here, not a failure, so the genotype
// and risk-scoring stages are skipped gracefully rather than erroring.

include { NANOPLOT; FASTQC; MULTIQC } from '../../modules/qc.nf'
include { IRMA_ASSEMBLE } from './modules/irma.nf'
include { GENOFLU } from './modules/genotype.nf'
include { RISK_SCORE } from './modules/risk.nf'
include { SURVEILLANCE_REPORT } from './modules/report.nf'

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }

    def marker_table = file("${workflow.projectDir}/assets/risk_markers.tsv", checkIfExists: true)
    def pb2_ref       = file("${workflow.projectDir}/assets/PB2_reference.fasta", checkIfExists: true)
    def pa_ref        = file("${workflow.projectDir}/assets/PA_reference.fasta", checkIfExists: true)
    def na_n1_ref     = file("${workflow.projectDir}/assets/NA_N1_reference.fasta", checkIfExists: true)

    // Samplesheet accepts either paired (fastq_1/fastq_2) or single-end
    // (fastq_1 only) rows in the same file, since this mode spans Illumina
    // (paired) and ONT/PacBio (single-end) -- unlike the DNA/RNA pipelines,
    // which each commit to one layout.
    def ch_reads = channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            if (!row.sample)   { error("Samplesheet row is missing a 'sample' column value") }
            if (!row.fastq_1)  { error("Sample '${row.sample}' is missing fastq_1") }
            def has_r2 = row.fastq_2 && row.fastq_2.toString().trim()
            def meta = [id: row.sample.toString().trim(), single_end: !has_r2]
            def reads = has_r2
                ? [file(row.fastq_1, checkIfExists: true), file(row.fastq_2, checkIfExists: true)]
                : [file(row.fastq_1, checkIfExists: true)]
            tuple(meta, reads)
        }

    def ch_qc = channel.empty()

    // ---- read QC (platform-appropriate, like the DNA/RNA pipelines) --------
    def ch_fastqc = ch_reads.filter { meta, _reads -> !meta.single_end }
    def ch_nanoplot = ch_reads.filter { meta, _reads -> meta.single_end }
    FASTQC(ch_fastqc, 'raw')
    ch_qc = ch_qc.mix(FASTQC.out.zip)
    NANOPLOT(ch_nanoplot)
    ch_qc = ch_qc.mix(NANOPLOT.out.report)

    // ---- segment assembly + typing ------------------------------------------
    IRMA_ASSEMBLE(ch_reads)
    ch_qc = ch_qc.mix(IRMA_ASSEMBLE.out.read_counts.map { _meta, f -> f })

    // A negative/incomplete sample assembles zero segments -- a real,
    // reportable outcome, not a pipeline error, so split here rather than
    // let an empty file list reach GenoFLU/risk-scoring.
    def ch_assembled = IRMA_ASSEMBLE.out.segments.filter { _meta, segs -> segs.size() > 0 }

    GENOFLU(ch_assembled)
    RISK_SCORE(ch_assembled, marker_table, pb2_ref, pa_ref, na_n1_ref)

    def ch_report_input = GENOFLU.out.genotype.join(RISK_SCORE.out.json)
    SURVEILLANCE_REPORT(ch_report_input)

    // ---- aggregate QC --------------------------------------------------------
    MULTIQC(ch_qc.collect())
}
