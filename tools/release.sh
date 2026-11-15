#!/usr/bin/env bash
# Cut a release: set VERSION in install.sh, point the README's install
# commands at the new tag, commit, and tag. Push afterwards with:
#   git push origin main vX.Y.Z
#
#   tools/release.sh 1.1.0
set -euo pipefail

new=${1:-}
[[ $new =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 X.Y.Z"; exit 1; }
cd "$(dirname "$0")/.."
[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first."; exit 1; }
git rev-parse -q --verify "refs/tags/v$new" >/dev/null && { echo "v$new already exists."; exit 1; }

old="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' install.sh)"
sed -i "s/^VERSION=\"$old\"$/VERSION=\"$new\"/" install.sh
sed -i "s#noctalia-installer/v$old/install.sh#noctalia-installer/v$new/install.sh#g" install.sh README.md
sed -i "s#git clone --branch v$old #git clone --branch v$new #g" README.md

bash -n install.sh
git commit -qam "Release v$new"
git tag -a "v$new" -m "noctalia-installer v$new"
echo "Tagged v$new (was v$old). Push with: git push origin main v$new"
