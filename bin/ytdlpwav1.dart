import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:chalkdart/chalk.dart';
import 'package:chalkdart/chalk_x11.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:logging/logging.dart';

import 'package:ytdlpwav1/app_preferences/app_preferences.dart';
import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmd_split_args;
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';

// Do NOT alter the <cookie_file> and/or <playlist_id> hardcoded strings.
// https://www.reddit.com/r/youtubedl/comments/t7b3mn/ytdlp_special_characters_in_output_o/ (I am a dumbass)
/// The template for the command used to fetch information about videos in a playlist
const fetchVideoInfosCmd =
    'yt-dlp --simulate --no-flat-playlist --no-mark-watched --print "%(.{title,id,description,uploader,upload_date})j" --restrict-filenames --windows-filenames --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';
// https://github.com/yt-dlp/yt-dlp/issues/8562
/// The template for the command used to fetch how many videos in a playlist
const fetchPlaylistItemCount =
    'yt-dlp --playlist-items 0-1 --simulate --no-flat-playlist --no-mark-watched --print "%(.{playlist_count})j" --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';
const verboseLogFileName = 'ytdlpwav1_verbose_log.txt';
const videoDataFileName = 'ytdlpwav1_video_data.json';

Future<int> getPlaylistQuantity(String cookieFile, String playlistId) async {
  final playlistItemCountCmd = cmd_split_args.split(fetchPlaylistItemCount
      .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
      .replaceAll(RegExp(r'<playlist_id>'), playlistId));
  settings.logger.fine(
      'Starting yt-dlp process for fetching playlist quantity using argument $playlistItemCountCmd');
  final picProc = await Process.start(
      playlistItemCountCmd.removeAt(0), playlistItemCountCmd);

  final broadcastStreams =
      implantVerboseLoggerReturnBackStream(picProc, 'yt-dlp');

  final data = await procAwaitFirstOutputHack(broadcastStreams['stdout']!);

  if (await picProc.exitCode != 0) {
    hardExit(
        'An error occured while fetching playlist quantity. Use the --verbose flag to see more details');
  }

  settings.logger.fine('Got $data on playlist count');

  return jsonDecode(data!)['playlist_count']!
      as int; // Data can't be null because of the exitCode check
}

Stream<VideoInPlaylist> getPlaylistVideoInfos(
    String cookieFile, String playlistId) async* {
  final videoInfosCmd = cmd_split_args.split(fetchVideoInfosCmd
      .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
      .replaceAll(RegExp(r'<playlist_id>'), playlistId));
  settings.logger.fine(
      'Starting yt-dlp process for fetching video informations using argument $videoInfosCmd');
  final picProc = await Process.start(videoInfosCmd.removeAt(0), videoInfosCmd);

  final broadcastStreams =
      implantVerboseLoggerReturnBackStream(picProc, 'yt-dlp');

  await for (final e in broadcastStreams['stdout']!) {
    final data = jsonDecode(String.fromCharCodes(e));

    final uploadDate = data['upload_date'] as String;
    final parsed = VideoInPlaylist(
        data['title'],
        data['id'],
        data['description'],
        data['uploader'],
        DateTime(
          int.parse(uploadDate.substring(0, 4)),
          int.parse(uploadDate.substring(4, 6)),
          int.parse(uploadDate.substring(6, 8)),
        ));
    settings.logger.fine('Got update on stdout, parsed as $parsed');
    yield parsed;
  }

  if (await picProc.exitCode != 0) {
    hardExit(
        'An error occured while fetching video infos. Use the --verbose flag to see more details');
  }
}

Future fetchVideosLogic(String cookieFile, String playlistId) async {
  final videoDataFile = File(videoDataFileName);
  if (await videoDataFile.exists()) {
    //print();
    // TODO:
  }

  final spinnerProcessLaunching = CliSpin(spinner: CliSpinners.dots);

  spinnerProcessLaunching.start('Waiting for yt-dlp output');
  final playlistQuantity = await getPlaylistQuantity(cookieFile, playlistId);
  spinnerProcessLaunching.stop();

  settings.logger.info('Fetched video quantity in playlist');

  final playlistFetchInfoProgress =
      ProgressBar(top: playlistQuantity, innerWidth: 32);

  final stopwatch = Stopwatch()..start();

  // Thank you https://www.reddit.com/r/dartlang/comments/t8pcbd/stream_periodic_from_a_future/
  final periodic =
      Stream.periodic(Duration(milliseconds: 10)).asyncMap((_) async {
    await playlistFetchInfoProgress.renderInLine((total, current) {
      final normTime = stopwatch.elapsedMilliseconds / 1000;

      final percStr = chalk.brightCyan(
          '${(((current / total) * 1000).truncate()) / 10}%'); // To have only 1 fractional part of the percentage, while cutting out any weird long fractions (e.g. 50.000001 will be converted to 50.0)
      final partStr =
          chalk.brightMagenta('${current.truncate()}/${total.truncate()}');
      final stopwatchStr =
          chalk.darkTurquoise('Running for ${normTime.toStringAsFixed(3)}s');
      return '[${ProgressBar.innerProgressBarIdent}] · $percStr · $partStr · $stopwatchStr'; // TODO: ADD ETA LOGIC!
    });
  }).listen((_) => 0);

  final videoInfos = <VideoInPlaylist>[];

  final res = getPlaylistVideoInfos(cookieFile, playlistId);
  await for (final videoInfo in res) {
    videoInfos.add(videoInfo);
    playlistFetchInfoProgress.increment();
  }

  stopwatch.stop();
  periodic.cancel();
  await playlistFetchInfoProgress.finishRender();

  settings.logger.fine('End result is $videoInfos');
}

void main(List<String> arguments) async {
  settings.logger = Logger('piss');
  Logger.root.onRecord.listen((rec) {
    String levelName = '[${rec.level.name}]';
    switch (rec.level) {
      case Level.INFO:
        levelName = chalk.grey(levelName);
        break;
      case Level.WARNING:
        levelName = chalk.yellowBright(levelName);
        break;
      case Level.SEVERE:
        levelName = chalk.redBright('[ERROR]');
        break;
    }
    if (rec.level == Level.FINE) {
      final logFile =
          File(verboseLogFileName); // Guaranteed to exist at this point
      logFile.writeAsStringSync(
          '${rec.time.toIso8601String()} : ${rec.message}${Platform.lineTerminator}',
          flush: true,
          mode: FileMode.append);
      return;
    }
    print('$levelName ${rec.message}');
  });
  Logger.root.level = Level.INFO;

  final argParser = ArgParser();
  argParser.addOption('cookie_file',
      abbr: 'c', help: 'The path to the YouTube cookie file', mandatory: true);
  argParser.addOption('playlist_id',
      abbr: 'p', help: 'The target YouTube playlist ID', mandatory: false);
  argParser.addFlag('verbose',
      abbr: 'v', help: 'Logs verbose output on a file');

  final parsedArgs = argParser.parse(arguments);

  if (parsedArgs.flag('verbose')) {
    Logger.root.level = Level.ALL;
    final logFile = File(verboseLogFileName);
    if (!await logFile.exists()) {
      await logFile.create();
    } else {
      logFile.writeAsStringSync('',
          flush: true, mode: FileMode.write); // Overwrite with nothing
    }
  }

  final cookieFile = parsedArgs.option('cookie_file') ?? '';
  final playlistId = parsedArgs.option('playlist_id');

  if (cookieFile.isEmpty) {
    hardExit('"cookie_file" argument not specified or empty');
  }

  if (!await File(cookieFile).exists()) {
    hardExit('Invalid cookie path given');
  }

  // No idea what is it for Unix systems
  // TODO: Figure out for Unix systems
  if (Platform.isWindows) {
    if ((await Process.run('where', ['yt-dlp'])).exitCode != 0) {
      hardExit(
          'Unable to find the yt-dlp command. Verify that yt-dlp is mounted in PATH');
    }
  }

  if (playlistId != null) {
    await fetchVideosLogic(cookieFile, playlistId);
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
