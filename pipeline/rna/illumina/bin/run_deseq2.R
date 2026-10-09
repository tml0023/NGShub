#!/usr/bin/env Rscript
# Differential expression via tximport + DESeq2.
# Usage: run_deseq2.R <samplesheet.csv> <tx2gene.tsv>
# Skips (exits 0, no output) when fewer than 2 distinct conditions are present.
args <- commandArgs(trailingOnly = TRUE)
samplesheet_path <- args[1]
tx2gene_path <- args[2]

suppressMessages({
  library(tximport)
  library(DESeq2)
})

samples <- read.csv(samplesheet_path, stringsAsFactors = FALSE)

# No "condition" column at all is a real case, not just a hypothetical: the
# backend always adds one for illumina_rna runs, but a samplesheet written
# by hand for standalone CLI use (see README) may not have it.
if (!"condition" %in% names(samples)) {
  cat("No condition column in samplesheet; skipping differential expression.\n")
  quit(status = 0)
}

samples$condition <- trimws(samples$condition)
samples <- samples[!is.na(samples$condition) & samples$condition != "", ]

if (length(unique(samples$condition)) < 2) {
  cat("Fewer than 2 distinct conditions; skipping differential expression.\n")
  quit(status = 0)
}

files <- file.path(samples$sample, "quant.sf")
names(files) <- samples$sample
missing <- files[!file.exists(files)]
if (length(missing) > 0) {
  stop("Missing quant.sf for: ", paste(names(missing), collapse = ", "))
}

tx2gene <- read.table(tx2gene_path, header = FALSE, col.names = c("tx", "gene"))
# No ignoreTxVersion: tx2gene.tsv and the Salmon index's transcript names
# both come straight from the same GTF's transcript_id attribute, so they
# already match exactly -- ignoreTxVersion's version-suffix stripping is only
# symmetric on the quant-file side, which turns an exact match into a false
# mismatch here.
txi <- tximport(files, type = "salmon", tx2gene = tx2gene, dropInfReps = TRUE)

coldata <- data.frame(condition = factor(samples$condition), row.names = samples$sample)
dds <- DESeqDataSetFromTximport(txi, colData = coldata, design = ~condition)
# Any dispersion trend fit (parametric or mean) needs enough genes with
# varied dispersion to fit a curve -- both error out on very small gene sets
# (a tiny custom reference, a targeted panel). Fall back to per-gene
# dispersion estimates directly, DESeq2's own documented recovery path for
# exactly this case.
dds <- tryCatch(
  DESeq(dds),
  error = function(e) {
    message("Dispersion trend fit failed (likely too few genes: ", conditionMessage(e), "); ",
            "using per-gene dispersion estimates directly")
    dds <- estimateSizeFactors(dds)
    dds <- estimateDispersionsGeneEst(dds)
    dispersions(dds) <- mcols(dds)$dispGeneEst
    nbinomWaldTest(dds)
  }
)
res <- results(dds)
write.csv(as.data.frame(res[order(res$pvalue), ]), "deseq2_results.csv")

# PCA/heatmap are diagnostic extras built on top of the already-written,
# already-valuable DE results above -- variance stabilization's own trend
# fitting hits the same too-few-genes failure mode DESeq() did, with no
# documented manual-dispersion workaround for this step. Skip the plots
# rather than lose the DE results over a diagnostic-only failure.
plots_ok <- tryCatch(
  {
    vsd <- varianceStabilizingTransformation(dds, blind = TRUE)
    pdf("pca.pdf")
    print(plotPCA(vsd, intgroup = "condition"))
    dev.off()

    sample_dists <- dist(t(assay(vsd)))
    pdf("sample_distance_heatmap.pdf")
    heatmap(as.matrix(sample_dists))
    dev.off()
    TRUE
  },
  error = function(e) {
    message("Skipping PCA/heatmap (variance stabilization failed, likely too few genes: ",
            conditionMessage(e), ")")
    FALSE
  }
)

if (plots_ok) {
  cat("Wrote deseq2_results.csv, pca.pdf, sample_distance_heatmap.pdf\n")
} else {
  cat("Wrote deseq2_results.csv (PCA/heatmap skipped)\n")
}
