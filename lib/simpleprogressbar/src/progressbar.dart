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

  Future renderInLine([String Function(num, num)? renderFuncIn]) async {
    try {
      // All this logic is to make sure that if either top or current is set as a double, then both of them should display as a decimal
      /*final topIsDouble = _top is double;
      final curIsDouble = _current is double;
      final onePartCompHasDecimal = topIsDouble || curIsDouble;

      final topArg =
          (topIsDouble && onePartCompHasDecimal) ? _top : (_top * 10) / 10;
      final curArg = (curIsDouble && onePartCompHasDecimal)
          ? _current
          : (_current * 10) / 10;*/

      // Hopefully there are no unforseen consequences with this approach
      final topFractStr = _top
          .toString()
          .replaceFirst(RegExp(_top.truncate().toString()), '')
          .substring(1);
      final curFractStr = _current
          .toString()
          .replaceFirst(RegExp(_current.truncate().toString()), '')
          .substring(1);

      final topPassed = double.parse(
          _top.toStringAsFixed(max(topFractStr.length, curFractStr.length)));
      final curPassed = double.parse(_current
          .toStringAsFixed(max(topFractStr.length, curFractStr.length)));

      late String str;
      if (renderFuncIn == null) {
        if (_renderFunc == null) {
          throw Exception(
              'Override function not given in constructor and function');
        }
        str = _renderFunc(topPassed, curPassed);
      } else {
        str = renderFuncIn(topPassed, curPassed);
      }

      str = str.replaceFirst(
          RegExp(innerProgressBarIdent),
          (_innerProgressBarOverrideFunc == null)
              ? generateInnerProgressBarDefault(_current, _top, _innerWidth)
              : _innerProgressBarOverrideFunc(_current, _top, _innerWidth));

      stdout.write(
          '\r$str${List.filled(stdout.terminalColumns - stripAnsi(str).length, ' ').join()}'); // Fill the rest of the empty lines to overwrite any remaining characters from the last print
      await stdout.flush();
    } catch (_) {
      // Error may be us not having enough space to print the base message
    }
  }

  Future finishRender() async {
    stdout.write('\n');
    await stdout.flush();
  }
}
