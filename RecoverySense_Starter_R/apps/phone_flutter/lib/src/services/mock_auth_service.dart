class MockAuthService {
  String currentEmail = 'participant@example.com';

  void signIn({required String email}) {
    currentEmail = email.trim().isEmpty ? 'participant@example.com' : email.trim();
  }

  void signOut() {
    currentEmail = 'participant@example.com';
  }
}
