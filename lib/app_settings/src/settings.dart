import 'package:logging/logging.dart';

final Logger logger = Logger('ytdlpwav1');

final class Preferences {
  final String? cookieFilePath;
  final String? playlistId;
  final String? outputDirPath;

  // Do NOT alter the <cookie_file>, <playlist_id>, <video_id>, <thumb_out>, <video_input>, <output_dir>, <video_input>, <captions_input_flags>, <caption_track_mapping_metadata>, <thumb_in> and <final_out> hardcoded strings.
  // https://www.reddit.com/r/youtubedl/comments/t7b3mn/ytdlp_special_characters_in_output_o/ (I am a dumbass)
  /// The template for the command used to fetch information about videos in a playlist
  final fetchVideoInfosCmd =
      'yt-dlp --verbose --simulate --no-flat-playlist --no-mark-watched --print "%(.{title,id,description,uploader,upload_date})j" --restrict-filenames --windows-filenames --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';
  // https://github.com/yt-dlp/yt-dlp/issues/8562
  /// The template for the command used to fetch how many videos in a playlist
  final fetchPlaylistItemCountCmd =
      'yt-dlp --verbose --playlist-items 0-1 --simulate --no-flat-playlist --no-mark-watched --print "%(.{playlist_count})j" --retries 999 --fragment-retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/playlist?list=<playlist_id>"';
  // https://www.reddit.com/r/youtubedl/comments/19ary5t/is_png_thumbnail_on_mkv_broken_on_ytdlp/
  /// The template for the command used to download a video (tries it with the preferred settings right out of the bat)
  final videoPreferredCmd =
      'yt-dlp --verbose --paths "<output_dir>" --format "bestvideo[width<=1920][height<=1080][fps<=60][vcodec^=av01][ext=mp4]+bestaudio[acodec=opus][audio_channels<=2][asr<=48000]" --output "%(title)s" --restrict-filenames --merge-output-format mkv --write-auto-subs --embed-thumbnail --convert-thumbnail png --embed-metadata --sub-lang "en.*" --progress-template {\'percentage\':\'%(progress._percent_str)s\',\'bytes_downloaded\':\'%(progress._downloaded_bytes_str)s\',\'bytes_total\':\'%(progress._total_bytes_str)s\',\'download_speed\':\'%(progress._speed_str)s\',\'ETA\':\'%(progress._eta_str)s\'} --fragment-retries 999 --retries 999 --extractor-retries 0 "https://www.youtube.com/watch?v=<video_id>"';
  /* 'yt-dlp --verbose --paths "<output_dir>" --format "bestvideo[width<=1920][height<=1080][fps<=60][vcodec^=av01][ext=mp4]+bestaudio[acodec=opus][audio_channels<=2][asr<=48000]" --output "%(title)s" --restrict-filenames --merge-output-format mkv --write-auto-subs --embed-thumbnail --convert-thumbnail png --embed-metadata --sub-lang "en.*" --progress-template {\'percentage\':\'%(progress._percent_str)s\',\'bytes_downloaded\':\'%(progress._downloaded_bytes_str)s\',\'bytes_total\':\'%(progress._total_bytes_str)s\',\'download_speed\':\'%(progress._speed_str)s\',\'ETA\':\'%(progress._eta_str)s\'} --fragment-retries 999 --retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/watch?v=<video_id>"'; */
  final videoRegularCmd =
      'yt-dlp --verbose --paths "<output_dir>" --format "bestvideo[width<=1920][height<=1080][fps<=60]+bestaudio[audio_channels<=2][asr<=48000]" --output "%(title)s" --restrict-filenames --merge-output-format mkv --write-auto-subs --embed-thumbnail --convert-thumbnail png --embed-metadata --sub-lang "en.*" --progress-template {\'percentage\':\'%(progress._percent_str)s\',\'bytes_downloaded\':\'%(progress._downloaded_bytes_str)s\',\'bytes_total\':\'%(progress._total_bytes_str)s\',\'download_speed\':\'%(progress._speed_str)s\',\'ETA\':\'%(progress._eta_str)s\'} --fragment-retries 999 --retries 999 --extractor-retries 0 --cookies "<cookie_file>" "https://www.youtube.com/watch?v=<video_id>"';
  final ffmpegExtractThumbnailCmd =
      'ffmpeg -hide_banner -i "<video_input>" -map 0:2 -update 1 -frames:v 1 <thumb_out>';
  final ffmpegCombineFinalVideo =
      'ffmpeg -hide_banner -i <video_input> <captions_input_flags> -y -map 0:0 -map 0:1 -c:v copy -c:a copy <caption_track_mapping_metadata> -attach "<thumb_in>" -metadata:s:t "mimetype=image/png" -metadata:s:t "filename=cover.png" <final_out>';
  final ffmpegReencodeAndCombine =
      'ffmpeg -hide_banner -i <video_input> <captions_input_flags> -y -progress - -nostats -map 0:0 -map 0:1 -c:v libsvtav1 -crf 40 -c:a libopus <caption_track_mapping_metadata> -attach "<thumb_in>" -metadata:s:t "mimetype=image/png" -metadata:s:t "filename=cover.png" <final_out>';
  final ffprobeFetchVideoInfo =
      'ffprobe -v quiet -show_format -show_streams -count_frames -print_format json "VOTE you have 1-4 days left.mkv"';

  final debugLogFileName = 'ytdlpwav1_debug_log.txt';
  final videoDataFileName = 'ytdlpwav1_video_data.json';

  Preferences({this.cookieFilePath, this.playlistId, this.outputDirPath});
}
