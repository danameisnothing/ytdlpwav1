import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:http/http.dart' as http;

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

Future<void> onDownloadFailureBeforeContinuing(
    Preferences pref, List<VideoInPlaylist> videos, VideoInPlaylist vid) async {
  final videoDataFile = File(pref.videoDataFileName);

  logger.fine('before $videos');
  videos.firstWhere((e) => e == vid).hasDownloadedSuccessfully = true;
  logger.fine('after $videos');

  final convertedRes =
      jsonEncode({'res': videos.map((e) => e.toJson()).toList()});

  await videoDataFile.writeAsString(convertedRes,
      flush: true, mode: FileMode.write);
}

Future<bool> doDownloadHandling(
    final DownloadVideoUI ui,
    Preferences pref,
    final VideoInPlaylist videoData,
    final List<VideoInPlaylist> videoInfos,
    final int idxInVideoInfo,
    final bool isSingle) async {
  // Exclusively for deletion in the case the process exited with a non-zero code
  final captionFP = <String>[];
  // This should only be reassigned once
  String? endVideoPath;

  Stream<DownloadReturnStatus> resBroadcast;
  bool isDownloadingPreferredFormat = true;

  resBroadcast = downloadAndRetrieveCaptionFilesAndVideoFile(
          pref, pref.videoPreferredCmd, videoData)
      .asBroadcastStream();
  ui.setUseAllStageTemplates(false);

  DownloadUIStageTemplate stage = DownloadUIStageTemplate.stageUninitialized;

  Future<DownloadReturnStatus> func(info) async {
    if (info is CaptionDownloadedMessage) {
      captionFP.add(info.captionFilePath);
      logger.fine('Found ${info.captionFilePath} as caption from logic');
    } else if (info is VideoAudioMergedMessage) {
      endVideoPath = info.finalVideoFilePath;
      logger.fine('Found $endVideoPath as merged video and audio from logic');
    }

    switch (info) {
      case CaptionDownloadingMessage() || CaptionDownloadedMessage():
        stage = DownloadUIStageTemplate.stageDownloadingCaptions;
        break;
      case VideoDownloadingMessage() || VideoDownloadedMessage():
        stage = DownloadUIStageTemplate.stageDownloadingVideo;
        break;
      case AudioDownloadingMessage() || AudioDownloadedMessage():
        stage = DownloadUIStageTemplate.stageDownloadingAudio;
        break;
    }

    await ui.printDownloadVideoUI(stage, info, idxInVideoInfo);
    return info;
  }

  late Stream lastRetStream;
  lastRetStream = resBroadcast.asyncMap(func).asBroadcastStream(); // What? How?

  final tmpFirst = await resBroadcast.first;

  // Assume we are not able to download in the preferred codec
  if (tmpFirst is ProcessNonZeroExitMessage) {
    logger.warning(
        'Video named ${videoData.title} failed to be downloaded, using fallback command : ${pref.videoRegularCmd}');
    isDownloadingPreferredFormat = false;

    resBroadcast = downloadAndRetrieveCaptionFilesAndVideoFile(
            pref, pref.videoRegularCmd, videoData)
        .asBroadcastStream();
    ui.setUseAllStageTemplates(true);

    lastRetStream =
        resBroadcast.asyncMap(func).asBroadcastStream(); // What? How?
  }

  // Dirty fix to capture first result (to prevent message dropout)
  await func(tmpFirst);

  // Changed due to us prior are not waiting for ui.printDownloadVideoUI to complete in the last moment in the main isolate, so the one inside asyncMap may still be going
  // Listen first to catch all messages, because in the previous version, due to a resBroadcast.first await placed before we register the asyncMap listener, it consumed the first ever event

  final lastRet = await lastRetStream.last;

  logger.fine('End result received : $captionFP');

  // The command can complete without setting subtitleFilePaths and/or endVideoPath to anything useful (e.g. if the file is already downloaded) (I think)
  // FIXME: not robust enough
  if (lastRet is! SuccessMessage) {
    for (final path in captionFP) {
      await File(path).delete();
      logger.fine('Deleted subtitle file on path $path');
    }
    if (endVideoPath != null) {
      await File(endVideoPath!).delete();
      logger.fine('Deleted video file on path $endVideoPath');
    }
  }

  // This block is for handling any other error that is not related to the video failed to be downloaded in our target codec
  switch (lastRet) {
    case ProcessNonZeroExitMessage():
      // TODO: More robust error handling!
      // FIXME: We are not capturing some residual files left by yt-dlp in the case that it errors out, such as leftover thumbnail and .part files while downloading
      logger.warning(
          'Video named ${videoData.title} failed to be downloaded${(!isSingle) ? ', continuing' : ''}');
      // In case the process managed to make progress far enough for the program to register that we are making progress, thus incrementing the counter
      await cleanupGeneratedFiles(
          captionFPs: captionFP, endVideoFP: endVideoPath);
      ui.onDownloadFailure();
      await onDownloadFailureBeforeContinuing(pref, videoInfos, videoData);
      return false;
    //break;
    case ProgressStateStayedUninitializedMessage():
      logger.warning(
          'yt-dlp did not create any video and audio file for video named ${videoData.title}. It is possible that the file is already downloaded, but have not been fully processed by this program${(!isSingle) ? ', continuing...' : ''}');
      await cleanupGeneratedFiles(
          captionFPs: captionFP, endVideoFP: endVideoPath);
      ui.onDownloadFailure();
      await onDownloadFailureBeforeContinuing(pref, videoInfos, videoData);
      return false;
  }

  final ffThumbExtractedPath =
      '${pref.outputDirPath}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.temp.png';
  final ffExtract =
      extractThumbnailFromVideo(pref, endVideoPath!, ffThumbExtractedPath);
  await ui.printExtractThumbnailUI(GenericProgressState.started, endVideoPath!);

  final ret = await ffExtract.last;
  if (ret!.eCode != 0) {
    await cleanupGeneratedFiles(
        captionFPs: captionFP,
        thumbFP: ffThumbExtractedPath,
        endVideoFP: endVideoPath!);
    // TODO: more verbose error message
    hardExit(
        'An error occured while running FFmpeg to extract thumbnail. Use the --debug flag to see more details');
  }

  await ui.printExtractThumbnailUI(
      GenericProgressState.completed, endVideoPath!);

  final mergedFinalVideoFP =
      '"${pref.outputDirPath}${Platform.pathSeparator}${File(endVideoPath!).uri.pathSegments.last.replaceAll(RegExp(r'\_'), ' ').replaceAll(RegExp(r'&'), 'and')}"';

  if (isDownloadingPreferredFormat) {
    final ffMerge = mergeFiles(pref, endVideoPath!, captionFP,
        ffThumbExtractedPath, mergedFinalVideoFP);
    ui.printMergeFilesUI(GenericProgressState.started, mergedFinalVideoFP);

    final ret2 = await ffMerge.last;
    if (ret2!.eCode != 0) {
      await cleanupGeneratedFiles(
          captionFPs: captionFP,
          thumbFP: ffThumbExtractedPath,
          endVideoFP: endVideoPath!);
      // TODO: more verbose error message
      hardExit(
          'An error occured while running FFmpeg to merging files. Use the --debug flag to see more details');
    }
    ui.printMergeFilesUI(GenericProgressState.completed, mergedFinalVideoFP);
  } else {
    ui.printFetchingVideoDataUI(GenericProgressState.started);
    final formerVideoData = await fetchVideoInfo(pref, endVideoPath!);
    ui.printFetchingVideoDataUI(GenericProgressState.started);

    // TODO: proper logic
    final ffReencodeAndMerge = reencodeAndMergeFiles(pref, endVideoPath!,
        captionFP, ffThumbExtractedPath, mergedFinalVideoFP);

    final last = await ffReencodeAndMerge.asyncMap((info) async {
      if (info is ReencodeAndMergeProgress) {
        final fps = double.parse(info.progressData['fps']);
        final approxTotalFrames = int.parse((formerVideoData['streams']
                as List<dynamic>)[0][
            'nb_read_packets']); // *Assume* the video stream is in the first stream
        final frames = int.parse(info.progressData['frame']);

        ui.printReencodeAndMergeFilesUI(
            (int.parse(info.progressData['frame']) / approxTotalFrames) * 100,
            mergedFinalVideoFP,
            frames,
            approxTotalFrames,
            fps,
            (info.progressData['speed'] as String)
                .trim(), // Can be N/A in frame 0
            (info.progressData['bitrate'] as String) // Can be N/A in frame 0
                .trim(),
            (fps.sign == fps)
                ? 'N/A'
                : '~${((approxTotalFrames - frames) / fps).toStringAsFixed(2)}s');
      }

      return info;
    }).last;

    if (last is ReencodeAndMergeProcessNonZeroExitCode) {
      // TODO: More robust error handling!
      logger.warning(
          'An error occured while re-encoding video ${videoData.title} to AV1 and merging it${(!isSingle) ? ', continuing' : ''}');
      // In case the process managed to make progress far enough for the program to register that we are making progress, thus incrementing the counter
      await cleanupGeneratedFiles(
          captionFPs: captionFP, endVideoFP: endVideoPath);
      ui.onDownloadFailure();
      await onDownloadFailureBeforeContinuing(pref, videoInfos, videoData);
      return false;
    }
  }

  await cleanupGeneratedFiles(
      captionFPs: captionFP,
      thumbFP: ffThumbExtractedPath,
      endVideoFP: endVideoPath!);

  await ui.cleanup();

  return true;
}

Future<void> fetchVideosLogic(
    Preferences pref, String cookieFile, String playlistId) async {
  final videoDataFile = File(pref.videoDataFileName);
  if (await videoDataFile.exists()) {
    hardExit(
        'File ${pref.videoDataFileName} already exists. Delete / rename the file and try again');
    // TODO: actual confirmation prompt to overwrite the file!
  }
  await videoDataFile.create();

  final spinner = CliSpin(spinner: CliSpinners.dots);

  spinner.start('Waiting for yt-dlp output');
  final playlistQuantity =
      await getPlaylistQuantity(pref, cookieFile, playlistId);
  spinner.stop();

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
      return '[${ProgressBar.innerProgressBarIdent}] · $percStr · $partStr';
    });
  }
  await playlistFetchInfoProgress.finishRender();

  logger.fine('End result is $videoInfos');

  final convertedRes =
      jsonEncode({'res': videoInfos.map((e) => e.toJson()).toList()});

  logger.fine('Converted video info map to $convertedRes');

  await videoDataFile.writeAsString(convertedRes, flush: true);
}

Future<void> downloadVideosLogic(
    Preferences pref, String cookieFile, String? passedOutDir) async {
  final videoDataFile = File(pref.videoDataFileName);
  if (!await videoDataFile.exists()) {
    // TODO: make unnecessary later on
    hardExit(
        'Video data file has not been created. Use the "fetch" command and try again');
  }

  final outDir = passedOutDir ?? Directory.current.path;
  // Exclusively for logging if you are wondering why
  if (passedOutDir != outDir) {
    logger.info('Using default path of current directory at $outDir');
  }
  // For checking the user-supplied path
  if (!await Directory(outDir).exists()) {
    // TODO: create a confirmation prompt to create the folder?
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
    if (videoData.hasDownloadedSuccessfully) {
      logger.info(
          'Video named ${videoData.title} has already been downloaded successfully, skipping');
      continue;
    }

    final ret = await doDownloadHandling(
        ui, pref, videoData, videoInfos, videoInfos.indexOf(videoData), false);

    if (!ret) {
      // doDownloadHandling already logs the error message at this point, so just continue
      continue;
    }

    videoInfos.firstWhere((e) => e == videoData).hasDownloadedSuccessfully =
        true;
    await videoDataFile.writeAsString(
        jsonEncode({'res': videoInfos.map((e) => e.toJson()).toList()}),
        flush: true);
  }
}

Future<void> downloadSingleVideosLogic(Preferences pref, String cookieFile,
    String? passedOutDir, final String id) async {
  final outDir = passedOutDir ?? Directory.current.path;
  // Exclusively for logging if you are wondering why
  if (passedOutDir != outDir) {
    logger.info('Using default path of current directory at $outDir');
  }
  // For checking the user-supplied path
  if (!await Directory(outDir).exists()) {
    // TODO: create a confirmation prompt to create the folder?
    hardExit('The output directory does not exist');
  }

  final decoyValue = <VideoInPlaylist>[
    VideoInPlaylist('', id, '', '', DateTime.now(), false)
  ]; // FIXME: Placeholder values, quick hack

  final ui = DownloadVideoUI(decoyValue);

  final ret =
      await doDownloadHandling(ui, pref, decoyValue.first, decoyValue, 0, true);

  if (!ret) {
    // doDownloadHandling already logs the error message at this point, so just continue
    return;
  }
}

void main(List<String> args) async {
  // TODO: Add detection to livestreams on playlist, as that will show the underlying FFmpeg output, with seemingly none of the usual yt-dlp output regarding downloading
  // TODO: Provide other methods of auth (see https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies and https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide), as an outdated cookie file could lead to missing subtitles in a language (see https://www.youtube.com/watch?v=LuVAWbg4kns for example)
  final argParser = ArgParser()
    ..addFlag('no_program_check',
        help:
            'Skips checking if you have installed FFmpeg, FFprobe, and yt-dlp. Useful if the program is falsely identifying that you do not have the programs installed',
        negatable: false)
    ..addFlag('no_update_check',
        help:
            'Skips checking for available updates for yt-dlp. Useful if the program consistently fails to check for updates, or is falsely identifying an out-of-date version',
        negatable: false)
    ..addFlag('debug', abbr: 'd', help: 'Logs debug output on a file');

  argParser.addCommand('fetch')
    ..addOption('cookie_file',
        abbr: 'c', help: 'The path to the YouTube cookie file', mandatory: true)
    ..addOption('playlist_id',
        abbr: 'p', help: 'The target YouTube playlist ID', mandatory: true);
  argParser.addCommand('download')
    ..addOption('cookie_file',
        abbr: 'c', help: 'The path to the YouTube cookie file', mandatory: true)
    ..addOption('output_dir',
        abbr: 'o', help: 'The target output directory of downloaded videos');
  argParser.addCommand('download_single')
    ..addOption('cookie_file',
        abbr: 'c', help: 'The path to the YouTube cookie file', mandatory: true)
    ..addOption('output_dir',
        abbr: 'o', help: 'The target output directory of downloaded videos')
    ..addOption('id',
        abbr: 'i', help: 'The video ID to download', mandatory: true);

  late final ArgResults parsedArgs;
  try {
    parsedArgs = argParser.parse(args);
  } on ArgParserException catch (_) {
    // We cannot use hardExit since we haven't set up the logger levels yet
    print(argParser.usage);
    exit(1);
  }

  if (parsedArgs.command == null) hardExit('No valid command specified');

  final preferences = Preferences();

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
      final logFile = File(preferences.debugLogFileName);
      logFile.writeAsStringSync(
          '${rec.time.toIso8601String()} : ${rec.message}${Platform.lineTerminator}',
          flush: true,
          mode: FileMode.append);
      return;
    }
    final toPrint = '$levelName ${rec.message}';
    final upper = (toPrint.length / stdout.terminalColumns).ceil();
    print(
        '$toPrint${List.filled((stdout.terminalColumns * upper) - toPrint.length, ' ').join()}');
  });

  ProcessSignal.sigint.watch().listen((_) {
    logger.info('Received SIGINT, cleaning up');
    ProcessRunner.killAll();
    exit(0);
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

  if (!parsedArgs.flag('no_program_check')) {
    if (!await hasProgramInstalled('yt-dlp')) {
      hardExit(
          'Unable to find yt-dlp. Verify that yt-dlp is mounted in PATH, or pass in --no_program_check to bypass this check');
    }
    if (!await hasProgramInstalled('ffprobe')) {
      hardExit(
          'Unable to find ffprobe. Verify that ffprobe is mounted in PATH, or pass in --no_program_check to bypass this check');
    }
    if (!await hasProgramInstalled('ffmpeg')) {
      hardExit(
          'Unable to find ffmpeg. Verify that ffmpeg is mounted in PATH, or pass in --no_program_check to bypass this check');
    }
  }

  if (!parsedArgs.flag('no_program_check')) {
    final updtRes = await http.get(preferences.ytdlpVersionCheckUri);
    if (updtRes.statusCode != 200) {
      final rlRemaining = int.parse(updtRes.headers['x-ratelimit-remaining']!);
      if (rlRemaining == 0) {
        final rlReset = DateTime.fromMillisecondsSinceEpoch(rlRemaining * 1000);
        logger.fine(
            'Failed to check for yt-dlp updates. Headers : ${updtRes.headers}');
        logger.warning(
            'Failed to check for yt-dlp updates. Rate limit exceeded. Please wait until ${rlReset.hour}:${rlReset.minute} and try again, or pass the --no_update_check flag to bypass this check. Continuing without checking for updates');
      } else {
        logger.fine(
            'Failed to check for yt-dlp updates. Status code : ${updtRes.statusCode}');
        logger.warning(
            'Failed to check for yt-dlp updates. You may not be connected to the Internet. Pass in --no_update_check to bypass this check. Continuing without checking for updates');
      }
    } else {
      final tagNameLatest = jsonDecode(updtRes.body)['tag_name'] as String;
      final tagNameCurrent = String.fromCharCodes(
          await (await ProcessRunner.spawn(
                  name: 'yt-dlp', argument: preferences.ytdlpCheckVersionCmd))
              .stdout
              .last);
      final isUpToDate = List.generate(3, (int i) => i).every((i) =>
          int.parse(tagNameCurrent.split('.').elementAt(i)) >=
          int.parse(tagNameLatest.split('.').elementAt(i)));

      if (!isUpToDate) {
        logger.fine(
            'yt-dlp is currently not up-to-date. Current version detected : $tagNameCurrent, Latest version fetched : $tagNameLatest');
        logger.warning(
            'yt-dlp is currently not up-to-date, yt-dlp may fail to download some videos. Consider updating yt-dlp for best compatibility');
      }
    }
  }

  // TODO: allow user to not use a cookiefile

  switch (parsedArgs.command!.name) {
    case 'fetch':
      final cookieFile = parsedArgs.command!.option('cookie_file');
      final playlistId = parsedArgs.command!.option('playlist_id')!;
      if (!await File((cookieFile ?? '')).exists()) {
        hardExit('Invalid cookie path given');
      }

      preferences
        ..cookieFilePath = cookieFile
        ..playlistId = playlistId;

      await fetchVideosLogic(preferences, cookieFile!, playlistId);
      exit(0);
    case 'download':
      final cookieFile = parsedArgs.command!.option('cookie_file');
      final outDir = parsedArgs.command!.option('output_dir');
      if (!await File((cookieFile ?? '')).exists()) {
        hardExit('Invalid cookie path given');
      }

      preferences
        ..cookieFilePath = cookieFile
        ..outputDirPath = outDir;

      await downloadVideosLogic(preferences, cookieFile!, outDir);
      exit(0);
    case 'download_single':
      final cookieFile = parsedArgs.command!.option('cookie_file');
      final outDir = parsedArgs.command!.option('output_dir');
      final id = parsedArgs.command!.option('id')!;
      if (!await File((cookieFile ?? '')).exists()) {
        hardExit('Invalid cookie path given');
      }

      preferences
        ..cookieFilePath = cookieFile
        ..outputDirPath = outDir;

      await downloadSingleVideosLogic(preferences, cookieFile!, outDir, id);
      exit(0);
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
