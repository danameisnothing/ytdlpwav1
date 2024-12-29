import 'dart:io';
import 'dart:async';

import 'package:ytdlpwav1/app_preferences/app_preferences.dart';

// From Processing's map() function code
double map(num value, num istart, num istop, num ostart, num ostop) {
  return ostart + (ostop - ostart) * ((value - istart) / (istop - istart));
}

void hardExit(String msg) {
  settings.logger.severe(msg);
  exit(1);
}

Map<String, Stream<List<int>>> implantVerboseLoggerReturnBackStream(
    Process proc, String procNameToLog) {
  // Thank you https://stackoverflow.com/questions/51396769/flutter-bad-state-stream-has-already-been-listened-to
  final stderrBroadcast = proc.stderr.asBroadcastStream();
  final stdoutBroadcast = proc.stdout.asBroadcastStream();

  stderrBroadcast.listen((e) => settings.logger
      .fine('[$procNameToLog STDERR] ${String.fromCharCodes(e).trim()}'));
  stdoutBroadcast.listen((e) => settings.logger
      .fine('[$procNameToLog STDOUT] ${String.fromCharCodes(e).trim()}'));

  return {
    'stderr': stderrBroadcast,
    'stdout': stdoutBroadcast,
  };
}

// wtf
Future<String?> procAwaitFirstOutputHack(Stream<List<int>> stream) async {
  await for (final e in stream) {
    return String.fromCharCodes(e); // just get 1
  }

  return null;
}

class VideoInPlaylist {
  final String title;
  final String id;
  final String description;
  final String uploader;
  final DateTime uploadDate;

  VideoInPlaylist(
      this.title, this.id, this.description, this.uploader, this.uploadDate);

  VideoInPlaylist.fromJson(Map<String, dynamic> json)
      : title = json['title'],
        id = json['id'],
        description = json['description'],
        uploader = json['uploader'],
        uploadDate = DateTime.parse(json['uploadDate']);

  Map<String, dynamic> toJson() => {
        'title': title,
        'id': id,
        'description': description,
        'uploader': uploader,
        'uploadDate': uploadDate.toIso8601String()
      };

  @override
  String toString() => toJson().toString();
}
