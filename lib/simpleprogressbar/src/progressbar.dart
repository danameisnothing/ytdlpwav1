import 'dart:io';
import 'dart:math';

import 'package:ansi_strip/ansi_strip.dart';
import 'package:chalkdart/chalk.dart';

import 'package:ytdlpwav1/app_utils/app_utils.dart';

// Based off of the progressbar2 package (https://pub.dev/packages/progressbar2)
final class ProgressBar {
  static final String innerProgressBarIdent = '<innerprogressbar>';

  final num _top;
  final int _innerWidth;
  final String _activeChar;
  final String _activeLeadingChar;
  final String Function(num, num)? _renderFunc;
  final String Function(num, num, int)? _innerProgressBarOverrideFunc;
  num _progress = 0;

  ProgressBar(
      {num top = 100,
      required int innerWidth,
      String activeCharacter = '=',
      String activeLeadingCharacter = '>',
      String Function(num, num)? renderFunc,
      String Function(num, num, int)? innerProgressBarOverrideFunc})
      : _top = top,
        _innerWidth = innerWidth,
        _activeChar = activeCharacter,
        _activeLeadingChar = activeLeadingCharacter,
        _renderFunc = renderFunc,
        _innerProgressBarOverrideFunc = innerProgressBarOverrideFunc;

  String get activeCharacter => _activeChar;
  String get activeLeadingCharacter => _activeLeadingChar;
  int get innerWidth => _innerWidth;
  num get top => _top;
  set top(num val) => _top;
  num get progress => _progress;
  set progress(num val) {
    if (val.clamp(0.0, _top) != val) {
      throw Exception("Value $val is more or less than $_top");
    }
    _progress = val;
  }

  void increment([num value = 1]) {
    _progress += value;
    _progress = _progress.clamp(0.0, _top);
  }

  bool isCompleted() => (_progress - _top).abs() <= 0.0001;

  String generateDefaultProgressBar() {
    final activePortionScaled = map(_progress, 0, _top, 0, _innerWidth)
        .floor(); // Amount of space occupied by active sections
    return '${chalk.brightGreen(List.filled(activePortionScaled, _activeChar).join())}${List.filled(map(top, 0, top, 0, _innerWidth).floor() - activePortionScaled, ' ').join()}'
        .replaceFirst(RegExp(r' '), chalk.brightGreen(_activeLeadingChar));
  }

  String formatPartStringNoColorDefault(num curr, num top) {
    // All this logic is to make sure that if either top or current is set as a double, then both of them should display as a decimal
    final topFractStr = getFractNumberPartStr(top);
    final curFractStr = getFractNumberPartStr(curr);

    final targetFractLen = max(topFractStr.length, curFractStr.length);
    final topPassedStr = _top.toStringAsFixed(targetFractLen);
    final curPassedStr = _progress.toStringAsFixed(targetFractLen);

    return '$curPassedStr/$topPassedStr';
  }

  Future<void> renderInLine([String Function(num, num)? renderFuncIn]) async {
    late String str;
    if (renderFuncIn == null) {
      if (_renderFunc == null) {
        throw ArgumentError.notNull('_renderFunc');
      }
      str = _renderFunc(_top, _progress);
    } else {
      str = renderFuncIn(_top, _progress);
    }

    try {
      str = str.replaceFirst(
          RegExp(innerProgressBarIdent),
          (_innerProgressBarOverrideFunc == null)
              ? generateDefaultProgressBar()
              : _innerProgressBarOverrideFunc(_progress, _top, _innerWidth));

      final strLen = stripAnsi(str).length;
      // Handle us not having enough space to print the base message
      if (stdout.terminalColumns < strLen) return;

      stdout.write(
          '\r$str${List.filled(stdout.terminalColumns - strLen, ' ').join()}'); // Fill the rest of the empty lines to overwrite any remaining characters from the last print
      await stdout.flush();
    } on RangeError catch (_) {
      rethrow;
    }
  }

  Future<void> finishRender() async {
    stdout.write('\n');
    await stdout.flush();
  }
}
