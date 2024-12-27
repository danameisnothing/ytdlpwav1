import 'dart:io';
import 'dart:math';
// Based off of the progressbar2 package

import 'package:chalkdart/chalk.dart';

import 'package:ytdlpwav1/simpleutils/simpleutils.dart';

class ProgressBar {
  static final String innerProgressBarIdent = "<innerprogressbar>";

  final int _top;
  final int _innerWidth;
  final Chalk _activeCol;
  final String _activeChar;
  final Chalk _activeLeadingCol;
  final String _activeLeadingChar;
  final String Function(int, int)? _renderFunc;
  final String Function(int, int, int)? _innerProgressBarOverrideFunc;
  int _current;

  ProgressBar(
      {int top = 100,
      int startAt = 0,
      required int innerWidth,
      required Chalk activeColor,
      String activeCharacter = '=',
      required Chalk activeLeadingColor,
      String activeLeadingCharacter = '>',
      String Function(int, int)? renderFunc,
      String Function(int, int, int)? innerProgressBarOverrideFunc})
      : _current = startAt,
        _top = top,
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

  void increment([int value = 1]) => _current += value;

  String generateInnerProgressBar(int curr, int top, int targetWidth) {
    final activePortionScaled = map(curr, 0, top, 0, targetWidth)
        .floor(); // Amount of space occupied by active sections
    return '${List.filled(activePortionScaled, _activeChar).join()}${List.filled(map(top, 0, top, 0, targetWidth).floor() - activePortionScaled, ' ').join()}'
        .replaceFirst(RegExp(r' '), _activeLeadingChar);
  }

  Future renderInLine([String Function(int, int)? renderOverride]) async {
    late final String str;
    if (renderOverride == null) {
      if (_renderFunc == null) {
        throw Exception(
            'Override function not given in constructor and function');
      }
      str = _renderFunc(_top, _current);
    } else {
      str = renderOverride(_top, _current);
    }

    stdout.write('\r');
    stdout.write(str
        .replaceFirst(
            RegExp(innerProgressBarIdent),
            (_innerProgressBarOverrideFunc == null)
                ? generateInnerProgressBar(_current, _top, _innerWidth)
                : _innerProgressBarOverrideFunc(_current, _top, _innerWidth))
        .replaceAll(RegExp(activeCharacter), _activeCol(activeCharacter))
        .replaceFirst(RegExp(activeLeadingCharacter),
            _activeLeadingCol(activeLeadingCharacter)));
    stdout.write(List.filled(stdout.terminalColumns - str.length, ' ')
        .join()); // Fill the rest of the empty lines to overwrite any remaining characters from the last print
    await stdout.flush();
  }
}
