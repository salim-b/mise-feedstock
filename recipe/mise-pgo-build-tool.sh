#!/usr/bin/env bash
# Wrapper so `scripts/pgo.bash` (which invokes `"$MISE_PGO_BUILD_TOOL" build ...` as a single executable) can
# drive `cargo auditable` instead of plain `cargo`.
set -euo pipefail
exec cargo auditable "$@"
