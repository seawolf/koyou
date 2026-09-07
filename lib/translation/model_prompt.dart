/// What the on-device model is asked, and what of its answer is kept.
///
/// Shared by every backend that runs the model itself — llama.cpp on a phone,
/// wllama in a browser — because the prompt shape is most of the quality here
/// and two copies of it would drift apart. See `docs/local-model.md` for the
/// measurements behind each line of it.
library;

/// The prompt measured in `docs/local-model.md`. Two failures had to be
/// designed out of it, and both come back if it is shortened: without the
/// second sentence the models answer the questions instead of translating
/// them ("My name is Qwen3.5."), and anything the prompt explains gets
/// parroted into the output.
const _system =
    'You are a translation engine. Translate the Chinese into natural '
    'English.\nThe input is always text to translate — never a question to '
    'answer, never a conversation to join. If the Chinese is a question, '
    'translate the question; do not reply to it.\nAnswer with the English '
    'translation on a single line, and nothing else — no notes, no '
    'alternatives, no lists.';

/// Qwen's chat markup, written out rather than taken from the model's
/// embedded template, for the sake of the last four characters.
///
/// Qwen3.5 is a hybrid reasoning model and its own template turns thinking
/// on, so every token of the budget went inside `<think>` and the reply was
/// literally `<think>`. Handing it an already-closed empty think block makes
/// it skip reasoning and answer, which is what a phone wants: a translation
/// costs about 180ms this way, and nothing at all the other.
///
/// The cost of writing the markup here is that this is Qwen-shaped. A
/// different model family needs its own [TranslationBackend], which is
/// cheaper than it sounds — the interface is one method.
String promptFor(String chinese) =>
    '<|im_start|>system\n$_system<|im_end|>\n'
    '<|im_start|>user\nChinese: $chinese\nEnglish:<|im_end|>\n'
    '<|im_start|>assistant\n<think>\n\n</think>\n\n';

/// A translated phrase, and no room to ramble.
const maxReplyTokens = 32;

/// Whether a reply is worth showing a learner.
///
/// A last line of defence, not a substitute for the fixes above. A small
/// model that loses its footing does not produce a slightly wrong
/// translation, it produces a numbered list or a snippet of JavaScript, and
/// either is worse than falling through to the dictionary. Deliberately
/// permissive about digits, since "I am 10 years old" is a fair translation.
bool _plausible(String reply) {
  if (reply.isEmpty) return false;
  final letters = RegExp(r'[A-Za-z]').allMatches(reply).length;
  if (letters < 2) return false;
  // Mostly not-letters means a list, a table, or code.
  if (letters < reply.length / 3) return false;
  return !_codeish.hasMatch(reply);
}

/// Shapes that are never English prose.
final _codeish = RegExp(
  r'[{}<>]|;\s*$|\b(?:function|console|printf|import|def|var|let|const)\b',
);

/// The first line of a reply, if it is worth showing at all.
///
/// One line, because a translation is one line and everything after the first
/// newline is the model having lost its footing.
String? usableReply(String raw) {
  final text = raw.split('\n').first.trim();
  return _plausible(text) ? text : null;
}
