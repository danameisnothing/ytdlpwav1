# ytdlpwav1
A program to download YouTube videos in AV1 and Opus, with MKV as a container.

## Description
ytdlpwav1 is a program to download videos from a YouTube playlist, and outputting the final video result as an AV1-encoded video with Opus for the audio. The program enforces this rule, even if that means re-encoding. Note that this re-encoding behaviour almost guarantees a worse quality than the downloaded video itself. Considering that, this program is not meant to do any kind of serious digital archives.

This program relies on FFmpeg and yt-dlp being installed and added to PATH.

## Requirements
* FFmpeg (TODO: CHECK WHAT MINIMUM VERSION!)
* yt-dlp (The latest version is **heavily recommended**, as an out-of-date version can cause issues regarding downloads, either to fetch video information, or downloading the actual video)

## Usage?
### Downloading from a Playlist
To download a collection of videos from a YouTube playlist, TODO

## Configuration
*For now, ytdlpwav1 outputs a video with a target resolution of max 1080p. You can not change this setting just yet. This is planned to be configurable in the future.*