#!/usr/bin/env nextflow

include { FASTQC as FASTQC_RAW  } from './modules/qc.nf'
include { FASTQC as FASTQC_TRIM } from './modules/qc.nf'
include { MULTIQC               } from './modules/qc.nf'
include { FASTP; TRIMGALORE     } from './modules/trim.nf'
include { SAMTOOLS_FAIDX; SAMTOOLS_DICT } from './modules/prepare.nf'
include { BWA_INDEX; BWAMEM2_INDEX; BOWTIE2_INDEX } from './modules/align.nf'
include { BWA_MEM; BWAMEM2_MEM; BOWTIE2_ALIGN     } from './modules/align.nf'
include { GATK_MARKDUPLICATES; SAMTOOLS_MARKDUP; PUBLISH_BAM } from './modules/markdup.nf'
include { SAMTOOLS_INDEX; SAMTOOLS_STATS } from './modules/bam.nf'
include { GATK_HAPLOTYPECALLER; BCFTOOLS_CALL; FREEBAYES; BCFTOOLS_STATS } from './modules/call.nf'

def validateChoice(String name, String value, List<String> allowed) {
    if (!allowed.contains(value)) {
        error("Invalid --${name} '${value}'. Valid options: ${allowed.join(', ')}")
    }
}

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }
    if (!params.fasta) { error("--fasta reference.fa is required") }

    validateChoice('trimmer', params.trimmer, ['fastp', 'trimgalore', 'none'])
    validateChoice('aligner', params.aligner, ['bwamem2', 'bwa', 'bowtie2'])
    validateChoice('markduplicates', params.markduplicates, ['gatk', 'samtools', 'none'])

    def callers = params.callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    if (!callers) { error("--callers requires at least one of: haplotypecaller, bcftools, freebayes") }
    callers.each { String c -> validateChoice('callers', c, ['haplotypecaller', 'bcftools', 'freebayes']) }

    def fasta = file(params.fasta, checkIfExists: true)

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

    // ---- read QC ----------------------------------------------------------
    if (!params.skip_fastqc) {
        FASTQC_RAW(ch_reads, 'raw')
        ch_qc = ch_qc.mix(FASTQC_RAW.out.zip)
    }

    // ---- adapter / quality trimming ---------------------------------------
    def ch_trimmed
    if (params.trimmer == 'fastp') {
        FASTP(ch_reads)
        ch_trimmed = FASTP.out.reads
        ch_qc = ch_qc.mix(FASTP.out.json)
    }
    else if (params.trimmer == 'trimgalore') {
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

    // ---- reference preparation --------------------------------------------
    def ch_fai  = SAMTOOLS_FAIDX(fasta)
    def ch_dict = SAMTOOLS_DICT(fasta)

    // ---- alignment ---------------------------------------------------------
    def ch_bam
    if (params.aligner == 'bwamem2') {
        BWAMEM2_MEM(ch_trimmed, BWAMEM2_INDEX(fasta).first())
        ch_bam = BWAMEM2_MEM.out.bam
    }
    else if (params.aligner == 'bwa') {
        BWA_MEM(ch_trimmed, BWA_INDEX(fasta).first())
        ch_bam = BWA_MEM.out.bam
    }
    else {
        BOWTIE2_ALIGN(ch_trimmed, BOWTIE2_INDEX(fasta).first())
        ch_bam = BOWTIE2_ALIGN.out.bam
        ch_qc = ch_qc.mix(BOWTIE2_ALIGN.out.log)
    }

    // ---- duplicate marking -------------------------------------------------
    def ch_markdup
    if (params.markduplicates == 'gatk') {
        GATK_MARKDUPLICATES(ch_bam)
        ch_markdup = GATK_MARKDUPLICATES.out.bam
        ch_qc = ch_qc.mix(GATK_MARKDUPLICATES.out.metrics)
    }
    else if (params.markduplicates == 'samtools') {
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

    // ---- variant calling ---------------------------------------------------
    def ch_vcf = channel.empty()

    if (callers.contains('haplotypecaller')) {
        GATK_HAPLOTYPECALLER(ch_bam_bai, fasta, ch_fai, ch_dict)
        ch_vcf = ch_vcf.mix(GATK_HAPLOTYPECALLER.out.vcf)
    }
    if (callers.contains('bcftools')) {
        BCFTOOLS_CALL(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(BCFTOOLS_CALL.out.vcf)
    }
    if (callers.contains('freebayes')) {
        FREEBAYES(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(FREEBAYES.out.vcf)
    }

    BCFTOOLS_STATS(ch_vcf)
    ch_qc = ch_qc.mix(BCFTOOLS_STATS.out.stats)

    // ---- aggregate report --------------------------------------------------
    MULTIQC(ch_qc.collect())
}
