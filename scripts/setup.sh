#!/usr/bin/env bash
# Provision the ngs-web development environment.
#
# Creates a single conda environment holding the web stack (Python/FastAPI,
# Node) and the workflow engine (Nextflow, Java). Pipeline tools themselves are
# provisioned per-process by Nextflow at run time.
set -euo pipefail

ENV_NAME="${NGSWEB_ENV:-ngsweb}"
MICROMAMBA="${HOME}/.local/bin/micromamba"

if ! command -v conda >/dev/null 2>&1; then
    echo "conda not found. Install Miniconda or Miniforge first." >&2
    exit 1
fi

# micromamba resolves environments far faster than conda, and Nextflow can use
# it directly to build each process environment.
if [[ ! -x "${MICROMAMBA}" ]]; then
    echo "==> Installing micromamba"
    mkdir -p "${HOME}/.local/bin"
    arch="$(uname -m)"
    case "$(uname -s)-${arch}" in
        Darwin-arm64)  platform="osx-arm64" ;;
        Darwin-x86_64) platform="osx-64" ;;
        Linux-aarch64) platform="linux-aarch64" ;;
        Linux-x86_64)  platform="linux-64" ;;
        *) echo "Unsupported platform: $(uname -s)-${arch}" >&2; exit 1 ;;
    esac
    curl -Ls "https://micro.mamba.pm/api/micromamba/${platform}/latest" \
        | tar -xj -C /tmp bin/micromamba
    mv /tmp/bin/micromamba "${MICROMAMBA}"
    chmod +x "${MICROMAMBA}"
fi

echo "==> Creating conda environment '${ENV_NAME}'"
"${MICROMAMBA}" create -y -n "${ENV_NAME}" \
    -c conda-forge -c bioconda \
    python=3.11 fastapi uvicorn python-multipart \
    nextflow openjdk=21 nodejs=22

ENV_PREFIX="$("${MICROMAMBA}" env list | awk -v n="${ENV_NAME}" '$1 == n {print $NF}')"

# The openjdk package ships its JVM under lib/jvm; Nextflow needs `java` on PATH.
if [[ -x "${ENV_PREFIX}/lib/jvm/bin/java" && ! -e "${ENV_PREFIX}/bin/java" ]]; then
    ln -sf ../lib/jvm/bin/java "${ENV_PREFIX}/bin/java"
fi

echo "==> Installing frontend dependencies"
(cd "$(dirname "$0")/../frontend" && PATH="${ENV_PREFIX}/bin:${PATH}" npm install)

cat <<EOF

Setup complete.

  conda activate ${ENV_NAME}
  ./scripts/dev.sh

EOF
