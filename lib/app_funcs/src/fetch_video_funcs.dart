import 'dart:io';
import 'dart:convert';

import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmd_split_args;
import 'package:ytdlpwav1/app_utils/app_utils.dart';
import 'package:ytdlpwav1/app_settings/app_settings.dart';

// TODO: document where if this function returns nothing, it means it failed to fetch the playlist quantity
Future<int?> getPlaylistQuantity(String cookieFile, String playlistId) async {
  final playlistItemCountCmd = cmd_split_args.split(fetchPlaylistItemCountCmd
      .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
      .replaceAll(RegExp(r'<playlist_id>'), playlistId));
  settings.logger.fine(
      'Starting yt-dlp process for fetching playlist quantity using argument $playlistItemCountCmd');
  final picProc = await Process.start(
      playlistItemCountCmd.removeAt(0), playlistItemCountCmd);

  final broadcastStreams =
      implantDebugLoggerReturnBackStream(picProc, 'yt-dlp');

  final data = await procAwaitFirstOutputHack(broadcastStreams['stdout']!);

  if (await picProc.exitCode != 0) {
    return null;
  }

  settings.logger.fine('Got $data on playlist count');

  return jsonDecode(data!)['playlist_count']!
      as int; // Data can't be null because of the exitCode check
}

// TODO: document where if this function returns nothing, it means it failed to fetch the playlist quantity
Stream<VideoInPlaylist> getPlaylistVideoInfos(
    String cookieFile, String playlistId) async* {
  final videoInfosCmd = cmd_split_args.split(fetchVideoInfosCmd
      .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
      .replaceAll(RegExp(r'<playlist_id>'), playlistId));
  settings.logger.fine(
      'Starting yt-dlp process for fetching video informations using argument $videoInfosCmd');
  final viProc = await Process.start(videoInfosCmd.removeAt(0), videoInfosCmd);

  final broadcastStreams = implantDebugLoggerReturnBackStream(viProc, 'yt-dlp');

  await for (final e in broadcastStreams['stdout']!) {
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
    settings.logger.fine('Got update on stdout, parsed as $parsed');
    yield parsed;
  }

  if (await viProc.exitCode != 0) {
    // FIXME: fail early instead!
    //return null;
    hardExit(
        'An error occured while fetching video infos. Use the --debug flag to see more details');
  }
}
