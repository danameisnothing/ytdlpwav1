import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:chalkdart/chalk.dart';
import 'package:chalkdart/chalk_x11.dart';
import 'package:logging/logging.dart';
import 'package:cli_spin/cli_spin.dart';

import 'package:ytdlpwav1/app_settings/app_settings.dart';
import 'package:ytdlpwav1/app_settings/src/settings.dart';
import 'package:ytdlpwav1/app_ui/src/download_video_ui.dart';
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';
import 'package:ytdlpwav1/app_funcs/app_funcs.dart';

// TODO: split across multiple files
Future<void> fetchVideosLogic(
    Preferences pref, String cookieFile, String playlistId) async {
  final videoDataFile = File(pref.videoDataFileName);
  if (await videoDataFile.exists()) {
    hardExit(
        'File ${pref.videoDataFileName} already exists. Delete / rename the file and try again, or do not supply the "--playlist_id" option to start downloading videos');
    // TODO: actual confirmation prompt to overwrite the file!
  }
  await videoDataFile.create();

  final spinner = CliSpin(spinner: CliSpinners.dots);

  spinner.start('Waiting for yt-dlp output');
  final playlistQuantity =
      await getPlaylistQuantity(pref, cookieFile, playlistId);
  spinner.stop();
  if (playlistQuantity == null) {
    // TODO: improve error message
    hardExit(
        'An error occured while fetching playlist quantity. Use the --debug flag to see more details');
  }

  logger.info('Fetched video quantity in playlist');

  final playlistFetchInfoProgress =
      ProgressBar(top: playlistQuantity, innerWidth: 32);

  final videoInfos = <VideoInPlaylist>[];

  final res = getPlaylistVideoInfos(pref, cookieFile, playlistId);
  await for (final videoInfo in res) {
    videoInfos.add(videoInfo);
    playlistFetchInfoProgress.increment();
    // FIXME: TEST!
    await playlistFetchInfoProgress.renderInLine((total, current) {
      final percStr =
          chalk.brightCyan('${((current / total) * 100).toStringAsFixed(1)}%');
      final partStr =
          chalk.brightMagenta('${current.truncate()}/${total.truncate()}');
      return '[${ProgressBar.innerProgressBarIdent}] · $percStr · $partStr'; // TODO: ADD ETA LOGIC!
    });
  }
  await playlistFetchInfoProgress.finishRender();

  logger.fine('End result is $videoInfos');

  final convertedRes =
      jsonEncode({'res': videoInfos.map((e) => e.toJson()).toList()});

  logger.fine('Converted video info map to $convertedRes');

  await videoDataFile.writeAsString(convertedRes);
}

Future<void> downloadVideosLogic(
    Preferences pref, String cookieFile, String? passedOutDir) async {
  final videoDataFile = File(pref.videoDataFileName);
  if (!await videoDataFile.exists()) {
    // TODO: make unnecessary later on
    hardExit(
        'Video data file has not been created. Supply the "--playlist_id" option first before downloading the videos');
  }

  final outDir = passedOutDir ?? Directory.current.path;
  // Exclusively for logging if you are wondering why
  if (passedOutDir != outDir) {
    logger.info('Using default path of current directory at $outDir');
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
  logger.fine('Retrieved video data as $videoInfos');

  final ui = DownloadVideoUI(videoInfos);

  for (final videoData in videoInfos) {
    // Exclusively for deletion in the case the process exited with a non-zero code
    final subtitleFp = <String>[];
    // This should only be reassigned once
    String? endVideoPath;

    final resBroadcast =
        downloadBestConfAndRetrieveCaptionFilesAndVideoFile(pref, videoData)
            .asBroadcastStream();

    DownloadUIStage stage = DownloadUIStage.stageUninitialized;

    resBroadcast.asyncMap((info) async {
      if (info is CaptionDownloadedMessage) {
        subtitleFp.add(info.captionFilePath);
        logger.fine('Found ${info.captionFilePath} as caption from logic');
      } else if (info is VideoAudioMergedMessage) {
        endVideoPath = info.finalVideoFilePath;
      }

      // FIXME:
      switch (info) {
        case CaptionDownloadingMessage():
        case CaptionDownloadedMessage():
          stage = DownloadUIStage.stageDownloadingCaption;
          break;
        case VideoDownloadingMessage():
        case VideoDownloadedMessage():
          stage = DownloadUIStage.stageDownloadingVideo;
          break;
        case AudioDownloadingMessage():
        case AudioDownloadedMessage():
          stage = DownloadUIStage.stageDownloadingAudio;
          break;
        default:
      }

      await ui.printDownloadVideoUI(stage, info, videoInfos.indexOf(videoData));
    }).listen((_) => 0);

    final lastRet = await resBroadcast.last;

    logger.fine('End result received : $subtitleFp'); // FIXME: change to fine

    // The command can complete without setting subtitleFilePaths and/or endVideoPath to anything useful (e.g. if the file is already downloaded) (I think)
    // FIXME: not robust enough
    if (lastRet is! SuccessMessage) {
      for (final path in subtitleFp) {
        await File(path).delete();
        logger.info(
            'Deleted subtitle file on path $path'); // FIXME: change to fine
      }
      if (endVideoPath != null) {
        await File(endVideoPath!).delete();
        logger.info(
            'Deleted video file on path $endVideoPath'); // FIXME: change to fine
      }
    }

    /*switch (lastRet) {
      case ProcessNonZeroExitMessage():
        pref.logger.warning(
            'Video named ${videoData.title} failed to be downloaded, continuing [NOT REALLY THIS IS TESTING THE PERFECT FORMAT DOWNLOAD FOR NOW!]');
        // In case the process managed to make progress far enough for the program to register that we are making progress, thus incrementing the counter
        downloadVideoProgress.progress =
            downloadVideoProgress.progress.floor() + 1;
        break;
      case ProgressStateStayedUninitializedMessage():
        pref.logger.warning(
            'yt-dlp did not create any video and audio file for video named ${videoData.title}. It is possible that the file is already downloaded, but have not been processed by this program, skipping... [NOT REALLY THIS IS QUITTING THE PROGRAM]');
        exit(0); // FIXME: for dev purposes
      //break;
    }*/

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
    // TODO: save progress on every loop!

    // TODO: FFMPEG LOGIC
    /* final ffmpegExtrThmbCmd = cmd_split_args
        .split(ffmpegExtractThumbnailCmd.replaceAll(
            RegExp(r'<video_input>'), cookieFile))
        .toList();
    settings.logger.fine(
        'Starting FFmpeg process for extracting thumbnail from video $endVideoPath using argument $ffmpegExtrThmbCmd');
    final dvbProc =
        await Process.start(ffmpegExtrThmbCmd.removeAt(0), ffmpegExtrThmbCmd); */
    /*final broadcastStreams =
        implantDebugLoggerReturnBackStream(dvbProc, 'ffmpeg');*/
  }
}

void main(List<String> arguments) async {
  // TODO: Add detection to livestreams on playlist, as that will show the underlying FFmpeg output, with seemingly none of the usual yt-dlp output regarding downloading
  final argParser = ArgParser();
  // TODO: Provide other methods of auth (https://yt-dlp.memoryview.in/docs/advanced-features/authentication-and-cookies-in-yt-dlp), and maybe methods of checking if the cookie file is outdated, as it could lead to missing subtitles in a language (see https://www.youtube.com/watch?v=LuVAWbg4kns for example)
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
    // TODO: add help message for available commands
    hardExit('TODO LIST AVAILABLE COMMANDS');
  }

  final cookieFile = parsedArgs.option('cookie_file');
  final playlistId = parsedArgs.option('playlist_id');
  final outDir = parsedArgs.option('output_dir');

  if (cookieFile == null) {
    hardExit('"cookie_file" argument not specified or empty');
  }

  if (!await File(cookieFile).exists()) hardExit('Invalid cookie path given');

  final preferences = Preferences(
      cookieFilePath: cookieFile,
      playlistId: playlistId,
      outputDirPath: outDir);

  ProcessSignal.sigint.watch().listen((_) {
    logger.info('Received SIGINT, cleaning up');
    ProcessRunner.killAll();
    exit(0);
  });

  Logger.root.level = Level.INFO;
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
      final logFile = File(
          preferences.debugLogFileName); // Guaranteed to exist at this point
      logFile.writeAsStringSync(
          '${rec.time.toIso8601String()} : ${rec.message}${Platform.lineTerminator}',
          flush: true,
          mode: FileMode.append);
      return;
    }
    print('$levelName ${rec.message}');
  });

  if (parsedArgs.flag('debug')) {
    Logger.root.level = Level.ALL;
    final logFile = File(preferences.debugLogFileName);
    if (!await logFile.exists()) {
      await logFile.create();
    } else {
      await logFile.writeAsString('',
          flush: true, mode: FileMode.write); // Overwrite with nothing
    }
  }

  // No idea what is it for Unix systems
  // TODO: Figure out for Unix systems
  // TODO: replace (based on https://github.com/pypa/distutils/blob/main/distutils/spawn.py)
  if (Platform.isWindows) {
    if ((await Process.run('where', ['yt-dlp'])).exitCode != 0) {
      hardExit(
          'Unable to find the yt-dlp command. Verify that yt-dlp is mounted in PATH');
    }
  }
  // TODO: Where the hell is the detection logic for FFmpeg?
  // TODO: check for yt-dlp updates. Out-of-date versions oftentimes causes random HTTP 403 Forbidden errors

  // We need playlist_id if the user is intending to choose this mode, but we don't explicitly need output_dir to be set
  if ((playlistId ?? '').isNotEmpty) {
    await fetchVideosLogic(preferences, cookieFile, playlistId!);
    exit(0);
  } else if (outDir != null) {
    await downloadVideosLogic(preferences, cookieFile, outDir);
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
