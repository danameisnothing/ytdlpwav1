import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';
import 'package:cli_spin/cli_spin.dart';

import 'package:ytdlpwav1/app_settings/app_settings.dart';
import 'package:ytdlpwav1/app_settings/src/settings.dart';
import 'package:ytdlpwav1/app_ui/src/download_video_ui.dart';
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';
import 'package:ytdlpwav1/app_funcs/app_funcs.dart';

Future<void> cleanupGeneratedFiles(
    {required List<String> captionFPs,
    String? thumbFP,
    String? endVideoFP}) async {
  for (final path in captionFPs) {
    final fSub = File(path);
    if (await fSub.exists()) await fSub.delete();
  }

  if (endVideoFP != null) {
    final fEV = File(endVideoFP);
    if (await fEV.exists()) await fEV.delete();
  }

  if (thumbFP != null) {
    final fThumb = File(thumbFP);
    if (await fThumb.exists()) await fThumb.delete();
  }
}

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
    final captionFP = <String>[];
    // This should only be reassigned once
    String? endVideoPath;

    Stream<DownloadReturnStatus> resBroadcast;
    bool isDownloadingPreferredFormat = true;

    resBroadcast = downloadAndRetrieveCaptionFilesAndVideoFile(
            pref, pref.videoPreferredCmd, videoData)
        .asBroadcastStream();
    ui.setUseAllStageTemplates(true);

    DownloadUIStageTemplate stage = DownloadUIStageTemplate.stageUninitialized;

    // Assume we are not able to download in the preferred codec
    if (await resBroadcast.first is ProcessNonZeroExitMessage) {
      logger.warning(
          'Video named ${videoData.title} failed to be downloaded, using fallback command : ${pref.videoRegularCmd}');
      isDownloadingPreferredFormat = false;

      resBroadcast = downloadAndRetrieveCaptionFilesAndVideoFile(
              pref, pref.videoRegularCmd, videoData)
          .asBroadcastStream();
      ui.setUseAllStageTemplates(false);
    }

    // Changed due to us prior are not waiting for ui.printDownloadVideoUI to complete in the last moment in the main isolate, so the one inside asyncMap may still be going
    final lastRet = await resBroadcast.asyncMap((info) async {
      if (info is CaptionDownloadedMessage) {
        captionFP.add(info.captionFilePath);
        logger.fine('Found ${info.captionFilePath} as caption from logic');
      } else if (info is VideoAudioMergedMessage) {
        endVideoPath = info.finalVideoFilePath;
        logger.fine('Found $endVideoPath as merged video and audio from logic');
      }

      // FIXME:
      switch (info) {
        case CaptionDownloadingMessage():
        case CaptionDownloadedMessage():
          stage = DownloadUIStageTemplate.stageDownloadingCaptions;
          break;
        case VideoDownloadingMessage():
        case VideoDownloadedMessage():
          stage = DownloadUIStageTemplate.stageDownloadingVideo;
          break;
        case AudioDownloadingMessage():
        case AudioDownloadedMessage():
          stage = DownloadUIStageTemplate.stageDownloadingAudio;
          break;
        default:
          break;
      }

      await ui.printDownloadVideoUI(stage, info, videoInfos.indexOf(videoData));
      return info;
    }).last;

    logger.fine('End result received : $captionFP');

    // The command can complete without setting subtitleFilePaths and/or endVideoPath to anything useful (e.g. if the file is already downloaded) (I think)
    // FIXME: not robust enough
    if (lastRet is! SuccessMessage) {
      for (final path in captionFP) {
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

    // This block is for handling any other error that is not related to the video failed to be downloaded in our target codec
    switch (lastRet) {
      case ProcessNonZeroExitMessage():
        // TODO: More robust error handling!
        // FIXME: We are not capturing some residual files left by yt-dlp in the case that it errors out, such as leftover thumbnail and .part files while downloading
        logger.warning(
            'Video named ${videoData.title} failed to be downloaded, continuing');
        // In case the process managed to make progress far enough for the program to register that we are making progress, thus incrementing the counter
        await cleanupGeneratedFiles(
            captionFPs: captionFP, endVideoFP: endVideoPath);
        ui.onDownloadFailure();
        continue;
      //break;
      case ProgressStateStayedUninitializedMessage():
        // TODO: save progress too!
        logger.warning(
            'yt-dlp did not create any video and audio file for video named ${videoData.title}. It is possible that the file is already downloaded, but have not been fully processed by this program, skipping...');
        await cleanupGeneratedFiles(
            captionFPs: captionFP, endVideoFP: endVideoPath);
        ui.onDownloadFailure();
        continue; // FIXME: for dev purposes
    }

    // TODO: save progress on every loop!
    final ffThumbExtractedPath =
        '${pref.outputDirPath}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.temp.png';
    final ffExtract =
        extractThumbnailFromVideo(pref, endVideoPath!, ffThumbExtractedPath);
    await ui.printExtractThumbnailUI(FFmpegExtractThumb.started, endVideoPath!);

    final ret = await ffExtract.last;
    if (ret!.eCode != 0) {
      await cleanupGeneratedFiles(
          captionFPs: captionFP,
          thumbFP: ffThumbExtractedPath,
          endVideoFP: endVideoPath!);
      // TODO: more verbose error message
      // FIXME: CHANGE TO ONLY WARNING, AND CONTINUE TO THE NEXT VIDEO (while saving the progress)!
      hardExit(
          'An error occured while running FFmpeg to extract thumbnail. Use the --debug flag to see more details');
    }

    await ui.printExtractThumbnailUI(
        FFmpegExtractThumb.completed, endVideoPath!);

    final mergedFinalVideoFP =
        '"${pref.outputDirPath}${Platform.pathSeparator}${File(endVideoPath!).uri.pathSegments.last.replaceAll(RegExp(r'\_'), ' ')}"'; // FIXME: improve

    if (isDownloadingPreferredFormat) {
      final ffMerge = mergeFiles(pref, endVideoPath!, captionFP,
          ffThumbExtractedPath, mergedFinalVideoFP);
      ui.printMergeFilesUI(FFmpegMergeFilesState.started, mergedFinalVideoFP);

      final ret2 = await ffMerge.last;
      if (ret2!.eCode != 0) {
        await cleanupGeneratedFiles(
            captionFPs: captionFP,
            thumbFP: ffThumbExtractedPath,
            endVideoFP: endVideoPath!);
        // TODO: more verbose error message
        // FIXME: CHANGE TO ONLY WARNING, AND CONTINUE TO THE NEXT VIDEO (while saving the progress)!
        hardExit(
            'An error occured while running FFmpeg to merging files. Use the --debug flag to see more details');
      }
      ui.printMergeFilesUI(FFmpegMergeFilesState.completed, mergedFinalVideoFP);
    } else {
      ui.printFetchingVideoDataUI(FFprobeFetchVideoDataState.started);
      final formerVideoData = await fetchVideoInfo(pref, endVideoPath!);
      ui.printFetchingVideoDataUI(FFprobeFetchVideoDataState.started);

      // TODO: proper logic
      final ffReencodeAndMerge = reencodeAndMergeFiles(pref, endVideoPath!,
          captionFP, ffThumbExtractedPath, mergedFinalVideoFP);

      final last = await ffReencodeAndMerge.asyncMap((info) async {
        if (info is ReencodeAndMergeProgress) {
          ui.printReencodeAndMergeFilesUI(
              (int.parse(info.progressData['frame']) /
                      int.parse((formerVideoData['streams'] as List<dynamic>)[0]
                          ['nb_read_frames'])) *
                  100,
              mergedFinalVideoFP); // *Assume* the video stream is in the first stream
        }

        return info;
      }).last;

      if (last is ReencodeAndMergeProcessNonZeroExitCode) {
        // TODO: More robust error handling!
        logger.warning(
            'An error occured while re-encoding video ${videoData.title} to AV1 and merging it, continuing');
        // In case the process managed to make progress far enough for the program to register that we are making progress, thus incrementing the counter
        await cleanupGeneratedFiles(
            captionFPs: captionFP, endVideoFP: endVideoPath);
        ui.onDownloadFailure();
        continue;
      }
    }

    await cleanupGeneratedFiles(
        captionFPs: captionFP,
        thumbFP: ffThumbExtractedPath,
        endVideoFP: endVideoPath!);
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
  // TODO: The same detection logic for FFmpeg
  // TODO: The same detection logic for FFprobe
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
