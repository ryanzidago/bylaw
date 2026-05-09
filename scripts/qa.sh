#!/usr/bin/env bash
set -euo pipefail

packages=(
  bylaw
  bylaw_db
  bylaw_ecto_query
  bylaw_postgres
  bylaw_credo
)

echo "qa running ..."

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

run_stage "deps.get" mix deps.get
run_stage "format" mix format --check-formatted
run_stage "compile" mix compile --warnings-as-errors
run_stage "test" mix test "$@"
run_stage "docs" mix docs

echo "qa passed"
