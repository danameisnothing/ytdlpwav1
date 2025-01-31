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

    final resBroadcast = downloadAndRetrieveCaptionFilesAndVideoFile(
            pref, pref.videoBestCmd, videoData)
        .asBroadcastStream();

    DownloadUIStage stage = DownloadUIStage.stageUninitialized;

    // Changed due to us prior are not waiting for ui.printDownloadVideoUI to complete in the last moment in the main isolate, so the one inside asyncMap may still be going
    final lastRet = await resBroadcast.asyncMap((info) async {
      if (info is CaptionDownloadedMessage) {
        subtitleFp.add(info.captionFilePath);
        logger.fine('Found ${info.captionFilePath} as caption from logic');
      } else if (info is VideoAudioMergedMessage) {
        endVideoPath = info.finalVideoFilePath;
        logger.fine('Found $endVideoPath as merged video and audio from logic');
      }

      // FIXME:
      switch (info) {
        case CaptionDownloadingMessage():
        case CaptionDownloadedMessage():
          stage = DownloadUIStage.stageDownloadingCaptions;
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
          break;
      }

      await ui.printDownloadVideoUI(stage, info, videoInfos.indexOf(videoData));
      return info;
    }).last;

    logger.fine('End result received : $subtitleFp');

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

    switch (lastRet) {
      case ProcessNonZeroExitMessage():
        logger.warning(
            'Video named ${videoData.title} failed to be downloaded, continuing [NOT REALLY THIS IS TESTING THE PERFECT FORMAT DOWNLOAD FOR NOW!]');
        // In case the process managed to make progress far enough for the program to register that we are making progress, thus incrementing the counter
        ui.onDownloadFailure();
        continue;
      //break;
      case ProgressStateStayedUninitializedMessage():
        logger.warning(
            'yt-dlp did not create any video and audio file for video named ${videoData.title}. It is possible that the file is already downloaded, but have not been processed by this program, skipping... [NOT REALLY THIS IS QUITTING THE PROGRAM]');
        ui.onDownloadFailure();
        continue; // FIXME: for dev purposes
      //break;
    }

    // TODO: save progress on every loop!
    // FIXME: only temporary hardcoded thumb.temp.png here! Put this setting on the launch arguments
    final ffThumbExtractedPath =
        '${pref.outputDirPath}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.temp.png';
    final ffExtract =
        extractThumbnailFromVideo(pref, endVideoPath!, ffThumbExtractedPath);
    await ui.printExtractThumbnailUI(FFmpegExtractThumb.started, endVideoPath!);

    final ret = await ffExtract.last;
    if (ret!.eCode != 0) {
      // TODO: more verbose error message
      hardExit(
          'An error occured while running FFmpeg to extract thumbnail. Use the --debug flag to see more details');
    }

    await ui.printExtractThumbnailUI(
        FFmpegExtractThumb.completed, endVideoPath!);

    final mergedVideoPath =
        '"${pref.outputDirPath}${Platform.pathSeparator}${File(endVideoPath!).uri.pathSegments.last.replaceAll(RegExp(r'\_'), ' ')}"'; // FIXME: improve
    // TODO:
    final proc = await ProcessRunner.spawn(
        name: 'ffmpeg',
        argument: pref.ffmpegCombineFinalVideo,
        replacements: {
          TemplateReplacements.videoInput: endVideoPath!,
          TemplateReplacements.captionsInputFlags: List<String>.generate(
                  subtitleFp.length, (i) => '-i "${subtitleFp.elementAt(i)}"',
                  growable: false)
              .join(' '),
          TemplateReplacements
              .captionTrackMappingMetadata: List<String>.generate(
                  subtitleFp.length,
                  (i) =>
                      '-map ${i + 1} -c:s:$i copy -metadata:s:$i language="en"', // TODO: add logic for language detection. for now it is hardcoded to be en
                  growable: false)
              .join(' '),
          TemplateReplacements.thumbIn: ffThumbExtractedPath,
          TemplateReplacements.finalOut: mergedVideoPath
        });
    logger
        .fine('Started FFmpeg process for merging files on to the final video');

    ui.printMergeFilesUI(FFmpegMergeFilesState.started, mergedVideoPath);

    if (await proc.process.exitCode != 0) {
      // TODO: more verbose error message
      hardExit(
          'An error occured while running FFmpeg to merging files. Use the --debug flag to see more details');
    }
    ui.printMergeFilesUI(FFmpegMergeFilesState.completed, mergedVideoPath);

    // Cleanup no matter what
    // TODO: do this to the instances where it failed to download, similar to Go's defer statement
    for (final path in subtitleFp) {
      final fSub = File(path);
      if (await fSub.exists()) await fSub.delete();
    }
    final fEV = File(endVideoPath!);
    if (await fEV.exists()) await fEV.delete();
    final fThumb = File(ffThumbExtractedPath);
    if (await fThumb.exists()) await fThumb.delete();
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
