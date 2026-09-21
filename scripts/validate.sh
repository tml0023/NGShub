#!/usr/bin/env bash
# Run representative tool combinations against synthetic data with known
# variants, and check each resulting VCF against the truth set.
#
# Every tool offered in the UI appears in at least one configuration.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="${REPO_ROOT}/data/validate"
PYTHON="${PYTHON:-python3}"

export PATH="${HOME}/.local/bin:${PATH}"

if [[ ! -f "${TEST_DIR}/samplesheet.csv" ]]; then
    echo "==> Generating synthetic dataset"
    "${PYTHON}" "${REPO_ROOT}/scripts/make_test_data.py" --outdir "${TEST_DIR}"
fi

# label|trimmer|aligner|markduplicates|callers
CONFIGURATIONS=(
    "fastp+bwa+samtools+bcftools|fastp|bwa|samtools|bcftools"
    "trimgalore+bwamem2+gatk+haplotypecaller|trimgalore|bwamem2|gatk|haplotypecaller"
    "none+bowtie2+none+freebayes,bcftools|none|bowtie2|none|freebayes,bcftools"
)

failures=0

for entry in "${CONFIGURATIONS[@]}"; do
    IFS='|' read -r label trimmer aligner markdup callers <<< "${entry}"
    outdir="${TEST_DIR}/results/${label//[+,]/_}"

    echo
    echo "==> ${label}"
    if ! (cd "${REPO_ROOT}/pipeline" && nextflow run main.nf \
            -profile test,micromamba -ansi-log false \
            --input "${TEST_DIR}/samplesheet.csv" \
            --fasta "${TEST_DIR}/reference.fa" \
            --outdir "${outdir}" \
            --trimmer "${trimmer}" \
            --aligner "${aligner}" \
            --markduplicates "${markdup}" \
            --callers "${callers}" > "${outdir}.log" 2>&1); then
        echo "FAIL  ${label} (pipeline error; see ${outdir}.log)"
        failures=$((failures + 1))
        continue
    fi

    IFS=',' read -ra caller_list <<< "${callers}"
    for caller in "${caller_list[@]}"; do
        vcf=$(find "${outdir}/variants/${caller}" -name '*.vcf.gz' 2>/dev/null | head -1)
        if [[ -z "${vcf}" ]]; then
            echo "FAIL  ${label} (no VCF from ${caller})"
            failures=$((failures + 1))
            continue
        fi
        "${PYTHON}" "${REPO_ROOT}/scripts/compare_vcf.py" \
            "${TEST_DIR}/truth.vcf" "${vcf}" --label "${label} :: ${caller}" \
            || failures=$((failures + 1))
    done
done

echo
if (( failures > 0 )); then
    echo "${failures} check(s) failed"
    exit 1
fi
echo "All configurations passed"
