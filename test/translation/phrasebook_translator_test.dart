import 'package:flutter_test/flutter_test.dart';
import 'package:kouyu/translation/phrasebook_translator.dart';
import 'package:kouyu/translation/translator.dart';

void main() {
  const translator = PhrasebookTranslator();

  test('matches a whole phrase', () async {
    expect(await translator.translate('nǐ hǎo'), const Translation('hello'));
    expect(
      await translator.translate('nǐ hǎo shìjiè'),
      const Translation('hello, world'),
    );
  });

  test('matches a single word', () async {
    expect(await translator.translate('shuǐ'), const Translation('water'));
  });

  test(
    'glosses word by word when the phrase is unknown, and says so',
    () async {
      expect(
        await translator.translate('wǒ hěn hǎo'),
        const Translation('I; me · very · good', wordByWord: true),
      );
    },
  );

  test('prefers a whole-phrase match over a gloss', () async {
    final result = await translator.translate('wǒ ài nǐ');
    expect(result, const Translation('I love you'));
    expect(result!.wordByWord, isFalse);
  });

  test('gives up rather than guessing at unknown words', () async {
    expect(await translator.translate('zhèige'), isNull);
    expect(await translator.translate('nǐ zhèige'), isNull);
  });

  test('ignores case and surrounding or repeated whitespace', () async {
    expect(
      await translator.translate('  Nǐ   hǎo '),
      const Translation('hello'),
    );
  });

  test('has nothing to say about empty input', () async {
    expect(await translator.translate(''), isNull);
    expect(await translator.translate('   '), isNull);
  });

  // Tones distinguish words, so a translator must not treat them as noise.
  test('does not match a phrase whose tones are wrong', () async {
    expect(await translator.translate('ni hao'), isNull);
    expect(await translator.translate('nì hǎo'), isNull);
  });
}
