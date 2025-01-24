import 'dart:io';

import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';

// Do NOT alter the <cookie_file>, <playlist_id>, <video_id>, <video_input> and <output_dir> hardcoded strings.
// https://www.reddit.com/r/youtubedl/comments/t7b3mn/ytdlp_special_characters_in_output_o/ (I am a dumbass)
/// The template for the command used to fetch information about videos in a playlist
const fetchVideoInfosCmd =
    'yt-dlp --verbose --simulate --no-flat-playlist --no-mark-watched --print "%(.{title,id,description,uploader,upload_date})j" --restrict-filenames --windows-filenames --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';
// https://github.com/yt-dlp/yt-dlp/issues/8562
/// The template for the command used to fetch how many videos in a playlist
const fetchPlaylistItemCountCmd =
    'yt-dlp --verbose --playlist-items 0-1 --simulate --no-flat-playlist --no-mark-watched --print "%(.{playlist_count})j" --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';
// https://www.reddit.com/r/youtubedl/comments/19ary5t/is_png_thumbnail_on_mkv_broken_on_ytdlp/
/// The template for the command used to download a video (tries it with the preferred settings right out of the bat)
const videoBestCmd =
    'yt-dlp --verbose --paths "<output_dir>" --format "bestvideo[width<=1920][height<=1080][fps<=60][vcodec^=av01][ext=mp4]+bestaudio[acodec=opus][audio_channels<=2][asr<=48000]" --output "%(title)s" --restrict-filenames --merge-output-format mkv --write-auto-subs --embed-thumbnail --convert-thumbnail png --embed-metadata --sub-lang "en.*" --progress-template {\'percentage\':\'%(progress._percent_str)s\',\'bytes_downloaded\':\'%(progress._total_bytes_str)s\',\'bytes_total\':\'%(filesize_approx)\',\'download_speed\':\'%(progress._speed_str)s\',\'ETA\':\'%(progress._eta_str)s\'} --fragment-retries 999 --retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/watch?v=<video_id>"';
const ffmpegExtractThumbnailCmd =
    'ffmpeg -hide_banner -i "<video_input>" -map 0:2 -update 1 -frames:v 1 thumb.temp.png';
const debugLogFileName = 'ytdlpwav1_debug_log.txt';
const videoDataFileName = 'ytdlpwav1_video_data.json';

class Preferences {
  late final Logger logger;
  final String? cookieFilePath;
  final String? playlistId;
  final String? outputDirPath;

  Preferences({this.cookieFilePath, this.playlistId, this.outputDirPath});
}

late final Preferences settings;

void initSettings({String? cookieFile, String? playlistId, String? outputDir}) {
  settings = Preferences(
      cookieFilePath: cookieFile,
      playlistId: playlistId,
      outputDirPath: outputDir);

  settings.logger = Logger('ytdlpwav1');
  Logger.root.onRecord.listen((rec) {
    String levelName = '[${rec.level.name}]';
    switch (rec.level) {
      case Level.INFO:
        levelName = chalk.grey(levelName);
        break;
      case Level.WARNING:
        levelName = chalk.yellowBright(levelName);
        break;
      case Level.SEVERE:
        levelName = chalk.redBright('[ERROR]');
        break;
    }
    if (rec.level == Level.FINE) {
      final logFile =
          File(debugLogFileName); // Guaranteed to exist at this point
      logFile.writeAsStringSync(
          '${rec.time.toIso8601String()} : ${rec.message}${Platform.lineTerminator}',
          flush: true,
          mode: FileMode.append);
      return;
    }
    print('$levelName ${rec.message}');
  });
}
