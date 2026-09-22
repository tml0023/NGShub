#!/usr/bin/env nextflow

include { FASTQC as FASTQC_RAW  } from './modules/qc.nf'
include { FASTQC as FASTQC_TRIM } from './modules/qc.nf'
include { MULTIQC               } from './modules/qc.nf'
include { FASTP; TRIMGALORE     } from './modules/trim.nf'
include { SAMTOOLS_FAIDX; SAMTOOLS_DICT } from './modules/prepare.nf'
include { BWA_INDEX; BWAMEM2_INDEX; BOWTIE2_INDEX; DRAGMAP_HASHTABLE } from './modules/align.nf'
include { BWA_MEM; BWAMEM2_MEM; BOWTIE2_ALIGN; DRAGMAP_ALIGN         } from './modules/align.nf'
include { GATK_MARKDUPLICATES; SAMTOOLS_MARKDUP; PUBLISH_BAM } from './modules/markdup.nf'
include { SAMTOOLS_INDEX; SAMTOOLS_INDEX as SAMTOOLS_INDEX_BQSR; SAMTOOLS_STATS } from './modules/bam.nf'
include { GATK_BASERECALIBRATOR; GATK_APPLYBQSR } from './modules/bqsr.nf' 
include { GATK_HAPLOTYPECALLER; BCFTOOLS_CALL; FREEBAYES; DEEPVARIANT; BCFTOOLS_STATS } from './modules/call.nf'

def validateChoice(String name, String value, List<String> allowed) {
    if (!allowed.contains(value)) {
        error("Invalid --${name} '${value}'. Valid options: ${allowed.join(', ')}")
    }
}

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }
    if (!params.fasta) { error("--fasta reference.fa is required") }

    validateChoice('trimmer', params.trimmer, ['fastp', 'trimgalore', 'none'])
    validateChoice('aligner', params.aligner, ['bwamem2', 'bwa', 'bowtie2', 'dragmap'])
    validateChoice('markduplicates', params.markduplicates, ['gatk', 'samtools', 'none'])
    if (params.bqsr && !params.known_sites) {
        error("--bqsr true requires --known_sites (comma-separated known-variant VCF paths)")
    }

    def callers = params.callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    if (!callers) { error("--callers requires at least one of: haplotypecaller, bcftools, freebayes") }
    callers.each { String c -> validateChoice('callers', c, ['haplotypecaller', 'bcftools', 'freebayes', 'deepvariant']) }

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
    else if (params.aligner == 'bowtie2') {
        BOWTIE2_ALIGN(ch_trimmed, BOWTIE2_INDEX(fasta).first())
        ch_bam = BOWTIE2_ALIGN.out.bam
        ch_qc = ch_qc.mix(BOWTIE2_ALIGN.out.log)
    }
    else {
        DRAGMAP_ALIGN(ch_trimmed, DRAGMAP_HASHTABLE(fasta).first())
        ch_bam = DRAGMAP_ALIGN.out.bam
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
    def ch_indexed = SAMTOOLS_INDEX.out.bam

    // ---- base quality score recalibration (optional) ----------------------
    def ch_bam_bai
    if (params.bqsr) {
        def known_sites = params.known_sites.toString().split(',').collect { String p -> file(p.trim(), checkIfExists: true) }
        def known_sites_tbi = known_sites.collect { java.nio.file.Path p -> file("${p}.tbi", checkIfExists: true) }

        GATK_BASERECALIBRATOR(ch_indexed, fasta, ch_fai, ch_dict, known_sites, known_sites_tbi)
        ch_qc = ch_qc.mix(GATK_BASERECALIBRATOR.out.table.map { _m, table -> table })

        def ch_recal_input = ch_indexed.join(GATK_BASERECALIBRATOR.out.table)
        GATK_APPLYBQSR(ch_recal_input, fasta, ch_fai, ch_dict)

        SAMTOOLS_INDEX_BQSR(GATK_APPLYBQSR.out.bam)
        ch_bam_bai = SAMTOOLS_INDEX_BQSR.out.bam
    }
    else {
        ch_bam_bai = ch_indexed
    }

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
    if (callers.contains('deepvariant')) {
        DEEPVARIANT(ch_bam_bai, fasta, ch_fai)
        ch_vcf = ch_vcf.mix(DEEPVARIANT.out.vcf)
    }

    BCFTOOLS_STATS(ch_vcf)
    ch_qc = ch_qc.mix(BCFTOOLS_STATS.out.stats)

    // ---- aggregate report --------------------------------------------------
    MULTIQC(ch_qc.collect())
}
