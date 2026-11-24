/// 服务层：书架管理、阅读进度、书签、设置持久化
library;

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 书架服务
class ShelfService {
  static final ShelfService instance = ShelfService._();
  ShelfService._();

  final List<ShelfEntry> _entries = [];
  final _controller = StreamController<List<ShelfEntry>>.broadcast();
  Stream<List<ShelfEntry>> get entries => _controller.stream;

  List<ShelfEntry> get list => List.unmodifiable(_entries);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('shelf_entries');
    if (json != null) {
      final List<dynamic> raw = jsonDecode(json);
      _entries.clear();
      _entries.addAll(raw.map((e) => ShelfEntry.fromJson(e as Map<String, dynamic>)));
    }
    _controller.add(List.of(_entries));
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shelf_entries', jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> add(Book book) async {
    if (_entries.any((e) => e.book.aid == book.aid)) return;
    _entries.insert(0, ShelfEntry(book: book, lastReadAt: DateTime.now().millisecondsSinceEpoch));
    _controller.add(List.of(_entries));
    await _save();
  }

  Future<void> remove(String aid) async {
    _entries.removeWhere((e) => e.book.aid == aid);
    _controller.add(List.of(_entries));
    await _save();
  }

  bool contains(String aid) => _entries.any((e) => e.book.aid == aid);

  Future<void> updateProgress(String aid, String cid, String chapterTitle, int chapterIdx, int position) async {
    final idx = _entries.indexWhere((e) => e.book.aid == aid);
    if (idx < 0) return;
    _entries[idx] = _entries[idx].copyWith(
      lastCid: cid,
      lastChapterTitle: chapterTitle,
      lastChapterIdx: chapterIdx,
      lastPosition: position,
      lastReadAt: DateTime.now().millisecondsSinceEpoch,
    );
    _controller.add(List.of(_entries));
    await _save();
  }

  ShelfEntry? get(String aid) {
    final idx = _entries.indexWhere((e) => e.book.aid == aid);
    return idx >= 0 ? _entries[idx] : null;
  }
}

/// 书签服务
class BookmarkService {
  static final BookmarkService instance = BookmarkService._();
  BookmarkService._();

  final List<Bookmark> _bookmarks = [];
  final _controller = StreamController<List<Bookmark>>.broadcast();
  Stream<List<Bookmark>> get bookmarks => _controller.stream;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('bookmarks');
    if (json != null) {
      final List<dynamic> raw = jsonDecode(json);
      _bookmarks.clear();
      _bookmarks.addAll(raw.map((e) => Bookmark.fromJson(e as Map<String, dynamic>)));
    }
    _controller.add(List.of(_bookmarks));
  }

  List<Bookmark> forBook(String aid) =>
      _bookmarks.where((b) => b.aid == aid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> add(Bookmark b) async {
    _bookmarks.add(b);
    _controller.add(List.of(_bookmarks));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bookmarks', jsonEncode(_bookmarks.map((e) => e.toJson()).toList()));
  }

  Future<void> remove(String id) async {
    _bookmarks.removeWhere((b) => b.id == id);
    _controller.add(List.of(_bookmarks));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bookmarks', jsonEncode(_bookmarks.map((e) => e.toJson()).toList()));
  }
}

/// 阅读设置服务
class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  ReaderSettings _settings = const ReaderSettings();
  final _controller = StreamController<ReaderSettings>.broadcast();
  Stream<ReaderSettings> get settings => _controller.stream;
  ReaderSettings get current => _settings;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('reader_settings');
    if (json != null) {
      _settings = ReaderSettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }
    _controller.add(_settings);
  }

  Future<void> update(ReaderSettings s) async {
    _settings = s;
    _controller.add(_settings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_settings', jsonEncode(s.toJson()));
  }
}

/// 登录状态服务
class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  String? _username;
  String? _password;
  bool _loggedIn = false;

  String? get username => _username;
  bool get isLoggedIn => _loggedIn;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('login_username');
    _password = prefs.getString('login_password');
    _loggedIn = prefs.getBool('login_status') ?? false;
  }

  Future<void> setLoggedIn(String username, String password) async {
    _username = username;
    _password = password;
    _loggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('login_username', username);
    await prefs.setString('login_password', password);
    await prefs.setBool('login_status', true);
  }

  Future<void> logout() async {
    _username = null;
    _password = null;
    _loggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('login_username');
    await prefs.remove('login_password');
    await prefs.setBool('login_status', false);
  }
}

/// 本地导入服务（TXT/EPUB）
class ImportService {
  static final ImportService instance = ImportService._();
  ImportService._();

  Future<String?> importTxt(String path) async {
    // 返回本地书 ID
    final file = File(path);
    if (!await file.exists()) return null;
    final name = path.split(Platform.pathSeparator).last;
    return 'local_txt_$name';
  }
}
