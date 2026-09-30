#!/usr/bin/env nextflow

// Oxford Nanopore pipeline: FASTQ -> QC -> filter -> align -> VCF.
//
// Shares its overall shape with the PacBio HiFi workflow (single-end reads,
// no R1/R2 pairing, long-read variant callers), but unlike HiFi's already-
// consensus-accurate reads, raw ONT reads benefit from quality/length
// filtering before alignment -- so this workflow has a filtering stage
// PacBio's doesn't.

include { NANOPLOT; MULTIQC                        } from '../modules/qc.nf'
include { CHOPPER                                   } from './modules/trim.nf'
include { MINIMAP2_INDEX; MINIMAP2_ALIGN             } from './modules/align.nf'
include { SAMTOOLS_FAIDX                             } from '../modules/prepare.nf'
include { SAMTOOLS_MARKDUP; PUBLISH_BAM               } from '../modules/markdup.nf'
include { SAMTOOLS_INDEX; SAMTOOLS_STATS             } from '../modules/bam.nf'
include { CLAIR3; DEEPVARIANT                        } from './modules/call.nf'
include { BCFTOOLS_STATS                             } from '../modules/call.nf'

def validateChoice(String name, String value, List<String> allowed) {
    if (!allowed.contains(value)) {
        error("Invalid --${name} '${value}'. Valid options: ${allowed.join(', ')}")
    }
}

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }
    if (!params.fasta) { error("--fasta reference.fa is required") }

    validateChoice('trimmer', params.trimmer, ['chopper', 'none'])
    validateChoice('markduplicates', params.markduplicates, ['samtools', 'none'])

    def callers = params.callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    if (!callers) { error("--callers requires at least one of: clair3, deepvariant") }
    callers.each { String c -> validateChoice('callers', c, ['clair3', 'deepvariant']) }

    def fasta = file(params.fasta, checkIfExists: true)

    // Samplesheet is single-column reads: ONT is single-end, like PacBio HiFi.
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

    def ch_fai = SAMTOOLS_FAIDX(fasta)

    // ---- alignment -----------------------------------------------------------
    MINIMAP2_ALIGN(ch_filtered, MINIMAP2_INDEX(fasta).first())
    def ch_bam = MINIMAP2_ALIGN.out.bam

    // ---- duplicate marking (optional; ONT libraries are typically PCR-free) --
    def ch_markdup
    if (params.markduplicates == 'samtools') {
        SAMTOOLS_MARKDUP(ch_bam)
        ch_markdup = SAMTOOLS_MARKDUP.out.bam
        ch_qc = ch_qc.mix(SAMTOOLS_MARKDUP.out.metrics)
    }
    else {
        PUBLISH_BAM(ch_bam)
        ch_markdup = PUBLISH_BAM.out.bam
    }

    SAMTOOLS_INDEX(ch_markdup)
    def ch_bam_bai = SAMTOOLS_INDEX.out.bam

    SAMTOOLS_STATS(ch_bam_bai)
    ch_qc = ch_qc.mix(SAMTOOLS_STATS.out.stats)

    // ---- variant calling -----------------------------------------------------
    def ch_vcf = channel.empty()

    if (callers.contains('clair3')) {
        CLAIR3(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(CLAIR3.out.vcf)
    }
    if (callers.contains('deepvariant')) {
        DEEPVARIANT(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(DEEPVARIANT.out.vcf)
    }

    BCFTOOLS_STATS(ch_vcf)
    ch_qc = ch_qc.mix(BCFTOOLS_STATS.out.stats)

    // ---- aggregate report ------------------------------------------------------
    MULTIQC(ch_qc.collect())
}
