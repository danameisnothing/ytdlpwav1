import 'dart:io';

import 'package:chalkdart/chalk.dart';

import 'package:ytdlpwav1/simpleutils/simpleutils.dart';

// Based off of the progressbar2 package
class ProgressBar {
  static final String innerProgressBarIdent = '<innerprogressbar>';

  final num _top;
  final int _innerWidth;
  final Chalk _activeCol;
  final String _activeChar;
  final Chalk _activeLeadingCol;
  final String _activeLeadingChar;
  final String Function(num, num)? _renderFunc;
  final String Function(num, num, int)? _innerProgressBarOverrideFunc;
  num _current = 0;

  ProgressBar(
      {num top = 100,
      required int innerWidth,
      required Chalk activeColor,
      String activeCharacter = '=',
      required Chalk activeLeadingColor,
      String activeLeadingCharacter = '>',
      String Function(num, num)? renderFunc,
      String Function(num, num, int)? innerProgressBarOverrideFunc})
      : _top = top,
        _innerWidth = innerWidth,
        _activeCol = activeColor,
        _activeChar = activeCharacter,
        _activeLeadingCol = activeLeadingColor,
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

  String generateInnerProgressBar(num curr, num top, int targetWidth) {
    final activePortionScaled = map(curr, 0, top, 0, targetWidth)
        .floor(); // Amount of space occupied by active sections
    return '${List.filled(activePortionScaled, _activeChar).join()}${List.filled(map(top, 0, top, 0, targetWidth).floor() - activePortionScaled, ' ').join()}'
        .replaceFirst(RegExp(r' '), _activeLeadingChar);
  }

  Future renderInLine([String Function(num, num)? renderFuncIn]) async {
    // All this logic is to make sure that if either top or current is set as a double, then both of them should display as a decimal
    final topIsDouble = _top is double;
    final curIsDouble = _current is double;
    final onePartCompHasDecimal = topIsDouble || curIsDouble;

    final topArg =
        (topIsDouble && onePartCompHasDecimal) ? _top : (_top * 10) / 10;
    final curArg = (curIsDouble && onePartCompHasDecimal)
        ? _current
        : (_current * 10) / 10;

    late String str;
    if (renderFuncIn == null) {
      if (_renderFunc == null) {
        throw Exception(
            'Override function not given in constructor and function');
      }
      str = _renderFunc(topArg, curArg);
    } else {
      str = renderFuncIn(topArg, curArg);
    }

    str = str.replaceFirst(
        RegExp(innerProgressBarIdent),
        (_innerProgressBarOverrideFunc == null)
            ? generateInnerProgressBar(_current, _top, _innerWidth)
            : _innerProgressBarOverrideFunc(_current, _top, _innerWidth));

    stdout.write('\r');
    stdout.write(str
        .replaceAll(RegExp(activeCharacter), _activeCol(activeCharacter))
        .replaceFirst(RegExp(activeLeadingCharacter),
            _activeLeadingCol(activeLeadingCharacter)));
    stdout.write(List.filled(stdout.terminalColumns - str.length, ' ')
        .join()); // Fill the rest of the empty lines to overwrite any remaining characters from the last print
    await stdout.flush();
  }

  Future finishRender() async {
    stdout.write('\n');
    await stdout.flush();
  }
}
