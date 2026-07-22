class WatchConnectionService {
  Future<bool> checkConnection() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return false;
  }
}
