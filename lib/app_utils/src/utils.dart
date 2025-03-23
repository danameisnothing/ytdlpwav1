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

/// Exits the program with an abnormal exit code, with a final [msg] beforehand
Never hardExit(String msg, [int eCode = 1]) {
  logger.severe(msg);
  exit(eCode);
}

Map<String, dynamic>? decodeJSONOrNull(String str) {
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

  stderrBroadcast.listen((e) =>
      logger.fine('[$procNameToLog STDERR] ${String.fromCharCodes(e).trim()}'));
  stdoutBroadcast.listen((e) =>
      logger.fine('[$procNameToLog STDOUT] ${String.fromCharCodes(e).trim()}'));

  return (stdout: stdoutBroadcast, stderr: stderrBroadcast);
}

/// Returns only the fractional part of [n], without the period as a [String]
///
/// Example :
/// ```dart
/// getFractNumberPartStr(6.2831) == '2831'
/// ```
String getFractNumberPartStr(num n) {
  final subFract =
      n.toString().replaceFirst(RegExp(n.truncate().toString()), '');

  if (subFract.isEmpty) {
    return "";
  }
  return subFract.substring(1);
}

// TODO: doc!
Future<bool> hasProgramInstalled(String program) async {
  for (final path in Platform.environment['PATH']!
      .split((Platform.isWindows) ? ';' : ':')) {
    if (!await Directory(path).exists()) continue;
    for (final file in await Directory(path).list().toList()) {
      final fName = file.uri.pathSegments.last;
      if (Platform.isWindows) {
        if (fName.contains(program) && fName.endsWith('.exe')) return true;
      } else {
        if (fName.contains(program)) return true;
      }
    }
  }

  return false;
}

final class VideoInPlaylist {
  final String title;
  final String id;
  final String description;
  final String uploader;
  final DateTime uploadDate;
  bool hasDownloadedSuccessfully;

  VideoInPlaylist(this.title, this.id, this.description, this.uploader,
      this.uploadDate, this.hasDownloadedSuccessfully);

  VideoInPlaylist.fromJson(Map<String, dynamic> json)
      : title = json['title'],
        id = json['id'],
        description = json['description'],
        uploader = json['uploader'],
        uploadDate = DateTime.parse(json['uploadDate']),
        hasDownloadedSuccessfully = json['hasDownloadedSuccessfully'];

  Map<String, dynamic> toJson() => {
        'title': title,
        'id': id,
        'description': description,
        'uploader': uploader,
        'uploadDate': uploadDate.toIso8601String(),
        'hasDownloadedSuccessfully': hasDownloadedSuccessfully
      };

  @override
  String toString() => toJson().toString();
}

/// An enum containing the string to be replaced in the command templates
enum TemplateReplacements {
  cookieFile(template: '<cookie_file>'),
  playlistId(template: '<playlist_id>'),
  videoId(template: '<video_id>'),
  videoInput(template: '<video_input>'),
  outputDir(template: '<output_dir>'),
  thumbOut(template: '<thumb_out>'),
  captionsInputFlags(template: '<captions_input_flags>'),
  captionTrackMappingMetadata(template: '<caption_track_mapping_metadata>'),
  thumbIn(template: '<thumb_in>'),
  finalOut(template: '<final_out>');

  const TemplateReplacements({required this.template});

  final String template;
}

// TODO: change to singleton?
sealed class ProcessRunner {
  static final List<Process> _processes = <Process>[];

  /// Spawns a process with a given name and template arguments, as well as a list of [replacements] for the template command
  static Future<
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

    // FIXME: WTF? this is confusing.
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
    logger.fine(
        'ProcessRunner: $name (${proc.pid}) spawned with arguments ($args) added to list');

    proc.exitCode.then((ec) {
      _processes.remove(proc);
      logger.fine(
          'ProcessRunner: $name (${proc.pid}) completed with exit code $ec and removed from list');
    });

    final streams = implantDebugLoggerReturnBackStream(proc, name);
    return (stdout: streams.stdout, stderr: streams.stderr, process: proc);
  }

  /// Tries to kill all of the processes that are still active
  static void killAll() {
    for (final proc in List<Process>.from(_processes)) {
      // FIXME: BROKEN LOGIC!
      if (!proc.kill(ProcessSignal.sigint)) {
        proc.kill();
      }
      logger.fine('ProcessRunner: killed process $proc');
      _processes.remove(proc);
    }
  }
}
