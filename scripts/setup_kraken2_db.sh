#!/usr/bin/env bash
# Download Kraken2's prebuilt "Viral" database (RefSeq viral, ~0.5 GB
# archive / ~1.1 GB extracted), needed by the targeted-influenza
# surveillance platforms for taxonomic composition screening.
#
# Deliberately NOT the full standard database (100+ GB) -- not practical on
# a single dev machine, and this app only needs viral-vs-not composition,
# not a full taxonomic census. That means this screens composition among
# viruses, not true host-genome depletion (no host genomes in this DB).
#
# Idempotent -- skips the download/extract if the DB already looks present.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KRAKEN2_DB_DIR="${NGSWEB_KRAKEN2_DB_DIR:-${REPO_ROOT}/data/kraken2_db}"
URL="https://genome-idx.s3.amazonaws.com/kraken/k2_viral_20260626.tar.gz"

mkdir -p "${KRAKEN2_DB_DIR}"

if [[ -s "${KRAKEN2_DB_DIR}/hash.k2d" ]]; then
    echo "==> Kraken2 viral DB already present in ${KRAKEN2_DB_DIR}"
    exit 0
fi

echo "==> Downloading Kraken2 viral DB (~0.5 GB)"
curl -fL --progress-bar -o "${KRAKEN2_DB_DIR}/k2_viral.tar.gz.part" "${URL}"
mv "${KRAKEN2_DB_DIR}/k2_viral.tar.gz.part" "${KRAKEN2_DB_DIR}/k2_viral.tar.gz"

echo "==> Extracting"
tar xzf "${KRAKEN2_DB_DIR}/k2_viral.tar.gz" -C "${KRAKEN2_DB_DIR}"
rm "${KRAKEN2_DB_DIR}/k2_viral.tar.gz"

echo
echo "Done. Kraken2 viral DB in ${KRAKEN2_DB_DIR}."
echo "Note: this is a periodically-rebuilt index named by build date -- if"
echo "${URL}"
echo "404s later, check https://benlangmead.github.io/aws-indexes/k2 for the"
echo "current \"Viral\" database link and update the URL above."
