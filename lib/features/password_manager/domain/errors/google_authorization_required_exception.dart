final class GoogleAuthorizationRequiredException implements Exception {
  const GoogleAuthorizationRequiredException();

  @override
  String toString() => 'Google authorization needs to be renewed.';
}
