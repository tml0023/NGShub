#!/usr/bin/env nextflow

// Illumina RNA-seq: FASTQ -> QC -> trim -> STAR (genomic align, QC only) +
// Salmon (quantification) -> DESeq2 (differential expression, only when 2+
// sample conditions are present in the samplesheet).
//
// Structurally distinct from Illumina DNA variant calling: no duplicate
// marking or BQSR (irrelevant to expression quantification), and the two
// "aligners" run in parallel rather than one feeding the other -- STAR's
// genomic BAM is QC/visualization only, Salmon quantifies directly from the
// trimmed reads against a transcriptome index.

include { FASTQC as FASTQC_RAW; FASTQC as FASTQC_TRIM; MULTIQC } from '../../modules/qc.nf'
include { TRIMGALORE } from '../../modules/trim.nf'
include { SAMTOOLS_STATS } from '../../modules/bam.nf'
include { STAR_INDEX; STAR_ALIGN } from './modules/align.nf'
include { GFFREAD_EXTRACT_TRANSCRIPTS; GTF_TO_TX2GENE; SALMON_INDEX; SALMON_QUANT } from './modules/quant.nf'
include { DESEQ2 } from './modules/deseq2.nf'

def validateChoice(String name, String value, List<String> allowed) {
    if (!allowed.contains(value)) {
        error("Invalid --${name} '${value}'. Valid options: ${allowed.join(', ')}")
    }
}

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }
    if (!params.fasta) { error("--fasta reference.fa is required") }
    if (!params.gtf)   { error("--gtf annotation.gtf is required") }

    validateChoice('trimmer', params.trimmer, ['trimgalore', 'none'])

    def callers = params.callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    if (!callers) { error("--callers requires: salmon") }
    callers.each { String c -> validateChoice('callers', c, ['salmon']) }

    def fasta = file(params.fasta, checkIfExists: true)
    def gtf   = file(params.gtf, checkIfExists: true)
    def samplesheet = file(params.input, checkIfExists: true)

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

    // ---- read QC ------------------------------------------------------------
    if (!params.skip_fastqc) {
        FASTQC_RAW(ch_reads, 'raw')
        ch_qc = ch_qc.mix(FASTQC_RAW.out.zip)
    }

    // ---- adapter / quality trimming -----------------------------------------
    def ch_trimmed
    if (params.trimmer == 'trimgalore') {
        TRIMGALORE(ch_reads)
        ch_trimmed = TRIMGALORE.out.reads
        ch_qc = ch_qc.mix(TRIMGALORE.out.report)
    }
    else {
        ch_trimmed = ch_reads
    }

    if (!params.skip_fastqc && params.trimmer != 'none') {
        FASTQC_TRIM(ch_trimmed, 'trimmed')
        ch_qc = ch_qc.mix(FASTQC_TRIM.out.zip)
    }

    // ---- genomic alignment (QC/visualization only) ---------------------------
    def ch_star_index = STAR_INDEX(fasta, gtf)
    STAR_ALIGN(ch_trimmed, ch_star_index.first())
    ch_qc = ch_qc.mix(STAR_ALIGN.out.log)
    SAMTOOLS_STATS(STAR_ALIGN.out.bam)
    ch_qc = ch_qc.mix(SAMTOOLS_STATS.out.stats)

    // ---- quantification --------------------------------------------------------
    def ch_transcripts = GFFREAD_EXTRACT_TRANSCRIPTS(fasta, gtf)
    def ch_tx2gene      = GTF_TO_TX2GENE(gtf, fasta)
    def ch_salmon_index  = SALMON_INDEX(ch_transcripts, fasta)

    if (callers.contains('salmon')) {
        SALMON_QUANT(ch_trimmed, ch_salmon_index.first())
        def ch_quant_dirs = SALMON_QUANT.out.quant_dir.map { _meta, dir -> dir }.collect()
        DESEQ2(ch_quant_dirs, samplesheet, ch_tx2gene)
    }

    // ---- aggregate report --------------------------------------------------------
    MULTIQC(ch_qc.collect())
}
