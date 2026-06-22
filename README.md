# Debian/Ubuntu Erlang Builds

APT repository serving Erlang/OTP built from source for Debian and Ubuntu (amd64 + arm64).

## Install

```sh
curl -fsSL https://jtdowney.github.io/erlang-builds/key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/erlang.gpg
echo "deb [signed-by=/usr/share/keyrings/erlang.gpg] https://jtdowney.github.io/erlang-builds $(. /etc/os-release; echo $VERSION_CODENAME) main" \
  | sudo tee /etc/apt/sources.list.d/erlang.list
sudo tee /etc/apt/preferences.d/erlang.pref <<'EOF'
Package: erlang*
Pin: origin jtdowney.github.io
Pin-Priority: 1001
EOF
sudo apt update && sudo apt install erlang
```

Optional: `erlang-dev`, `erlang-wx`, `erlang-odbc`.
