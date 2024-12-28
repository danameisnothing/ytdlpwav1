import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:chalkdart/chalk.dart';
import 'package:chalkdart/chalk_x11.dart';
import 'package:cli_spin/cli_spin.dart';

import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmdSplitArgs;
import 'package:ytdlpwav1/simpleutils/simpleutils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';

// Do NOT alter the <cookie_file> and/or <playlist_id> hardcoded strings.
// https://www.reddit.com/r/youtubedl/comments/t7b3mn/ytdlp_special_characters_in_output_o/ (I am a dumbass)
/// The template for the command used to fetch information about videos in a playlist
const fetchVideoDataCmd =
    'yt-dlp --simulate --no-flat-playlist --no-mark-watched --print "%(.{title,id,description,uploader,upload_date})j" --restrict-filenames --windows-filenames --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';

// https://github.com/yt-dlp/yt-dlp/issues/8562
/// The template for the command used to fetch how many videos in a playlist
const fetchPlaylistItemCount =
    'yt-dlp --playlist-items 0-1 --simulate --no-flat-playlist --no-mark-watched --print "%(.{playlist_count})j" --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';

bool verbose = false;

class VideoInPlaylist {
  final String name;
  final String id;
  final String description;
  final String uploaderName;
  final String uploadedDateUTCStr;

  VideoInPlaylist(this.name, this.id, this.description, this.uploaderName,
      this.uploadedDateUTCStr);

  VideoInPlaylist.fromJson(Map<String, dynamic> json)
      : name = json['name'],
        id = json['id'],
        description = json['description'],
        uploaderName = json['uploaderName'],
        uploadedDateUTCStr = json['uploadedDateUTCStr'];

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'description': description,
        'uploaderName': uploaderName,
        'uploadedDateUTCStr': uploadedDateUTCStr
      };
}

Future<int> getPlaylistQuantity(String cookieFile, String playlistId) async {
  final playlistItemCountCmd = cmdSplitArgs.split(fetchPlaylistItemCount
      .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
      .replaceAll(RegExp(r'<playlist_id>'), playlistId));
  final picProc = await Process.start(
      playlistItemCountCmd.removeAt(0), playlistItemCountCmd);

  // Thank you https://stackoverflow.com/questions/51396769/flutter-bad-state-stream-has-already-been-listened-to
  final stderrBroadcast = picProc.stderr.asBroadcastStream();
  final stdoutBroadcast = picProc.stdout.asBroadcastStream();

  if (await picProc.exitCode != 0) {
    await hardExit('An unknown error occured while fetching video lists');
  }

  final playlistItemData = jsonDecode(String.fromCharCodes(await stdoutBroadcast
      .first)); // Wait for the process to spit an output. With this command, this ALWAYS prints first

  // TODO: SET UP LOGGING FOR THIS PROCESS!

  return playlistItemData["playlist_count"]! as int;
}

Future fetchVideos(String cookieFile, String playlistId) async {
  final spinnerProcessLaunching =
      CliSpin(spinner: CliSpinners.dots, hideCursor: false);

  spinnerProcessLaunching.start('Waiting for yt-dlp output');
  final playlistQuantity = await getPlaylistQuantity(cookieFile, playlistId);
  spinnerProcessLaunching.stop();

  final playlistFetchInfoProgress =
      ProgressBar(top: playlistQuantity, innerWidth: 64);

  final videoDataCmd = cmdSplitArgs.split(fetchVideoDataCmd
      .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
      .replaceAll(RegExp(r'<playlist_id>'), playlistId));
  final picProc = await Process.start(videoDataCmd.removeAt(0), videoDataCmd);

  final stopwatch = Stopwatch()..start();

  // Thank you https://stackoverflow.com/questions/51396769/flutter-bad-state-stream-has-already-been-listened-to
  final stderrBroadcast = picProc.stderr.asBroadcastStream();
  final stdoutBroadcast = picProc.stdout.asBroadcastStream();

  final timer = Timer.periodic(Duration(milliseconds: 10), (_) {
    playlistFetchInfoProgress.renderInLine((total, current) {
      final percStr = chalk.brightCyan(
          '${(((current / total) * 1000).truncate()) / 10}%'); // To have only 1 fractional part of the percentage, while cutting out any weird long fractions (e.g. 50.000001 will be converted to 50.0)
      final partStr =
          chalk.brightMagenta('${current.truncate()}/${total.truncate()}');
      final stopwatchStr = chalk.darkTurquoise(
          "Running for ${stopwatch.elapsedMilliseconds / 1000}s");
      return '[${ProgressBar.innerProgressBarIdent}] · $percStr · $partStr · $stopwatchStr';
    });
  });

  stdoutBroadcast.forEach((e) {
    final norm = String.fromCharCodes(e);
    playlistFetchInfoProgress.increment();
  });

  if (await picProc.exitCode != 0) {
    await hardExit('An unknown error occured while fetching video lists');
  }

  stopwatch.stop();
  await playlistFetchInfoProgress.finishRender();

  timer.cancel();

  /*final e = ProgressBar(
      top: 69,
      innerWidth: 64,
      activeColor: chalk.brightGreen,
      activeLeadingColor: chalk.brightGreen,
      renderFunc: (total, current) {
        final percStr = chalk.brightCyan(
            '${(((current / total) * 1000).truncate()) / 10}%'); // To have only 1 fractional part of the percentage, while cutting out any weird long fractions (e.g. 50.000001 will be converted to 50.0)
        final partStr = chalk.brightMagenta('$current/$total');
        return '[${ProgressBar.innerProgressBarIdent}] · $percStr · $partStr';
      });

  while (e.progress < e.top) {
    await e.renderInLine();
    e.increment(Random().nextDouble());
    await Future.delayed(const Duration(milliseconds: 1));
    await e.renderInLine()
  }

  await e.finishRender();*/
}

void main(List<String> arguments) async {
  final argParser = ArgParser();
  argParser.addOption('cookie_file',
      abbr: 'c', help: 'The path to the YouTube cookie file', mandatory: true);
  argParser.addOption('playlist_id',
      abbr: 'p', help: 'The target YouTube playlist ID', mandatory: false);
  argParser.addFlag('verbose', abbr: 'v', help: 'Print verbose output');

  // No idea what is it for Unix systems
  // TODO: Figure out for Unix systems
  if (Platform.isWindows) {
    if ((await Process.run('where', ['yt-dlp'])).exitCode != 0) {
      await hardExit(
          'Unable to find the yt-dlp command. Verify that yt-dlp is mounted in PATH');
    }
  }

  final parsedArgs = argParser.parse(arguments);

  final cookieFile = parsedArgs.option('cookie_file') ?? '';
  final playlistId = parsedArgs.option('playlist_id');

  if (cookieFile.isEmpty) {
    await hardExit('"cookie_file" argument not specified or empty');
  }

  if (!await File(cookieFile).exists()) {
    await hardExit('Invalid cookie path given');
  }

  if (playlistId != null) {
    await fetchVideos(cookieFile, playlistId);
  }

  /*print(cmdSplitArgs.split(
      'yt-dlp --format "bestvideo[width<=1920][height<=1080][fps<=60]+bestaudio[acodec=opus][audio_channels<=2][asr<=48000]" --output "%(title)s" --restrict-filenames --merge-output-format mkv --write-auto-subs --embed-thumbnail --sub-lang "en.*" --fragment-retries 999 --retries 999 --extractor-retries 0 --cookies "C:\\Users\\testnow720\\Downloads\\cookies-youtube-com.txt" "https://www.youtube.com/watch?v=TXgYLmN6m1U"'));*/

  /*final playlistInfoProc = await Process.start('yt-dlp', [
    '--simulate',
    '--no-flat-playlist',
    '--no-mark-watched',
    '--output',
    '$playlistInternalPrefixIdent%(title)s$playlistInternalSplitTarget%(id)s$playlistInternalSplitTarget%(description)s$playlistInternalSplitTarget%(uploader)s$playlistInternalSplitTarget%(upload_date)s',
    '--get-filename',
    '--retries',
    '999',
    '--fragment-retries',
    '999',
    '--extractor-retries',
    '0',
    '--cookies',
    cookieFile,
    'https://www.youtube.com/playlist?list=$playlistID'
  ]);

  final videosToDownload = <VideoInPlaylist>[];

  playlistInfoProc.stderr
      .forEach((e) => print('stderr : ${String.fromCharCodes(e)}'));

  playlistInfoProc.stdout.forEach((tmp) {
    String str = String.fromCharCodes(tmp);

    if (!str.startsWith(playlistInternalPrefixIdent)) return;

    final filter = playlistInternalPrefixIdent
        .replaceFirst(RegExp(r'\['), r'\[')
        .replaceFirst(RegExp(r'\]'), r'\]');
    str = str.replaceAll(RegExp(filter), '');

    final res =
        str.split(playlistInternalSplitTarget).map((e) => e.trim()).toList();

    videosToDownload
        .add(VideoInPlaylist(res[0], res[1], res[2], res[3], res[4]));

    print('stdout : $str');
  });

  await playlistInfoProc.exitCode;

  final videosToDownloadFile =
      File('C:\\Users\\testnow720\\Desktop\\notimeforthisshit.json');

  videosToDownloadFile.writeAsString(jsonEncode({'res': videosToDownload}));*/

  /*final videosToDownload =
      File('C:\\Users\\testnow720\\Desktop\\notimeforthisshit.json');*/

  // yt-dlp --format 'bestvideo[width<=1920][height<=1080][fps<=60][vcodec^=av01][ext=mp4]+bestaudio[acodec=opus][audio_channels<=2][asr<=48000]' --embed-subs --embed-thumbnail --sub-lang 'en,en-orig' --merge-output-format mp4 --fragment-retries 999 --retries 999 --extractor-retries 0 --cookies 'C:\Users\testnow720\Downloads\cookies-youtube-com.txt' 'https://www.youtube.com/watch?v=1y7fZ_WtUGE'

  // TEST :
  // yt-dlp --format 'bestvideo[width<=1920][height<=1080][fps<=60][vcodec^=av01][ext=mp4]+bestaudio[acodec=opus][audio_channels<=2][asr<=48000]' --embed-subs --embed-thumbnail --sub-lang 'en,en-orig' --merge-output-format mp4 --fragment-retries 999 --retries 999 --extractor-retries 0 --cookies 'C:\Users\testnow720\Downloads\cookies-youtube-com.txt' 'https://www.youtube.com/watch?v=HBCYHb58jQc'
  // This video does NOT have the av01 encoding available
}
