import 'dart:io';

import 'package:chalkdart/chalk.dart';

// From Processing's map() function code
double map(num value, num istart, num istop, num ostart, num ostop) {
  return ostart + (ostop - ostart) * ((value - istart) / (istop - istart));
}

Future printErr(Object? obj) async {
  stderr.writeln('${chalk.brightRed('[ERROR]')} $obj');
  await stderr.flush();
}

Future hardExit(String msg) async {
  await printErr(msg);
  exit(1);
}
