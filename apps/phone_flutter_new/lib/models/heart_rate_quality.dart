class HeartRateQuality {
  const HeartRateQuality._();

  static const int valid = 0;
  static const int noReading = 1;
  static const int stale = 2;
  static const int offBody = 3;
  static const int noContact = 4;
  static const int unreliable = 5;
  static const int implausible = 6;
  static const int lowAccuracy = 7;

  static String reason(int code) {
    switch (code) {
      case valid:
        return 'valid';
      case noReading:
        return 'no_reading';
      case stale:
        return 'stale';
      case offBody:
        return 'off_body';
      case noContact:
        return 'no_contact';
      case unreliable:
        return 'unreliable';
      case implausible:
        return 'implausible';
      case lowAccuracy:
        return 'low_accuracy';
      default:
        return 'unknown';
    }
  }

  static bool isHardInvalid(int code) {
    return code == noReading ||
        code == stale ||
        code == offBody ||
        code == noContact ||
        code == unreliable ||
        code == implausible;
  }
}
