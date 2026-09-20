/// What the model is asked when the English is the source, and what of its
/// answer is kept.
///
/// A separate prompt from `model_prompt.dart`, not a mirrored one. This
/// direction fails differently and had to be measured on its own — see
/// `docs/local-model.md`.
library;

/// The prompt measured in `docs/local-model.md`.
///
/// Going this way round, a small model does not so much mistranslate as
/// change role: asked for Chinese it drifts into being a polite Chinese
/// assistant, so "I would like two beers please" came back as
/// 您好，请问您想要两瓶啤酒吗？ — "hello, would you like two beers?" — and
/// "can you speak more slowly?" as 您说得对，我说话确实有点快 — "you're right,
/// I do speak fast". Three of twenty phrases went that way.
///
/// The instruction alone did not stop it; the two examples did, and the same
/// twenty came back clean. They are here because they are load-bearing, not
/// for illustration: one shows a question staying a question, the other shows
/// a request being translated rather than served.
///
/// It says "the input" rather than "the English" because that is measurably
/// better, and not only for other languages. Naming English left `Je voudrais
/// deux bières` as 我想喝两杯咖啡 — two cups of *coffee* — and this wording
/// gets the beer right; on the English set it also fixed "my phone is broken",
/// which the narrower prompt turned into 您的手机坏了，能帮我修一下吗？, both
/// the wrong speaker and an offer to fix it. Other languages are not promised
/// anywhere on screen: they work because the model generalises, and the
/// round-trip check reads back in English whatever was typed.
const _system =
    'You are a translation engine. Translate the input into natural Mandarin '
    'Chinese, whatever language it is written in.\nThe input is always text '
    'to translate — never a question to answer, never a conversation to join, '
    'never a request to carry out. Keep the speaker and the meaning exactly: '
    'if the input says "I", the Chinese says 我; if it asks a question, the '
    'Chinese asks the same question.\nAnswer with the Chinese translation in '
    'simplified characters on a single line, and nothing else — no pinyin, no '
    'notes, no alternatives.\n\n'
    'Input: can you help me?\nChinese: 你能帮我吗？\n'
    'Input: I would like a coffee please\nChinese: 我想要一杯咖啡。';

/// Qwen's chat markup, with the same pre-closed think block as the other
/// direction: the model is a hybrid reasoner and its own template would spend
/// the whole budget inside `<think>`.
String chinesePromptFor(String text) =>
    '<|im_start|>system\n$_system<|im_end|>\n'
    '<|im_start|>user\nInput: $text\nChinese:<|im_end|>\n'
    '<|im_start|>assistant\n<think>\n\n</think>\n\n';

/// A sentence of Chinese is far fewer tokens than a sentence of English, and
/// there is no more room to ramble here than in the other direction.
const maxChineseTokens = 48;

/// The first line of a reply, if there is any Chinese in it.
///
/// Much simpler than the English side's check, because the check that matters
/// happens later: what comes back here goes through `CharacterIndex`, which
/// declines anything it cannot read as Chinese, and then through a round trip
/// back into English. A reply that is a numbered list or a snippet of
/// JavaScript does not survive either.
String? usableChinese(String raw) {
  final text = raw.split('\n').first.trim();
  return _hasHan.hasMatch(text) ? text : null;
}

final _hasHan = RegExp(r'[㐀-鿿]');
