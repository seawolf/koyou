import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pinyin/word.dart';
import 'favourites.dart';

/// Favourites kept as one JSON string wherever [read] and [write] keep it.
///
/// The storage is two closures rather than a plugin, so everything worth
/// testing here — loading, saving twice, surviving a bad row — runs without a
/// platform. [StoredFavourites.preferences] is the only part that needs one.
class StoredFavourites implements Favourites {
  StoredFavourites({
    required this.read,
    required this.write,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _loaded = _load().whenComplete(() => _ready = true);
  }

  /// Kept in the platform's preferences: `SharedPreferences` on Android,
  /// `NSUserDefaults` on iOS, `localStorage` in a browser.
  ///
  /// Preferences rather than a file, because it is the one store that works on
  /// every target this app builds for — `path_provider` has no directory to
  /// offer a browser — and a list of saved phrases is small enough to be a
  /// preference.
  ///
  /// Opened on first use rather than here. The constructor throws at once
  /// where no platform store is registered, and thrown here that would stop
  /// the app starting; thrown on first use it lands in the handling that
  /// already turns unreadable storage into an empty list.
  factory StoredFavourites.preferences() {
    SharedPreferencesAsync? preferences;
    SharedPreferencesAsync open() => preferences ??= SharedPreferencesAsync();
    return StoredFavourites(
      read: () => open().getString(storageKey),
      write: (json) => open().setString(storageKey, json),
    );
  }

  /// Versioned, so a change of shape can be read alongside the old one rather
  /// than misread as it.
  static const storageKey = 'favourites.v1';

  final Future<String?> Function() read;
  final Future<void> Function(String json) write;
  final DateTime Function() _clock;

  @override
  final ValueNotifier<List<Favourite>> items = ValueNotifier(const []);

  late final Future<void> _loaded;

  /// Whether [_loaded] has finished, so a change can be published without
  /// waiting on it. Awaiting even a completed future yields, and a reordered
  /// list published a moment late is drawn for one frame in its old order —
  /// the dragged row visibly jumps back before it settles.
  bool _ready = false;

  /// Writes go one at a time, in order. Two saves close together would
  /// otherwise race, and the older list could land last and win.
  Future<void> _writing = Future<void>.value();

  Future<void> _load() async {
    String? stored;
    try {
      stored = await read();
    } on Object {
      // Storage that cannot be read is an empty list, not a broken screen.
      return;
    }
    if (stored == null) return;

    Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return;
    }
    if (decoded is! List) return;
    items.value = List.unmodifiable([
      for (final raw in decoded) ?Favourite.fromJson(raw),
    ]);
  }

  @override
  Future<void> save(List<Word> line, {String? meaning}) async {
    await _loaded;
    final words = Favourite.kept(line);
    if (words.isEmpty || find(words) != null) return;
    _publish([
      Favourite(words: words, meaning: meaning, saved: _clock()),
      ...items.value,
    ]);
    await _persist();
  }

  @override
  Future<void> remove(Favourite favourite) async {
    await _loaded;
    _publish([
      for (final kept in items.value)
        if (!kept.isFor(favourite.words)) kept,
    ]);
    await _persist();
  }

  @override
  Future<void> reorder(List<Favourite> order) async {
    if (!_ready) await _loaded;
    final kept = items.value;
    final placed = <Favourite>[
      for (final favourite in order)
        if (kept.contains(favourite)) favourite,
    ];
    _publish([
      ...placed,
      for (final favourite in kept)
        if (!placed.contains(favourite)) favourite,
    ]);
    await _persist();
  }

  void _publish(List<Favourite> next) => items.value = List.unmodifiable(next);

  Future<void> _persist() {
    final json = jsonEncode([for (final f in items.value) f.toJson()]);
    final done = _writing.then((_) => write(json));
    // A failed write leaves the list as it is on screen and the next write
    // carries the whole of it, so there is nothing to recover by throwing.
    _writing = done.then((_) {}, onError: (_) {});
    return _writing;
  }

  @override
  void dispose() => items.dispose();
}
