/// Defines the screen width breakpoints for responsive layouts.
class Breakpoints {
  Breakpoints._();

  /// Maximum width for mobile devices.
  static const double mobile = 600;

  /// Maximum width for tablet devices.
  static const double tablet = 1024;
}

/// spec-018 FR-002b: the vault's normative column widths, one value per
/// column. These come from the adopted design (model 1a) as reconciled on
/// 2026-08-28; see `specs/018-desktop-vault-navigation/spec.md` §Design
/// decisions. They are single values, not ranges: the `76` rail and `352`
/// list that appear in some artboards are corrected drift, not variants.
class VaultColumns {
  VaultColumns._();

  /// Icon rail, fixed.
  static const double rail = 72;

  /// Folder column, fixed. Shown only from [VaultLayoutWidths.folderPane] up.
  static const double folders = 236;

  /// Records list column, fixed.
  static const double list = 330;

  /// On wide windows the folder and list columns grow with the surplus
  /// (15% / 30% of it) up to these caps; the rest goes to the detail pane.
  /// Below the caps' reach the normative widths above still hold exactly.
  static const double foldersMax = 340;
  static const double listMax = 520;

  /// The detail pane and the editor flex, but never below this.
  static const double detailMin = 300;

  /// Generator column, fixed. Divider on its *left*, unlike every other
  /// column, which carries it on the right.
  static const double generator = 290;

  /// Every column is separated by a 1 px divider, never a shadow.
  static const double divider = 1;
}

/// spec-018 FR-002a/FR-002d: the vault's layout thresholds, each written as
/// its derivation from [VaultColumns] rather than as a bare constant.
///
/// These are the ONLY vault layout thresholds. Anything else comparing a
/// width to pick a presentation is the defect spec-018 removes — the previous
/// code carried an unexplained `708`, which was this arithmetic done with the
/// old (since corrected) rail width of 76.
class VaultLayoutWidths {
  VaultLayoutWidths._();

  /// At or above this, the detail lives in a persistent pane beside the list.
  /// Below it, the detail is pushed over the list.
  ///
  /// `72 (rail) + 330 (list) + 300 (detail min) + 2 dividers = 704`
  static const double detailPane =
      VaultColumns.rail +
      VaultColumns.list +
      VaultColumns.detailMin +
      2 * VaultColumns.divider;

  /// At or above this, the folder column joins the strip.
  ///
  /// 2026-08-31 (user direction): raised from the bare sum of the column
  /// minima (`72 + 236 + 330 + 300 + 3 dividers = 941`) to 1024 — at 941
  /// three columns fit arithmetically but read as cramped, so the folder
  /// column now waits for a genuinely wide window.
  static const double folderPane = 1024;

  /// At or above this, an open generator is a column rather than a sheet over
  /// the editor. Below it the sheet is a declared fallback, not an accident
  /// (FR-002e).
  ///
  /// `72 + 330 + 300 + 290 (generator) + 3 dividers = 995`
  static const double generatorColumn =
      VaultColumns.rail +
      VaultColumns.list +
      VaultColumns.detailMin +
      VaultColumns.generator +
      3 * VaultColumns.divider;

  /// The folder column and the generator column coexist only from here up. At
  /// the 1024 design baseline they never do — which is what the arithmetic in
  /// the spec's design-decisions section proved.
  ///
  /// `72 + 236 + 330 + 290 + 300 + 4 dividers = 1232`
  static const double foldersAndGenerator =
      VaultColumns.rail +
      VaultColumns.folders +
      VaultColumns.list +
      VaultColumns.generator +
      VaultColumns.detailMin +
      4 * VaultColumns.divider;
}

/// spec-018 FR-002/FR-002a: the single classification every vault navigation
/// decision consults.
///
/// The shell computes this once from the **window** width and passes it down.
/// No descendant may re-measure its own `BoxConstraints` to decide how a
/// surface is presented — that capability is exactly the defect spec-018
/// removes (D2: three components each answered "is this wide?" differently).
enum VaultLayoutClass {
  /// Bottom tab bar; the records list fills the width; the detail pushes.
  narrowTabBar,

  /// Icon rail instead of the tab bar; the list still fills the remaining
  /// width and the detail still pushes. Chrome differs from [narrowTabBar];
  /// **presentation does not**, which is what keeps mobile behaviour intact
  /// across the 600 boundary.
  narrowRail,

  /// Rail + records list + persistent detail pane.
  wide,

  /// Rail + folder column + records list + persistent detail pane.
  wideWithFolders;

  /// Total and monotonic over every non-negative width.
  static VaultLayoutClass fromWidth(double width) {
    if (width < Breakpoints.mobile) return VaultLayoutClass.narrowTabBar;
    if (width < VaultLayoutWidths.detailPane) {
      return VaultLayoutClass.narrowRail;
    }
    if (width < VaultLayoutWidths.folderPane) return VaultLayoutClass.wide;
    return VaultLayoutClass.wideWithFolders;
  }

  /// True when the detail is a pane beside the list rather than a pushed
  /// screen. The **only** predicate allowed to select pane over push.
  bool get hasDetailPane =>
      this == VaultLayoutClass.wide || this == VaultLayoutClass.wideWithFolders;

  /// True when the folder column is part of the strip.
  bool get hasFolderPane => this == VaultLayoutClass.wideWithFolders;

  /// True when the bottom tab bar carries the destinations.
  bool get hasTabBar => this == VaultLayoutClass.narrowTabBar;
}
