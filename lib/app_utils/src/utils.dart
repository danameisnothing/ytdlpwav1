import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmd_split_args;
import 'package:ytdlpwav1/app_settings/app_settings.dart';

// From Processing's map() function code
double map(num value, num istart, num istop, num ostart, num ostop) {
  return ostart + (ostop - ostart) * ((value - istart) / (istop - istart));
}

Never hardExit(String msg) {
  settings.logger.severe(msg);
  exit(1);
}

Map<String, dynamic>? decodeJSONOrFail(String str) {
  try {
    return jsonDecode(str);
  } catch (e) {
    return null;
  }
}

({Stream<List<int>> stdout, Stream<List<int>> stderr})
    implantDebugLoggerReturnBackStream(Process proc, String procNameToLog) {
  // Thank you https://stackoverflow.com/questions/51396769/flutter-bad-state-stream-has-already-been-listened-to
  final stderrBroadcast = proc.stderr.asBroadcastStream();
  final stdoutBroadcast = proc.stdout.asBroadcastStream();

  stderrBroadcast.listen((e) => settings.logger
      .fine('[$procNameToLog STDERR] ${String.fromCharCodes(e).trim()}'));
  stdoutBroadcast.listen((e) => settings.logger
      .fine('[$procNameToLog STDOUT] ${String.fromCharCodes(e).trim()}'));

  return (stdout: stdoutBroadcast, stderr: stderrBroadcast);
}

String getFractNumberPartStr(num n) {
  final subFract =
      n.toString().replaceFirst(RegExp(n.truncate().toString()), '');

  if (subFract.isEmpty) {
    return "";
  }
  return subFract.substring(1);
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

enum TemplateReplacements {
  cookieFile(template: '<cookie_file>'),
  playlistId(template: '<playlist_id>'),
  videoId(template: '<video_id>'),
  videoInput(template: '<video_input>'),
  outputDir(template: '<output_dir>');

  const TemplateReplacements({required this.template});

  final String template;
}

class ProcessRunner {
  final List<Process> _processes = <Process>[];

  // TODO: doc
  Future<
          ({
            Stream<List<int>> stdout,
            Stream<List<int>> stderr,
            Process process
          })>
      spawn(
          {required String name,
          required String argument,
          Map<TemplateReplacements, String> replacements =
              const <TemplateReplacements, String>{}}) async {
    for (final replacement in replacements.entries) {
      argument = argument.replaceAll(
          RegExp(replacement.key.template), replacement.value);
    }

    final args = cmd_split_args
        .split(argument)
        .map((arg) => arg.replaceAll(RegExp('\''), '"'))
        .toList(); // Replacing all escaped single quotes in case I make use of this again

    final proc = await Process.start(
        name,
        args
          ..removeAt(
              0)); // 2nd param is the arguments, without the yt-dlp element

    _processes.add(proc);
    settings.logger.fine('ProcessRunner: $name spawned and added to list');

    proc.exitCode.then((ec) {
      _processes.remove(proc);
      settings.logger.fine(
          'ProcessRunner: $name completed with exit code $ec and removed from list');
    });

    final streams = implantDebugLoggerReturnBackStream(proc, name);
    return (stdout: streams.stdout, stderr: streams.stderr, process: proc);
  }

  void killAll() {
    for (final proc in List.from(_processes)) {
      proc.kill(ProcessSignal.sigint);
      settings.logger.fine('ProcessRunner: killed process $proc');
      _processes.remove(proc);
    }
  }
}
