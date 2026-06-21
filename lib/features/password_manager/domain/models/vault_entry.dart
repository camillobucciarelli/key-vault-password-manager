import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

import 'vault_attachment.dart';
import 'vault_custom_field.dart';

class VaultEntry extends Equatable {
  const VaultEntry({
    required this.id,
    required this.groupId,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.customFields = const [],
    this.attachments = const [],
    this.otpUri,
    this.createdAt,
    this.updatedAt,
    this.lastPasswordChangedAt,
  });

  final String id;
  final String groupId;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final List<VaultCustomField> customFields;
  final List<VaultAttachment> attachments;
  final String? otpUri;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastPasswordChangedAt;

  @override
  List<Object?> get props => [
    id,
    groupId,
    title,
    username,
    RedactedValue(password),
    url,
    RedactedValue(notes, redaction: '<redacted notes>'),
    customFields,
    attachments,
    otpUri == null
        ? null
        : RedactedValue(otpUri, redaction: '<redacted otpUri>'),
    createdAt,
    updatedAt,
    lastPasswordChangedAt,
  ];

  @override
  String toString() {
    final otpSummary = otpUri == null ? 'null' : '<redacted>';
    return 'VaultEntry('
        'id: $id, '
        'groupId: $groupId, '
        'title: $title, '
        'username: $username, '
        'password: <redacted>, '
        'url: $url, '
        'notes: <redacted>, '
        'customFields: ${customFields.length}, '
        'attachments: ${attachments.length}, '
        'otpUri: $otpSummary, '
        'createdAt: $createdAt, '
        'updatedAt: $updatedAt, '
        'lastPasswordChangedAt: $lastPasswordChangedAt)';
  }
}
