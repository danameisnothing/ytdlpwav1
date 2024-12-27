import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:chalkdart/chalk.dart';

import 'package:ytdlpwav1/simplecommandsplit/simplecommandsplit.dart'
    as cmdSplitArgs;
import 'package:ytdlpwav1/simpleutils/simpleutils.dart';
import 'package:ytdlpwav1/simpleprogressbar/simpleprogressbar.dart';

// Do NOT alter the <cookie_file> and/or <playlist_id> hardcoded string.
// I am a dumbass
// https://www.reddit.com/r/youtubedl/comments/t7b3mn/ytdlp_special_characters_in_output_o/
/// The template for the command used to fetch information about videos in a playlist
const fetchVideoDataCmd =
    'yt-dlp --simulate --no-flat-playlist --no-mark-watched --print "%(.{title,id,description,uploader,upload_date})j" --restrict-filenames --windows-filenames --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';

class VideoInPlaylist {
  final String name;
  final String id;
  final String description;
  final String uploaderName;
  final String uploadedDateUTCStr;

  VideoInPlaylist(this.name, this.id, this.description, this.uploaderName,
      this.uploadedDateUTCStr);

  VideoInPlaylist.fromJson(Map<String, dynamic> json)
      : name = json['name'],
        id = json['id'],
        description = json['description'],
        uploaderName = json['uploaderName'],
        uploadedDateUTCStr = json['uploadedDateUTCStr'];

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'description': description,
        'uploaderName': uploaderName,
        'uploadedDateUTCStr': uploadedDateUTCStr
      };
}

Future fetchVideos(String cookieFile, String playlistId) async {
  /*final devFVD = await Process.start(
      'yt-dlp',
      cmdSplitArgs.split(fetchVideoDataCmd
          .replaceAll(RegExp(r'<cookie_file>'), cookieFile)
          .replaceAll(RegExp(r'<playlist_id>'), playlistId))
        ..removeAt(0));

  devFVD.stderr.forEach((e) => print('STDERR : ${String.fromCharCodes(e)}'));
  devFVD.stdout.forEach((e) => print('STDOUT : ${String.fromCharCodes(e)}'));

  if (await devFVD.exitCode != 0) throw Exception('');*/

  /*final e = ProgressBar(
      formatter: (current, total, progress, elapsedTime) {
        final percStr = chalk.brightCyan(
            '${((progress * 1000).truncate()) / 10}%'); // To have only 1 fractional part of the percentage, while cutting out any weird long fractions (e.g. 50.000001 will be converted to 50.0)
        final partStr = chalk.brightMagenta('$current/$total');
        print(ProgressBar.formatterBarToken);
        return '[${ProgressBar.formatterBarToken.replaceFirst(RegExp(r' '), ">")}] · $percStr · $partStr · ${chalk.brightBlue('Running for ${elapsedTime.inMilliseconds / 1000}s')}';
      },
      total: 100,
      completeChar: chalk.brightGreen('='),
      incompleteChar: ' ',
      width: 30);

  for (var i = 0; i < 100; i++) {
    e.render();
    e.value += 1;
    e.render();
    await Future.delayed(const Duration(milliseconds: 10));
  }*/

  final e = ProgressBar(
      top: 100,
      innerWidth: 30,
      activeColor: chalk.brightGreen,
      activeLeadingColor: chalk.brightGreen,
      renderFunc: (total, current) {
        final percStr = chalk.brightCyan(
            '${(((current / total) * 1000).truncate()) / 10}%'); // To have only 1 fractional part of the percentage, while cutting out any weird long fractions (e.g. 50.000001 will be converted to 50.0)
        final partStr = chalk.brightMagenta('$current/$total');
        return '[${ProgressBar.innerProgressBarIdent}] · $percStr · $partStr';
      });

  for (var i = 0; i < 100; i++) {
    await e.renderInLine();
    e.increment();
    await Future.delayed(const Duration(milliseconds: 10));
  }
  e.increment();
  await e.renderInLine();

  print('hell');
  print('hell');
  print('hell');
  print('hell');
}

void main(List<String> arguments) async {
  final argParser = ArgParser();
  argParser.addOption('cookie_file',
      abbr: 'c', help: 'The path to the YouTube cookie file', mandatory: true);
  argParser.addOption('playlist_id',
      abbr: 'p', help: 'The target YouTube playlist ID', mandatory: false);

  // No idea what is it for Unix systems
  // TODO: Figure out for Unix systems
  if (Platform.isWindows) {
    if ((await Process.run('where', ['yt-dlp'])).exitCode != 0) {
      throw Exception(
          'Unable to find the yt-dlp command. Verify that yt-dlp is mounted in PATH');
    }
  }

  final parsedArgs = argParser.parse(arguments);

  final cookieFile = parsedArgs.option('cookie_file') ?? '';
  final playlistId = parsedArgs.option('playlist_id');

  if (cookieFile.isEmpty) {
    throw Exception('"cookie_file" argument not specified or empty');
  }

  if (!await File(cookieFile).exists()) {
    throw Exception('Invalid cookie path given');
  }

  if (playlistId != null) {
    await fetchVideos(cookieFile, playlistId);
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
