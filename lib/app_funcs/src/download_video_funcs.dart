import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/app_settings/app_settings.dart';

// TODO: ENUM DOC!
enum DownloadProgressState {
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

// TODO: ENUM DOC!
// FIXME: necessary with these enums having the same values?
enum FFmpegExtractThumb { started, completed }

// TODO: ENUM DOC!
// FIXME: necessary with these enums having the same values?
enum FFmpegMergeFilesState { started, completed }

abstract class DownloadReturnStatus {
  DownloadReturnStatus();

  factory DownloadReturnStatus.captionDownloading(final String captionFilePath,
          final Map<String, dynamic> jsonProgressData) =>
      CaptionDownloadingMessage(captionFilePath, jsonProgressData);
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

final class FFmpegThumbReturnStatus {
  final String thumbPicFilePath;
  final int eCode;

  FFmpegThumbReturnStatus(
      {required this.thumbPicFilePath, required this.eCode});
}

final class FFmpegMergeFilesStatus {
  final int eCode;

  FFmpegMergeFilesStatus({required this.eCode});
}

// TODO: cleanup
Stream<DownloadReturnStatus> downloadAndRetrieveCaptionFilesAndVideoFile(
    Preferences pref, String targetCmd, VideoInPlaylist videoData) async* {
  final proc = await ProcessRunner.spawn(
      name: 'yt-dlp',
      argument: targetCmd,
      replacements: {
        TemplateReplacements.cookieFile: pref.cookieFilePath!,
        TemplateReplacements.videoId: videoData.id,
        TemplateReplacements.outputDir: pref.outputDirPath!
      });
  logger.fine(
      'Started yt-dlp process for downloading video with best configuration');

  // FIXME: swap with a class or something, like the sealed class that we have been using up until now?
  DownloadProgressState state = DownloadProgressState
      .uninitialized; // Holds the state of which the logging must be done
  late String videoAudioToBeDownloaded;
  // For later when we enable the user to not download captions
  String? captionToDownload;

  // yt-dlp can sometimes claim to have it 100% downloaded, but in reality the bytes_downloaded can sometimes still is still going up, but the percentage is still at 100%, causing this function to return multiple times
  final captionFilesPreventMultiple = <String>[];

  // FIXME: move out of this func?
  await for (final tmpO in proc.stdout) {
    // There can be multiple lines (and \r) in 1 stdout message
    for (String tmpO2 in String.fromCharCodes(tmpO).split('\r')) {
      for (String output in tmpO2.split('\n')) {
        output = output.trim();
        if (output.isEmpty) continue;

        if (RegExp(r'\[download\]').hasMatch(output) &&
            output.endsWith('.vtt')) {
          state = DownloadProgressState.captionDownloading;

          final foundCaptFn = output.split(' ').elementAt(2);
          logger.fine("Found caption file : $foundCaptFn");
          captionToDownload = foundCaptFn;
        }
        if (RegExp(r'\[Merger\]').hasMatch(output)) {
          state = DownloadProgressState.videoAudioMerged;

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
          if (state == DownloadProgressState.captionDownloaded) {
            state = DownloadProgressState.videoDownloading;
            logger.fine('Found video soon-to-be downloaded : $output');
          } else {
            state = DownloadProgressState.audioDownloading;
            logger.fine('Found audio soon-to-be downloaded : $output');
          }
          final foundMedia = output.split(' ').elementAt(2);
          videoAudioToBeDownloaded = foundMedia;
        }

        // FIXME: The section where we send the captionDownloaded or captionDownloading is problematic, it is dropping stuff for some reason
        final progressOut = decodeJSONOrFail(output);
        //logger.warning('Raw ${String.fromCharCodes(tmpO)}');
        if (progressOut != null &&
            state != DownloadProgressState.uninitialized) {
          //logger.fine('yt-dlp JSON output : $progressOut on mode $state');

          // Only return progress on video and audio downloads. Caption download progress are mostly insignificant (finishes too fast)
          if (state == DownloadProgressState.captionDownloading &&
              !captionFilesPreventMultiple.contains(captionToDownload!)) {
            // Check if 100%
            if ((progressOut['percentage'] as String).contains('100')) {
              logger.fine(
                  'Sent caption $captionToDownload with progress : $progressOut');
              captionFilesPreventMultiple.add(captionToDownload);
              state = DownloadProgressState.captionDownloaded;
              yield DownloadReturnStatus.captionDownloaded(
                  captionToDownload, progressOut);
            } else {
              logger.fine(
                  'Progress caption $captionToDownload with progress : $progressOut');
              yield DownloadReturnStatus.captionDownloading(
                  captionToDownload, progressOut);
            }
          } else if (state == DownloadProgressState.videoDownloading ||
              state == DownloadProgressState.uninitialized) {
            // Check if 100%
            if ((progressOut['percentage'] as String).contains('100')) {
              state = DownloadProgressState.videoDownloaded;
              yield DownloadReturnStatus.videoDownloaded(
                  videoAudioToBeDownloaded, progressOut);
            } else {
              yield DownloadReturnStatus.videoDownloading(
                  videoAudioToBeDownloaded, progressOut);
            }
          } else if (state == DownloadProgressState.audioDownloading) {
            // Check if 100%
            if ((progressOut['percentage'] as String).contains('100')) {
              state = DownloadProgressState.audioDownloaded;
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
  } //);

  if (await proc.process.exitCode != 0) {
    yield DownloadReturnStatus.processNonZeroExit(await proc.process.exitCode);
    return;
  }
  if (state == DownloadProgressState.uninitialized) {
    yield DownloadReturnStatus.progressStateStayedUninitialized();
    return;
  }

  yield DownloadReturnStatus.success();
  return;
}

Stream<FFmpegThumbReturnStatus?> extractThumbnailFromVideo(
    Preferences pref, String endVideoPath, String outPath) async* {
  final proc = await ProcessRunner.spawn(
      name: 'ffmpeg',
      argument: pref.ffmpegExtractThumbnailCmd,
      replacements: {
        TemplateReplacements.videoInput: endVideoPath,
        TemplateReplacements.thumbOut: outPath
      });
  logger.fine('Started FFmpeg process for extracting thumbnail from video');

  yield null;

  yield FFmpegThumbReturnStatus(
      thumbPicFilePath: outPath, eCode: await proc.process.exitCode);
}

Stream<FFmpegMergeFilesStatus?> mergeFiles(Preferences pref, String baseVideoFP,
    List<String> captionFP, String thumbFP, String targetOutFP) async* {
  final proc = await ProcessRunner.spawn(
      name: 'ffmpeg',
      argument: pref.ffmpegCombineFinalVideo,
      replacements: {
        TemplateReplacements.videoInput: baseVideoFP,
        TemplateReplacements.captionsInputFlags: List<String>.generate(
                captionFP.length, (i) => '-i "${captionFP.elementAt(i)}"',
                growable: false)
            .join(' '),
        TemplateReplacements.captionTrackMappingMetadata: List<String>.generate(
                captionFP.length,
                (i) =>
                    '-map ${i + 1} -c:s:$i copy -metadata:s:$i language="en"', // TODO: add logic for language detection. for now it is hardcoded to be en
                growable: false)
            .join(' '),
        TemplateReplacements.thumbIn: thumbFP,
        TemplateReplacements.finalOut: targetOutFP
      });
  logger.fine('Started FFmpeg process for merging files on to the final video');

  yield null;

  yield FFmpegMergeFilesStatus(eCode: await proc.process.exitCode);
}
