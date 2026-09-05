import 'package:equatable/equatable.dart';

/// Safe display summary of the connected cloud storage account: a label the
/// UI can show and, when the provider can assert it, an email. Never a token,
/// credential or SDK account object.
class StorageAccountSummary extends Equatable {
  const StorageAccountSummary({required this.displayLabel, this.email});

  final String displayLabel;
  final String? email;

  @override
  List<Object?> get props => [displayLabel, email];
}
