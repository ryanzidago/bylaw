#!/usr/bin/env bash
set -euo pipefail

packages=(
  bylaw_contract
  bylaw_test
  bylaw_core
  bylaw_db
  bylaw_ecto_query
  bylaw_html
  bylaw_postgres
  bylaw_credo
)

echo "qa running ..."

scripts/test-reject-main
scripts/test-remove-finished-pr-worktrees
scripts/test-pre-switch-hook

run_stage() {
  local stage="$1"
  shift

  local -a labels=()
  local -a outputs=()
  local -a pids=()
  local -a statuses=()

  local package
  for package in "${packages[@]}"; do
    labels+=("packages/${package}")

    local output
    output="$(mktemp)"
    outputs+=("${output}")

    (
      cd "packages/${package}"
      "$@"
    ) >"${output}" 2>&1 &

    pids+=("$!")
  done

  local failed=false
  local index
  for index in "${!pids[@]}"; do
    if wait "${pids[${index}]}"; then
      statuses[${index}]=0
    else
      statuses[${index}]=$?
      failed=true
    fi
  done

  if [[ "${failed}" == true ]]; then
    echo "==> failed: ${stage}"

    for index in "${!outputs[@]}"; do
      if [[ "${statuses[${index}]}" != 0 ]]; then
        echo
        echo "==> ${labels[${index}]}"
        cat "${outputs[${index}]}"
      fi
    done
  fi

  rm -f "${outputs[@]}"

  if [[ "${failed}" == true ]]; then
    exit 1
  fi
}

# Parallel deps.get runs share the Hex cache and can read each other's
# half-written tarballs on a cold cache, so fetch dependencies one at a time.
for package in "${packages[@]}"; do
  (cd "packages/${package}" && mix deps.get) || {
    echo "==> failed: deps.get (packages/${package})"
    exit 1
  }
done

# mix deps.get only warns about security advisories and retired packages;
# mix hex.audit exits non-zero on them, so a known advisory fails QA.
audit_failed=false
for package in "${packages[@]}"; do
  if ! output="$(cd "packages/${package}" && mix hex.audit 2>&1)"; then
    affected="$(
      printf '%s\n' "${output}" |
        sed -nE 's/^  ([a-z0-9_]+) [0-9][^ ]* - .*/\1/p' |
        sort -u |
        tr '\n' ' ' |
        sed 's/ $//'
    )"

    echo "==> failed: hex.audit (packages/${package})"
    printf '%s\n' "${output}"
    echo
    echo "Fix: cd packages/${package} && mix deps.update ${affected:-<package>}"
    echo "If the fixed version is outside a requirement in mix.exs, raise that"
    echo "requirement and note it in the CHANGELOG. To accept an advisory that"
    echo "does not apply, add its ID to hex: [ignore_advisories: [...]] in"
    echo "mix.exs with a comment explaining why."
    echo
    audit_failed=true
  fi
done

if [[ "${audit_failed}" == true ]]; then
  exit 1
fi

run_stage "format" mix format --check-formatted
run_stage "compile" mix compile --warnings-as-errors
run_stage "credo" mix credo --strict
run_stage "test" mix test "$@"
run_stage "docs" mix docs

# TODO(bylaw-ui-playwright-qa-broken-on-machine): the bylaw_ui browser suite
# fails on this machine even on clean main; re-enable this stage once the
# Playwright/Chromium environment is fixed.
echo "skipping bylaw_ui QA stage (bylaw-ui-playwright-qa-broken-on-machine)"
# (
#   cd "packages/bylaw_ui"
#   bun install --frozen-lockfile
#   bunx playwright-core install chromium
#   bun run qa
# )

echo "qa passed"
