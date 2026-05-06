#!/usr/bin/env bash
set -euo pipefail

cd packages/bylaw_postgres
mix test.postgres "$@"
