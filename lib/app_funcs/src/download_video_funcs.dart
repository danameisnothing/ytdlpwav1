import 'dart:async';

import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/app_settings/app_settings.dart';

// TODO: ENUM DOC!
enum ProgressState {
  /// Uninitialized means we haven't encountered an output that would indicate that yt-dlp is downloading video or audio
  uninitialized,
  captionDownloading,
  captionDownloaded,
  videoDownloading,
  videoDownloaded,
  audioDownloading,
  audioDownloaded,
  videoAudioMerged
}

abstract class DownloadReturnStatus {
  DownloadReturnStatus();

  factory DownloadReturnStatus.captionDownloading(final String captionFilePath,
          final Map<String, dynamic> jsonProgressData) =>
      CaptionDownloadedMessage(captionFilePath, jsonProgressData);
  factory DownloadReturnStatus.captionDownloaded(final String captionFilePath,
          final Map<String, dynamic> jsonProgressData) =>
      CaptionDownloadedMessage(captionFilePath, jsonProgressData);
  factory DownloadReturnStatus.videoDownloading(final String videoFilePath,
          final Map<String, dynamic> jsonProgressData) =>
      VideoDownloadingMessage(videoFilePath, jsonProgressData);
  factory DownloadReturnStatus.videoDownloaded(final String videoFilePath,
          final Map<String, dynamic> jsonProgressData) =>
      VideoDownloadedMessage(videoFilePath, jsonProgressData);
  factory DownloadReturnStatus.audioDownloading(final String audioFilePath,
          final Map<String, dynamic> jsonProgressData) =>
      AudioDownloadingMessage(audioFilePath, jsonProgressData);
  factory DownloadReturnStatus.audioDownloaded(final String audioFilePath,
          final Map<String, dynamic> jsonProgressData) =>
      AudioDownloadedMessage(audioFilePath, jsonProgressData);
  factory DownloadReturnStatus.videoAudioMerged(
          final String finalVideoFilePath) =>
      VideoAudioMergedMessage(finalVideoFilePath);
  factory DownloadReturnStatus.processNonZeroExit(final int eCode) =>
      ProcessNonZeroExitMessage(eCode);
  factory DownloadReturnStatus.progressStateStayedUninitialized() =>
      ProgressStateStayedUninitializedMessage();
  factory DownloadReturnStatus.success() => SuccessMessage();
}

final class CaptionDownloadingMessage extends DownloadReturnStatus {
  final String captionFilePath;
  final Map<String, dynamic> progressData;

  CaptionDownloadingMessage(this.captionFilePath, this.progressData) : super();
}

final class CaptionDownloadedMessage extends DownloadReturnStatus {
  final String captionFilePath;
  final Map<String, dynamic> progressData;

  CaptionDownloadedMessage(this.captionFilePath, this.progressData) : super();
}

final class VideoDownloadingMessage extends DownloadReturnStatus {
  final String videoFilePath;
  final Map<String, dynamic> progressData;

  VideoDownloadingMessage(this.videoFilePath, this.progressData) : super();
}

final class VideoDownloadedMessage extends DownloadReturnStatus {
  final String videoFilePath;
  final Map<String, dynamic> progressData;

  VideoDownloadedMessage(this.videoFilePath, this.progressData) : super();
}

final class AudioDownloadingMessage extends DownloadReturnStatus {
  final String audioFilePath;
  final Map<String, dynamic> progressData;

  AudioDownloadingMessage(this.audioFilePath, this.progressData) : super();
}

final class AudioDownloadedMessage extends DownloadReturnStatus {
  final String audioFilePath;
  final Map<String, dynamic> progressData;

  AudioDownloadedMessage(this.audioFilePath, this.progressData) : super();
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
        Preferences pref, VideoInPlaylist videoData) async* {
  final proc = await ProcessRunner.spawn(
      name: 'yt-dlp',
      argument: pref.videoBestCmd,
      replacements: {
        TemplateReplacements.cookieFile: pref.cookieFilePath!,
        TemplateReplacements.videoId: videoData.id,
        TemplateReplacements.outputDir: pref.outputDirPath!
      });
  proc.stdout.listen((event) {
    //logger.fine(String.fromCharCodes(event));
  });
  logger.fine(
      'Started yt-dlp process for downloading video with best configuration');

  // FIXME: swap with a class or something, like the sealed class that we have been using up until now?
  ProgressState state = ProgressState
      .uninitialized; // Holds the state of which the logging must be done
  late String videoAudioToBeDownloaded;
  // For later when we enable the user to not download captions
  String? captionToDownload;

  // FIXME: move out of this func?
  await for (final tmpO in proc.stdout) {
    // There can be multiple lines in 1 stdout message
    for (final output in String.fromCharCodes(tmpO).split('\n')) {
      if (RegExp(r'\[download\]').hasMatch(output) && output.endsWith('.vtt')) {
        state = ProgressState.captionDownloading;

        final foundCaptFn = output.split(' ').elementAt(2);
        logger.fine("Found caption file : $foundCaptFn");
        captionToDownload = foundCaptFn;
      }
      if (RegExp(r'\[Merger\]').hasMatch(output)) {
        state = ProgressState.videoAudioMerged;

        // https://stackoverflow.com/questions/27545081/best-way-to-get-all-substrings-matching-a-regexp-in-dart
        final endVideoFp =
            RegExp(r'(?<=\")\S+(?=\")').firstMatch(output)!.group(0)!;
        logger.fine('Found merged video : $endVideoFp');
        yield DownloadReturnStatus.videoAudioMerged(endVideoFp);
      }

      // FIXME: TEMP ALTERNATIVE MODE!
      // This output is actually yt-dlp choosing the target directory before downloading the media
      if (RegExp(r'\[download\]').hasMatch(output) &&
          (output.endsWith('.mkv') ||
              output.endsWith('.webm') ||
              output.endsWith('.mp4'))) {
        if (state == ProgressState.captionDownloaded) {
          state = ProgressState.videoDownloading;
          logger.fine('Found video soon-to-be downloaded : $output');
        } else {
          state = ProgressState.audioDownloading;
          logger.fine('Found audio soon-to-be downloaded : $output');
        }
        final foundMedia = output.split(' ').elementAt(2);
        videoAudioToBeDownloaded = foundMedia;
      }

      final progressOut = decodeJSONOrFail(output);
      if (progressOut != null && state != ProgressState.uninitialized) {
        logger.fine('yt-dlp JSON output : $progressOut on mode $state');

        // Only return progress on video and audio downloads. Caption download progress are mostly insignificant (finishes too fast)
        if (state == ProgressState.captionDownloading) {
          // Check if 100%
          if ((progressOut['percentage'] as String).contains('100')) {
            yield DownloadReturnStatus.captionDownloaded(
                captionToDownload!, progressOut);
          } else {
            yield DownloadReturnStatus.captionDownloading(
                captionToDownload!, progressOut);
          }
        } else if (state == ProgressState.videoDownloading ||
            state == ProgressState.uninitialized) {
          // Check if 100%
          if ((progressOut['percentage'] as String).contains('100')) {
            yield DownloadReturnStatus.videoDownloaded(
                videoAudioToBeDownloaded, progressOut);
          } else {
            yield DownloadReturnStatus.videoDownloading(
                videoAudioToBeDownloaded, progressOut);
          }
        } else if (state == ProgressState.audioDownloading) {
          // Check if 100%
          if ((progressOut['percentage'] as String).contains('100')) {
            yield DownloadReturnStatus.audioDownloaded(
                videoAudioToBeDownloaded, progressOut);
          } else {
            yield DownloadReturnStatus.audioDownloading(
                videoAudioToBeDownloaded, progressOut);
          }
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
