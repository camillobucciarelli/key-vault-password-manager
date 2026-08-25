# 007A — App icon family review evidence

Complete this file after deterministic generation. Keep it outside
`assets/logo/app_icon_family/` and `SHA256SUMS`. Do not edit generated PNGs to add
review metadata.

## Review record

- **Status**: Approved
- **Reviewer**: Independent QA — OpenAI gpt-5.6-sol
- **Review date (UTC, YYYY-MM-DD)**: 2026-08-05
- **Branch/commit or tree identifier**: `feat/app-icon-family` at `85dcbea941ef`
  with uncommitted 007A implementation/output
- **Canonical host**: macOS 26.6 (25G72), arm64
- **Python**: CPython 3.14.6, cp314, 64-bit
- **Pillow wheel SHA-256**:
  `80b2da48193b2f33ed0c32c38140f9d3186583ce7d516526d462645fd98660ae`
- **Pillow/zlib/FreeType**: 12.2.0 / 1.3.1.zlib-ng / 2.14.3
- **`tool/app_icon_host.lock.json` SHA-256**:
  `b94009d8cba528f6f5ec970a1e710cd4fcba46602d9d3d2f8e21a922c1696a0b`
- **Generated `SHA256SUMS` SHA-256**:
  `ab03297f8c7b74e715deeff456e7531bea9dee4905895d54773ca57850e84eff`
- **Review-sheet SHA-256**:
  `b85767d5a346fdef00cd191b5a4b0017320fbbdddfa953f0fdaa78c30a776bb4`

## Automated checks

| Check | Command/evidence | Result |
| --- | --- | --- |
| Provisioned host | `./tool/bootstrap_app_icon_host.sh` | Passed; exact locked wheel and host verified |
| Toolchain fingerprint | `.dart_tool/app_icon_host/venv/bin/python tool/build_app_icon_family.py --print-toolchain` | Passed; canonical executable/venv/base Python/PIL attested; macOS 26.6/25G72, arm64, CPython 3.14.6/cp314, Pillow 12.2.0, zlib 1.3.1.zlib-ng, FreeType 2.14.3 |
| Master/XML/oracle | `.dart_tool/app_icon_host/venv/bin/python tool/build_app_icon_family.py --check-sources` | Passed; integer/Decimal component masks, decoded 16 px probe coverage, and mutation tests |
| Generated inventory and raster checks | `--check --output assets/logo/app_icon_family`; supplied path safety passed | Passed |
| Stdlib generator tests | `.dart_tool/app_icon_host/venv/bin/python -m unittest tool/test_build_app_icon_family.py` | Passed; 17 tests including per-size badge quadrant/ring/core mutations |
| Two-tree byte determinism | manifest `cmp` + `diff -rq`; generated tree also compared with committed output | Passed |
| Output path safety | direct and subprocess generation/check cases, including `symlink/../leaf` and dangling links | Passed |
| Checkout-clean read-only check | before/after porcelain empty | See "A015 closure" below — run post-merge on repinned host |
| Repository analysis/tests | `fvm flutter analyze`; `fvm flutter test` | Passed; analyze clean, all 224 tests passed |

## Visual review at 100%

Review `assets/logo/app_icon_family/review/app-icon-family-review.png` without
resampling.

| Requirement | Result | Notes |
| --- | --- | --- |
| Selected Combinatore identity is clear; no placeholder/current logo remains | Passed | |
| Circle, squircle, and rounded-square previews preserve complete mark | Passed | |
| Separate no-crop review shows no clipped ring, hand, hub, or notch | Passed | |
| Foreground/monochrome alpha edges are clean on white, peach, and dark | Passed | |
| Ready 16 px keeps hub, hand, and ring distinguishable | Passed | |
| Notches remain viable at each represented size | Passed | |
| Locked 16/32/48 states use visible neutral cores and transparent rings | Passed | |
| No-host 16/32/48 states use visible peach cores and transparent rings | Passed | |
| 16 px 1 px ring deviation is acceptable | Passed | |
| No 128 state badge is present | Passed | |
| Review sheet itself has no crop, scaling, or missing inventory cell | Passed | |

## Decision

- **Approved for 007B consumption**: Yes
- **Blocking findings**: None
- **Follow-up notes**: Checkout-clean read-only check completed; see "A015
  closure" below.

## A015 closure — host repin and checkout-clean check

The original review host (macOS 26.6/25G72, CPython 3.14.6) was no longer
available post-merge; the working machine had moved to macOS 26.6.2/25G83 with
a CPython 3.14.7 patch release at the same canonical path. Per FR-2 the
generator refuses to run on an unpinned host, so `tool/app_icon_host.lock.json`,
`tool/bootstrap_app_icon_host.sh`, `specs/007-app-icon-family/spec.md` (FR-2
table), `plan.md`, and `tasks.md` (A001) were repinned to this host deliberately,
following the same discipline as the `.fvmrc` Flutter pin. The Pillow wheel
entry (`pillow-12.2.0-cp314-cp314-macosx_11_0_arm64.whl`) was kept unchanged —
the `cp314` ABI tag is unaffected by the CPython patch bump.

- **Repinned host**: macOS 26.6.2 (25G83), arm64
- **Repinned Python**: CPython 3.14.7, cp314, 64-bit, executable
  `/opt/homebrew/opt/python@3.14/bin/python3.14`,
  SHA-256 `87d4df53fd91304be5bac391fb204643c36b7df2023c04a0953bcbc7d4fdf634`
- **Date (UTC, YYYY-MM-DD)**: 2026-08-25

| Check | Command | Result |
| --- | --- | --- |
| Bootstrap on repinned host | `tool/bootstrap_app_icon_host.sh` | Passed; wheel/host/ABI verified against updated lock |
| Toolchain fingerprint | `--print-toolchain` | Passed; macOS 26.6.2/25G83, CPython 3.14.7/cp314, Pillow 12.2.0, zlib 1.3.1.zlib-ng, FreeType 2.14.3 |
| Master/XML/oracle | `--check-sources` | Passed |
| Two-tree byte determinism | fresh `run-a`/`run-b`, each `--check`ed, `SHA256SUMS` `cmp` + `diff -rq` | Passed; byte-identical |
| Stdlib generator tests | `.dart_tool/app_icon_host/venv/bin/python -m unittest tool/test_build_app_icon_family.py` | Passed; 17/17 |
| Checkout-clean read-only check (A015, spec criterion 10) | `--check --output assets/logo/app_icon_family`; `git status --porcelain=v1` diffed before/after | Passed; committed output validates on repinned host, check made no additional change to tree state |
| Repository verification | `fvm flutter analyze && fvm flutter test` | Passed; analyze clean, 1405 tests passed |
