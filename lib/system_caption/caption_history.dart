/// Turns overlapping Whisper windows into a readable rolling transcript.
///
/// The service re-transcribes the latest ~6 seconds every ~2.5 seconds, so
/// consecutive results repeat most of their words ("the cat sat on" then
/// "sat on the mat"). This merges the overlap instead of showing the same
/// words twice, and keeps a short list of recent phrases for the expanded box.
class CaptionHistory {
  CaptionHistory({this.maxLines = 12, this.maxWordsPerLine = 30});

  final int maxLines;
  final int maxWordsPerLine;
  final List<String> _lines = <String>[];

  List<String> get lines => List<String>.unmodifiable(_lines);

  /// The newest phrase, or an empty string.
  String get latest => _lines.isEmpty ? '' : _lines.last;

  bool get isEmpty => _lines.isEmpty;

  void clear() => _lines.clear();

  /// Adds the text of one transcription window. Returns whether anything
  /// changed.
  bool add(String text) {
    final next = text.trim();
    if (next.isEmpty) {
      return false;
    }
    if (_lines.isEmpty) {
      _lines.add(next);
      return true;
    }

    final merged = mergeOverlap(_lines.last, next);
    if (merged == null) {
      _append(next);
      return true;
    }
    if (merged == _lines.last) {
      return false;
    }
    if (_wordCount(merged) > maxWordsPerLine) {
      // Long run-on: start a fresh line from the newest window.
      _append(next);
    } else {
      _lines[_lines.length - 1] = merged;
    }
    return true;
  }

  void _append(String line) {
    _lines.add(line);
    while (_lines.length > maxLines) {
      _lines.removeAt(0);
    }
  }

  static int _wordCount(String text) =>
      text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;

  /// Joins [previous] and [next] when they overlap, or returns `null` when
  /// they are separate phrases.
  ///
  /// Overlap means the end of [previous] equals the start of [next] (at least
  /// two words), or one contains the other. Comparison ignores case and
  /// punctuation, because Whisper re-punctuates the same words differently
  /// between windows.
  static String? mergeOverlap(String previous, String next) {
    final previousWords = _words(previous);
    final nextWords = _words(next);
    if (previousWords.isEmpty || nextWords.isEmpty) {
      return null;
    }
    final previousKeys = previousWords.map(_key).toList(growable: false);
    final nextKeys = nextWords.map(_key).toList(growable: false);

    if (_contains(previousKeys, nextKeys)) {
      return previous;
    }
    if (_contains(nextKeys, previousKeys)) {
      return next;
    }

    final longest = previousKeys.length < nextKeys.length
        ? previousKeys.length
        : nextKeys.length;
    for (var overlap = longest; overlap >= 2; overlap--) {
      var matches = true;
      for (var i = 0; i < overlap; i++) {
        if (previousKeys[previousKeys.length - overlap + i] != nextKeys[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return <String>[
          ...previousWords,
          ...nextWords.sublist(overlap),
        ].join(' ');
      }
    }
    return null;
  }

  static List<String> _words(String text) =>
      text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

  static String _key(String word) => word.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  /// True when [needle] appears as a contiguous run inside [haystack].
  static bool _contains(List<String> haystack, List<String> needle) {
    if (needle.length > haystack.length) {
      return false;
    }
    for (var start = 0; start <= haystack.length - needle.length; start++) {
      var matches = true;
      for (var i = 0; i < needle.length; i++) {
        if (haystack[start + i] != needle[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return true;
      }
    }
    return false;
  }
}
