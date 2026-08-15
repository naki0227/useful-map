#!/bin/bash
# 配布用証明書を作り、CI へ渡せる .p12 に固める。
#
# クラウド署名は CI からだと権限エラーになるため、鍵をこちら側で持つ。
# 秘密鍵はここで生成したものだけで、Apple へは CSR しか送らない。
#
#   ASC_KEY_ID=... ASC_ISSUER_ID=... scripts/make-distribution-cert.sh <出力先>
set -euo pipefail

out="${1:?出力先ディレクトリを指定してください}"
mkdir -p "$out"
chmod 700 "$out"

openssl genrsa -out "$out/dist.key" 2048 2>/dev/null
openssl req -new -key "$out/dist.key" -out "$out/dist.csr" \
  -subj "/CN=Useful Map Distribution/C=JP" 2>/dev/null

echo "CSR を作成しました。App Store Connect へ送ります。"
