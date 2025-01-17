import 'dart:io';

import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmd_split_args;
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/app_settings/app_settings.dart';

enum ProgressState { uninitialized, video, audio }
// TODO: ENUM DOC!
enum DownloadProgressMessageType {
  subtitle,
  videoProgress,
  videoFinal,
  audioProgress,
  endVideo,
  completed
} // 'Completed' is the final ever message from the download function
enum DownloadReturnStatus {
  success,
  processNonZeroExit,
  progressStateStayedUninitialized
}

// TODO: cleanup
Stream<({DownloadProgressMessageType msgType, Object? message})>
    downloadBestConfAndRetrieveCaptionFilesAndVideoFile(VideoInPlaylist videoData) async* {
      // We use single quotes and replace them with double quotes once parsed to circumvent my basic parser (if we use double quotes, it will be stripped out by the parser)
    final downloadVideoBestCmd = cmd_split_args
        .split(videoBestCmd
            .replaceAll(RegExp(r'<cookie_file>'), settings.cookieFilePath!)
            .replaceAll(RegExp(r'<video_id>'), videoData.id)
            .replaceAll(RegExp(r'<output_dir>'), settings.outputDirPath!))
        .map((str) => str.replaceAll(RegExp('\''), '"'))
        .toList();
    settings.logger.fine(
        'Starting yt-dlp process for downloading videos using argument $downloadVideoBestCmd');
    final vbProc = await Process.start(
        downloadVideoBestCmd.removeAt(0), downloadVideoBestCmd);

    final broadcastStreams =
        implantDebugLoggerReturnBackStream(vbProc, 'yt-dlp');

    // FIXME: right type of doc comment?
    /// Holds the state for which is used to track what state the progress is in
    /// For example, if the state is [ProgressState.video], it is currently downloading video
    /// Likewise, [ProgressState.audio] means it is currently downloading audio
    /// In this case, it is used to keep track of progress to display to the user
    /// [ProgressState.uninitialized] just means we haven't encountered an output that would indicate that yt-dlp is downloading video or audio
    ProgressState progressState = ProgressState
        .uninitialized; // Holds the state of which the logging must be done

    // FIXME: move out of this func?
    await for (final tmpO in broadcastStreams.stdout) {
      // There can be multiple lines in 1 stdout message
      for (final output in String.fromCharCodes(tmpO).split('\n')) {
        if (RegExp(r'\[download\]').hasMatch(output) &&
            output.endsWith('.vtt')) {
          final foundSubFn = output.split(' ').elementAt(2);
          settings.logger.info(foundSubFn); // FIXME: change to fine
          yield (msgType: DownloadProgressMessageType.subtitle, message: foundSubFn);
        }
        if (RegExp(r'\[Merger\]').hasMatch(output)) {
          // https://stackoverflow.com/questions/27545081/best-way-to-get-all-substrings-matching-a-regexp-in-dart
          final endVideoFp =
              RegExp(r'(?<=\")\S+(?=\")').firstMatch(output)!.group(0)!;
          settings.logger
              .info('found end video $endVideoFp'); // FIXME: change to finex`
          yield (msgType: DownloadProgressMessageType.videoFinal, message: endVideoFp);
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
          
          // FIXME: improve?
          late final DownloadProgressMessageType retType;
          switch (progressState) {
            case ProgressState.video:
              retType = DownloadProgressMessageType.videoProgress;
              break;
            case ProgressState.audio:
              retType = DownloadProgressMessageType.audioProgress;
            default:
          }
          yield (msgType: retType, message: progressOut["percentage"] as String);
        }
      }
    }

    if (await vbProc.exitCode != 0) {
      yield (msgType: DownloadProgressMessageType.completed, message: DownloadReturnStatus.processNonZeroExit);
      return;
    }
    if (progressState == ProgressState.uninitialized) {
      yield (msgType: DownloadProgressMessageType.completed, message: DownloadReturnStatus.progressStateStayedUninitialized);
      return;
    }

    yield (msgType: DownloadProgressMessageType.completed, message: DownloadReturnStatus.success);
    return;
}