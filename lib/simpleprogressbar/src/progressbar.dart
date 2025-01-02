import 'dart:io';
import 'dart:math';

import 'package:ansi_strip/ansi_strip.dart';
import 'package:chalkdart/chalk.dart';

import 'package:ytdlpwav1/app_utils/app_utils.dart';

// Based off of the progressbar2 package (https://pub.dev/packages/progressbar2)
class ProgressBar {
  static final String innerProgressBarIdent = '<innerprogressbar>';

  final num _top;
  final int _innerWidth;
  final String _activeChar;
  final String _activeLeadingChar;
  final String Function(num, num)? _renderFunc;
  final String Function(num, num, int)? _innerProgressBarOverrideFunc;
  num _current = 0;

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
  num get progress => _current;
  num get top => _top;

  void increment([num value = 1]) {
    _current += value;
    _current = _current.clamp(0.0, _top);
  }

  bool isCompleted() => (_current - _top).abs() <= 0.0001;

  String generateInnerProgressBarDefault(num curr, num top, int targetWidth) {
    final activePortionScaled = map(curr, 0, top, 0, targetWidth)
        .floor(); // Amount of space occupied by active sections
    return '${chalk.brightGreen(List.filled(activePortionScaled, _activeChar).join())}${List.filled(map(top, 0, top, 0, targetWidth).floor() - activePortionScaled, ' ').join()}'
        .replaceFirst(RegExp(r' '), chalk.brightGreen(_activeLeadingChar));
  }

  String formatPartStringNoColorDefault(num curr, num top) {
    // All this logic is to make sure that if either top or current is set as a double, then both of them should display as a decimal
    final topFractStr = getFractNumberPartStr(top);
    final curFractStr = getFractNumberPartStr(curr);

    final targetFractLen = max(topFractStr.length, curFractStr.length);
    final topPassedStr = _top.toStringAsFixed(targetFractLen);
    final curPassedStr = _current.toStringAsFixed(targetFractLen);

    return '$curPassedStr/$topPassedStr';
  }

  Future renderInLine([String Function(num, num)? renderFuncIn]) async {
    late String str;
    if (renderFuncIn == null) {
      if (_renderFunc == null) {
        throw Exception(
            'Override function not given in constructor and function');
      }
      str = _renderFunc(_top, _current);
    } else {
      str = renderFuncIn(_top, _current);
    }

    str = str.replaceFirst(
        RegExp(innerProgressBarIdent),
        (_innerProgressBarOverrideFunc == null)
            ? generateInnerProgressBarDefault(_current, _top, _innerWidth)
            : _innerProgressBarOverrideFunc(_current, _top, _innerWidth));

    final strLen = stripAnsi(str).length;
    // Handle us not having enough space to print the base message
    if (stdout.terminalColumns < strLen) return;

    stdout.write(
        '\r$str${List.filled(stdout.terminalColumns - strLen, ' ').join()}'); // Fill the rest of the empty lines to overwrite any remaining characters from the last print
    await stdout.flush();
  }

  Future finishRender() async {
    stdout.write('\n');
    await stdout.flush();
  }
}
