import 'dart:math';

/// A utility class for generating random strings and numbers
class RandomString {
  /// The random number generator
  static final Random _random = Random();

  /// Generates a random integer between [from] and [to] (inclusive)
  ///
  /// [from] is the minimum value (inclusive)
  /// [to] is the maximum value (inclusive)
  /// Returns a random integer between [from] and [to]
  static int randomBetween(int from, int to) {
    if (from > to) {
      throw ArgumentError('from must be less than or equal to to');
    }
    return from + _random.nextInt(to - from + 1);
  }

  /// Generates a random string of specified length
  ///
  /// [length] is the length of the string to generate
  /// [from] is the starting character code (inclusive)
  /// [to] is the ending character code (inclusive)
  /// Returns a random string of the specified length
  static String randomString(int length, {int from = 33, int to = 126}) {
    if (length <= 0) {
      throw ArgumentError('length must be greater than 0');
    }
    if (from > to) {
      throw ArgumentError('from must be less than or equal to to');
    }
    return String.fromCharCodes(
      List.generate(length, (_) => randomBetween(from, to)),
    );
  }

  /// Generates a random numeric string of specified length
  ///
  /// [length] is the length of the string to generate
  /// Returns a random string containing only digits
  static String randomNumeric(int length) {
    if (length <= 0) {
      throw ArgumentError('length must be greater than 0');
    }
    return randomString(length, from: 48, to: 57);
  }

  /// Generates a random alphabetic string of specified length
  ///
  /// [length] is the length of the string to generate
  /// Returns a random string containing only letters
  static String randomAlpha(int length) {
    if (length <= 0) {
      throw ArgumentError('length must be greater than 0');
    }
    return randomString(length, from: 65, to: 90);
  }

  /// Generates a random alphanumeric string of specified length
  ///
  /// [length] is the length of the string to generate
  /// Returns a random string containing letters and digits
  static String randomAlphaNumeric(int length) {
    if (length <= 0) {
      throw ArgumentError('length must be greater than 0');
    }
    return randomString(length, from: 48, to: 57) +
        randomString(length, from: 65, to: 90);
  }

  /// Returns the current time in milliseconds since epoch
  static int currentTimeMillis() {
    return DateTime.now().millisecondsSinceEpoch;
  }
}
