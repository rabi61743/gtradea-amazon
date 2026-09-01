import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One past visual search.
@immutable
class VisualSearch {
  const VisualSearch({
    required this.id,
    required this.imagePath,
    required this.searchedAt,
    this.resultCount = 0,
  });

  final String id;

  /// Where the thumbnail lives in the app's own documents directory.
  ///
  /// A copy, not the picker's file: `image_picker` hands back something in a
  /// cache directory the OS may clear whenever it likes, so a history that
  /// pointed at those would show broken thumbnails within days.
  final String imagePath;

  final DateTime searchedAt;

  /// How many matches it found. Shown so a search that came back with nothing
  /// is recognisable before it is tapped again.
  final int resultCount;

  File get file => File(imagePath);

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': imagePath,
    'at': searchedAt.toIso8601String(),
    'count': resultCount,
  };

  static VisualSearch? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final path = json['path'];
    if (id is! String || path is! String || id.isEmpty || path.isEmpty) {
      return null;
    }
    return VisualSearch(
      id: id,
      imagePath: path,
      searchedAt: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
      resultCount: json['count'] is int ? json['count'] as int : 0,
    );
  }
}

/// The visual searches this shopper has run, newest first.
///
/// Local, and staying local: the API has no visual-search history endpoint, and
/// inventing one client-side that pretended to sync would be worse than an
/// honest device-only list. It also means a shared phone does not leak one
/// person's photographs to the next -- there is nothing to leak from a server.
///
/// The metadata lives in SharedPreferences and the pictures live as files
/// beside it. Base64-ing photographs into a preferences string would put
/// megabytes into a store meant for flags.
class VisualSearchStore extends ChangeNotifier {
  VisualSearchStore._();

  static final instance = VisualSearchStore._();

  static const _key = 'gtradea_visual_searches';

  /// How many to keep. Each one is a file on disk, so this is a real cost
  /// rather than a tidiness preference.
  static const limit = 12;

  static const _folder = 'visual_search';

  List<VisualSearch> _items = const [];
  bool _loaded = false;

  List<VisualSearch> get items => _items;
  bool get isEmpty => _items.isEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items = decoded
              .whereType<Map>()
              .map((e) => VisualSearch.fromJson(e.cast<String, dynamic>()))
              .whereType<VisualSearch>()
              // A thumbnail whose file has gone -- the app reinstalled, the
              // user cleared storage -- is an entry that would render as a
              // grey hole. Dropped on the way in rather than shown broken.
              .where((s) => s.file.existsSync())
              .toList(growable: false);
        }
      }
    } catch (_) {
      // An unreadable history is an empty history. Nothing here is worth a
      // failure the shopper has to read.
    }
    notifyListeners();
  }

  /// Copies [source] somewhere durable and records the search.
  ///
  /// Returns the stored entry, whose [VisualSearch.file] is the copy -- the
  /// caller should show that rather than the picker's original.
  Future<VisualSearch?> record(File source, {int resultCount = 0}) =>
      _keep(resultCount: resultCount, write: (path) => source.copy(path));

  /// Records a search made with a picture the app holds only as bytes.
  ///
  /// A search started from a product page has a catalogue address rather than
  /// a file, and the history is files: every entry shows a thumbnail without
  /// the network and is re-run by handing that same file back. Writing the
  /// bytes down keeps both of those true, so an entry from a product page
  /// behaves exactly like one from the camera.
  Future<VisualSearch?> recordBytes(Uint8List bytes, {int resultCount = 0}) =>
      _keep(
        resultCount: resultCount,
        write: (path) async => File(path)..writeAsBytesSync(bytes),
      );

  Future<VisualSearch?> _keep({
    required int resultCount,
    required Future<File> Function(String path) write,
  }) async {
    try {
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/$_folder',
      );
      if (!dir.existsSync()) await dir.create(recursive: true);

      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final saved = await write('${dir.path}/$id.jpg');

      final entry = VisualSearch(
        id: id,
        imagePath: saved.path,
        searchedAt: DateTime.now(),
        resultCount: resultCount,
      );

      final kept = [entry, ..._items];
      // Anything past the limit loses its file too, or the directory grows
      // without bound behind a list that shows twelve.
      for (final dropped in kept.skip(limit)) {
        unawaited(_deleteFile(dropped));
      }
      _items = kept.take(limit).toList(growable: false);
      _loaded = true;
      notifyListeners();
      unawaited(_persist());
      return entry;
    } catch (_) {
      // Failing to save the history must not fail the search itself -- the
      // results are already on screen and are the thing being asked for.
      return null;
    }
  }

  Future<void> remove(String id) async {
    final gone = _items.where((s) => s.id == id).toList();
    _items = _items.where((s) => s.id != id).toList(growable: false);
    notifyListeners();
    for (final entry in gone) {
      unawaited(_deleteFile(entry));
    }
    unawaited(_persist());
  }

  Future<void> clear() async {
    final gone = _items;
    _items = const [];
    notifyListeners();
    for (final entry in gone) {
      unawaited(_deleteFile(entry));
    }
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _items = const [];
    _loaded = false;
  }

  Future<void> _deleteFile(VisualSearch entry) async {
    try {
      final file = entry.file;
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A thumbnail that will not delete is a few kilobytes, not a problem to
      // report.
    }
  }

  Future<void> _persist() async {
    // Captured before the first await: the list can change while the write is
    // in flight, and writing whatever it became would drop the newest entry.
    final payload = jsonEncode([for (final s in _items) s.toJson()]);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, payload);
    } catch (_) {
      // Best effort, like every other convenience cache in the app.
    }
  }
}
