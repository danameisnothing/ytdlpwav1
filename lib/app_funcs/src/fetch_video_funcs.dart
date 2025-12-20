import 'dart:convert';

import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/app_settings/app_settings.dart';

// FIXME: add support for more authentication options when we do support them
/// Returns the playlist quantity of a YouTube playlist, with a given cookiefile path for authentication
///
/// Throws a [ProcessExitNonZeroException] if yt-dlp exits with a non-zero exit code
Future<int> getPlaylistQuantity(Preferences pref, String playlistId) async {
  final proc = await ProcessRunner.spawn(
      name: 'yt-dlp',
      argument: pref.fetchPlaylistItemCountCmd,
      replacements: {
        TemplateReplacements.cookie: (pref.cookieFilePath != null)
            ? '--cookies "${pref.cookieFilePath}"'
            : "",
        TemplateReplacements.playlistId: playlistId
      });
  logger.fine('Started yt-dlp process for fetching playlist quantity');

  final data = await proc.stdout.first
      .then((e) => String.fromCharCodes(e), onError: (e) => '');

  if (await proc.process.exitCode != 0) {
    // TODO: change to specific type
    throw Exception(
        'yt-dlp exited abnormally while fetching playlist quantity of playlist ID $playlistId. This may be caused by outdated auth cookies, or an outdated yt-dlp version. Pass --debug to see detailed logs');
  }

  logger.fine('Got $data on playlist count');

  return jsonDecode(data)['playlist_count']
      as int; // Data can't possibly be null because of the exitCode check
}

// FIXME: add support for more authentication options when we do support them
/// Returns a stream of [VideoInPlaylist] objects for every video in the YouTube playlist, with a given cookiefile path for authentication
///
/// Throws a [ProcessExitNonZeroException] if yt-dlp exits with a non-zero exit code
Stream<VideoInPlaylist> getPlaylistVideoInfos(
    Preferences pref, String playlistId) async* {
  final proc = await ProcessRunner.spawn(
      name: 'yt-dlp',
      argument: pref.fetchVideoInfosCmd,
      replacements: {
        TemplateReplacements.cookie: (pref.cookieFilePath != null)
            ? '--cookies "${pref.cookieFilePath}"'
            : "",
        TemplateReplacements.playlistId: playlistId
      });
  logger.fine('Started yt-dlp process for fetching video infos');

  await for (final e in proc.stdout) {
    final data = jsonDecode(String.fromCharCodes(e));

    final uploadDate = data['upload_date'] as String;
    final parsed = VideoInPlaylist(
        data['title'],
        data['id'],
        data['description'],
        data['uploader'],
        DateTime(
          int.parse(uploadDate.substring(0, 4)),
          int.parse(uploadDate.substring(4, 6)),
          int.parse(uploadDate.substring(6, 8)),
        ),
        false);
    logger.fine('Got update on stdout, parsed as $parsed');
    yield parsed;
  }

  if (await proc.process.exitCode != 0) {
    hardExit(
        'yt-dlp exited abnormally while fetching playlist info of playlist ID $playlistId');
  }
}
