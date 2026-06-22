#!/usr/bin/env bash
set -euo pipefail

OTP_VERSION="${OTP_VERSION:?set OTP_VERSION}"
CODENAME="${CODENAME:?set CODENAME}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential devscripts equivs ca-certificates curl xz-utils file

curl -fsSL -o /tmp/otp.tar.gz \
  "https://github.com/erlang/otp/releases/download/OTP-${OTP_VERSION}/otp_src_${OTP_VERSION}.tar.gz"

rm -rf build && mkdir -p build
tar -xzf /tmp/otp.tar.gz -C build --strip-components=1
cp -r debian build/debian
cd build

cat > debian/changelog <<EOF
erlang (${OTP_VERSION}-1~${CODENAME}) ${CODENAME}; urgency=medium

  * Automated build of Erlang/OTP ${OTP_VERSION} for ${CODENAME}.

 -- erlang-builds <noreply@example.com>  $(date -uR)
EOF

mk-build-deps -i -t "apt-get -y --no-install-recommends" debian/control
rm -f erlang-build-deps_*.deb erlang-build-deps_*.buildinfo erlang-build-deps_*.changes

dpkg-buildpackage -b -us -uc

cd ..
rm -rf out && mkdir -p out
mv ./*.deb out/
ls -l out/
