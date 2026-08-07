/// Moved out of `presentation/bloc/database_selection/database_selection_event.dart`
/// so the coordinator (domain-only imports, C-7) can reference it without
/// importing a BLoC event file. Re-exported from that file for source
/// compatibility with existing callers/tests.
enum RecentDatabaseRemovalMode { removeOnly, removeAndDeleteFile }
