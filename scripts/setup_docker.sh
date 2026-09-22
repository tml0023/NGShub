#!/usr/bin/env bash
# Install Docker Desktop -- needed only for the containerized tools (DragMap,
# DeepVariant, pbmarkdup, Clair3). Everything else in ngs-web works without it.
#
# Docker Desktop's first run needs one manual step no script can do for you:
# macOS will prompt you to grant it privileged access (for its network
# helper). You'll see that prompt when it launches -- accept it once.
set -euo pipefail

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "Docker is already installed and running. Nothing to do."
    exit 0
fi

os="$(uname -s)"

if [[ "${os}" != "Darwin" ]]; then
    cat <<'EOF'
This script only automates the macOS install. On Linux, install Docker
Engine directly (no "Desktop" GUI needed) -- see:
  https://docs.docker.com/engine/install/
Then add your user to the docker group and re-log in:
  sudo usermod -aG docker $USER
EOF
    exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
    cat <<'EOF'
Homebrew isn't installed. Either install it (https://brew.sh) and re-run this
script, or download Docker Desktop directly:
  https://www.docker.com/products/docker-desktop/
EOF
    exit 1
fi

# On Intel Macs in particular, Homebrew's cask installer needs to write to a
# few /usr/local subdirectories that sometimes end up root-owned (from an old
# system Python/Java install, or a prior sudo brew invocation). When that
# happens the cask install fails partway through with a plain "Permission
# denied" that's easy to misread as a Docker problem. Check up front instead
# of letting the install fail into that.
unwritable=()
for dir in /usr/local/share/man/man3 /usr/local/cli-plugins /usr/local/bin /usr/local/lib; do
    if [[ -d "${dir}" && ! -w "${dir}" ]]; then
        unwritable+=("${dir}")
    fi
done
if [[ ${#unwritable[@]} -gt 0 ]]; then
    echo "Homebrew needs write access to these directories, currently owned by another user:" >&2
    printf '  %s\n' "${unwritable[@]}" >&2
    echo >&2
    echo "Fix (needs your password once):" >&2
    for dir in "${unwritable[@]}"; do
        echo "  sudo chown -R \$(whoami) ${dir} && sudo chmod u+w ${dir}" >&2
    done
    echo >&2
    echo "Then re-run this script." >&2
    exit 1
fi

echo "==> Installing Docker Desktop via Homebrew"
brew install --cask docker

echo
echo "==> Launching Docker Desktop"
open -a Docker

cat <<'EOF'

Docker Desktop is launching. On first run, macOS will show a system dialog
asking Docker to grant itself privileged network access -- accept it, then
wait for the whale icon in the menu bar to show "Docker Desktop is running."

Once it's running:
  NGSWEB_NEXTFLOW_PROFILE=docker ./scripts/dev.sh

EOF
