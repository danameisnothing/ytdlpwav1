import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:chalkdart/chalk.dart';
import 'package:chalkdart/chalk_x11.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:logging/logging.dart';

import 'package:ytdlpwav1/app_settings/app_settings.dart';
import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmd_split_args;
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';
import 'package:ytdlpwav1/app_funcs/app_funcs.dart';

Future fetchVideosLogic(String cookieFile, String playlistId) async {
  final videoDataFile = File(videoDataFileName);
  if (await videoDataFile.exists()) {
    hardExit(
        'File $videoDataFileName already exists. Delete / rename the file and try again, or do not supply the "--playlist_id" option to start downloading videos');
    // FIXME: actual confirmation prompt to overwrite the file!
  }
  await videoDataFile.create();

  final spinnerProcessLaunching = CliSpin(spinner: CliSpinners.dots);

  spinnerProcessLaunching.start('Waiting for yt-dlp output');
  final playlistQuantity = await getPlaylistQuantity(cookieFile, playlistId);
  spinnerProcessLaunching.stop();

  if (playlistQuantity == null) {
    hardExit(
        'An error occured while fetching playlist quantity. Use the --debug flag to see more details');
  }

  settings.logger.info('Fetched video quantity in playlist');

  final playlistFetchInfoProgress =
      ProgressBar(top: playlistQuantity!, innerWidth: 32);

  final stopwatch = Stopwatch()..start();

  // Thank you https://www.reddit.com/r/dartlang/comments/t8pcbd/stream_periodic_from_a_future/
  final periodic =
      Stream.periodic(const Duration(milliseconds: 10)).asyncMap((_) async {
    await playlistFetchInfoProgress.renderInLine((total, current) {
      final normTime = stopwatch.elapsedMilliseconds / 1000;

      final percStr =
          chalk.brightCyan('${((current / total) * 100).toStringAsFixed(1)}%');
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

  final convertedRes =
      jsonEncode({'res': videoInfos.map((e) => e.toJson()).toList()});

  settings.logger.fine('Converted video info map to $convertedRes');

  await videoDataFile.writeAsString(convertedRes);
}

Future downloadVideosLogic(String cookieFile, String? passedOutDir) async {
  final videoDataFile = File(videoDataFileName);
  if (!await videoDataFile.exists()) {
    hardExit(
        'Video data file has not been created. Supply the "--playlist_id" option first before downloading the videos');
  }

  final outDir = passedOutDir ?? Directory.current.path;
  // Exclusively for logging if you are wondering why this if statement is here
  if (passedOutDir != outDir) {
    settings.logger.info('Using default path of current directory at $outDir');
  }

  // For checking the user-supplied path
  if (!await Directory(outDir).exists()) {
    hardExit('The output directory does not exist');
  }

  // Downloading logic
  final videoInfos =
      (jsonDecode(await videoDataFile.readAsString())['res'] as List<dynamic>)
          .map((e) => VideoInPlaylist.fromJson(e))
          .toList();
  settings.logger.fine('Retrieved video data as $videoInfos');

  final downloadVideoProgress =
      ProgressBar(top: videoInfos.length, innerWidth: 32);
  final periodic =
      Stream.periodic(const Duration(milliseconds: 10)).asyncMap((_) async {
    await downloadVideoProgress.renderInLine((total, current) {
      final percStr =
          chalk.brightCyan('${((current / total) * 100).toStringAsFixed(1)}%');
      final partStr = chalk.brightMagenta(
          '${current.toStringAsFixed(0)}/${total.toStringAsFixed(0)}');
      return '[${ProgressBar.innerProgressBarIdent}] · $percStr · $partStr'; // TODO: ADD ETA LOGIC!
    });
  }).listen((_) => 0);

  final subtitleFp = <String>[];
  // This is only re-assigned once, but we can't make this final (because you can not set a starting value of a final variable and change it again, but if we don't initialize it, then the endVideoPath != null check will fail)
  String? endVideoPath;

  for (final videoData in videoInfos) {
    final res = downloadBestConfAndRetrieveCaptionFilesAndVideoFile(videoData);
    final resBroadcast = res.asBroadcastStream();
    await for (final info in resBroadcast) {
      // FIXNME: Cleanup
      settings.logger.info(info);

      if (info.msgType == DownloadProgressMessageType.subtitle) subtitleFp.add(info.message! as String);
      if (info.msgType == DownloadProgressMessageType.videoFinal) endVideoPath = info.message! as String;

      if (info.msgType == DownloadProgressMessageType.completed) {
        // FIXME: only for now! we have not implemented the other download option yet!
        downloadVideoProgress.increment();

        // DEBUGGING LOGIC!
        // The command can complete without setting subtitleFilePaths and/or endVideoPath to anything useful (e.g. if the file is already downloaded) (I think)
        for (final path in subtitleFp) {
          await File(path).delete();
          settings.logger.info(
              'Deleted subtitle file on path $path'); // FIXME: change to fine
        }
        if (endVideoPath != null) {
          await File(endVideoPath).delete();
          settings.logger.info(
              'Deleted video file on path $endVideoPath'); // FIXME: change to fine
        }

        switch (info.message) {
          case DownloadReturnStatus.processNonZeroExit:
            settings.logger.warning(
              'Video named ${videoData.title} failed to be downloaded, continuing [NOT REALLY THIS IS TESTING THE PERFECT FORMAT DOWNLOAD FOR NOW!]');
            break;
          case DownloadReturnStatus.progressStateStayedUninitialized:
            settings.logger.warning(
              'yt-dlp did not create any video and audio file for video named ${videoData.title}. It is possible that the file is already downloaded, but have not been processed by this program, skipping... [NOT REALLY THIS IS QUITTING THE PROGRAM]');
            break;
        }

        // FIXME: only for now! we have not implemented the other download option yet!
        continue;
      }
    }

    settings.logger.info(await resBroadcast.last);

    // FIXME: right type of doc comment?
          /// Fractional number to represent the download progress if separated onto 4 stages, here it is basically clamped to a max value of 1/4 (0.000 - 1/4) range
          /// The three parts include : downloading video, audio, then mixing subtitles, extracting thumbnail from original video, then embedding captions and thumbnail onto a new video file
          /* final standalonePartProgStr = (double.parse(
                      (progressOut["percentage"] as String)
                          .trim()
                          .replaceFirst(RegExp(r'%'), '')) /
                  100) /
              4;
          downloadVideoProgress.progress = downloadVideoProgress.progress
                  .truncate() +
              (((1 / 4) * (progressState.index - 1)) + standalonePartProgStr); */
    /* // We use single quotes and replace them with double quotes once parsed to circumvent my basic parser (if we use double quotes, it will be stripped out by the parser)
    final downloadVideoBestCmd = cmd_split_args
        .split(videoBestCmd
            .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
            .replaceAll(RegExp(r'<video_id>'), videoData.id)
            .replaceAll(RegExp(r'<output_dir>'), outDir))
        .map((str) => str.replaceAll(RegExp('\''), '"'))
        .toList();
    settings.logger.fine(
        'Starting yt-dlp process for downloading videos using argument $downloadVideoBestCmd');
    final vbProc = await Process.start(
        downloadVideoBestCmd.removeAt(0), downloadVideoBestCmd);

    final broadcastStreams =
        implantDebugLoggerReturnBackStream(vbProc, 'yt-dlp');

    final subtitleFilePaths = <String>[];
    String? endVideoPath;

    // FIXME: right type of doc comment?
    /// Holds the state for which is used to track what state the progress is in
    /// For example, if the state is [ProgressState.video], it is currently downloading video
    /// Likewise, [ProgressState.audio] means it is currently downloading audio
    /// In this case, it is used to keep track of progress to display to the user
    /// [ProgressState.uninitialized] just means we haven't encountered an output that would indicate that yt-dlp is downloading video or audio
    ProgressState progressState = ProgressState
        .uninitialized; // Holds the state of which the logging must be done

    // FIXME: move out of this func?
    await for (final tmpO in broadcastStreams['stdout']!) {
      // There can be multiple lines in 1 stdout message
      for (final output in String.fromCharCodes(tmpO).split('\n')) {
        if (RegExp(r'\[download\]').hasMatch(output) &&
            output.endsWith('.vtt')) {
          subtitleFilePaths.add(output.split(' ').elementAt(2));
          settings.logger.info(subtitleFilePaths); // FIXME: change to fine
        }
        if (RegExp(r'\[Merger\]').hasMatch(output)) {
          // https://stackoverflow.com/questions/27545081/best-way-to-get-all-substrings-matching-a-regexp-in-dart
          endVideoPath =
              RegExp(r'(?<=\")\S+(?=\")').firstMatch(output)!.group(0)!;
          settings.logger
              .info('found end video $endVideoPath'); // FIXME: change to fine
        }

        // TEMP ALTERNATIVE MODE!
        if (RegExp(r'\[download\]').hasMatch(output) &&
            (output.endsWith('.mkv') ||
                output.endsWith('.webm') ||
                output.endsWith('.mp4'))) {
          if (progressState == ProgressState.uninitialized) {
            progressState = ProgressState.video;
          } else {
            progressState = ProgressState.audio;
          }

          settings.logger.info('found $output'); // FIXME: change to fine
        }

        final progressOut = decodeJSONOrFail(output);
        if (progressOut != null &&
            progressState != ProgressState.uninitialized) {
          settings.logger.info(
              'json: $progressOut on mode $progressState'); // FIXME: change to fine

          // FIXME: right type of doc comment?
          /// Fractional number to represent the download progress if separated onto 4 stages, here it is basically clamped to a max value of 1/4 (0.000 - 1/4) range
          /// The three parts include : downloading video, audio, then mixing subtitles, extracting thumbnail from original video, then embedding captions and thumbnail onto a new video file
          final standalonePartProgStr = (double.parse(
                      (progressOut["percentage"] as String)
                          .trim()
                          .replaceFirst(RegExp(r'%'), '')) /
                  100) /
              4;
          downloadVideoProgress.progress = downloadVideoProgress.progress
                  .truncate() +
              (((1 / 4) * (progressState.index - 1)) + standalonePartProgStr);
        }
      } */
    }

    // TODO: save progress on every loop!

    // TODO: FFMPEG LOGIC
    final ffmpegExtrThmbCmd = cmd_split_args
        .split(ffmpegExtractThumbnailCmd.replaceAll(
            RegExp(r'<video_input>'), cookieFile))
        .toList();
    settings.logger.fine(
        'Starting FFmpeg process for extracting thumbnail from video $endVideoPath using argument $ffmpegExtrThmbCmd');
    final dvbProc = await Process.start(
        ffmpegExtrThmbCmd.removeAt(0), ffmpegExtrThmbCmd);

    /*final broadcastStreams =
        implantDebugLoggerReturnBackStream(dvbProc, 'ffmpeg');*/
}

  /* periodic.cancel();
  await downloadVideoProgress.finishRender(); */


void main(List<String> arguments) async {
  Logger.root.level = Level.INFO;

  final argParser = ArgParser();
  argParser.addOption('cookie_file',
      abbr: 'c', help: 'The path to the YouTube cookie file', mandatory: true);
  argParser.addOption('playlist_id',
      abbr: 'p', help: 'The target YouTube playlist ID', mandatory: false);
  argParser.addOption('output_dir',
      abbr: 'o',
      help: 'The target output directory of downloaded videos',
      mandatory: false);
  argParser.addFlag('debug', abbr: 'd', help: 'Logs debug output on a file');

  late final ArgResults parsedArgs;
  try {
    parsedArgs = argParser.parse(arguments);
  } on ArgParserException catch (_) {
    // TODO: add help message for available commands?
    hardExit('TODO LIST AVAILABLE COMMANDS');
  }

  final cookieFile = parsedArgs.option('cookie_file');
  final playlistId = parsedArgs.option('playlist_id');
  final outDir = parsedArgs.option('output_dir');

  if (cookieFile == null) {
    hardExit('"cookie_file" argument not specified or empty');
  }

  if (!await File(cookieFile!).exists()) hardExit('Invalid cookie path given');

  initSettings(cookieFile: cookieFile, playlistId: playlistId, outputDir: outDir);

  if (parsedArgs.flag('debug')) {
    Logger.root.level = Level.ALL;
    final logFile = File(debugLogFileName);
    if (!await logFile.exists()) {
      await logFile.create();
    } else {
      await logFile.writeAsString('',
          flush: true, mode: FileMode.write); // Overwrite with nothing
    }
  }

  // No idea what is it for Unix systems
  // TODO: Figure out for Unix systems
  if (Platform.isWindows) {
    if ((await Process.run('where', ['yt-dlp'])).exitCode != 0) {
      hardExit(
          'Unable to find the yt-dlp command. Verify that yt-dlp is mounted in PATH');
    }
  }

  // We need playlist_id if the user is intending to choose this mode, but we don't explicitly need output_dir to be set
  if ((playlistId ?? '').isNotEmpty) {
    await fetchVideosLogic(cookieFile, playlistId!);
    exit(0);
  } else if (outDir != null) {
    await downloadVideosLogic(cookieFile, outDir);
    exit(0);
  }

  hardExit('Invalid mode of operation');

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
