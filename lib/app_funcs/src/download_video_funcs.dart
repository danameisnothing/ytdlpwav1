import 'dart:async';
import 'dart:io';

import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmd_split_args;
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/app_settings/app_settings.dart';

// TODO: ENUM DOC!
enum ProgressState {
  /// Uninitialized means we haven't encountered an output that would indicate that yt-dlp is downloading video or audio
  uninitialized,
  captionDownloaded,
  videoDownloading,
  videoDownloaded,
  audioDownloading,
  audioDownloaded,
  videoAudioMerged
}

abstract class DownloadReturnStatus {
  DownloadReturnStatus();

  factory DownloadReturnStatus.captionDownloaded(
          final String captionFilePath) =>
      CaptionDownloadedMessage(captionFilePath);
  factory DownloadReturnStatus.videoDownloading(
          final Map<String, dynamic> jsonProgressData) =>
      VideoDownloadingMessage(jsonProgressData);
  factory DownloadReturnStatus.videoDownloaded(final String videoFilePath) =>
      VideoDownloadedMessage(videoFilePath);
  factory DownloadReturnStatus.audioDownloading(
          final Map<String, dynamic> jsonProgressData) =>
      AudioDownloadingMessage(jsonProgressData);
  factory DownloadReturnStatus.audioDownloaded(final String audioFilePath) =>
      AudioDownloadedMessage(audioFilePath);
  factory DownloadReturnStatus.videoAudioMerged(
          final String finalVideoFilePath) =>
      VideoAudioMergedMessage(finalVideoFilePath);
  factory DownloadReturnStatus.processNonZeroExit(final int eCode) =>
      ProcessNonZeroExitMessage(eCode);
  factory DownloadReturnStatus.progressStateStayedUninitialized() =>
      ProgressStateStayedUninitializedMessage();
  factory DownloadReturnStatus.success() => SuccessMessage();
}

final class CaptionDownloadedMessage extends DownloadReturnStatus {
  final String captionFilePath;

  CaptionDownloadedMessage(this.captionFilePath) : super();
}

final class VideoDownloadingMessage extends DownloadReturnStatus {
  final Map<String, dynamic> progressData;

  VideoDownloadingMessage(this.progressData) : super();
}

final class VideoDownloadedMessage extends DownloadReturnStatus {
  final String videoFilePath;

  VideoDownloadedMessage(this.videoFilePath) : super();
}

final class AudioDownloadingMessage extends DownloadReturnStatus {
  final Map<String, dynamic> progressData;

  AudioDownloadingMessage(this.progressData) : super();
}

final class AudioDownloadedMessage extends DownloadReturnStatus {
  final String audioFilePath;

  AudioDownloadedMessage(this.audioFilePath) : super();
}

final class VideoAudioMergedMessage extends DownloadReturnStatus {
  final String finalVideoFilePath;

  VideoAudioMergedMessage(this.finalVideoFilePath) : super();
}

final class ProcessNonZeroExitMessage extends DownloadReturnStatus {
  final int eCode;

  ProcessNonZeroExitMessage(this.eCode) : super();
}

final class ProgressStateStayedUninitializedMessage
    extends DownloadReturnStatus {
  ProgressStateStayedUninitializedMessage() : super();
}

final class SuccessMessage extends DownloadReturnStatus {
  SuccessMessage() : super();
}

// TODO: cleanup
Stream<DownloadReturnStatus>
    downloadBestConfAndRetrieveCaptionFilesAndVideoFile(
        VideoInPlaylist videoData) async* {
  final proc = await ProcessRunner.spawn(
      name: 'yt-dlp',
      argument: videoBestCmd,
      replacements: {
        TemplateReplacements.cookieFile: Preferences.cookieFilePath!,
        TemplateReplacements.videoId: videoData.id,
        TemplateReplacements.outputDir: Preferences.outputDirPath!
      });
  Preferences.logger.fine(
      'Started yt-dlp process for downloading video with best configuration');

  // FIXME: swap with a class or something, like the sealed class that we have been using up until now?
  ProgressState state = ProgressState
      .uninitialized; // Holds the state of which the logging must be done

  // FIXME: move out of this func?
  await for (final tmpO in proc.stdout) {
    // There can be multiple lines in 1 stdout message
    for (final output in String.fromCharCodes(tmpO).split('\n')) {
      if (RegExp(r'\[download\]').hasMatch(output) && output.endsWith('.vtt')) {
        state = ProgressState.captionDownloaded;

        final foundCaptFn = output.split(' ').elementAt(2);
        Preferences.logger
            .info("Found caption file : $foundCaptFn"); // FIXME: change to fine
        yield DownloadReturnStatus.captionDownloaded(foundCaptFn);
      }
      if (RegExp(r'\[Merger\]').hasMatch(output)) {
        state = ProgressState.videoAudioMerged;

        // https://stackoverflow.com/questions/27545081/best-way-to-get-all-substrings-matching-a-regexp-in-dart
        final endVideoFp =
            RegExp(r'(?<=\")\S+(?=\")').firstMatch(output)!.group(0)!;
        Preferences.logger
            .info('Found merged video : $endVideoFp'); // FIXME: change to fine
        yield DownloadReturnStatus.videoAudioMerged(endVideoFp);
      }

      // FIXME: TEMP ALTERNATIVE MODE!
      // This output is actually yt-dlp choosing the target directory before downloading the media
      if (RegExp(r'\[download\]').hasMatch(output) &&
          (output.endsWith('.mkv') ||
              output.endsWith('.webm') ||
              output.endsWith('.mp4'))) {
        if (state == ProgressState.uninitialized) {
          state = ProgressState.videoDownloading;
          Preferences.logger.info(
              'Found video soon-to-be downloaded : $output'); // FIXME: change to fine
        } else {
          state = ProgressState.audioDownloading;
          Preferences.logger.info(
              'Found audio soon-to-be downloaded : $output'); // FIXME: change to fine
        }
      }

      final progressOut = decodeJSONOrFail(output);
      if (progressOut != null && state != ProgressState.uninitialized) {
        Preferences.logger.info(
            'yt-dlp JSON output : $progressOut on mode $state'); // FIXME: change to fine

        // Only return progress on video and audio downloads. Caption download progress are mostly insignificant (finishes too fast)
        if (state == ProgressState.videoDownloading) {
          yield DownloadReturnStatus.videoDownloading(progressOut);
        } else if (state == ProgressState.audioDownloading) {
          yield DownloadReturnStatus.audioDownloading(progressOut);
        }
      }
    }
  }

  if (await proc.process.exitCode != 0) {
    yield DownloadReturnStatus.processNonZeroExit(await proc.process.exitCode);
    return;
  }
  if (state == ProgressState.uninitialized) {
    yield DownloadReturnStatus.progressStateStayedUninitialized();
    return;
  }

  yield DownloadReturnStatus.success();
  return;
}
