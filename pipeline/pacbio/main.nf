#!/usr/bin/env nextflow

// PacBio HiFi germline pipeline: FASTQ -> QC -> align -> VCF.
//
// Structurally different from the Illumina workflow, not just a parameter
// variant of it: HiFi reads are single-end (no R1/R2), duplicate marking (if
// used at all) happens pre-alignment on raw reads rather than post-alignment
// on a BAM, and there is no BQSR step (HiFi's per-base error profile isn't
// what BQSR's covariate model was built to correct).

include { NANOPLOT; MULTIQC              } from '../modules/qc.nf'
include { PBMARKDUP                      } from './modules/markdup.nf'
include { PBMM2_INDEX; PBMM2_ALIGN; MINIMAP2_INDEX; MINIMAP2_ALIGN } from './modules/align.nf'
include { SAMTOOLS_FAIDX                 } from '../modules/prepare.nf'
include { SAMTOOLS_INDEX; SAMTOOLS_STATS } from '../modules/bam.nf'
include { DEEPVARIANT; CLAIR3            } from './modules/call.nf'
include { BCFTOOLS_STATS                 } from '../modules/call.nf'
include { PBSV_CALL; PBSV_INDEX          } from './modules/sv.nf'
include { SNIFFLES2                      } from '../modules/sv.nf'

def validateChoice(String name, String value, List<String> allowed) {
    if (!allowed.contains(value)) {
        error("Invalid --${name} '${value}'. Valid options: ${allowed.join(', ')}")
    }
}

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }
    if (!params.fasta) { error("--fasta reference.fa is required") }

    validateChoice('aligner', params.aligner, ['pbmm2', 'minimap2'])
    validateChoice('markduplicates', params.markduplicates, ['pbmarkdup', 'none'])

    def callers = params.callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    if (!callers) { error("--callers requires at least one of: deepvariant, clair3") }
    callers.each { String c -> validateChoice('callers', c, ['deepvariant', 'clair3']) }

    def sv_callers = params.sv_callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    sv_callers.each { String c -> validateChoice('sv_callers', c, ['pbsv', 'sniffles2']) }

    def fasta = file(params.fasta, checkIfExists: true)

    // Samplesheet is single-column reads: HiFi is single-end, unlike Illumina's R1/R2.
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

    // ---- duplicate marking (pre-alignment, reference-free) -----------------
    def ch_input_reads
    if (params.markduplicates == 'pbmarkdup') {
        PBMARKDUP(ch_reads)
        ch_input_reads = PBMARKDUP.out.reads
        ch_qc = ch_qc.mix(PBMARKDUP.out.log)
    }
    else {
        ch_input_reads = ch_reads
    }

    def ch_fai = SAMTOOLS_FAIDX(fasta)

    // ---- alignment -----------------------------------------------------------
    def ch_bam
    if (params.aligner == 'pbmm2') {
        PBMM2_ALIGN(ch_input_reads, PBMM2_INDEX(fasta).first())
        ch_bam = PBMM2_ALIGN.out.bam
    }
    else {
        MINIMAP2_ALIGN(ch_input_reads, MINIMAP2_INDEX(fasta).first())
        ch_bam = MINIMAP2_ALIGN.out.bam
    }

    SAMTOOLS_INDEX(ch_bam)
    def ch_bam_bai = SAMTOOLS_INDEX.out.bam

    SAMTOOLS_STATS(ch_bam_bai)
    ch_qc = ch_qc.mix(SAMTOOLS_STATS.out.stats)

    // ---- variant calling -----------------------------------------------------
    def ch_vcf = channel.empty()

    if (callers.contains('deepvariant')) {
        DEEPVARIANT(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(DEEPVARIANT.out.vcf)
    }
    if (callers.contains('clair3')) {
        CLAIR3(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(CLAIR3.out.vcf)
    }

    // ---- structural variant calling (optional) -----------------------------
    if (sv_callers.contains('pbsv')) {
        PBSV_CALL(ch_bam_bai, fasta, ch_fai)
        PBSV_INDEX(PBSV_CALL.out.vcf)
        ch_vcf = ch_vcf.mix(PBSV_INDEX.out.vcf)
    }
    if (sv_callers.contains('sniffles2')) {
        SNIFFLES2(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(SNIFFLES2.out.vcf)
    }

    BCFTOOLS_STATS(ch_vcf)
    ch_qc = ch_qc.mix(BCFTOOLS_STATS.out.stats)

    // ---- aggregate report ------------------------------------------------------
    MULTIQC(ch_qc.collect())
}
