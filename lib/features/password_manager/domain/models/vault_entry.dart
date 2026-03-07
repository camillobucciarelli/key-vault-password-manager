import 'package:equatable/equatable.dart';

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

  @override
  List<Object?> get props => [
    id,
    groupId,
    title,
    username,
    password,
    url,
    notes,
    customFields,
    attachments,
    otpUri,
  ];
}
