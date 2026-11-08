import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/system_caption/caption_history.dart';

void main() {
  group('CaptionHistory.mergeOverlap', () {
    test('joins windows that share their edge words', () {
      expect(
        CaptionHistory.mergeOverlap('The cat sat on', 'sat on the mat'),
        'The cat sat on the mat',
      );
    });

    test('ignores case and punctuation when comparing', () {
      expect(
        CaptionHistory.mergeOverlap(
          'Hello there, my friend.',
          'My friend! How are you',
        ),
        'Hello there, my friend. How are you',
      );
    });

    test('keeps the previous text when the new window is contained in it', () {
      expect(
        CaptionHistory.mergeOverlap('one two three four', 'two three'),
        'one two three four',
      );
    });

    test('takes the new text when it contains the previous one', () {
      expect(
        CaptionHistory.mergeOverlap('two three', 'one two three four'),
        'one two three four',
      );
    });

    test('returns null for unrelated phrases', () {
      expect(
        CaptionHistory.mergeOverlap(
          'good morning everyone',
          'welcome to the show',
        ),
        isNull,
      );
    });

    test('a single shared word is not enough to merge', () {
      expect(
        CaptionHistory.mergeOverlap('see you at the', 'the weather is nice'),
        isNull,
      );
    });
  });

  group('CaptionHistory', () {
    test('ignores blank text', () {
      final history = CaptionHistory();
      expect(history.add('   '), isFalse);
      expect(history.isEmpty, isTrue);
      expect(history.latest, '');
    });

    test('merges rolling windows into one growing line', () {
      final history = CaptionHistory();
      expect(history.add('the quick brown fox'), isTrue);
      expect(history.add('brown fox jumps over'), isTrue);
      expect(history.add('jumps over the lazy dog'), isTrue);
      expect(history.lines, ['the quick brown fox jumps over the lazy dog']);
      expect(history.latest, 'the quick brown fox jumps over the lazy dog');
    });

    test('reports no change for a repeated window', () {
      final history = CaptionHistory()..add('hello everyone');
      expect(history.add('Hello everyone.'), isFalse);
      expect(history.lines, ['hello everyone']);
    });

    test('starts a new line for a new sentence', () {
      final history = CaptionHistory()
        ..add('good morning everyone')
        ..add('welcome to the show');
      expect(history.lines, ['good morning everyone', 'welcome to the show']);
      expect(history.latest, 'welcome to the show');
    });

    test('starts a new line when a merged line grows too long', () {
      final history = CaptionHistory(maxWordsPerLine: 6)
        ..add('one two three four five')
        ..add('four five six seven eight');
      expect(history.lines.length, 2);
      expect(history.latest, 'four five six seven eight');
    });

    test('keeps only the most recent lines', () {
      final history = CaptionHistory(maxLines: 3);
      for (final phrase in [
        'alpha beta',
        'gamma delta',
        'epsilon zeta',
        'eta theta',
      ]) {
        history.add(phrase);
      }
      expect(history.lines, ['gamma delta', 'epsilon zeta', 'eta theta']);
    });

    test('clear empties the history', () {
      final history = CaptionHistory()..add('hello there');
      history.clear();
      expect(history.isEmpty, isTrue);
    });
  });
}
