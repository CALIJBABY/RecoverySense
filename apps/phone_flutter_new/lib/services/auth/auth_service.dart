class AuthService {
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return email.trim().isNotEmpty && password.trim().isNotEmpty;
  }

  Future<bool> createAccount({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return email.trim().isNotEmpty && password.trim().length >= 6;
  }
}
