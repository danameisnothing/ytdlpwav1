# ytdlpwav1
A program to download YouTube videos in AV1 and Opus, with MKV as a container.

## Description
ytdlpwav1 is a program to download videos from a YouTube playlist, and outputting the final video result as an AV1-encoded video with Opus for the audio. The program enforces this rule, even if that means re-encoding.
Note that this re-encoding behaviour almost guarantees a worse quality than the downloaded video itself. Considering that, this program is **not** meant to do any kind of serious digital archives. Please keep this in mind when using the program!

This program relies on FFmpeg, FFprobe and yt-dlp being installed and added to PATH.

## Requirements
* FFmpeg and FFprobe
* yt-dlp (The latest version is **heavily recommended**, as an out-of-date version can cause issues regarding downloads, either to fetch video information, or downloading the actual video)

## Getting Started Guide

> [!NOTE]
> Do not use shorthands for the `cookie_path` argument, such as `~` for your current home folder. Always use absolute paths!

> [!NOTE]
> And also make sure to have an up-to-date YouTube cookie file! If not, then you might experience unexpected download failures, or sub-optimal video quality.

### Downloading YouTube videos from a YouTube Playlist
* To download a collection of videos from a YouTube playlist, you must first fetch a list of videos from a playlist. To do that, first run the executable with arguments as such : `ytdlpwav1 fetch --cookie_file "YOUR_COOKIE_FILE_PATH" --playlist_id "YOUR_YOUTUBE_PLAYLIST_ID"`. This command will generate a file called `ytdlpwav1_video_data.json` that contains YouTube video IDs from the chosen playlist.
* After that, to download the videos themselves, run the executable with the following arguments : `ytdlpwav1 download --cookie_file "YOUR_COOKIE_FILE_PATH" --output_dir "YOUR_OUTPUT_DIR"`

### Downloading a single YouTube video
* To download just a single YouTube, run the executable with this : `ytdlpwav1 download_single --cookie_file "YOUR_COOKIE_FILE_PATH" --output_dir "YOUR_OUTPUT_DIR" --id "YOUR_YOUTUBE_VIDEO_ID"`

### Configuration
* If you are having trouble with the program falsely identifying that you do not have either FFmpeg, FFprobe, or yt-dlp, pass in `--no_program_check`, like so : `ytdlpwav1 fetch --cookie_file "YOUR_COOKIE_FILE_PATH" --playlist_id "YOUR_YOUTUBE_PLAYLIST_ID --no_program_check`, or `ytdlpwav1 download_single --cookie_file "YOUR_COOKIE_FILE_PATH" --output_dir "YOUR_OUTPUT_DIR" --id "YOUR_YOUTUBE_VIDEO_ID" --no_program_check` for downloading multiple videos
* If the program is not working, use `--debug` to tell the program to output a verbose log file, which can be used to diagnose failures
* If you don't want to supply a cookie file, just omit the `--cookie_file` argument
* If you want to also download YouTube's automatic captions, supply the `--download_auto_subs` flag for the download sub-commands (`download`, and `download_single`)
* If you want to set the preferred width and height for the downloaded video(s), use `--preferred_width` and `--preferred_height`.

> [!WARNING]
> Downloading videos with YouTube's automatic captions may cause you to be throttled by YouTube, by `yt-dlp` erroring out, complaining about a Too Many Requests error (HTTP 429). If this happens, do not use the `--download_auto_subs` option

> [!NOTE]
> Currently, the combining step of this program doesn't make the subtitles a default. This is planned to be addressed