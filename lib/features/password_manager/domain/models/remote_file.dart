import 'package:equatable/equatable.dart';

/// One remote object as the application sees it (spec 010 §Domain
/// vocabulary). Identity is the tuple `(providerId, id)`: opaque ids may
/// collide across providers, so callers never compare [id] alone.
///
/// [name] is display/fallback-create data, never identity.
/// [contentChecksum] is comparable to the local MD5 baseline when present;
/// a provider that cannot supply it returns `null` and the orchestrator
/// falls back to downloading and hashing the bytes.
class RemoteFile extends Equatable {
  const RemoteFile({
    required this.providerId,
    required this.id,
    required this.name,
    this.modifiedTime,
    this.contentChecksum,
    this.size,
  });

  final String providerId;
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final String? contentChecksum;

  /// Size in bytes when the provider reports it.
  final int? size;

  @override
  List<Object?> get props => [
    providerId,
    id,
    name,
    modifiedTime,
    contentChecksum,
    size,
  ];
}
