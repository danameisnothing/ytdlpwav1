import 'dart:io';

import "package:args/args.dart";

const playlistInternalPrefixIdent = "[CIDENT]";
const playlistInternalSplitTarget =
    " () "; // The leading and trailing whitespace is intentional!

void main(List<String> arguments) async {
  final argParser = ArgParser();
  argParser.addOption("cookiefile",
      abbr: "c", help: "The path to the YouTube cookie file", mandatory: true);
  argParser.addOption("playlistid",
      abbr: "p", help: "The target YouTube playlist ID", mandatory: true);

  if (Platform.isWindows) {
    if (Process.runSync("where", ["yt-dlp"]).exitCode != 0) {
      throw Exception(
          "Unable to find the yt-dlp command. Verify that yt-dlp is mounted in PATH");
    }
  }

  final parsedArgs = argParser.parse(arguments);

  if ((parsedArgs.option("cookiefile") ?? "").isEmpty) {
    throw Exception("\"cookiefile\" argument not specified or empty");
  }
  if ((parsedArgs.option("playlistid") ?? "").isEmpty) {
    throw Exception("\"playlistid\" argument not specified or empty");
  }

  final cookieFile = parsedArgs.option("cookiefile")!;
  final playlistID = parsedArgs.option("playlistid")!;

  if (!await File(cookieFile).exists()) {
    throw Exception("Invalid cookie path given");
  }

  final playlistInfoProc = await Process.start("yt-dlp", [
    "--simulate",
    "--no-flat-playlist",
    "--no-mark-watched",
    "--output",
    "$playlistInternalPrefixIdent%(title)s$playlistInternalSplitTarget%(id)s",
    "--get-filename",
    "--retries",
    "999",
    "--fragment-retries",
    "999",
    "--extractor-retries",
    "0",
    "--cookies",
    cookieFile,
    "https://www.youtube.com/playlist?list=$playlistID"
  ]);

  playlistInfoProc.stderr
      .forEach((e) => print("stderr : ${String.fromCharCodes(e)}"));

  playlistInfoProc.stdout.forEach((tmp) {
    String str = String.fromCharCodes(tmp);

    if (!str.startsWith(playlistInternalPrefixIdent)) return;

    final filter = playlistInternalPrefixIdent
        .replaceFirst(RegExp(r"\["), r"\[")
        .replaceFirst(RegExp(r"\]"), r"\]");
    str = str.replaceAll(RegExp(filter), "");

    print("stdout : $str");
  });

  await playlistInfoProc.exitCode;
}
