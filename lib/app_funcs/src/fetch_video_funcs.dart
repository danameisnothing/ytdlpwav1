import 'dart:convert';

import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/app_settings/app_settings.dart';

// TODO: document where if this function returns nothing, it means it failed to fetch the playlist quantity
Future<int?> getPlaylistQuantity(
    Preferences pref, String cookieFile, String playlistId) async {
  final proc = await ProcessRunner.spawn(
      name: 'yt-dlp',
      argument: pref.fetchPlaylistItemCountCmd,
      replacements: {
        TemplateReplacements.cookieFile: cookieFile,
        TemplateReplacements.playlistId: playlistId
      });
  logger.fine('Started yt-dlp process for fetching playlist quantity');

  final data = await proc.stdout.first
      .then((e) => String.fromCharCodes(e), onError: (_) => null);

  if (await proc.process.exitCode != 0) {
    return null;
  }

  logger.fine('Got $data on playlist count');

  return jsonDecode(data)['playlist_count']
      as int; // Data can't possibly be null because of the exitCode check
}

// TODO: document where if this function returns nothing, it means it failed to fetch the playlist quantity
Stream<VideoInPlaylist> getPlaylistVideoInfos(
    Preferences pref, String cookieFile, String playlistId) async* {
  final proc = await ProcessRunner.spawn(
      name: 'yt-dlp',
      argument: pref.fetchPlaylistItemCountCmd,
      replacements: {
        TemplateReplacements.cookieFile: cookieFile,
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
        ));
    logger.fine('Got update on stdout, parsed as $parsed');
    yield parsed;
  }

  if (await proc.process.exitCode != 0) {
    // FIXME: fail early instead!
    //return null;
    hardExit(
        'An error occured while fetching video infos. Use the --debug flag to see more details');
  }
}
