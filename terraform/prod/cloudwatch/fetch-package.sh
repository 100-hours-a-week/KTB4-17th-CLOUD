#!/usr/bin/env bash
set -euo pipefail
logging_root="$(cd "$(dirname "$0")" && pwd)"
artifact="lambda-promtail-v1.0.1.zip"
expected_sha256="2a436a30772ac638f715dd240784f787b9f0c745ba292a49cd23d132c477fd13"
mkdir -p "$logging_root/dist"
package_temp="$(mktemp "$logging_root/dist/.download.XXXXXX")"
trap 'rm -f "$package_temp"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 --retry 2 \
  --output "$package_temp" \
  "https://github.com/grafana/lambda-promtail/releases/download/v1.0.1/$artifact"
printf '%s  %s\n' "$expected_sha256" "$package_temp" | shasum -a 256 --check
mv "$package_temp" "$logging_root/dist/$artifact"
