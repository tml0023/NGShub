#!/usr/bin/env bash
# Download hg38 and hg19 reference genomes, their matching BQSR known-sites
# resources (dbSNP138, Mills gold-standard indels), and matching gene
# annotations (GTF) for the RNA-seq platforms.
#
# ~10 GB total. Idempotent -- already-downloaded files are skipped, so it's
# safe to re-run after an interruption.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFERENCES_DIR="${NGSWEB_REFERENCES_DIR:-${REPO_ROOT}/data/references}"
KNOWN_SITES_DIR="${NGSWEB_KNOWN_SITES_DIR:-${REPO_ROOT}/data/known_sites}"

mkdir -p "${REFERENCES_DIR}" "${KNOWN_SITES_DIR}/hg38" "${KNOWN_SITES_DIR}/hg19"

# fetch <url> <destination>
# Skips the download if the destination already exists and is non-empty --
# does not verify checksums, just presence, so a partial prior failure needs
# the file removed manually before re-running.
fetch() {
    local url="$1" dest="$2"
    if [[ -s "${dest}" ]]; then
        echo "  already have $(basename "${dest}")"
        return
    fi
    echo "  fetching $(basename "${dest}")"
    curl -fL --progress-bar -o "${dest}.part" "${url}"
    mv "${dest}.part" "${dest}"
}

echo "==> hg38 (GRCh38, UCSC chr-prefixed contigs)"
if [[ -s "${REFERENCES_DIR}/hg38.fa" ]]; then
    echo "  already have hg38.fa"
else
    fetch "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz" \
        "${REFERENCES_DIR}/hg38.fa.gz"
    echo "  decompressing hg38.fa.gz"
    gunzip "${REFERENCES_DIR}/hg38.fa.gz"
fi

echo "==> hg19 (GRCh37, Broad b37-style bare contigs -- matches the known-sites bundle below)"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg19/v0/Homo_sapiens_assembly19.fasta" \
    "${REFERENCES_DIR}/hg19.fa"

echo "==> hg38 known-sites (dbSNP138, Mills gold-standard indels)"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dbsnp138.vcf.gz" \
    "${KNOWN_SITES_DIR}/hg38/dbsnp138.vcf.gz"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dbsnp138.vcf.gz.tbi" \
    "${KNOWN_SITES_DIR}/hg38/dbsnp138.vcf.gz.tbi"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz" \
    "${KNOWN_SITES_DIR}/hg38/mills_indels.vcf.gz"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg38/v0/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz.tbi" \
    "${KNOWN_SITES_DIR}/hg38/mills_indels.vcf.gz.tbi"

echo "==> hg19/b37 known-sites (dbSNP138, Mills gold-standard indels)"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg19/v0/dbsnp_138.b37.vcf.gz" \
    "${KNOWN_SITES_DIR}/hg19/dbsnp138.vcf.gz"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg19/v0/dbsnp_138.b37.vcf.gz.tbi" \
    "${KNOWN_SITES_DIR}/hg19/dbsnp138.vcf.gz.tbi"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg19/v0/Mills_and_1000G_gold_standard.indels.b37.vcf.gz" \
    "${KNOWN_SITES_DIR}/hg19/mills_indels.vcf.gz"
fetch "https://storage.googleapis.com/gcp-public-data--broad-references/hg19/v0/Mills_and_1000G_gold_standard.indels.b37.vcf.gz.tbi" \
    "${KNOWN_SITES_DIR}/hg19/mills_indels.vcf.gz.tbi"

echo "==> hg38 gene annotation (GENCODE, chr-prefixed -- matches hg38.fa)"
if [[ -s "${REFERENCES_DIR}/hg38.gtf" ]]; then
    echo "  already have hg38.gtf"
else
    fetch "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_44/gencode.v44.annotation.gtf.gz" \
        "${REFERENCES_DIR}/hg38.gtf.gz"
    echo "  decompressing hg38.gtf.gz"
    gunzip "${REFERENCES_DIR}/hg38.gtf.gz"
fi

echo "==> hg19/b37 gene annotation (Ensembl GRCh37, bare contig names -- matches hg19.fa)"
if [[ -s "${REFERENCES_DIR}/hg19.gtf" ]]; then
    echo "  already have hg19.gtf"
else
    fetch "https://ftp.ensembl.org/pub/grch37/release-87/gtf/homo_sapiens/Homo_sapiens.GRCh37.87.gtf.gz" \
        "${REFERENCES_DIR}/hg19.gtf.gz"
    echo "  decompressing hg19.gtf.gz"
    gunzip "${REFERENCES_DIR}/hg19.gtf.gz"
fi

echo
echo "Done. References in ${REFERENCES_DIR}, known-sites in ${KNOWN_SITES_DIR}."
echo "Note: hg19.fa uses bare contig names (1, not chr1) -- deliberate, it matches"
echo "the known-sites bundle. Don't swap in a UCSC-style chr-prefixed hg19 fasta;"
echo "GATK's sequence-dictionary validation will reject the mismatch outright."
