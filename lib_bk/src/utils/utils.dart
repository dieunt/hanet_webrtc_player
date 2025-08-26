import 'dart:math';

// --- LogUtil --- (từ log_util.dart)
class LogUtil {
  static String _separator = "=";
  static String _split =
      "$_separator$_separator$_separator$_separator$_separator$_separator$_separator$_separator$_separator";
  static String _title = "###common_utils###";
  static bool _isDebug = true;
  static int _limitLength = 800;
  static String _startLine = "$_split$_title$_split";
  static String _endLine = "$_split$_separator$_separator$_separator$_split";

  static void init(
      {String title = "", bool isDebug = false, int limitLength = 100}) {
    _title = title;
    _isDebug = isDebug;
    _limitLength = limitLength;
    _startLine = "$_split$_title$_split";
    var endLineStr = StringBuffer();
    var cnCharReg = RegExp("[\u4e00-\u9fa5]");
    for (int i = 0; i < _startLine.length; i++) {
      if (cnCharReg.stringMatch(_startLine[i]) != null) {
        endLineStr.write(_separator);
      }
      endLineStr.write(_separator);
    }
    _endLine = endLineStr.toString();
  }

  static void d(dynamic obj) {
    if (_isDebug) {
      _log(obj.toString());
    }
  }

  static void v(dynamic obj) {
    _log(obj.toString());
  }

  static void _log(String msg) {
    print("$_startLine");
    _logEmpyLine();
    if (msg.length < _limitLength) {
      print(msg);
    } else {
      segmentationLog(msg);
    }
    _logEmpyLine();
    print("$_endLine");
  }

  static void segmentationLog(String msg) {
    var outStr = StringBuffer();
    for (var index = 0; index < msg.length; index++) {
      outStr.write(msg[index]);
      if (index % _limitLength == 0 && index != 0) {
        print(outStr);
        outStr.clear();
        var lastIndex = index + 1;
        if (msg.length - lastIndex < _limitLength) {
          var remainderStr = msg.substring(lastIndex, msg.length);
          print(remainderStr);
          break;
        }
      }
    }
  }

  static void _logEmpyLine() {
    print("");
  }
}

// --- RandomString --- (từ random_string.dart)
class RandomString {
  static final Random _random = Random();

  static int randomBetween(int from, int to) {
    if (from > to) {
      throw ArgumentError('from must be less than or equal to to');
    }
    return from + _random.nextInt(to - from + 1);
  }

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

  static String randomNumeric(int length) {
    if (length <= 0) {
      throw ArgumentError('length must be greater than 0');
    }
    return randomString(length, from: 48, to: 57);
  }

  static String randomAlpha(int length) {
    if (length <= 0) {
      throw ArgumentError('length must be greater than 0');
    }
    return randomString(length, from: 65, to: 90);
  }

  static String randomAlphaNumeric(int length) {
    if (length <= 0) {
      throw ArgumentError('length must be greater than 0');
    }
    return randomString(length, from: 48, to: 57) +
        randomString(length, from: 65, to: 90);
  }

  static int currentTimeMillis() {
    return DateTime.now().millisecondsSinceEpoch;
  }
}
