#!/usr/bin/env bash
set -euo pipefail

: "${GPG_PRIVATE_KEY:?}"
: "${GPG_PASSPHRASE:?}"
: "${PAGES_BASE_URL:?}"
: "${GH_TOKEN:?}"

rm -rf debs repo _site
mkdir -p debs repo/conf _site

for tag in $(gh release list --limit 200 --json tagName -q '.[].tagName' | grep '^OTP-'); do
  gh release download "$tag" --dir debs --pattern '*.deb' --clobber || true
done

export GNUPGHOME
GNUPGHOME=$(mktemp -d)
chmod 700 "$GNUPGHOME"
echo "allow-preset-passphrase" > "$GNUPGHOME/gpg-agent.conf"
echo "$GPG_PRIVATE_KEY" | gpg --batch --import
gpg-connect-agent reloadagent /bye
KEYGRIP=$(gpg --batch --with-keygrip --list-secret-keys | awk '/Keygrip/{print $3; exit}')
/usr/lib/gnupg/gpg-preset-passphrase --preset --passphrase "$GPG_PASSPHRASE" "$KEYGRIP"

(cd detect && gleam run -- distributions) > repo/conf/distributions
shopt -s nullglob
for deb in debs/*.deb; do
  codename=$(basename "$deb" | sed -E 's/.*-1[~.]([a-z]+)_.*/\1/')
  reprepro -b repo includedeb "$codename" "$deb"
done

cp -r repo/dists repo/pool _site/
gpg --armor --export > _site/key.gpg
sed "s|__BASE_URL__|${PAGES_BASE_URL}|g" site/index.html > _site/index.html
