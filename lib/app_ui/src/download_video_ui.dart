import 'dart:io';

import 'package:chalkdart/chalk.dart';
import 'package:ansi_strip/ansi_strip.dart';

import 'package:ytdlpwav1/app_funcs/app_funcs.dart';
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';

// TODO: ENUM DOC!
// FIXME: necessary with these enums having the same values?
enum FFmpegExtractThumb { started, completed }

// TODO: ENUM DOC!
// FIXME: necessary with these enums having the same values?
enum FFmpegMergeFilesState { started, completed }

// TODO: ENUM DOC!
// FIXME: necessary with these enums having the same values?
enum FFprobeFetchVideoDataState { started, completed }

enum DownloadUIStageTemplate {
  stageUninitialized(uiStageMapping: 'Uninitialized'),
  stageDownloadingCaptions(uiStageMapping: 'Downloading caption(s)'),
  stageDownloadingVideo(uiStageMapping: 'Downloading video'),
  stageDownloadingAudio(uiStageMapping: 'Downloading audio'),
  stageFFmpegExtractingThumbnail(uiStageMapping: 'Extracting thumbnail'),
  stageFFprobeFetchVideoData(uiStageMapping: 'Fetching video data'),
  stageFFmpegReencodeAndMergeVideo(
      uiStageMapping: 'Re-encoding video to AV1 and merging files'),
  stageFFmpegMergeFiles(uiStageMapping: 'Merging files');

  const DownloadUIStageTemplate({required this.uiStageMapping});

  final String uiStageMapping;
}

final class DownloadVideoUI {
  final ProgressBar _pb;
  final List<VideoInPlaylist> _videos;

  int _maxStageUI = -1;

  DownloadVideoUI(this._videos)
      : _pb = ProgressBar(
            top: _videos.length,
            innerWidth: 32,
            renderFunc: (total, current) {
              return '[${ProgressBar.innerProgressBarIdent}]';
            });

  void onDownloadFailure() => _pb.progress = _pb.progress.floor() + 1;

  void setUseAllStageTemplates(bool useAll) {
    // FIXME: Need to update when we add more stages
    _maxStageUI = (useAll)
        ? DownloadUIStageTemplate.values.length - 1
        : DownloadUIStageTemplate.values.length - 2;
  }

  String _getDownloadVideoMediaKindMapping(DownloadReturnStatus status) {
    switch (status) {
      case CaptionDownloadingMessage() || CaptionDownloadedMessage():
        return chalk.magentaBright('(caption)');
      case VideoDownloadingMessage() || VideoDownloadedMessage():
        return chalk.blueBright('(video)');
      case AudioDownloadingMessage() || AudioDownloadedMessage():
        return chalk.greenBright('(audio)');
      default:
        return '';
    }
  }

  Map<String, dynamic>? _getDownloadVideoProgDataMapped(
      DownloadReturnStatus status) {
    // FIXME: improve, is this even necessary?
    switch (status) {
      case CaptionDownloadingMessage():
        return status.progressData;
      case CaptionDownloadedMessage():
        return status.progressData;
      case VideoDownloadingMessage():
        return status.progressData;
      case VideoDownloadedMessage():
        return status.progressData;
      case AudioDownloadingMessage():
        return status.progressData;
      case AudioDownloadedMessage():
        return status.progressData;
      default:
        // They do not have the progressData field
        return null;
    }
  }

  String _getDownloadVideoBytesMapping(
      Map<String, dynamic>? progData, String targetKey) {
    final fallback = '0.0MiB';
    if (progData != null) {
      final trm = (progData[targetKey] as String).trim();
      if (trm.contains('N/A')) {
        return fallback;
      } else {
        return trm;
      }
    } else {
      return fallback;
    }
  }

  bool _getDownloadVideoIsStillDownloading(DownloadReturnStatus status) {
    switch (status) {
      case CaptionDownloadingMessage() ||
            CaptionDownloadedMessage() ||
            VideoDownloadingMessage() ||
            VideoDownloadedMessage() ||
            AudioDownloadingMessage() ||
            AudioDownloadedMessage():
        return true;
      default:
        return false;
    }
  }

  String _getDownloadVideoMediaNameMapping(
      DownloadReturnStatus status, int idxInVideoInfo) {
    // FIXME:
    switch (status) {
      case CaptionDownloadingMessage():
        return status.captionFilePath;
      case CaptionDownloadedMessage():
        return status.captionFilePath;
      case VideoDownloadingMessage():
        return status.videoFilePath;
      case VideoDownloadedMessage():
        return status.videoFilePath;
      case AudioDownloadingMessage():
        return status.audioFilePath;
      case AudioDownloadedMessage():
        return status.audioFilePath;
      default:
        return _videos.elementAt(idxInVideoInfo).title;
    }
  }

  Future<void> _printUI(String data) async {
    final chunked = data.split('\n').map((str) {
      final strLen = stripAnsi(str).length;
      // Handle us not having enough space to print the base message
      // TODO: handle too long string
      return '$str${(stdout.terminalColumns < strLen) ? 'TODO: too long logic here' : List.filled(stdout.terminalColumns - strLen, ' ').join()}';
    }).join('\n');

    // Joined it all to prevent cursor jerking around
    stdout.write('\r$chunked\r\x1b[${chunked.split('\n').length - 1}A');
    await stdout
        .flush(); // https://github.com/dart-lang/sdk/issues/25277 (we do need to await it)
  }

  Future<void> printDownloadVideoUI(DownloadUIStageTemplate stage,
      DownloadReturnStatus status, int idxInVideoInfo) async {
    final prog = _getDownloadVideoProgDataMapped(status);

    final String? progStr = (prog != null) ? prog['percentage'] : null;

    // When we pass this check, the last message are either downloading / downloaded video / audio
    if (progStr != null) {
      final standalonePartProgStr =
          double.parse(progStr.trim().replaceFirst(RegExp(r'%'), ''));

      // FIXME:
      switch (status) {
        case CaptionDownloadingMessage() || CaptionDownloadedMessage():
          _pb.progress = _pb.progress.truncate() +
              map(standalonePartProgStr, 0, 100, (1 / _maxStageUI) * 0,
                  (1 / _maxStageUI) * 1);
          break;
        case VideoDownloadingMessage() || VideoDownloadedMessage():
          _pb.progress = _pb.progress.truncate() +
              map(standalonePartProgStr, 0, 100, (1 / _maxStageUI) * 1,
                  (1 / _maxStageUI) * 2);
        case AudioDownloadingMessage() || AudioDownloadedMessage():
          _pb.progress = _pb.progress.truncate() +
              map(standalonePartProgStr, 0, 100, (1 / _maxStageUI) * 2,
                  (1 / _maxStageUI) * 3);
        default:
          break;
      }
    }

    final templateStr =
        """Downloading : ${_getDownloadVideoMediaNameMapping(status, idxInVideoInfo)}${(_getDownloadVideoIsStillDownloading(status)) ? ' ${_getDownloadVideoMediaKindMapping(status)}' : ''}
[${_pb.generateDefaultProgressBar()}] ${chalk.brightCyan('${map(_pb.progress, 0, _pb.top, 0, 100).toStringAsFixed(2)}%')}
Stage ${stage.index}/$_maxStageUI ${stage.uiStageMapping}${(_getDownloadVideoIsStillDownloading(status)) ? '      Downloaded : ${_getDownloadVideoBytesMapping(prog, 'bytes_downloaded')}/${_getDownloadVideoBytesMapping(prog, 'bytes_total')} | Speed : ${_getDownloadVideoBytesMapping(prog, 'download_speed')} | ETA : ${_getDownloadVideoBytesMapping(prog, 'ETA')}' : ''}""";

    await _printUI(templateStr);
  }

  Future<void> printExtractThumbnailUI(
      FFmpegExtractThumb state, String videoTarget) async {
    bool completed = false;
    if (state == FFmpegExtractThumb.completed) {
      completed = true;
    }

    _pb.progress = _pb.progress.truncate() +
        map((completed) ? 100 : 0, 0, 100, (1 / _maxStageUI) * 3,
            (1 / _maxStageUI) * 4);

    final templateStr = """Extracting PNG from $videoTarget
[${_pb.generateDefaultProgressBar()}] ${chalk.brightCyan('${map(_pb.progress, 0, _pb.top, 0, 100).toStringAsFixed(2)}%')}
Stage ${DownloadUIStageTemplate.stageFFmpegExtractingThumbnail.index}/$_maxStageUI ${DownloadUIStageTemplate.stageFFmpegExtractingThumbnail.uiStageMapping}""";

    await _printUI(templateStr);
  }

  Future<void> printMergeFilesUI(
      FFmpegMergeFilesState state, String finalVidOut) async {
    bool completed = false;
    if (state == FFmpegMergeFilesState.completed) {
      completed = true;
    }

    _pb.progress = _pb.progress.truncate() +
        map((completed) ? 100 : 0, 0, 100, (1 / _maxStageUI) * 4,
            (1 / _maxStageUI) * 5);

    final templateStr = """Merging final output to $finalVidOut
[${_pb.generateDefaultProgressBar()}] ${chalk.brightCyan('${map(_pb.progress, 0, _pb.top, 0, 100).toStringAsFixed(2)}%')}
Stage ${DownloadUIStageTemplate.stageFFmpegMergeFiles.index}/$_maxStageUI ${DownloadUIStageTemplate.stageFFmpegMergeFiles.uiStageMapping}""";

    await _printUI(templateStr);
  }

  Future<void> printFetchingVideoDataUI(
      FFprobeFetchVideoDataState state) async {
    bool completed = false;
    if (state == FFprobeFetchVideoDataState.completed) {
      completed = true;
    }

    _pb.progress = _pb.progress.truncate() +
        map((completed) ? 100 : 0, 0, 100, (1 / _maxStageUI) * 4,
            (1 / _maxStageUI) * 5);

    final templateStr =
        """[${_pb.generateDefaultProgressBar()}] ${chalk.brightCyan('${map(_pb.progress, 0, _pb.top, 0, 100).toStringAsFixed(2)}%')}
Stage ${DownloadUIStageTemplate.stageFFprobeFetchVideoData.index}/$_maxStageUI ${DownloadUIStageTemplate.stageFFprobeFetchVideoData.uiStageMapping}""";

    await _printUI(templateStr);
  }

  Future<void> printReencodeAndMergeFilesUI(
      double percentageProg, String finalVidOut) async {
    _pb.progress = _pb.progress.truncate() +
        map(percentageProg, 0, 100, (1 / _maxStageUI) * 5,
            (1 / _maxStageUI) * 6);

    final templateStr = """Re-encoding and merging final output to $finalVidOut
[${_pb.generateDefaultProgressBar()}] ${chalk.brightCyan('${map(_pb.progress, 0, _pb.top, 0, 100).toStringAsFixed(2)}%')}
Stage ${DownloadUIStageTemplate.stageFFmpegReencodeAndMergeVideo.index}/$_maxStageUI ${DownloadUIStageTemplate.stageFFmpegReencodeAndMergeVideo.uiStageMapping}""";

    await _printUI(templateStr);
  }
}
