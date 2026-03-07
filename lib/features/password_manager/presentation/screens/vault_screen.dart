import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../../core/responsive/breakpoints.dart';
import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../injection_container.dart' as di;
import '../../domain/models/vault_custom_field.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/models/vault_group.dart';
import '../../domain/models/sync_conflict.dart';
import '../../domain/models/database_sync_status.dart';
import '../bloc/vault/vault_bloc.dart';
import '../bloc/vault/vault_event.dart';
import '../bloc/vault/vault_state.dart';
import '../utils/totp_utils.dart';
import '../widgets/android_autofill_action.dart';

class _VaultLayoutBreakpoints {
  const _VaultLayoutBreakpoints._();

  static const double tabletMax = Breakpoints.tablet;
  static const double compactPhone = 380;
  static const double searchSortStack = 620;
  static const double breadcrumbBarHeight = 40;
  static const double syncStripHeight = 44;
}

class _VaultUiTokens {
  const _VaultUiTokens._();

  static const double cardPadding = 14;
  static const double cardRadius = 18;
  static const double folderItemRadius = 12;
  static const double folderItemHeight = 56;
  static const double folderListSpacing = 8;
  static const double folderIconContainerSize = 32;
  static const double recordItemRadius = 12;
  static const double recordItemHeight = 62;
  static const double recordListSpacing = 8;
  static const Duration expandDuration = Duration(milliseconds: 280);
  static const Duration itemTransitionDuration = Duration(milliseconds: 190);
  static const Duration buttonTransitionDuration = Duration(milliseconds: 220);
  static const Duration chipTransitionDuration = Duration(milliseconds: 180);
  static const AnimationStyle expansionAnimationStyle = AnimationStyle(
    duration: expandDuration,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: Curves.easeInOutCubic,
  );
}

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key, required this.databasePath});

  final String databasePath;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<VaultBloc>(param1: databasePath)..add(const InitializeVault()),
      child: const _VaultView(),
    );
  }
}

class _VaultView extends StatelessWidget {
  const _VaultView();

  double _contentTopPadding(
    BuildContext context, {
    required bool isCompactLayout,
    required bool avoidAppBarOverlap,
  }) {
    if (avoidAppBarOverlap) {
      return isCompactLayout ? 8 : 12;
    }

    return MediaQuery.paddingOf(context).top +
        kToolbarHeight +
        _VaultLayoutBreakpoints.breadcrumbBarHeight +
        _VaultLayoutBreakpoints.syncStripHeight +
        (isCompactLayout ? 6 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isTabletViewport =
        viewportWidth >= Breakpoints.mobile &&
        viewportWidth < _VaultLayoutBreakpoints.tabletMax;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: !isTabletViewport,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            final current = state.currentGroup;
            if (current?.parentId == null) {
              return const SizedBox.shrink();
            }

            return IconButton(
              tooltip: 'Go to parent folder',
              onPressed: () {
                context.read<VaultBloc>().add(const OpenParentGroup());
              },
              icon: const Icon(AppIcons.back),
            );
          },
        ),
        title: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            final colorScheme = Theme.of(context).colorScheme;
            final title = state.currentGroup?.name;
            final resolvedTitle = (title == null || title.trim().isEmpty)
                ? 'Vault'
                : title;
            return Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _syncStatusColor(state.syncStatus, colorScheme),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(resolvedTitle, overflow: TextOverflow.ellipsis),
                ),
              ],
            );
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(
            _VaultLayoutBreakpoints.breadcrumbBarHeight +
                _VaultLayoutBreakpoints.syncStripHeight,
          ),
          child: BlocBuilder<VaultBloc, VaultState>(
            builder: (context, state) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BreadcrumbsBar(
                    groups: state.breadcrumbs(),
                    rootGroupId: state.rootGroupId,
                  ),
                  _SyncStatusStrip(state: state),
                ],
              );
            },
          ),
        ),
        actions: [
          const AndroidAutofillAction(),
          IconButton(
            tooltip: 'Open recycle bin',
            onPressed: () => _showRecycleBinDialog(context),
            icon: const Icon(AppIcons.delete),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              context.read<VaultBloc>().add(const RefreshVault());
            },
            icon: const Icon(AppIcons.refresh),
          ),
          BlocBuilder<VaultBloc, VaultState>(
            builder: (context, state) {
              final icon = switch (state.syncStatus) {
                DatabaseSyncStatus.syncing => AppIcons.sync,
                DatabaseSyncStatus.success => AppIcons.cloudDone,
                DatabaseSyncStatus.error => AppIcons.cloudOff,
                DatabaseSyncStatus.conflict => AppIcons.warning,
                DatabaseSyncStatus.disconnected => AppIcons.cloudOff,
                DatabaseSyncStatus.idle => AppIcons.cloud,
              };
              return PopupMenuButton<String>(
                tooltip: 'Drive sync',
                icon: Icon(icon),
                onSelected: (value) async {
                  switch (value) {
                    case 'connect':
                      context.read<VaultBloc>().add(const ConnectGoogleDrive());
                      break;
                    case 'disconnect':
                      context.read<VaultBloc>().add(
                        const DisconnectGoogleDrive(),
                      );
                      break;
                    case 'link':
                      context.read<VaultBloc>().add(
                        const LoadDriveRemoteFiles(),
                      );
                      final choice = await _showLinkDatabaseDialog(context);
                      if (choice != null && context.mounted) {
                        context.read<VaultBloc>().add(
                          LinkCurrentDatabaseToDrive(
                            remoteFileId: choice.remoteFileId,
                            remoteFileName: choice.remoteFileName,
                          ),
                        );
                      }
                      break;
                    case 'syncNow':
                      context.read<VaultBloc>().add(
                        const SyncCurrentDatabaseNow(),
                      );
                      break;
                    case 'toggleAutoSync':
                      context.read<VaultBloc>().add(
                        ToggleCurrentDatabaseAutoSync(!state.autoSyncEnabled),
                      );
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'Status: ${_syncStatusLabel(state.syncStatus)}',
                    ),
                  ),
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      state.linkedDriveFileName == null
                          ? 'Linked file: -'
                          : 'Linked file: ${state.linkedDriveFileName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      state.lastSyncAt == null
                          ? 'Last sync: never'
                          : 'Last sync: ${_formatSyncDateTime(state.lastSyncAt!)}',
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: state.isDriveConnected ? 'disconnect' : 'connect',
                    child: Text(
                      state.isDriveConnected
                          ? 'Disconnect Google Drive'
                          : 'Connect Google Drive',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'link',
                    child: Text('Link this database'),
                  ),
                  const PopupMenuItem(
                    value: 'syncNow',
                    child: Text('Sync now'),
                  ),
                  PopupMenuItem(
                    value: 'toggleAutoSync',
                    child: Text(
                      state.autoSyncEnabled
                          ? 'Disable auto-sync'
                          : 'Enable auto-sync',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppBackgrounds.gradient(context),
            ),
          ),
          BlocConsumer<VaultBloc, VaultState>(
            listener: (context, state) {
              if (state.errorMessage != null &&
                  state.errorMessage!.isNotEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
                context.read<VaultBloc>().add(const ClearVaultError());
              }
              if (state.infoMessage != null && state.infoMessage!.isNotEmpty) {
                final isSyncInfo =
                    state.infoMessage!.toLowerCase().contains('sync') ||
                    state.infoMessage!.toLowerCase().contains('google drive');
                if (isSyncInfo) {
                  _showSyncSnackBar(
                    context,
                    state.infoMessage!,
                    status: state.syncStatus,
                  );
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(state.infoMessage!)));
                }
                context.read<VaultBloc>().add(const ClearVaultInfo());
              }
              if (state.syncError != null && state.syncError!.isNotEmpty) {
                _showSyncSnackBar(
                  context,
                  state.syncError!,
                  status: state.syncStatus,
                );
                context.read<VaultBloc>().add(const ClearVaultSyncFeedback());
              }
              if (state.pendingSyncConflict != null) {
                _showSyncConflictDialog(context, state.pendingSyncConflict!);
              }
            },
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmallScreen =
                          constraints.maxWidth <
                          _VaultLayoutBreakpoints.tabletMax;
                      final isTabletLayout =
                          constraints.maxWidth >= Breakpoints.mobile &&
                          constraints.maxWidth <
                              _VaultLayoutBreakpoints.tabletMax;
                      final horizontalPadding =
                          constraints.maxWidth <
                              _VaultLayoutBreakpoints.compactPhone
                          ? 12.0
                          : 16.0;

                      if (isSmallScreen) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            _contentTopPadding(
                              context,
                              isCompactLayout: true,
                              avoidAppBarOverlap: isTabletLayout,
                            ),
                            horizontalPadding,
                            horizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Card(
                                child: ExpansionTile(
                                  expansionAnimationStyle:
                                      _VaultUiTokens.expansionAnimationStyle,
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  childrenPadding: const EdgeInsets.only(
                                    left: 10,
                                    right: 10,
                                    bottom: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      _VaultUiTokens.cardRadius,
                                    ),
                                  ),
                                  collapsedShape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      _VaultUiTokens.cardRadius,
                                    ),
                                  ),
                                  title: _SectionTitleWithCount(
                                    title: 'Folders',
                                    count: state.currentChildGroups.length,
                                    onAddPressed: () async {
                                      final name = await _showGroupDialog(
                                        context,
                                      );
                                      if (name != null &&
                                          name.trim().isNotEmpty &&
                                          context.mounted) {
                                        context.read<VaultBloc>().add(
                                          CreateVaultGroup(name.trim()),
                                        );
                                      }
                                    },
                                    addLabel: '+ Add folder',
                                    addTooltip: 'Add folder',
                                    addIcon: AppIcons.folderAdd,
                                  ),
                                  initiallyExpanded: false,
                                  children: [
                                    _GroupsCard(
                                      groups: state.currentChildGroups,
                                      isScrollablePage: true,
                                      showHeader: false,
                                      wrapWithCard: false,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Card(
                                child: ExpansionTile(
                                  expansionAnimationStyle:
                                      _VaultUiTokens.expansionAnimationStyle,
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  childrenPadding: const EdgeInsets.only(
                                    left: 10,
                                    right: 10,
                                    bottom: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      _VaultUiTokens.cardRadius,
                                    ),
                                  ),
                                  collapsedShape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      _VaultUiTokens.cardRadius,
                                    ),
                                  ),
                                  title: _SectionTitleWithCount(
                                    title: 'Records',
                                    count: state.visibleEntries.length,
                                    onAddPressed: () async {
                                      final payload = await _showEntryDialog(
                                        context,
                                      );
                                      if (payload != null && context.mounted) {
                                        context.read<VaultBloc>().add(
                                          CreateVaultEntry(
                                            title: payload.title,
                                            username: payload.username,
                                            password: payload.password,
                                            url: payload.url,
                                            notes: payload.notes,
                                            customFields: payload.customFields,
                                          ),
                                        );
                                      }
                                    },
                                    addLabel: '+ Add record',
                                    addTooltip: 'Add record',
                                    addIcon: AppIcons.cardAdd,
                                  ),
                                  initiallyExpanded: true,
                                  children: [
                                    _EntriesCard(
                                      entries: state.visibleEntries,
                                      groups: state.groups,
                                      searchQuery: state.searchQuery,
                                      sortBy: state.sortBy,
                                      keepSearchSortInline: isTabletLayout,
                                      isScrollablePage: true,
                                      showHeader: false,
                                      wrapWithCard: false,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          _contentTopPadding(
                            context,
                            isCompactLayout: false,
                            avoidAppBarOverlap: false,
                          ),
                          horizontalPadding,
                          horizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _GroupsCard(
                                      groups: state.currentChildGroups,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _EntriesCard(
                                      entries: state.visibleEntries,
                                      groups: state.groups,
                                      searchQuery: state.searchQuery,
                                      sortBy: state.sortBy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (state.isSaving)
                    Container(
                      color: Colors.black.withValues(alpha: 0.15),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitleWithCount extends StatelessWidget {
  const _SectionTitleWithCount({
    required this.title,
    required this.count,
    this.onAddPressed,
    this.addLabel,
    this.addTooltip,
    this.addIcon,
  });

  final String title;
  final int count;
  final Future<void> Function()? onAddPressed;
  final String? addLabel;
  final String? addTooltip;
  final IconData? addIcon;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedLabel = constraints.maxWidth < 320
            ? '+ Add'
            : (addLabel ?? '+ Add');

        final addButton = FilledButton.tonalIcon(
          onPressed: onAddPressed,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            animationDuration: _VaultUiTokens.buttonTransitionDuration,
          ),
          icon: Icon(addIcon ?? AppIcons.add, size: 18),
          label: Text(resolvedLabel),
        );

        if (constraints.maxWidth < 220) {
          return Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (onAddPressed != null)
                Tooltip(message: addTooltip, child: addButton),
              badge,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
            if (onAddPressed != null)
              Tooltip(message: addTooltip, child: addButton),
            const SizedBox(width: 8),
            badge,
          ],
        );
      },
    );
  }
}

class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({required this.state});

  final VaultState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _syncStatusColor(state.syncStatus, colorScheme);
    final statusIcon = switch (state.syncStatus) {
      DatabaseSyncStatus.syncing => AppIcons.sync,
      DatabaseSyncStatus.success => AppIcons.cloudDone,
      DatabaseSyncStatus.error => AppIcons.cloudOff,
      DatabaseSyncStatus.conflict => AppIcons.warning,
      DatabaseSyncStatus.disconnected => AppIcons.cloudOff,
      DatabaseSyncStatus.idle => AppIcons.cloud,
    };
    final label = state.lastSyncAt == null
        ? _syncStatusLabel(state.syncStatus)
        : '${_syncStatusLabel(state.syncStatus)} • ${_formatSyncDateTime(state.lastSyncAt!)}';
    final details = state.linkedDriveFileName == null
        ? label
        : '$label • ${state.linkedDriveFileName}';
    final canSyncNow = state.isDriveConnected && state.isDriveLinked;

    return SizedBox(
      height: _VaultLayoutBreakpoints.syncStripHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactAction = constraints.maxWidth < 560;

              final syncAction = compactAction
                  ? FilledButton.tonal(
                      onPressed: canSyncNow
                          ? () {
                              context.read<VaultBloc>().add(
                                const SyncCurrentDatabaseNow(),
                              );
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(40, 34),
                        padding: EdgeInsets.zero,
                        animationDuration:
                            _VaultUiTokens.buttonTransitionDuration,
                      ),
                      child: const Tooltip(
                        message: 'Sync now',
                        child: Icon(AppIcons.sync, size: 16),
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: canSyncNow
                          ? () {
                              context.read<VaultBloc>().add(
                                const SyncCurrentDatabaseNow(),
                              );
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        animationDuration:
                            _VaultUiTokens.buttonTransitionDuration,
                      ),
                      icon: const Icon(AppIcons.sync, size: 16),
                      label: const Text('Sync now'),
                    );

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(statusIcon, size: 12, color: statusColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    syncAction,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbsBar extends StatelessWidget {
  const _BreadcrumbsBar({required this.groups, required this.rootGroupId});

  final List<VaultGroup> groups;
  final String? rootGroupId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rootLabelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.9),
      fontWeight: FontWeight.w600,
    );
    final crumbStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.8),
      fontWeight: FontWeight.w500,
    );
    final currentStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );

    final path = groups.length > 1 ? groups.sublist(1) : const <VaultGroup>[];
    final children = <Widget>[
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: rootGroupId == null
            ? null
            : () {
                context.read<VaultBloc>().add(OpenGroup(rootGroupId!));
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.home, size: 16),
              const SizedBox(width: 4),
              Text('Vault', style: rootLabelStyle),
            ],
          ),
        ),
      ),
    ];

    for (var i = 0; i < path.length; i++) {
      final group = path[i];
      final isLast = i == path.length - 1;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            AppIcons.chevronRight,
            size: 16,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
      children.add(
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isLast
              ? null
              : () {
                  context.read<VaultBloc>().add(OpenGroup(group.id));
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              group.name,
              style: isLast ? currentStyle : crumbStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _VaultLayoutBreakpoints.breadcrumbBarHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: children),
        ),
      ),
    );
  }
}

Future<void> _showRecycleBinDialog(BuildContext context) async {
  final bloc = context.read<VaultBloc>();
  bloc.add(const LoadRecycleBinEntries());

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return BlocProvider.value(value: bloc, child: const _RecycleBinDialog());
    },
  );
}

class _RecycleBinDialog extends StatelessWidget {
  const _RecycleBinDialog();

  Future<void> _handleRecycleEntryAction(
    BuildContext context,
    VaultEntry entry,
    _RecycleBinEntryAction action,
  ) async {
    switch (action) {
      case _RecycleBinEntryAction.restore:
        context.read<VaultBloc>().add(RestoreVaultEntry(entry.id));
        break;
      case _RecycleBinEntryAction.deletePermanently:
        final confirmed = await _showDeleteConfirm(
          context,
          label:
              'Permanently delete this record? This action cannot be undone.',
          actionLabel: 'Delete forever',
        );
        if (confirmed && context.mounted) {
          context.read<VaultBloc>().add(DeleteVaultEntryPermanently(entry.id));
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Recycle bin')),
          IconButton(
            tooltip: 'Refresh recycle bin',
            onPressed: () {
              context.read<VaultBloc>().add(const LoadRecycleBinEntries());
            },
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      content: SizedBox(
        width: _dialogContentWidth(context, 620),
        height: _dialogContentHeight(context, 420),
        child: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            if (state.isRecycleBinLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.recycleBinEntries.isEmpty) {
              return const _RecycleBinEmptyState();
            }

            return ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: state.recycleBinEntries.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: _VaultUiTokens.recordListSpacing),
              itemBuilder: (context, index) {
                final entry = state.recycleBinEntries[index];
                return _RecycleBinEntryListItem(
                  entry: entry,
                  onSelectedAction: (action) {
                    _handleRecycleEntryAction(context, entry, action);
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            final isDisabled =
                state.isSaving ||
                state.isRecycleBinLoading ||
                state.recycleBinEntries.isEmpty;

            return FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              onPressed: isDisabled
                  ? null
                  : () async {
                      final confirmed = await _showDeleteConfirm(
                        context,
                        label:
                            'This will permanently remove all items from recycle bin. This action cannot be undone.',
                        actionLabel: 'Empty bin',
                      );
                      if (confirmed && context.mounted) {
                        context.read<VaultBloc>().add(const EmptyRecycleBin());
                      }
                    },
              icon: state.isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    )
                  : const Icon(AppIcons.deleteSweep),
              label: Text(
                state.recycleBinEntries.isEmpty
                    ? 'Empty bin'
                    : 'Empty bin (${state.recycleBinEntries.length})',
              ),
            );
          },
        ),
      ],
    );
  }
}

enum _RecycleBinEntryAction { restore, deletePermanently }

class _InteractiveItemSurface extends StatefulWidget {
  const _InteractiveItemSurface({
    required this.radius,
    required this.child,
    this.minHeight,
    this.onTap,
    this.baseColor,
    this.hoveredColor,
    this.baseBorderColor,
    this.hoveredBorderColor,
  });

  final double radius;
  final double? minHeight;
  final VoidCallback? onTap;
  final Color? baseColor;
  final Color? hoveredColor;
  final Color? baseBorderColor;
  final Color? hoveredBorderColor;
  final Widget child;

  @override
  State<_InteractiveItemSurface> createState() =>
      _InteractiveItemSurfaceState();
}

class _InteractiveItemSurfaceState extends State<_InteractiveItemSurface> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlight = _isHovered || _isFocused;
    final backgroundColor = highlight
        ? (widget.hoveredColor ?? colorScheme.surface.withValues(alpha: 0.82))
        : (widget.baseColor ?? colorScheme.surface.withValues(alpha: 0.74));
    final borderColor = highlight
        ? (widget.hoveredBorderColor ??
              colorScheme.primary.withValues(alpha: 0.32))
        : (widget.baseBorderColor ??
              colorScheme.outlineVariant.withValues(alpha: 0.7));

    final body = AnimatedContainer(
      duration: _VaultUiTokens.itemTransitionDuration,
      curve: Curves.easeOutCubic,
      constraints: widget.minHeight == null
          ? null
          : BoxConstraints(minHeight: widget.minHeight!),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: borderColor),
      ),
      child: widget.child,
    );

    return FocusableActionDetector(
      onShowFocusHighlight: (value) {
        if (_isFocused != value) {
          setState(() {
            _isFocused = value;
          });
        }
      },
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _isHovered = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isHovered = false;
          });
        },
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(widget.radius),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _RecycleBinEntryListItem extends StatelessWidget {
  const _RecycleBinEntryListItem({
    required this.entry,
    required this.onSelectedAction,
  });

  final VaultEntry entry;
  final ValueChanged<_RecycleBinEntryAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.recordItemRadius,
      minHeight: _VaultUiTokens.recordItemHeight,
      baseColor: colorScheme.surface.withValues(alpha: 0.72),
      hoveredColor: colorScheme.surface.withValues(alpha: 0.84),
      baseBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.7),
      hoveredBorderColor: colorScheme.error.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 8, bottom: 8),
        child: Row(
          children: [
            Container(
              width: _VaultUiTokens.folderIconContainerSize,
              height: _VaultUiTokens.folderIconContainerSize,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppIcons.delete,
                size: 18,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title.isEmpty ? '(Untitled)' : entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.username.isNotEmpty
                        ? entry.username
                        : (entry.url.isNotEmpty ? entry.url : 'No username'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<_RecycleBinEntryAction>(
              tooltip: 'Recycle bin actions',
              onSelected: onSelectedAction,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _RecycleBinEntryAction.restore,
                  child: Text('Restore'),
                ),
                PopupMenuItem(
                  value: _RecycleBinEntryAction.deletePermanently,
                  child: Text('Delete permanently'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecycleBinEmptyState extends StatelessWidget {
  const _RecycleBinEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcons.deleteSweep,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recycle bin is empty',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Deleted records will appear here until they are restored or removed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupsCard extends StatelessWidget {
  const _GroupsCard({
    required this.groups,
    this.isScrollablePage = false,
    this.showHeader = true,
    this.wrapWithCard = true,
  });

  final List<VaultGroup> groups;
  final bool isScrollablePage;
  final bool showHeader;
  final bool wrapWithCard;

  Future<void> _handleCreateFolder(BuildContext context) async {
    final name = await _showGroupDialog(context);
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      context.read<VaultBloc>().add(CreateVaultGroup(name.trim()));
    }
  }

  Future<void> _handleGroupAction(
    BuildContext context,
    VaultGroup group,
    _GroupAction action,
  ) async {
    switch (action) {
      case _GroupAction.rename:
        final name = await _showGroupDialog(
          context,
          initialName: group.name,
          title: 'Rename folder',
          actionLabel: 'Save',
        );
        if (name != null && name.trim().isNotEmpty && context.mounted) {
          context.read<VaultBloc>().add(
            RenameVaultGroup(groupId: group.id, newName: name.trim()),
          );
        }
        break;
      case _GroupAction.delete:
        final confirmed = await _showDeleteConfirm(
          context,
          label: 'Permanently delete this empty folder?',
          actionLabel: 'Delete forever',
        );
        if (confirmed && context.mounted) {
          context.read<VaultBloc>().add(DeleteVaultGroup(group.id));
        }
        break;
      case _GroupAction.move:
        final target = await _showMoveTargetDialog(
          context,
          groups,
          currentGroupId: group.id,
        );
        if (target != null && context.mounted) {
          context.read<VaultBloc>().add(
            MoveVaultGroup(groupId: group.id, targetGroupId: target),
          );
        }
        break;
    }
  }

  Widget _buildGroupsList(BuildContext context) {
    if (groups.isEmpty) {
      final emptyState = _FoldersEmptyState(
        onAddPressed: () => _handleCreateFolder(context),
      );

      if (isScrollablePage) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: emptyState,
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight > 32
              ? constraints.maxHeight - 32
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(child: emptyState),
            ),
          );
        },
      );
    }

    final list = ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: isScrollablePage,
      physics: isScrollablePage
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: groups.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _VaultUiTokens.folderListSpacing),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _FolderListItem(
          group: group,
          onOpen: () {
            context.read<VaultBloc>().add(OpenGroup(group.id));
          },
          onSelectedAction: (action) {
            _handleGroupAction(context, group, action);
          },
        );
      },
    );

    if (isScrollablePage) {
      return list;
    }

    return Scrollbar(child: list);
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(_VaultUiTokens.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            _SectionTitleWithCount(
              title: 'Folders',
              count: groups.length,
              onAddPressed: () => _handleCreateFolder(context),
              addLabel: '+ Add folder',
              addTooltip: 'Add folder',
              addIcon: AppIcons.folderAdd,
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
          ],
          if (isScrollablePage)
            _buildGroupsList(context)
          else
            Expanded(child: _buildGroupsList(context)),
        ],
      ),
    );

    if (!wrapWithCard) {
      return content;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_VaultUiTokens.cardRadius),
      ),
      child: content,
    );
  }
}

enum _GroupAction { rename, move, delete }

class _FolderListItem extends StatelessWidget {
  const _FolderListItem({
    required this.group,
    required this.onOpen,
    required this.onSelectedAction,
  });

  final VaultGroup group;
  final VoidCallback onOpen;
  final ValueChanged<_GroupAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.folderItemRadius,
      minHeight: _VaultUiTokens.folderItemHeight,
      onTap: onOpen,
      baseColor: colorScheme.surface.withValues(alpha: 0.74),
      hoveredColor: colorScheme.surface.withValues(alpha: 0.86),
      baseBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.7),
      hoveredBorderColor: colorScheme.primary.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6),
        child: Row(
          children: [
            Container(
              width: _VaultUiTokens.folderIconContainerSize,
              height: _VaultUiTokens.folderIconContainerSize,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppIcons.folder,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(
              AppIcons.chevronRight,
              size: 20,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            PopupMenuButton<_GroupAction>(
              tooltip: 'Folder actions',
              onSelected: onSelectedAction,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _GroupAction.rename,
                  child: Text('Rename'),
                ),
                PopupMenuItem(value: _GroupAction.move, child: Text('Move')),
                PopupMenuItem(
                  value: _GroupAction.delete,
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FoldersEmptyState extends StatelessWidget {
  const _FoldersEmptyState({required this.onAddPressed});

  final Future<void> Function() onAddPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(
              AppIcons.folderCopy,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No subfolders yet',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a folder to organize records in this area.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAddPressed,
            style: FilledButton.styleFrom(
              animationDuration: _VaultUiTokens.buttonTransitionDuration,
            ),
            icon: const Icon(AppIcons.folderAdd),
            label: const Text('+ Add folder'),
          ),
        ],
      ),
    );
  }
}

class _EntriesCard extends StatelessWidget {
  const _EntriesCard({
    required this.entries,
    required this.groups,
    required this.searchQuery,
    required this.sortBy,
    this.keepSearchSortInline = false,
    this.isScrollablePage = false,
    this.showHeader = true,
    this.wrapWithCard = true,
  });

  final List<VaultEntry> entries;
  final List<VaultGroup> groups;
  final String searchQuery;
  final VaultEntrySort sortBy;
  final bool keepSearchSortInline;
  final bool isScrollablePage;
  final bool showHeader;
  final bool wrapWithCard;

  Future<void> _handleCreateEntry(BuildContext context) async {
    final payload = await _showEntryDialog(context);
    if (payload != null && context.mounted) {
      context.read<VaultBloc>().add(
        CreateVaultEntry(
          title: payload.title,
          username: payload.username,
          password: payload.password,
          url: payload.url,
          notes: payload.notes,
          customFields: payload.customFields,
        ),
      );
    }
  }

  Future<void> _handleEntryAction(
    BuildContext context,
    VaultEntry entry,
    _EntryAction action,
  ) async {
    switch (action) {
      case _EntryAction.edit:
        final payload = await _showEntryDialog(context, initial: entry);
        if (payload != null && context.mounted) {
          context.read<VaultBloc>().add(
            UpdateVaultEntry(
              entryId: entry.id,
              title: payload.title,
              username: payload.username,
              password: payload.password,
              url: payload.url,
              notes: payload.notes,
              customFields: payload.customFields,
            ),
          );
        }
        break;
      case _EntryAction.move:
        final target = await _showMoveTargetDialog(context, groups);
        if (target != null && context.mounted) {
          context.read<VaultBloc>().add(
            MoveVaultEntry(entryId: entry.id, targetGroupId: target),
          );
        }
        break;
      case _EntryAction.attachments:
        await _showAttachmentsDialog(context, entry);
        break;
      case _EntryAction.showTotp:
        await _showTotpDialog(context, entry);
        break;
      case _EntryAction.delete:
        final confirmed = await _showDeleteConfirm(
          context,
          label: 'Move this record to recycle bin?',
        );
        if (confirmed && context.mounted) {
          context.read<VaultBloc>().add(DeleteVaultEntry(entry.id));
        }
        break;
    }
  }

  void _onSortChanged(BuildContext context, VaultEntrySort? value) {
    if (value == null) {
      return;
    }
    context.read<VaultBloc>().add(SetVaultSort(value));
  }

  Widget _buildSortField(BuildContext context) {
    return DropdownButtonFormField<VaultEntrySort>(
      initialValue: sortBy,
      isExpanded: true,
      icon: const Icon(AppIcons.chevronDown),
      decoration: const InputDecoration(labelText: 'Sort by'),
      onChanged: (value) => _onSortChanged(context, value),
      items: const [
        DropdownMenuItem(
          value: VaultEntrySort.titleAsc,
          child: Text('Title A-Z'),
        ),
        DropdownMenuItem(
          value: VaultEntrySort.titleDesc,
          child: Text('Title Z-A'),
        ),
        DropdownMenuItem(
          value: VaultEntrySort.usernameAsc,
          child: Text('Username A-Z'),
        ),
      ],
    );
  }

  Widget _buildEntriesList(BuildContext context) {
    if (entries.isEmpty) {
      final emptyState = _RecordsEmptyState(
        searchQuery: searchQuery,
        onAddPressed: () => _handleCreateEntry(context),
        onClearSearch: searchQuery.isNotEmpty
            ? () {
                context.read<VaultBloc>().add(const ClearVaultSearchQuery());
              }
            : null,
      );

      if (isScrollablePage) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: emptyState,
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight > 32
              ? constraints.maxHeight - 32
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(child: emptyState),
            ),
          );
        },
      );
    }

    final list = ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: isScrollablePage,
      physics: isScrollablePage
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _VaultUiTokens.recordListSpacing),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _RecordListItem(
          entry: entry,
          onOpen: () {
            _showRecordDetailsDialog(context, entry);
          },
          onSelectedAction: (action) {
            _handleEntryAction(context, entry, action);
          },
        );
      },
    );

    if (isScrollablePage) {
      return list;
    }

    return Scrollbar(child: list);
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(_VaultUiTokens.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            _SectionTitleWithCount(
              title: 'Records',
              count: entries.length,
              onAddPressed: () => _handleCreateEntry(context),
              addLabel: '+ Add record',
              addTooltip: 'Add record',
              addIcon: AppIcons.cardAdd,
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final shouldStackSearchSort =
                  !keepSearchSortInline &&
                  constraints.maxWidth <
                      _VaultLayoutBreakpoints.searchSortStack;

              final searchField = TextFormField(
                key: ValueKey('vault-search-$searchQuery'),
                initialValue: searchQuery,
                decoration: InputDecoration(
                  labelText: 'Search records',
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            context.read<VaultBloc>().add(
                              const ClearVaultSearchQuery(),
                            );
                          },
                          icon: const Icon(AppIcons.close),
                        )
                      : null,
                ),
                onChanged: (value) {
                  context.read<VaultBloc>().add(UpdateVaultSearchQuery(value));
                },
              );

              if (shouldStackSearchSort) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    _buildSortField(context),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: math.min(250, constraints.maxWidth * 0.38),
                    child: _buildSortField(context),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (isScrollablePage)
            _buildEntriesList(context)
          else
            Expanded(child: _buildEntriesList(context)),
        ],
      ),
    );

    if (!wrapWithCard) {
      return content;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_VaultUiTokens.cardRadius),
      ),
      child: content,
    );
  }
}

enum _EntryAction { edit, move, attachments, showTotp, delete }

Future<void> _copyTextToClipboard(
  BuildContext context, {
  required String text,
  required String successMessage,
}) async {
  if (text.isEmpty) {
    return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(successMessage)));
}

Future<void> _showRecordDetailsDialog(
  BuildContext context,
  VaultEntry entry,
) async {
  var passwordVisible = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final colorScheme = theme.colorScheme;
      final isCompactViewport =
          MediaQuery.sizeOf(dialogContext).width < Breakpoints.mobile;
      final customFields = entry.customFields
          .where((field) => !_isOtpFieldKey(field.key))
          .toList(growable: false);

      Widget credentialSection({
        required String label,
        required String value,
        required String emptyLabel,
        VoidCallback? onCopy,
        Widget? trailing,
      }) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  trailing ?? const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                value.isEmpty ? emptyLabel : value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: value.isEmpty
                      ? colorScheme.onSurface.withValues(alpha: 0.62)
                      : colorScheme.onSurface,
                ),
              ),
              if (onCopy != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: onCopy,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 34),
                      animationDuration:
                          _VaultUiTokens.buttonTransitionDuration,
                    ),
                    icon: const Icon(AppIcons.copy, size: 16),
                    label: Text('Copy $label'),
                  ),
                ),
              ],
            ],
          ),
        );
      }

      Widget customFieldsSection() {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Custom fields',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...customFields.asMap().entries.expand((entry) {
                final index = entry.key;
                final field = entry.value;
                final rows = <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field.key,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.78,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            SelectableText(
                              field.value.isEmpty ? 'Not set' : field.value,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: field.value.isEmpty
                                    ? colorScheme.onSurface.withValues(
                                        alpha: 0.62,
                                      )
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (field.value.isNotEmpty)
                        IconButton(
                          tooltip: 'Copy ${field.key}',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _copyTextToClipboard(
                              dialogContext,
                              text: field.value,
                              successMessage: '${field.key} copied.',
                            );
                          },
                          icon: const Icon(AppIcons.copy, size: 16),
                        ),
                    ],
                  ),
                ];

                if (index < customFields.length - 1) {
                  rows.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  );
                }

                return rows;
              }),
            ],
          ),
        );
      }

      return StatefulBuilder(
        builder: (context, setState) {
          final hiddenPassword = entry.password.isEmpty
              ? 'Not set'
              : '••••••••••••';
          final resolvedPassword = passwordVisible
              ? (entry.password.isEmpty ? 'Not set' : entry.password)
              : hiddenPassword;

          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompactViewport ? 12 : 26,
              vertical: isCompactViewport ? 14 : 24,
            ),
            title: Text(entry.title.isEmpty ? '(Untitled)' : entry.title),
            content: SizedBox(
              width: _dialogContentWidth(dialogContext, 500),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    credentialSection(
                      label: 'Username',
                      value: entry.username,
                      emptyLabel: 'No username',
                      onCopy: entry.username.isEmpty
                          ? null
                          : () {
                              _copyTextToClipboard(
                                dialogContext,
                                text: entry.username,
                                successMessage: 'Username copied.',
                              );
                            },
                    ),
                    const SizedBox(height: 10),
                    credentialSection(
                      label: 'Password',
                      value: resolvedPassword,
                      emptyLabel: 'No password',
                      onCopy: entry.password.isEmpty
                          ? null
                          : () {
                              _copyTextToClipboard(
                                dialogContext,
                                text: entry.password,
                                successMessage: 'Password copied.',
                              );
                            },
                      trailing: IconButton(
                        tooltip: passwordVisible
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: entry.password.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  passwordVisible = !passwordVisible;
                                });
                              },
                        icon: Icon(
                          passwordVisible ? AppIcons.eyeOff : AppIcons.eye,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    credentialSection(
                      label: 'URL',
                      value: entry.url,
                      emptyLabel: 'No URL',
                      onCopy: entry.url.isEmpty
                          ? null
                          : () {
                              _copyTextToClipboard(
                                dialogContext,
                                text: entry.url,
                                successMessage: 'URL copied.',
                              );
                            },
                    ),
                    const SizedBox(height: 10),
                    credentialSection(
                      label: 'Notes',
                      value: entry.notes,
                      emptyLabel: 'No notes',
                      onCopy: entry.notes.isEmpty
                          ? null
                          : () {
                              _copyTextToClipboard(
                                dialogContext,
                                text: entry.notes,
                                successMessage: 'Notes copied.',
                              );
                            },
                    ),
                    if (customFields.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      customFieldsSection(),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _RecordListItem extends StatelessWidget {
  const _RecordListItem({
    required this.entry,
    required this.onOpen,
    required this.onSelectedAction,
  });

  final VaultEntry entry;
  final VoidCallback onOpen;
  final ValueChanged<_EntryAction> onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _InteractiveItemSurface(
      radius: _VaultUiTokens.recordItemRadius,
      minHeight: _VaultUiTokens.recordItemHeight,
      onTap: onOpen,
      baseColor: colorScheme.surface.withValues(alpha: 0.74),
      hoveredColor: colorScheme.surface.withValues(alpha: 0.85),
      baseBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.7),
      hoveredBorderColor: colorScheme.secondary.withValues(alpha: 0.33),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6, top: 8, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _VaultUiTokens.folderIconContainerSize,
              height: _VaultUiTokens.folderIconContainerSize,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppIcons.key,
                size: 18,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title.isEmpty ? '(Untitled)' : entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.username.isEmpty
                        ? (entry.url.isEmpty ? 'No username' : entry.url)
                        : entry.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (entry.otpUri != null) ...[
                    const SizedBox(height: 7),
                    _TotpChip(otpUri: entry.otpUri!),
                  ],
                ],
              ),
            ),
            PopupMenuButton<_EntryAction>(
              tooltip: 'Record actions',
              onSelected: onSelectedAction,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _EntryAction.edit,
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: _EntryAction.move,
                  child: Text('Move'),
                ),
                const PopupMenuItem(
                  value: _EntryAction.attachments,
                  child: Text('Attachments'),
                ),
                PopupMenuItem(
                  value: _EntryAction.showTotp,
                  child: Text(
                    entry.otpUri == null ? 'OTP unavailable' : 'Show OTP',
                  ),
                ),
                const PopupMenuItem(
                  value: _EntryAction.delete,
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsEmptyState extends StatelessWidget {
  const _RecordsEmptyState({
    required this.searchQuery,
    required this.onAddPressed,
    this.onClearSearch,
  });

  final String searchQuery;
  final Future<void> Function() onAddPressed;
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSearchActive = searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSearchActive ? AppIcons.searchOff : AppIcons.key,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isSearchActive ? 'No records found' : 'No records yet',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            isSearchActive
                ? 'Try a different keyword or clear the search.'
                : 'Add a record to start storing credentials in this folder.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (isSearchActive && onClearSearch != null)
            OutlinedButton.icon(
              onPressed: onClearSearch,
              style: OutlinedButton.styleFrom(
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              icon: const Icon(AppIcons.close),
              label: const Text('Clear search'),
            )
          else
            FilledButton.icon(
              onPressed: onAddPressed,
              style: FilledButton.styleFrom(
                animationDuration: _VaultUiTokens.buttonTransitionDuration,
              ),
              icon: const Icon(AppIcons.cardAdd),
              label: const Text('+ Add record'),
            ),
        ],
      ),
    );
  }
}

class _EntryDialogPayload {
  const _EntryDialogPayload({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    required this.otpUri,
    required this.customFields,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String otpUri;
  final List<VaultCustomField> customFields;
}

Future<_EntryDialogPayload?> _showEntryDialog(
  BuildContext context, {
  VaultEntry? initial,
}) async {
  var title = initial?.title ?? '';
  var username = initial?.username ?? '';
  var password = initial?.password ?? '';
  var url = initial?.url ?? '';
  var notes = initial?.notes ?? '';
  var otpUri = initial?.otpUri ?? '';
  var customFieldsText =
      initial?.customFields
          .where((field) => !_isOtpFieldKey(field.key))
          .map((field) => '${field.key}=${field.value}')
          .join('\n') ??
      '';
  final formKey = GlobalKey<FormState>();
  var passwordVisible = false;

  final result = await showDialog<_EntryDialogPayload>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(initial == null ? 'Add record' : 'Edit record'),
            content: SizedBox(
              width: _dialogContentWidth(context, 500),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: title,
                        decoration: const InputDecoration(labelText: 'Title'),
                        onChanged: (value) => title = value,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Title is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: username,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                        onChanged: (value) => username = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: password,
                        obscureText: !passwordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                passwordVisible = !passwordVisible;
                              });
                            },
                            icon: Icon(
                              passwordVisible ? AppIcons.eyeOff : AppIcons.eye,
                            ),
                          ),
                        ),
                        onChanged: (value) => password = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: url,
                        decoration: const InputDecoration(labelText: 'URL'),
                        onChanged: (value) => url = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: notes,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(labelText: 'Notes'),
                        onChanged: (value) => notes = value,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        key: ValueKey('entry-otp-uri-$otpUri'),
                        initialValue: otpUri,
                        decoration: InputDecoration(
                          labelText: 'OTP URI (otpauth://...)',
                          suffixIcon: _supportsOtpQrScan()
                              ? IconButton(
                                  tooltip: 'Scan QR',
                                  onPressed: () async {
                                    final scannedOtpUri =
                                        await _scanOtpUriFromQr(context);
                                    if (scannedOtpUri == null) {
                                      return;
                                    }
                                    setState(() {
                                      otpUri = scannedOtpUri;
                                    });
                                  },
                                  icon: const Icon(AppIcons.qrCode),
                                )
                              : null,
                        ),
                        onChanged: (value) => otpUri = value,
                        validator: (value) => _validateOtpUri(value ?? ''),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: customFieldsText,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Custom fields (key=value, one per line)',
                        ),
                        onChanged: (value) => customFieldsText = value,
                        validator: (value) {
                          final parseError = _validateCustomFieldsText(
                            value ?? '',
                          );
                          return parseError;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }

                  Navigator.of(context).pop(
                    _EntryDialogPayload(
                      title: title.trim(),
                      username: username.trim(),
                      password: password,
                      url: url.trim(),
                      notes: notes.trim(),
                      otpUri: otpUri.trim(),
                      customFields: _buildCustomFields(
                        customFieldsText: customFieldsText,
                        otpUri: otpUri,
                      ),
                    ),
                  );
                },
                child: Text(initial == null ? 'Create' : 'Save'),
              ),
            ],
          );
        },
      );
    },
  );
  return result;
}

bool _supportsOtpQrScan() {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}

Future<String?> _scanOtpUriFromQr(BuildContext context) async {
  if (!_supportsOtpQrScan()) {
    return null;
  }

  return showDialog<String>(
    context: context,
    builder: (_) => const _OtpQrScannerDialog(),
  );
}

String? _validateCustomFieldsText(String text) {
  final seen = <String>{};
  final lines = text.split('\n');
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      return 'Invalid custom field format. Use key=value.';
    }

    final key = line.substring(0, separatorIndex).trim();
    if (key.isEmpty) {
      return 'Custom field key cannot be empty.';
    }

    final normalized = key.toLowerCase();
    if (seen.contains(normalized)) {
      return 'Custom field keys must be unique.';
    }
    seen.add(normalized);
  }

  return null;
}

String? _validateOtpUri(String otpUri) {
  final trimmed = otpUri.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !trimmed.startsWith('otpauth://')) {
    return 'OTP URI must start with otpauth://';
  }

  return null;
}

bool _isOtpFieldKey(String key) {
  final normalized = key.toLowerCase().trim();
  return normalized == 'otp' ||
      normalized == 'totp' ||
      normalized == 'otpauth' ||
      normalized.contains('otp');
}

List<VaultCustomField> _buildCustomFields({
  required String customFieldsText,
  required String otpUri,
}) {
  final fields = _parseCustomFields(
    customFieldsText,
  ).where((field) => !_isOtpFieldKey(field.key)).toList(growable: true);

  final trimmedOtpUri = otpUri.trim();
  if (trimmedOtpUri.isNotEmpty) {
    fields.add(VaultCustomField(key: 'otp', value: trimmedOtpUri));
  }

  return fields;
}

List<VaultCustomField> _parseCustomFields(String text) {
  final fields = <VaultCustomField>[];
  final lines = text.split('\n');
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    if (key.isEmpty) {
      continue;
    }
    fields.add(VaultCustomField(key: key, value: value));
  }
  return fields;
}

Future<String?> _showGroupDialog(
  BuildContext context, {
  String? initialName,
  String title = 'Create folder',
  String actionLabel = 'Create',
}) async {
  var name = initialName ?? '';
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: _dialogContentWidth(context, 380),
          child: Form(
            key: formKey,
            child: TextFormField(
              initialValue: initialName ?? '',
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Folder name'),
              onChanged: (value) => name = value,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Folder name is required.';
                }
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }
              Navigator.of(context).pop(name.trim());
            },
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );
  return result;
}

Future<bool> _showDeleteConfirm(
  BuildContext context, {
  required String label,
  String actionLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm delete'),
        content: Text(label),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

Future<String?> _showMoveTargetDialog(
  BuildContext context,
  List<VaultGroup> groups, {
  String? currentGroupId,
}) async {
  String selectedGroupId;
  final options = groups
      .where((group) => group.id != currentGroupId)
      .toList(growable: false);

  if (options.isEmpty) {
    return null;
  }
  selectedGroupId = options.first.id;

  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Move to folder'),
            content: DropdownButtonFormField<String>(
              initialValue: selectedGroupId,
              isExpanded: true,
              icon: const Icon(AppIcons.chevronDown),
              items: options
                  .map(
                    (group) => DropdownMenuItem(
                      value: group.id,
                      child: Text(group.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  selectedGroupId = value;
                });
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selectedGroupId),
                child: const Text('Move'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showAttachmentsDialog(
  BuildContext context,
  VaultEntry entry,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Attachments'),
        content: SizedBox(
          width: _dialogContentWidth(dialogContext, 520),
          child: entry.attachments.isEmpty
              ? const Text('No attachments for this record.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    final attachment = entry.attachments[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.attachment),
                      title: Text(attachment.name),
                      subtitle: Text(_formatBytes(attachment.size)),
                      trailing: PopupMenuButton<_AttachmentAction>(
                        onSelected: (action) async {
                          if (!dialogContext.mounted) {
                            return;
                          }

                          switch (action) {
                            case _AttachmentAction.export:
                              final directory = await FilePicker.platform
                                  .getDirectoryPath();
                              if (directory != null && dialogContext.mounted) {
                                dialogContext.read<VaultBloc>().add(
                                  ExportVaultAttachment(
                                    entryId: entry.id,
                                    attachmentKey: attachment.key,
                                    destinationDirectory: directory,
                                  ),
                                );
                                Navigator.of(dialogContext).pop();
                              }
                              break;
                            case _AttachmentAction.remove:
                              final confirmed = await _showDeleteConfirm(
                                dialogContext,
                                label: 'Remove attachment ${attachment.name}?',
                                actionLabel: 'Remove',
                              );
                              if (confirmed && dialogContext.mounted) {
                                dialogContext.read<VaultBloc>().add(
                                  RemoveVaultAttachment(
                                    entryId: entry.id,
                                    attachmentKey: attachment.key,
                                  ),
                                );
                                Navigator.of(dialogContext).pop();
                              }
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _AttachmentAction.export,
                            child: Text('Export'),
                          ),
                          PopupMenuItem(
                            value: _AttachmentAction.remove,
                            child: Text('Remove'),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemCount: entry.attachments.length,
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                allowMultiple: false,
                withData: false,
              );
              final path = result?.files.single.path;
              if (path != null && dialogContext.mounted) {
                dialogContext.read<VaultBloc>().add(
                  AddVaultAttachment(entryId: entry.id, filePath: path),
                );
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Add attachment'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _showTotpDialog(BuildContext context, VaultEntry entry) async {
  if (entry.otpUri != null) {
    await _showTotpUriDialog(context, entry.otpUri!);
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('OTP'),
        content: const Text('No valid OTP URI configured for this record.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _showTotpUriDialog(BuildContext context, String otpUri) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('OTP'),
        content: _TotpDialogContent(otpUri: otpUri),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _OtpQrScannerDialog extends StatefulWidget {
  const _OtpQrScannerDialog();

  @override
  State<_OtpQrScannerDialog> createState() => _OtpQrScannerDialogState();
}

class _OtpQrScannerDialogState extends State<_OtpQrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _isHandlingCapture = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan OTP QR'),
      content: SizedBox(
        width: _dialogContentWidth(context, 320),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) async {
                if (_isHandlingCapture) {
                  return;
                }

                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue?.trim();
                  if (value == null || value.isEmpty) {
                    continue;
                  }

                  _isHandlingCapture = true;
                  if (value.startsWith('otpauth://')) {
                    if (context.mounted) {
                      Navigator.of(context).pop(value);
                    }
                    return;
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('QR does not contain a valid OTP URI.'),
                      ),
                    );
                  }
                  _isHandlingCapture = false;
                  return;
                }
              },
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TotpDialogContent extends StatefulWidget {
  const _TotpDialogContent({required this.otpUri});

  final String otpUri;

  @override
  State<_TotpDialogContent> createState() => _TotpDialogContentState();
}

class _TotpDialogContentState extends State<_TotpDialogContent> {
  late Timer _timer;
  DateTime _nowUtc = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nowUtc = DateTime.now().toUtc();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totpData = TotpUtils.fromOtpAuthUri(widget.otpUri, _nowUtc);
    if (totpData == null) {
      return const Text('Invalid OTP URI.');
    }

    return SizedBox(
      width: _dialogContentWidth(context, 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            totpData.code,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontFeatures: const []),
          ),
          const SizedBox(height: 8),
          Text('Expires in ${totpData.remainingSeconds}s'),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              animationDuration: _VaultUiTokens.buttonTransitionDuration,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: totpData.code));
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('OTP copied.')));
            },
            icon: const Icon(AppIcons.copy),
            label: const Text('Copy code'),
          ),
        ],
      ),
    );
  }
}

class _TotpChip extends StatefulWidget {
  const _TotpChip({required this.otpUri});

  final String otpUri;

  @override
  State<_TotpChip> createState() => _TotpChipState();
}

class _TotpChipState extends State<_TotpChip> {
  late Timer _timer;
  DateTime _nowUtc = DateTime.now().toUtc();
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nowUtc = DateTime.now().toUtc();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = TotpUtils.fromOtpAuthUri(widget.otpUri, _nowUtc);
    if (data == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final highlighted = _isHovered || _isFocused;

    return FocusableActionDetector(
      onShowFocusHighlight: (value) {
        if (_isFocused != value) {
          setState(() {
            _isFocused = value;
          });
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _isHovered = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isHovered = false;
          });
        },
        child: AnimatedScale(
          duration: _VaultUiTokens.chipTransitionDuration,
          curve: Curves.easeOutCubic,
          scale: highlighted ? 1.02 : 1,
          child: InkWell(
            onTap: () async {
              await _showTotpUriDialog(context, widget.otpUri);
            },
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: _VaultUiTokens.chipTransitionDuration,
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: highlighted
                      ? colorScheme.secondary.withValues(alpha: 0.35)
                      : colorScheme.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
              child: Chip(
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                backgroundColor: highlighted
                    ? colorScheme.secondaryContainer.withValues(alpha: 0.75)
                    : colorScheme.secondaryContainer.withValues(alpha: 0.55),
                label: Text('Show OTP (${data.remainingSeconds}s)'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _AttachmentAction { export, remove }

double _dialogContentWidth(BuildContext context, double preferredWidth) {
  final viewport = MediaQuery.sizeOf(context).width;
  final availableWidth = viewport - 56;
  if (availableWidth < 280) {
    return viewport - 24;
  }
  return math.min(preferredWidth, availableWidth);
}

double _dialogContentHeight(BuildContext context, double preferredHeight) {
  final viewport = MediaQuery.sizeOf(context).height;
  final availableHeight = viewport - 140;
  return math.min(preferredHeight, availableHeight);
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _LinkDatabaseChoice {
  const _LinkDatabaseChoice._({this.remoteFileId, this.remoteFileName});

  final String? remoteFileId;
  final String? remoteFileName;

  factory _LinkDatabaseChoice.existing(String remoteFileId) {
    return _LinkDatabaseChoice._(remoteFileId: remoteFileId);
  }

  factory _LinkDatabaseChoice.newFile(String? remoteFileName) {
    return _LinkDatabaseChoice._(remoteFileName: remoteFileName);
  }
}

Future<_LinkDatabaseChoice?> _showLinkDatabaseDialog(
  BuildContext context,
) async {
  final controller = TextEditingController();
  var useExisting = false;
  String? selectedExistingId;

  final result = await showDialog<_LinkDatabaseChoice?>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final state = context.watch<VaultBloc>().state;
          final remoteFiles = state.remoteDriveFiles;

          if (selectedExistingId == null && remoteFiles.isNotEmpty) {
            selectedExistingId = remoteFiles.first.id;
          }

          return AlertDialog(
            title: const Text('Link current database'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Create new'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Use existing'),
                      ),
                    ],
                    selected: {useExisting},
                    onSelectionChanged: (selection) {
                      setState(() {
                        useExisting = selection.first;
                      });
                    },
                  ),
                ),
                if (!useExisting)
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Remote filename (optional)',
                      hintText: 'my-vault.kdbx',
                    ),
                  ),
                const SizedBox(height: 12),
                if (useExisting)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Use existing Drive file',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                if (useExisting)
                  state.isLoadingRemoteDriveFiles
                      ? const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: CircularProgressIndicator(),
                        )
                      : remoteFiles.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('No files found in appDataFolder.'),
                        )
                      : DropdownButton<String>(
                          isExpanded: true,
                          icon: const Icon(AppIcons.chevronDown),
                          value: selectedExistingId,
                          items: remoteFiles
                              .map(
                                (file) => DropdownMenuItem<String>(
                                  value: file.id,
                                  child: Text(
                                    file.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            setState(() {
                              selectedExistingId = value;
                            });
                          },
                        ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (useExisting) {
                    if (selectedExistingId == null ||
                        selectedExistingId!.isEmpty) {
                      return;
                    }
                    Navigator.of(
                      dialogContext,
                    ).pop(_LinkDatabaseChoice.existing(selectedExistingId!));
                    return;
                  }

                  Navigator.of(
                    dialogContext,
                  ).pop(_LinkDatabaseChoice.newFile(controller.text.trim()));
                },
                child: const Text('Link'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}

Future<void> _showSyncConflictDialog(
  BuildContext context,
  SyncConflict conflict,
) async {
  final resolution = await showDialog<SyncConflictResolution>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Sync conflict detected'),
        content: Text(
          'The local database and Drive file "${conflict.driveFileName}" both changed. Choose what to keep.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(SyncConflictResolution.cancel),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SyncConflictResolution.useRemote),
            child: const Text('Use remote'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SyncConflictResolution.keepLocal),
            child: const Text('Keep local'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) {
    return;
  }

  context.read<VaultBloc>().add(const ClearVaultSyncFeedback());

  if (resolution == null || resolution == SyncConflictResolution.cancel) {
    return;
  }

  context.read<VaultBloc>().add(SyncCurrentDatabaseNow(resolution: resolution));
}

String _syncStatusLabel(DatabaseSyncStatus status) {
  return switch (status) {
    DatabaseSyncStatus.idle => 'Idle',
    DatabaseSyncStatus.syncing => 'Syncing',
    DatabaseSyncStatus.success => 'Synced',
    DatabaseSyncStatus.error => 'Error',
    DatabaseSyncStatus.conflict => 'Conflict',
    DatabaseSyncStatus.disconnected => 'Disconnected',
  };
}

Color _syncStatusColor(DatabaseSyncStatus status, ColorScheme colorScheme) {
  return switch (status) {
    DatabaseSyncStatus.idle => colorScheme.outline,
    DatabaseSyncStatus.syncing => colorScheme.primary,
    DatabaseSyncStatus.success => AppColors.success,
    DatabaseSyncStatus.error => colorScheme.error,
    DatabaseSyncStatus.conflict => AppColors.warning,
    DatabaseSyncStatus.disconnected => colorScheme.outline,
  };
}

void _showSyncSnackBar(
  BuildContext context,
  String message, {
  required DatabaseSyncStatus status,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final background = switch (status) {
    DatabaseSyncStatus.success => AppColors.success,
    DatabaseSyncStatus.conflict => AppColors.warning,
    DatabaseSyncStatus.error => theme.colorScheme.error,
    DatabaseSyncStatus.syncing => theme.colorScheme.primary,
    DatabaseSyncStatus.idle => theme.colorScheme.surfaceContainerHighest,
    DatabaseSyncStatus.disconnected =>
      theme.colorScheme.surfaceContainerHighest,
  };

  final foreground = switch (status) {
    DatabaseSyncStatus.error => theme.colorScheme.onError,
    DatabaseSyncStatus.idle => theme.colorScheme.onSurface,
    DatabaseSyncStatus.disconnected => theme.colorScheme.onSurface,
    _ => Colors.white,
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: foreground)),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        closeIconColor: foreground,
      ),
    );
}

String _formatSyncDateTime(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}
