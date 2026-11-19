/// 服务层：书架、本地书库、设置、TTS。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/wenku8_api.dart';
import '../models/models.dart';

/// 书架管理（收藏 + 进度），持久化到 SharedPreferences。
class BookshelfService {
  static const _key = 'bookshelf_v1';
  final List<ShelfEntry> _entries = [];
  final _ctrl = StreamController<List<ShelfEntry>>.broadcast();
  Stream<List<ShelfEntry>> get stream => _ctrl.stream;
  List<ShelfEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _entries
        ..clear()
        ..addAll(list
            .map((e) => ShelfEntry.fromJson(e as Map<String, dynamic>)));
      _ctrl.add(_entries);
    }
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    _ctrl.add(_entries);
  }

  bool has(String aid) => _entries.any((e) => e.book.aid == aid);

  ShelfEntry? get(String aid) {
    for (final e in _entries) {
      if (e.book.aid == aid) return e;
    }
    return null;
  }

  Future<void> addOrUpdate(Book book,
      {String? lastCid, String? lastChapterTitle, int? lastPosition}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final idx = _entries.indexWhere((e) => e.book.aid == book.aid);
    if (idx >= 0) {
      final e = _entries[idx];
      // m6 修复：同一章重复打开时不重复写盘
      if (e.lastCid == lastCid &&
          e.lastChapterTitle == lastChapterTitle &&
          (lastPosition == null || e.lastPosition == lastPosition)) {
        return;
      }
      _entries[idx] = e.copyWith(
        lastCid: lastCid,
        lastChapterTitle: lastChapterTitle,
        lastPosition: lastPosition,
        lastReadAt: now,
      );
    } else {
      _entries.insert(
          0,
          ShelfEntry(
            book: book,
            lastCid: lastCid,
            lastChapterTitle: lastChapterTitle,
            lastPosition: lastPosition ?? 0,
            lastReadAt: now,
          ));
    }
    await _save();
  }

  Future<void> remove(String aid) async {
    _entries.removeWhere((e) => e.book.aid == aid);
    await _save();
  }
}

/// 本地书库：下载整本书章节到磁盘、统计、删除。
class LocalLibraryService {
  final Wenku8Api api;
  final ContentCache cache;
  final _progress = StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progress => _progress.stream;

  LocalLibraryService(this.api, this.cache);

  Future<Directory> get root async =>
      cache.root;

  Future<void> downloadBook(Book book, List<Volume> volumes,
      {void Function(DownloadProgress)? onProgress}) async {
    final totalChapters = volumes.fold<int>(0, (s, v) => s + v.chapters.length);
    var done = 0;
    for (final vol in volumes) {
      for (final ch in vol.chapters) {
        if (await cache.exists(ch.aid, ch.cid)) {
          done++;
        } else {
          try {
            final text = await api.chapterContent(ch.aid, ch.cid);
            await cache.put(ch.aid, ch.cid, text);
            done++;
          } catch (_) {
            // 单章失败不中断整本下载
          }
        }
        final p = DownloadProgress(
          aid: book.aid,
          total: totalChapters,
          done: done,
          chapterTitle: ch.title,
        );
        _progress.add(p);
        onProgress?.call(p);
      }
    }
  }

  Future<bool> isBookDownloaded(List<Volume> volumes) async {
    var all = true;
    for (final v in volumes) {
      for (final c in v.chapters) {
        if (!await cache.exists(c.aid, c.cid)) {
          all = false;
          break;
        }
      }
      if (!all) break;
    }
    return all;
  }

  Future<int> sizeBytes() => cache.totalSize();

  Future<void> removeBook(String aid) => cache.removeBook(aid);
}

class DownloadProgress {
  final String aid;
  final int total;
  final int done;
  final String chapterTitle;
  DownloadProgress({
    required this.aid,
    required this.total,
    required this.done,
    required this.chapterTitle,
  });
  double get ratio => total == 0 ? 0 : done / total;
}

/// 阅读设置持久化。
class SettingsService {
  static const _key = 'reader_settings_v1';
  ReaderSettings _settings = const ReaderSettings();
  ReaderSettings get settings => _settings;
  final _ctrl = StreamController<ReaderSettings>.broadcast();
  Stream<ReaderSettings> get stream => _ctrl.stream;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw != null) {
      _settings = ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _ctrl.add(_settings);
    }
  }

  Future<void> update(ReaderSettings s) async {
    _settings = s;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(s.toJson()));
    _ctrl.add(s);
  }
}

/// 在线听书（系统 TTS，经 flutter_tts）。iPad 使用 AVSpeechSynthesis。
class TtsService {
  final FlutterTts _tts = FlutterTts();
  final _ctrl = StreamController<TtsState>.broadcast();
  Stream<TtsState> get stateStream => _ctrl.stream;
  TtsState _state = TtsState.idle;
  TtsState get state => _state;

  List<String> _paragraphs = [];
  int _index = 0;
  String? _chapterKey;

  bool _inited = false;

  Future<void> _init() async {
    if (_inited) return;
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() {
      _next();
    });
    _tts.setCancelHandler(() => _setState(TtsState.stopped));
    _inited = true;
  }

  void _setState(TtsState s) {
    _state = s;
    _ctrl.add(s);
  }

  Future<void> playChapter(String aid, String cid, String content) async {
    await _init();
    _chapterKey = '$aid-$cid';
    _paragraphs = content
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    _index = 0;
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (_index >= _paragraphs.length) {
      _setState(TtsState.finished);
      return;
    }
    _setState(TtsState.playing);
    try {
      await _tts.speak(_paragraphs[_index]);
    } catch (_) {
      _setState(TtsState.finished);
    }
  }

  Future<void> _next() async {
    _index++;
    await _speakCurrent();
  }

  Future<void> pause() async {
    await _tts.pause();
    _setState(TtsState.paused);
  }

  Future<void> resume() async {
    // M7 修复：从当前段重新播报（原来 speak('') 不会续播）
    if (_index < _paragraphs.length) {
      await _speakCurrent();
    } else {
      _setState(TtsState.finished);
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _setState(TtsState.stopped);
  }

  Future<void> setRate(double rate) => _tts.setSpeechRate(rate);
  Future<void> setVolume(double v) => _tts.setVolume(v);
  Future<void> setPitch(double p) => _tts.setPitch(p);

  String? get currentChapterKey => _chapterKey;
  int get paragraphIndex => _index;
}

enum TtsState { idle, playing, paused, stopped, finished }
