# Contributing

Thanks for your interest! This is a small, focused project — a Debian/Lightsail
WireGuard launch script with a CLI and an optional web portal.

## Layout

- `src/` — the canonical, editable sources.
- `lightsail-launch.sh` — **generated** by `build.sh` from `src/`. Don't edit it
  by hand; edit `src/` and rebuild.
- `tests/` — the test suite (`run.sh` runs everything).
- `docs/` — additional documentation.

## Dev workflow

```bash
# edit files under src/, then:
make build      # regenerate lightsail-launch.sh from src/
make test       # run the full suite (lint + build drift + wg-manage + portal)
make lint       # just syntax checks
```

Requirements: `bash`, `python3`, `curl`, and (optionally) `shellcheck`.

## Before opening a PR

1. `make build` — commit the regenerated `lightsail-launch.sh` alongside your
   `src/` change. CI fails if the bundle is stale.
2. `make test` — everything must pass. Add or update a test under `tests/` for
   any behaviour change.
3. Keep shell scripts `shellcheck`-clean (CI runs `shellcheck -S error`) and
   `set -euo pipefail`-safe; keep `portal.py` to the standard library (no pip
   dependencies — it must run on a stock Debian box).

## Scope

Favour changes that keep the project turnkey and dependency-light. Security
fixes and robustness improvements are especially welcome — see
[SECURITY.md](SECURITY.md).
