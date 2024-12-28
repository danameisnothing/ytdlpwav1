import 'dart:io';

import 'package:ytdlpwav1/app_preferences/app_preferences.dart';

// From Processing's map() function code
double map(num value, num istart, num istop, num ostart, num ostop) {
  return ostart + (ostop - ostart) * ((value - istart) / (istop - istart));
}

void hardExit(String msg) {
  settings.logger.severe(msg);
  exit(1);
}
