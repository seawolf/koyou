import 'package:flutter/foundation.dart';

import '../pinyin/word.dart';
import 'favourite.dart';

export 'favourite.dart';

/// The learner's saved lines.
///
/// An interface for the same reason the translators are one: the screens show
/// and edit a list, and where it is kept — preferences on a phone,
/// `localStorage` in a browser, a list in memory in a test — is decided once,
/// in `app.dart`.
abstract interface class Favourites {
  /// Newest first. Rebuilds whatever is listening when it changes, so the star
  /// on one screen and the list on another cannot disagree.
  ValueListenable<List<Favourite>> get items;

  /// Keeps [line], or does nothing if it is already kept.
  ///
  /// Not an error to save twice: the star shows whether a line is saved, so
  /// the only way to ask twice is two taps racing each other.
  Future<void> save(List<Word> line, {String? meaning});

  Future<void> remove(Favourite favourite);

  /// Puts the list in [order], which is the learner's own from then on.
  ///
  /// Given the whole order rather than a pair of indices, because the list on
  /// screen is not always the list in the store — a row just swiped away is
  /// hidden before the store has dropped it — and an index into one is not an
  /// index into the other. Favourites [order] leaves out keep their places
  /// after it; ones it names that are no longer kept are ignored.
  Future<void> reorder(List<Favourite> order);

  void dispose();
}

/// Lookups every caller would otherwise write for itself.
extension FavouritesLookup on Favourites {
  /// The favourite for [line], or null if it has not been kept.
  Favourite? find(List<Word> line) {
    for (final favourite in items.value) {
      if (favourite.isFor(line)) return favourite;
    }
    return null;
  }
}
