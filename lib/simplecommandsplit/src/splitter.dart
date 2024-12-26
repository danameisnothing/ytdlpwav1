List<String> split(String input) {
  final regexp = RegExp(r'(".*?")|(\S+)');

  return regexp
      .allMatches(input)
      .map((e) => e.group(0)!.replaceAll(r'"', ''))
      .toList(); // https://stackoverflow.com/questions/27545081/best-way-to-get-all-substrings-matching-a-regexp-in-dart, wot?
}
