#!/usr/bin/env nextflow

// Oxford Nanopore RNA-seq: FASTQ -> QC -> filter -> spliced alignment ->
// transcript reconstruction + quantification (including novel isoforms).
//
// Unlike Illumina RNA-seq, there's no standard differential-expression step
// here -- long-read per-sample depth is typically too low for the kind of
// per-gene statistical comparison DESeq2 does well, so this stops at
// quantification. Bambu and StringTie2 both need every sample's BAM at once
// (joint multi-sample calling improves novel-isoform discovery), unlike the
// per-sample channels used elsewhere in this pipeline.

include { NANOPLOT; MULTIQC } from '../../modules/qc.nf'
include { CHOPPER } from '../../ont/modules/trim.nf'
include { MINIMAP2_INDEX; MINIMAP2_ALIGN } from './modules/align.nf'
include { BAMBU; STRINGTIE_ASSEMBLE; STRINGTIE_MERGE; FEATURECOUNTS } from './modules/quant.nf'

def validateChoice(String name, String value, List<String> allowed) {
    if (!allowed.contains(value)) {
        error("Invalid --${name} '${value}'. Valid options: ${allowed.join(', ')}")
    }
}

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }
    if (!params.fasta) { error("--fasta reference.fa is required") }
    if (!params.gtf)   { error("--gtf annotation.gtf is required") }

    def callers = params.callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    if (!callers) { error("--callers requires at least one of: bambu, stringtie2") }
    callers.each { String c -> validateChoice('callers', c, ['bambu', 'stringtie2']) }

    def fasta = file(params.fasta, checkIfExists: true)
    def gtf   = file(params.gtf, checkIfExists: true)

    // Samplesheet is single-column reads: single-end, like PacBio.
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

    // ---- quality/length filtering --------------------------------------------
    def ch_filtered
    if (params.trimmer == 'chopper') {
        CHOPPER(ch_reads)
        ch_filtered = CHOPPER.out.reads
    }
    else {
        ch_filtered = ch_reads
    }

    // ---- spliced alignment -----------------------------------------------------
    def ch_index = MINIMAP2_INDEX(fasta)
    MINIMAP2_ALIGN(ch_filtered, ch_index.first())
    def ch_bam_bai = MINIMAP2_ALIGN.out.bam

    // ---- transcript reconstruction + quantification (joint, all samples) -------
    if (callers.contains('bambu')) {
        def ch_bams = ch_bam_bai.map { _meta, bam, _bai -> bam }.collect()
        def ch_bais = ch_bam_bai.map { _meta, _bam, bai -> bai }.collect()
        BAMBU(ch_bams, ch_bais, fasta, gtf)
    }
    if (callers.contains('stringtie2')) {
        STRINGTIE_ASSEMBLE(ch_bam_bai, gtf)
        def ch_merged = STRINGTIE_MERGE(STRINGTIE_ASSEMBLE.out.collect(), gtf)
        def ch_bams = ch_bam_bai.map { _meta, bam, _bai -> bam }.collect()
        FEATURECOUNTS(ch_bams, ch_merged)
    }

    // ---- aggregate report --------------------------------------------------------
    MULTIQC(ch_qc.collect())
}
