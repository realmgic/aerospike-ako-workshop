#!/usr/bin/env bash
# Validate that workshop scripts source existing lib files.
set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

resolve_source_path() {
  local script_dir="$1"
  local suffix="$2"
  suffix="${suffix#/}"
  (
    cd "${script_dir}"
    cd "$(dirname "${suffix}")"
    echo "$(pwd)/$(basename "${suffix}")"
  )
}

check_source_path() {
  local script="$1"
  local suffix="$2"
  local script_dir resolved

  script_dir="$(cd "$(dirname "${script}")" && pwd)"
  resolved="$(resolve_source_path "${script_dir}" "${suffix}")"

  if [[ ! -f "${resolved}" ]]; then
    echo "FAIL ${script#${SCRIPTS_ROOT}/}: source '${suffix}' -> missing ${resolved}" >&2
    fail=1
  fi
}

while IFS= read -r script; do
  while IFS= read -r line; do
    suffix=""
    if [[ "${line}" =~ source\ \"\$\(dirname\ \"\$0\"\)([^\"]+)\" ]]; then
      suffix="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ source\ \"\$\{UPGRADE_DIR\}([^\"]+)\" ]]; then
      suffix="${BASH_REMATCH[1]}"
    fi
    [[ -n "${suffix}" ]] || continue
    check_source_path "${script}" "${suffix}"
  done < <(grep -E 'source "\$\(dirname "\$0"\)|source "\$\{UPGRADE_DIR\}' "${script}" || true)
done < <(find "${SCRIPTS_ROOT}" -name '*.sh' -type f | sort)

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi

echo "OK  all script lib source paths resolve under ${SCRIPTS_ROOT}"
