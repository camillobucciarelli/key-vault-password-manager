# Contract — router additions

Spec 018 owns the router. This spec adds one surface and one presentation and
changes nothing else about it (FR-019).

## New surface

`ManageFoldersSurface` — the single folder-management surface of DQ-6.

## New presentation

`VaultDialogPresentation` — a centred dialog over the vault. Justified in the
plan's Complexity Tracking.

## Presentation table — the only rows this spec adds

| Surface | `< 704` | `>= 704` |
| --- | --- | --- |
| `ManageFoldersSurface` | `VaultRoutePresentation` | `VaultDialogPresentation` |

The predicate is `layout.hasDetailPane`, which is already `width >= 704`. No new
threshold, no new constant.

## Guarantees

- **S1** — Every existing row of `presentationFor` is unchanged; a test asserts
  the table for all pre-existing surfaces at the spec-018 boundary widths.
- **S2** — The dialog adds no column. The width arithmetic of
  `VaultLayoutWidths` is untouched, and a test asserts the derived thresholds
  still equal the values `test/core/responsive/vault_layout_class_test.dart`
  pins today.
- **S3** — `ManageFoldersSurface` participates in the router's sessions,
  cancellation and results like every other surface; it is not opened by a bare
  `showDialog`.
- **S4** — Exactly one entry point exists per width (FR-006a), asserted by
  counting the affordances that open the surface.
