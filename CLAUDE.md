# kit

Personal machine-setup tool: a bash CLI (`bin/kit`) plus one profile per machine under `hosts/`.

- Requirements: `SPEC.md` is the source of truth. Read it before changing anything.
- What gets installed on a host comes from its setup log (`docs/hosts/<host>/SETUP-LOG.md`). Don't add steps that aren't in the log, except SPEC §12.
- Core (`bin/`, `lib/`, `install.sh`, `modules/common/`) must run on bash 3.2 (macOS).
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, clean under `shellcheck`.
- State changes go through `run_cmd`/`run_sudo` so `--dry-run` works. Prompts read from `/dev/tty`.
- Safety rules in SPEC §8 are enforced in code and are never skipped by `--yes`.
- `install.sh` is the curl one-liner (SPEC §1.1): body inside `main()`, last line `main "$@"`.
- Tests: `shellcheck` + `bats tests/`.
