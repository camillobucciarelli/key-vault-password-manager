# 007A — Tasks

Order is mandatory. Milestone ends with reviewed source assets; all 007B
runtime/platform integration remains blocked.

- [x] **A001 — Canonical host lock.** Create `tool/app_icon_host.lock.json` with
      macOS 26.6/25G72, arm64/64-bit/cp314, CPython 3.14.6 executable path/hash,
      exact Pillow wheel URL/hash, Pillow 12.2.0, zlib 1.3.1.zlib-ng, FreeType
      2.14.3, `_imaging` arm64, and renderer contract from spec FR-2.
- [x] **A002 — Provision bootstrap.** Create `tool/bootstrap_app_icon_host.sh`.
      Verify host/Python before network; download only locked HTTPS wheel; verify
      SHA-256 before `pip install --no-index --no-deps` into
      `.dart_tool/app_icon_host/venv`; verify ABI/features/architecture afterward.
      Mismatch fails; no fallback wheel or silent venv replacement.
- [x] **A003 — Generator CLI and path safety.** Create
      `tool/build_app_icon_family.py` with `--print-toolchain`, `--check-sources`,
      required `--output PATH`, and read-only `--check --output PATH`. Generation
      accepts only a new absent leaf below an existing real safe parent. Reject
      raw lexical traversal before normalization, including `symlink/../leaf`,
      symlinks, dangling links, resolved-path drift, existing paths, root, home,
      repo root, `.git`, and unsafe parents. Read-only check must independently validate supplied
      existing directory with the same path rules and reject files/dangling
      symlinks before reading it. Add no default/publish/replace/delete/recover
      mode.
- [x] **A004 — Master/record validation.** Pin both source hashes; parse exact XML
      order/geometry/paints/transform; reject unknown structures. Record but do not
      edit ICONS x-bbox discrepancy. Compute authoritative union `[23,77]²` from
      centred transformed strokes, round caps/joins, hub, hand, and notches.
- [x] **A005 — Size-aware independent geometry oracle.** Implement
      Decimal/integer signed-distance predicates without Pillow drawing/resizing.
      Generate expected component masks only from this oracle; compare decoded
      raster extents, coverage, and mask tolerance independently from renderer
      helpers.
      At 1024 and compatible smaller sizes, derive stable one-final-pixel-margin
      component probes. At 16, derive expected fractional coverage ranges for
      component-centre/hand/ring pixels instead; project decoded RGB to actual
      8-bit component coverage and require every range/nonzero intended centre,
      threshold safe zone, and separate no-crop. Test transform order, centred
      stroke scaling, round caps/joins, bboxes, and quantization.
- [x] **A006 — Monochrome derivative and core rasters.** Derive monochrome SVG by
      replacing only hex paints; preserve transparent canvas, order, geometry,
      `fill="none"`, LF, final newline. Render validated full/foreground/monochrome
      targets at 4× and downsample once with pinned LANCZOS.
- [x] **A007 — App and extension bases.** Generate RGB `app-192.png`,
      `app-512.png`, and `ext-16/32/48/128.png` from full master. No alpha, extra
      padding, or corner rounding.
- [x] **A008 — Six state assets only.** Generate locked/no-host at 16/32/48. Base
      alpha is 115. Apply exact outer/ring/core values 4/1/2, 9/2/5, and 13/2/9
      with centres/insets from FR-6. Rings erase to alpha zero; cores are opaque
      `#a19786` or `#f6a06b`. Generate no 128 state or count-badge asset.
      Validate per-pixel analytic core/ring masks, exact extents/centre, reflected
      symmetry, and every quadrant with FR-6 size-aware antialias tolerances.
- [x] **A009 — Raster safety checks.** Build in-memory component/union coverage
      masks. Coverage ≥128 is ink and must fit Android safe band; coverage 1–127
      outside vector bbox is allowed halo. Independently assert zero outer-edge
      coverage/background or alpha and all size-compatible analytic probes.
- [x] **A010 — Review sheet and manifest.** Generate exact 1600×1200 RGB sheet
      with ready 16/32/48/128 and states 16/32/48. Write `SHA256SUMS` last with
      exactly 19 sorted lines: two masters + 17 payloads. Exclude manifest itself
      and `review-evidence.md`.
- [x] **A011 — Stdlib generator tests.** Create
      `tool/test_build_app_icon_family.py` using `unittest` and temporary
      directories only. Cover size-aware geometry oracle including 16 px
      fractional ranges, path rejection/absent-leaf acceptance, two-run byte
      determinism, exact 18-output inventory, independent 19-line manifest
      validation, subprocess toolchain/bootstrap attestation, metadata/state
      corruption, and component mutations at 48/1024.
      Run exactly:

      ```bash
      .dart_tool/app_icon_host/venv/bin/python -m unittest tool/test_build_app_icon_family.py
      ```

- [x] **A012 — Inventory acceptance.** Generate into a canonicalized temporary
      parent and absent child, then run read-only `--check --output`. Decode all 16
      PNGs and assert dimensions, bit depth, RGB/RGBA, sRGB/chunks,
      alpha/background/corners, size-aware analytic probes, threshold safe zone,
      permitted halo, separate no-crop, badge inventory/geometry/colours, and
      manifest coverage.
- [x] **A013 — Canonical determinism.** Set
      `tmp_dir="$(realpath "$(mktemp -d)")"`, print it immediately, then generate
      sequentially into absent `$tmp_dir/run-a` and `$tmp_dir/run-b`; check both;
      `cmp` manifests and `diff -rq` trees. Chain success with `&&`; remove temp
      only on success and print/preserve canonical temp path on failure. Use `rc`,
      not zsh's readonly `status`, for failure code.
- [x] **A014 — Review evidence and initial copy.** Generate a separate fresh
      review run; validate and inspect review PNG at 100%; complete reviewer, UTC
      date, host lock hash, host fingerprint, manifest/review hashes, exact unittest
      command/result, and checklist in `review-evidence.md`. Confirm
      both `test ! -e assets/logo/app_icon_family` and
      `test ! -L assets/logo/app_icon_family`, rejecting existing paths and
      dangling symlinks; copy validated run there once, then run read-only check.
      Generator never writes committed assets. Future regeneration uses a fresh
      temp directory and Git review owns replacement.
- [ ] **A015 — Repository verification.** Run `flutter analyze && flutter test`.
      Allow only four provision/generator/test files, exact 18 generated outputs,
      and `review-evidence.md` beyond this 007 spec set. From clean checkout, run
      read-only check against committed output and require porcelain status empty
      before and after.

## 007B gate — not tasks in this milestone

Do not edit `pubspec.yaml`, platform resources, web/Linux destinations, Flutter
UI, extension runtime/icon destinations, or old assets/references.

Every 007B slice depends on 001/002/007A. Welcome/database/unlock marks also wait
for 003; security/extension marks and badge runtime wait for 006; in-page overlay
mark waits for 009 only for that surface.

007B must set `web.generate: false`; byte-copy 192/512 to both normal/maskable
destinations; copy 48 favicon separately; keep
`desaturate_tinted_to_grayscale_ios: true`; generate no 128 state badge without
approval; and handle Linux through explicit packaging copy/compare/archive checks.
