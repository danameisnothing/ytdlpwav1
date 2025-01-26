import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:ansi_strip/ansi_strip.dart';
import 'package:args/args.dart';
import 'package:chalkdart/chalk.dart';
import 'package:chalkdart/chalk_x11.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:logging/logging.dart';

import 'package:ytdlpwav1/app_settings/app_settings.dart' as app_settings;
import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmd_split_args;
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';
import 'package:ytdlpwav1/app_funcs/app_funcs.dart';

// TODO: change to singleton?
sealed class DownloadVideosUIData {
  static DownloadReturnStatus? lastReturnValue;
  static String? mediaTitleOrVideoTitle;

  /// To indicate whether we should display the video title in YouTube, or the downloaded media name
  static bool hasReceivedMediaUpdateEver = false;

  /// A variable that indicates the current stage of the download process per video!
  static int stagePerVideo = 0;

  static void reset() {
    lastReturnValue = null;
    mediaTitleOrVideoTitle = null;
    hasReceivedMediaUpdateEver = false;
    stagePerVideo = 0;
  }
}

Future fetchVideosLogic(String cookieFile, String playlistId) async {
  final videoDataFile = File(app_settings.videoDataFileName);
  if (await videoDataFile.exists()) {
    hardExit(
        'File ${app_settings.videoDataFileName} already exists. Delete / rename the file and try again, or do not supply the "--playlist_id" option to start downloading videos');
    // TODO: actual confirmation prompt to overwrite the file!
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

  app_settings.Preferences.logger.info('Fetched video quantity in playlist');

  final playlistFetchInfoProgress =
      ProgressBar(top: playlistQuantity, innerWidth: 32);

  final videoInfos = <VideoInPlaylist>[];

  final res = getPlaylistVideoInfos(cookieFile, playlistId);
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

  app_settings.Preferences.logger.fine('End result is $videoInfos');

  final convertedRes =
      jsonEncode({'res': videoInfos.map((e) => e.toJson()).toList()});

  app_settings.Preferences.logger
      .fine('Converted video info map to $convertedRes');

  await videoDataFile.writeAsString(convertedRes);
}

Future downloadVideosLogic(String cookieFile, String? passedOutDir) async {
  final videoDataFile = File(app_settings.videoDataFileName);
  if (!await videoDataFile.exists()) {
    hardExit(
        'Video data file has not been created. Supply the "--playlist_id" option first before downloading the videos');
  }

  final outDir = passedOutDir ?? Directory.current.path;
  // Exclusivel y for logging if you are wondering why this if statement is here
  if (passedOutDir != outDir) {
    Preferences.logger
        .info('Using default path of current directory at $outDir');
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
  Preferences.logger.fine('Retrieved video data as $videoInfos');

  final downloadVideoProgress = ProgressBar(
      top: videoInfos.length,
      innerWidth: 32,
      renderFunc: (total, current) {
        return '[${ProgressBar.innerProgressBarIdent}]';
      });
  final periodic =
      Stream.periodic(const Duration(milliseconds: 10)).asyncMap((_) async {
    // FIXME: all of these UI mapping stuff moved to separate function?
    late final String? videoAudioMapping;
    switch (DownloadVideosUIData.lastReturnValue) {
      case CaptionDownloadedMessage():
        videoAudioMapping = chalk.magentaBright('(caption)');
        break;
      case VideoDownloadingMessage():
      case VideoDownloadedMessage():
        videoAudioMapping = chalk.blueBright('(video)');
        break;
      case AudioDownloadingMessage():
      case AudioDownloadedMessage():
        videoAudioMapping = chalk.greenBright('(audio)');
        break;
      default:
        videoAudioMapping = null;
        break;
    }

    // FIXME: improve, is this even necessary?
    // A variable that holds the progressData of lastReturnValue pulled from their respective classes
    late final Map<String, dynamic>? progDataLocal;
    switch (DownloadVideosUIData.lastReturnValue) {
      case VideoDownloadingMessage():
        progDataLocal =
            (DownloadVideosUIData.lastReturnValue as VideoDownloadingMessage)
                .progressData;
        break;
      case VideoDownloadedMessage():
        progDataLocal =
            (DownloadVideosUIData.lastReturnValue as VideoDownloadedMessage)
                .progressData;
        break;
      case AudioDownloadingMessage():
        progDataLocal =
            (DownloadVideosUIData.lastReturnValue as AudioDownloadingMessage)
                .progressData;
        break;
      case AudioDownloadedMessage():
        progDataLocal =
            (DownloadVideosUIData.lastReturnValue as AudioDownloadedMessage)
                .progressData;
        break;
      default:
        // They do not have the progressData field
        progDataLocal = null;
        break;
    }

    final String? progStr =
        (progDataLocal != null) ? progDataLocal['percentage'] : null;

    // When we pass this check, the last message are either downloading / downloaded video / audio
    if (progStr != null) {
      final standalonePartProgStr =
          (double.parse(progStr.trim().replaceFirst(RegExp(r'%'), '')) / 100) /
              4;

      // FIXME:
      switch (DownloadVideosUIData.lastReturnValue) {
        case VideoDownloadingMessage():
        case VideoDownloadedMessage():
          downloadVideoProgress.progress =
              downloadVideoProgress.progress.truncate() +
                  ((((DownloadVideosUIData.stagePerVideo + 1) / 4) * 0) +
                      standalonePartProgStr);
          break;
        case AudioDownloadingMessage():
        case AudioDownloadedMessage():
          downloadVideoProgress.progress =
              downloadVideoProgress.progress.truncate() +
                  ((((DownloadVideosUIData.stagePerVideo + 1) / 4) * 1) +
                      standalonePartProgStr);
        default:
          break;
      }
    }

    late final String stageMapping;
    switch (DownloadVideosUIData.stagePerVideo) {
      case 0:
        stageMapping = 'Downloading Video';
        break;
      case 1:
        stageMapping = 'Downloading Audio';
        break;
      case 2:
        stageMapping = 'TODO: FFMPEG'; // FIXME: REPLACE
        break;
      case 3:
        stageMapping = 'TODO: TBA'; // FIXME: REPLACE
        break;
      default:
        throw Exception(); // FIXME: remove, just for debugging in case something incremented beyond
      // break;
    }

    late final String? bytesDownloadedMapping;
    if (progDataLocal != null) {
      final trm = (progDataLocal['bytes_downloaded'] as String).trim();
      if (trm.contains('N/A')) {
        bytesDownloadedMapping = null;
      } else {
        bytesDownloadedMapping = trm;
      }
    } else {
      bytesDownloadedMapping = null;
    }

    late final String? bytesTotalMapping;
    if (progDataLocal != null) {
      final trm = (progDataLocal['bytes_total'] as String).trim();
      if (trm.contains('N/A')) {
        bytesTotalMapping = null;
      } else {
        bytesTotalMapping = trm;
      }
    } else {
      bytesTotalMapping = null;
    }

    // FIXME: also check for mediaTitleOrVideoTitle is null, not required since if hasReceivedMediaUpdateEver is false, then this mediaTitleOrVideoTitle is null
    final templateStr =
        """Downloading : ${(DownloadVideosUIData.hasReceivedMediaUpdateEver && videoAudioMapping != null) ? '${chalk.brightCyan(DownloadVideosUIData.mediaTitleOrVideoTitle!)} $videoAudioMapping' : chalk.brightCyan(chalk.brightCyan(DownloadVideosUIData.mediaTitleOrVideoTitle!))}
[${downloadVideoProgress.generateProgressBar()}] ${chalk.brightCyan('${map(downloadVideoProgress.progress, 0, downloadVideoProgress.top, 0, 100)}%')}
Stage ${DownloadVideosUIData.stagePerVideo + 1}/4 $stageMapping\t${(bytesDownloadedMapping != null) ? bytesDownloadedMapping : '0.0MiB'}/${(bytesTotalMapping != null) ? bytesTotalMapping : '0.0MiB'}""";
    final chunked = templateStr.split('\n').map((str) {
      final strLen = stripAnsi(str).length;
      // Handle us not having enough space to print the base message
      // TODO: CHECK IF THIS IS FINE
      return '$str${(stdout.terminalColumns < strLen) ? List.filled(stdout.terminalColumns, ' ').join() : List.filled(stdout.terminalColumns - strLen, ' ').join()}';
    }).join('\n');

    // Joined it all to prevent cursor jerking around
    stdout.write('$chunked\r\x1b[${templateStr.split('\n').length}A');
    await stdout.flush();
  }).listen((_) => 0);

  for (final videoData in videoInfos) {
    // Reset data for the UI to update accordingly
    DownloadVideosUIData.reset();
    // Set our appropriate stage
    DownloadVideosUIData.stagePerVideo = 0;
    DownloadVideosUIData.mediaTitleOrVideoTitle = videoData.title;

    // Exclusively for deletion incase the process exited with a non-zero code
    final subtitleFp = <String>[];
    // This should only be reassigned once
    String? endVideoPath;

    final resBroadcast =
        downloadBestConfAndRetrieveCaptionFilesAndVideoFile(videoData)
            .asBroadcastStream();

    resBroadcast.forEach((info) async {
      DownloadVideosUIData.lastReturnValue = info;

      // FIXME: IMPROVE!
      switch (info) {
        case VideoDownloadingMessage():
          DownloadVideosUIData.hasReceivedMediaUpdateEver = true;
          DownloadVideosUIData.mediaTitleOrVideoTitle = info.videoFilePath;
          break;
        case VideoDownloadedMessage():
          DownloadVideosUIData.hasReceivedMediaUpdateEver = true;
          DownloadVideosUIData.mediaTitleOrVideoTitle = info.videoFilePath;
          break;
        case AudioDownloadingMessage():
          DownloadVideosUIData.hasReceivedMediaUpdateEver = true;
          DownloadVideosUIData.mediaTitleOrVideoTitle = info.audioFilePath;
          break;
        case AudioDownloadedMessage():
          DownloadVideosUIData.hasReceivedMediaUpdateEver = true;
          DownloadVideosUIData.mediaTitleOrVideoTitle = info.audioFilePath;
          break;
        default:
          break;
      }

      if (info is CaptionDownloadedMessage) {
        subtitleFp.add(info.captionFilePath);
      } else if (info is VideoAudioMergedMessage) {
        endVideoPath = info.finalVideoFilePath;
      }
    });

    final lastRet = await resBroadcast.last;

    // The command can complete without setting subtitleFilePaths and/or endVideoPath to anything useful (e.g. if the file is already downloaded) (I think)
    if (lastRet is! SuccessMessage) {
      for (final path in subtitleFp) {
        await File(path).delete();
        Preferences.logger.info(
            'Deleted subtitle file on path $path'); // FIXME: change to fine
      }
      if (endVideoPath != null) {
        await File(endVideoPath!).delete();
        Preferences.logger.info(
            'Deleted video file on path $endVideoPath'); // FIXME: change to fine
      }
    }

    switch (lastRet) {
      case ProcessNonZeroExitMessage():
        Preferences.logger.warning(
            'Video named ${videoData.title} failed to be downloaded, continuing [NOT REALLY THIS IS TESTING THE PERFECT FORMAT DOWNLOAD FOR NOW!]');
        // In case the process managed to make progress far enough for the program to register that we are making progress, thus incrementing the counter
        downloadVideoProgress.progress =
            downloadVideoProgress.progress.floor() + 1;
        break;
      case ProgressStateStayedUninitializedMessage():
        Preferences.logger.warning(
            'yt-dlp did not create any video and audio file for video named ${videoData.title}. It is possible that the file is already downloaded, but have not been processed by this program, skipping... [NOT REALLY THIS IS QUITTING THE PROGRAM]');
        exit(0); // FIXME: for dev purposes
      //break;
    }

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
  periodic.cancel();
  await downloadVideoProgress.finishRender();
}

void main(List<String> arguments) async {
  // TODO: Add detection to livestreams on playlist, as that will show the underlying FFmpeg output, with seemingly none of the usual yt-dlp output regarding downloading
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

  Preferences.initSettings(
      cookieFile: cookieFile, playlistId: playlistId, outputDir: outDir);
  ProcessSignal.sigint.watch().listen((_) {
    Preferences.logger.info('Received SIGINT, cleaning up');
    ProcessRunner.killAll();
    exit(0);
  });

  Logger.root.level = Level.INFO;
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
  // TODO: Where the hell is the detection logic for FFmpeg?
  // TODO: check for yt-dlp updates. Out-of-date versions oftentimes causes random HTTP 403 Forbidden errors

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
