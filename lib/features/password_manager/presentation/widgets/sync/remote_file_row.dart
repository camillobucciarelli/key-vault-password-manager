import 'package:flutter/material.dart';

import '../../../../../core/theme/app_glyph.dart';
import '../../../../../core/theme/keyvault_colors.dart';
import '../../../../../core/widgets/kv_icon.dart';
import '../../../../../core/widgets/kv_list_row.dart';
import '../../../../../core/widgets/kv_tag.dart';
import '../../../domain/models/drive_remote_file.dart';

/// FR-2 / T8: one row per `DriveRemoteFile` — name, `modifiedTime`, and an
/// already-linked warning `KvTag` when the file id appears in another
/// `DatabaseSyncMapping` ([isLinkedElsewhere], AC4).
///
/// `DriveRemoteFile` does not carry a file-size field today (only id, name,
/// modifiedTime, md5Checksum) — this row therefore does not show one; the
/// mock's "2.4 MB" is illustrative, not backed by a real field. See the
/// final report for this gap.
class RemoteFileRow extends StatelessWidget {
  const RemoteFileRow({
    super.key,
    required this.file,
    required this.selected,
    required this.isLinkedElsewhere,
    this.onTap,
  });

  final DriveRemoteFile file;
  final bool selected;
  final bool isLinkedElsewhere;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final subtitleParts = <String>[
      if (file.modifiedTime != null)
        'Modified ${_formatDate(file.modifiedTime!)}',
      if (isLinkedElsewhere) 'linked to another database',
    ];

    return KvListRow(
      title: file.name,
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.surfaceNested,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: KvIcon(
          glyph: AppGlyph.fileText,
          size: 18,
          color: colors.textSecondary,
        ),
      ),
      trailing: isLinkedElsewhere
          ? const KvTag(label: 'Linked', variant: KvTagVariant.attention)
          : _selectionDot(colors, selected),
    );
  }

  Widget _selectionDot(KeyVaultColors colors, bool selected) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.actionEmphasis : null,
        border: selected ? null : Border.all(color: colors.divider, width: 1.5),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = value.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
