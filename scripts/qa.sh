#!/usr/bin/env bash
set -euo pipefail

packages=(
  bylaw_db
  bylaw_ecto_query
  bylaw_postgres
  bylaw_credo
)

for package in "${packages[@]}"; do
  echo "==> packages/${package}"
  (
    cd "packages/${package}"
    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test "$@"
  )
done
