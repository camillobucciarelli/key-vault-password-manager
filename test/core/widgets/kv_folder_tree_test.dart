// spec-019 T015 (T-ONE-TREE) — the eight guarantees in
// `specs/019-vault-model-1a/contracts/folder-tree.md`, asserted by name.
//
// The tree has three hosts. These tests are what stops the second and third
// host from quietly growing their own behaviour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/theme/app_colors.dart';
import 'package:password_manager/core/theme/app_theme.dart';
import 'package:password_manager/core/widgets/kv_folder_tree.dart';

const _nodes = <KvFolderNode>[
  KvFolderNode(
    id: 'work',
    name: 'Work',
    count: 12,
    depth: 0,
    hasChildren: true,
    isExpanded: true,
  ),
  KvFolderNode(id: 'clients', name: 'Clients', count: 5, depth: 1),
  KvFolderNode(id: 'personal', name: 'Personal', count: 3, depth: 0),
];

void main() {
  late List<String> selected;
  late List<(String, bool)> toggled;
  late List<(String, KvFolderAction)> actions;

  setUp(() {
    selected = [];
    toggled = [];
    actions = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    KvFolderTreeMode mode = KvFolderTreeMode.filter,
    String? selectedId = 'work',
    bool withActions = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 236,
            child: KvFolderTree(
              nodes: _nodes,
              selectedId: selectedId,
              mode: mode,
              onSelect: selected.add,
              onToggleExpanded: (id, expanded) =>
                  toggled.add((id, expanded)),
              onRowAction: withActions
                  ? (id, action) => actions.add((id, action))
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('G1 — filter mode carries no action affordance', (tester) async {
    await pump(tester);
    expect(find.byType(PopupMenuButton<KvFolderAction>), findsNothing);
    expect(find.byTooltip('Folder actions'), findsNothing);
  });

  testWidgets('G2 — manage mode offers Rename, Move, Delete in that order', (
    tester,
  ) async {
    await pump(
      tester,
      mode: KvFolderTreeMode.manage,
      withActions: true,
    );
    expect(
      find.byType(PopupMenuButton<KvFolderAction>),
      findsNWidgets(_nodes.length),
    );

    await tester.tap(find.byTooltip('Folder actions').first);
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(PopupMenuItem<KvFolderAction>),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(labels, ['Rename', 'Move', 'Delete']);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(actions, [('work', KvFolderAction.rename)]);
  });

  testWidgets('G2 (amended) — a row that cannot be reparented offers Rename alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: KvFolderTree(
            nodes: const [
              KvFolderNode(
                id: 'root',
                name: 'Vault',
                count: 20,
                depth: 0,
                canReparent: false,
              ),
            ],
            selectedId: 'root',
            mode: KvFolderTreeMode.manage,
            onSelect: selected.add,
            onToggleExpanded: (id, expanded) => toggled.add((id, expanded)),
            onRowAction: (id, action) => actions.add((id, action)),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Folder actions'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Move'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('G2 — manage mode renders no chevron: the tree is fully open', (
    tester,
  ) async {
    await pump(tester, mode: KvFolderTreeMode.manage, withActions: true);
    expect(find.byTooltip('Collapse Work'), findsNothing);
    expect(find.byTooltip('Expand Work'), findsNothing);
  });

  testWidgets('G3 — the chevron appears only on nodes with children, and toggles only', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byTooltip('Collapse Work'), findsOneWidget);
    // Two childless nodes, no chevrons.
    expect(find.byTooltip('Expand Clients'), findsNothing);
    expect(find.byTooltip('Collapse Personal'), findsNothing);

    await tester.tap(find.byTooltip('Collapse Work'));
    await tester.pump();
    expect(toggled, [('work', false)]);
    expect(selected, isEmpty, reason: 'the chevron must not select (G3)');
  });

  testWidgets('G4 — activating a row selects and does not toggle', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Clients'));
    await tester.pump();
    expect(selected, ['clients']);
    expect(toggled, isEmpty);
  });

  testWidgets('G5 — one indentation level per depth, and nothing else', (
    tester,
  ) async {
    await pump(tester);
    final work = tester.getTopLeft(find.text('Work')).dx;
    final clients = tester.getTopLeft(find.text('Clients')).dx;
    final personal = tester.getTopLeft(find.text('Personal')).dx;
    expect(clients - work, KvFolderTree.indentPerDepth);
    expect(personal, work, reason: 'same depth, same inset');
  });

  testWidgets('G5 — manage mode adds no subtitle', (tester) async {
    await pump(tester, mode: KvFolderTreeMode.manage, withActions: true);
    // Three names and three counts, nothing else.
    expect(find.byType(Text), findsNWidgets(_nodes.length * 2));
  });

  testWidgets('G6 — the selected row is accent-200 with accent-800 semibold text', (
    tester,
  ) async {
    await pump(tester);
    final label = tester.widget<Text>(find.text('Work'));
    expect(label.style?.color, AppColors.accent800);
    expect(label.style?.fontWeight, FontWeight.w600);

    final fills = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .where((c) => c == AppColors.accent200);
    expect(fills, hasLength(1), reason: 'exactly one row reads as selected');
  });

  testWidgets('G6 — the same style appears in manage mode, unchanged', (
    tester,
  ) async {
    await pump(tester, mode: KvFolderTreeMode.manage, withActions: true);
    final label = tester.widget<Text>(find.text('Work'));
    expect(label.style?.color, AppColors.accent800);
    expect(label.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('G7 — chevron and row are both >= 44x44 and do not overlap', (
    tester,
  ) async {
    await pump(tester);
    final chevron = tester.getRect(find.byTooltip('Collapse Work'));
    expect(chevron.width, greaterThanOrEqualTo(44));
    expect(chevron.height, greaterThanOrEqualTo(44));

    final row = tester.getRect(
      find.ancestor(
        of: find.text('Work'),
        matching: find.byType(InkWell),
      ),
    );
    expect(row.height, greaterThanOrEqualTo(44));
    expect(
      chevron.overlaps(row),
      isFalse,
      reason: 'two overlapping targets are one target that guesses (R5)',
    );
  });

  testWidgets('G8 — every row publishes its selected state to semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(
      tester.getSemantics(
        find.ancestor(of: find.text('Work'), matching: find.byType(InkWell)),
      ),
      matchesSemantics(
        hasSelectedState: true,
        isSelected: true,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    // An unselected row says so rather than staying silent: it carries the
    // selected state and reports false.
    expect(
      tester.getSemantics(
        find.ancestor(
          of: find.text('Personal'),
          matching: find.byType(InkWell),
        ),
      ),
      matchesSemantics(
        hasSelectedState: true,
        isSelected: false,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    handle.dispose();
  });
}
