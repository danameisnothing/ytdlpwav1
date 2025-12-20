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
> And also make sure to have an up-to-date YouTube cookie file! If not, then you might experience unexpected download failures, or sub-optimal video quality.
### Downloading YouTube videos from a YouTube Playlist
* To download a collection of videos from a YouTube playlist, you must first fetch a list of videos from a playlist. To do that, first run the executable with arguments as such : `ytdlpwav1 fetch --cookie_file "YOUR_COOKIE_FILE_PATH" --playlist_id "YOUR_YOUTUBE_PLAYLIST_ID"`. This command will generate a file called `ytdlpwav1_video_data.json` that contains YouTube video IDs from the chosen playlist.
* After that, to download the videos themselves, run the executable with the following arguments : `ytdlpwav1 download --cookie_file "YOUR_COOKIE_FILE_PATH" --output_dir "YOUR_OUTPUT_DIR"`

### Downloading a single YouTube video
* To download just a single YouTube, run the executable with this : `ytdlpwav1 download_single --cookie_file "YOUR_COOKIE_FILE_PATH" --output_dir "YOUR_OUTPUT_DIR" --id "YOUR_YOUTUBE_VIDEO_ID"`

### Miscellaneous
* If you are having trouble with the program falsely identifying that you do not have either FFmpeg, FFprobe, or yt-dlp, pass in `--no_program_check`, like so : `ytdlpwav1 fetch --cookie_file "YOUR_COOKIE_FILE_PATH" --playlist_id "YOUR_YOUTUBE_PLAYLIST_ID --no_program_check`, or `ytdlpwav1 download_single --cookie_file "YOUR_COOKIE_FILE_PATH" --output_dir "YOUR_OUTPUT_DIR" --id "YOUR_YOUTUBE_VIDEO_ID" --no_program_check` for downloading multiple videos
* If the program is not working, use `--debug` to tell the program to output a verbose log file, which can be used to diagnose failures

> [!NOTE]
> Currently, it is required to supply the `cookie_file` option. This will not be required in the future.

> [!NOTE]

## Configuration
*For now, ytdlpwav1 outputs a video with a target resolution of max 1080p. You can not change this setting just yet. This is planned to be configurable in the future.*