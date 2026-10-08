#!/usr/bin/env Rscript
# Usage: run_bambu.R <genome.fa> <annotations.gtf> <bam1> [<bam2> ...]
args <- commandArgs(trailingOnly = TRUE)
genome <- args[1]
gtf <- args[2]
bams <- args[3:length(args)]

suppressMessages(library(bambu))

se <- bambu(reads = bams, annotations = gtf, genome = genome, ncore = 1)
writeBambuOutput(se, path = "./")
