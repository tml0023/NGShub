#!/usr/bin/env nextflow

// PacBio Iso-Seq: full-length cDNA -> isoform discovery and classification.
//
// Fundamentally different task from DNA variant calling or short-read
// quantification: this discovers and classifies transcript isoforms (known
// and novel) against a reference annotation, rather than counting reads
// against pre-defined genes. Fixed canonical workflow (lima -> isoseq refine
// -> isoseq cluster2 -> pbmm2 -> isoseq collapse -> pigeon classify/filter) --
// no meaningful tool alternatives at each step the way DNA platforms offer.

include { NANOPLOT; MULTIQC } from '../../modules/qc.nf'
include { FASTQ_TO_BAM; LIMA; ISOSEQ_REFINE; ISOSEQ_CLUSTER2 } from './modules/isoseq.nf'
include { PBMM2_INDEX_ISOSEQ; PBMM2_ALIGN_ISOSEQ; ISOSEQ_COLLAPSE; PIGEON_PREPARE_REFERENCE; PIGEON_CLASSIFY; PIGEON_FILTER } from './modules/pigeon.nf'

workflow {
    if (!params.input) { error("--input samplesheet.csv is required") }
    if (!params.fasta) { error("--fasta reference.fa is required") }
    if (!params.gtf)   { error("--gtf annotation.gtf is required") }

    def callers = params.callers.toString()
        .split(',')
        .collect { String c -> c.trim().toLowerCase() }
        .findAll { String c -> c }
    if (!callers.contains('pigeon')) { error("--callers requires: pigeon") }

    def fasta = file(params.fasta, checkIfExists: true)
    def gtf   = file(params.gtf, checkIfExists: true)
    def primers = params.primers
        ? file(params.primers, checkIfExists: true)
        : file("${workflow.projectDir}/assets/primers.fasta", checkIfExists: true)

    // Samplesheet is single-column reads: full-length cDNA is single-end, like HiFi DNA.
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

    // ---- primer removal, full-length/polyA refinement, clustering -----------
    FASTQ_TO_BAM(ch_reads)
    LIMA(FASTQ_TO_BAM.out.bam, primers)
    ISOSEQ_REFINE(LIMA.out.bam, primers)
    ISOSEQ_CLUSTER2(ISOSEQ_REFINE.out.bam)

    // ---- alignment ------------------------------------------------------------
    def ch_index = PBMM2_INDEX_ISOSEQ(fasta)
    PBMM2_ALIGN_ISOSEQ(ISOSEQ_CLUSTER2.out.bam, ch_index.first())

    // ---- collapse + classify against the reference annotation -----------------
    ISOSEQ_COLLAPSE(PBMM2_ALIGN_ISOSEQ.out.bam, ISOSEQ_REFINE.out.bam)
    def ch_ref_prepared = PIGEON_PREPARE_REFERENCE(gtf, fasta)
    PIGEON_CLASSIFY(
        ISOSEQ_COLLAPSE.out.gff.join(ISOSEQ_COLLAPSE.out.flnc_count),
        ch_ref_prepared.gtf.first(),
        ch_ref_prepared.gtf_index.first(),
        ch_ref_prepared.fasta.first(),
        ch_ref_prepared.fai.first(),
    )
    PIGEON_FILTER(PIGEON_CLASSIFY.out.classification)

    // ---- aggregate report --------------------------------------------------------
    MULTIQC(ch_qc.collect())
}
