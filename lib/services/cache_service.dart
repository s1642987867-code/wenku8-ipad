/// 章节缓存 + 阅读历史 + 数据备份
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'local_import.dart';
import 'services.dart';

/// 章节缓存服务：在线章节缓存到内存+磁盘，离线可读
class ChapterCacheService {
  static final ChapterCacheService instance = ChapterCacheService._();
  ChapterCacheService._();

  static Directory get _dir {
    final d = Directory('${Directory.systemTemp.path}/wenku8_chache');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  File _file(String aid, String cid) => File('${_dir.path}/${aid}_$cid.json');

  /// 读缓存（无网络时）
  Future<String?> get(String aid, String cid) async {
    final f = _file(aid, cid);
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        return j['content']?.toString();
      } catch (_) {}
    }
    return null;
  }

  /// 写缓存
  Future<void> put(String aid, String cid, String content) async {
    try {
      await _file(aid, cid).writeAsString(jsonEncode({
        'aid': aid, 'cid': cid, 'content': content,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  /// 是否已缓存
  Future<bool> has(String aid, String cid) async => _file(aid, cid).exists();

  /// 缓存统计
  Future<(int, int)> stats() async {
    var count = 0;
    var bytes = 0;
    await for (final f in _dir.list()) {
      if (f is File) { count++; bytes += await f.length(); }
    }
    return (count, bytes);
  }

  /// 清空缓存
  Future<void> clear() async {
    await for (final f in _dir.list()) {
      if (f is File) await f.delete();
    }
  }

  /// 整本缓存（下载全书）
  Future<int> cacheWholeBook(String aid, List<Volume> volumes, Future<String> Function(String cid) fetch) async {
    var cached = 0;
    for (final vol in volumes) {
      for (final ch in vol.chapters) {
        if (await has(aid, ch.cid)) { cached++; continue; }
        try {
          final content = await fetch(ch.cid);
          await put(aid, ch.cid, content);
          cached++;
        } catch (_) {
          // 单章失败继续
        }
      }
    }
    return cached;
  }
}

/// 阅读历史服务（最近阅读记录，独立于书架进度）
class HistoryService {
  static final HistoryService instance = HistoryService._();
  HistoryService._();

  final List<Map<String, dynamic>> _history = []; // {aid, title, cid, chapterTitle, at}

  List<Map<String, dynamic>> get list => List.unmodifiable(_history);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('reading_history');
    if (json != null) {
      final List<dynamic> raw = jsonDecode(json);
      _history..clear()..addAll(raw.whereType<Map<String, dynamic>>());
    }
  }

  Future<void> record(String aid, String title, String cid, String chapterTitle) async {
    _history.removeWhere((h) => h['aid'] == aid);
    _history.insert(0, {
      'aid': aid, 'title': title, 'cid': cid, 'chapterTitle': chapterTitle,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    if (_history.length > 100) _history.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reading_history', jsonEncode(_history));
  }

  Future<void> clear() async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reading_history');
  }
}

/// 备份服务：导出/导入 ZIP（书架+进度+书签+设置+历史）
class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  Map<String, dynamic> _collect() => {
        'version': 3,
        'exportedAt': DateTime.now().toIso8601String(),
        'shelf': ShelfService.instance.list.map((e) => e.toJson()).toList(),
        'bookmarks': BookmarkService.instance.all.map((b) => b.toJson()).toList(),
        'settings': SettingsService.instance.current.toJson(),
        'history': HistoryService.instance.list,
        'localBooks': LocalLibraryService.instance.books.map((b) => b.toJson()).toList(),
      };

  Future<String> exportToFile() async {
    final data = jsonEncode(_collect());
    final dataBytes = Uint8List.fromList(utf8.encode(data));
    final archive = Archive()
      ..addFile(ArchiveFile('backup.json', dataBytes.length, dataBytes));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    final path = await FilePicker.platform.saveFile(
      fileName: 'wenku8_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
      bytes: bytes,
    );
    return path ?? '';
  }

  Future<int> importFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? f;
    for (final x in archive.files) {
      if (x.name == 'backup.json') { f = x; break; }
    }
    if (f == null) throw Exception('备份文件无效');
    final data = jsonDecode(utf8.decode(f.content as Uint8List)) as Map<String, dynamic>;

    var count = 0;
    // 书架
    final shelf = (data['shelf'] as List<dynamic>? ?? [])
        .map((e) => ShelfEntry.fromJson(e as Map<String, dynamic>));
    for (final entry in shelf) {
      if (!ShelfService.instance.contains(entry.book.aid)) {
        await ShelfService.instance.add(entry.book);
        if (entry.lastCid != null) {
          await ShelfService.instance.updateProgress(
            entry.book.aid, entry.lastCid!, entry.lastChapterTitle ?? '',
            entry.lastChapterIdx ?? 0, entry.lastPosition,
          );
        }
        count++;
      }
    }
    // 书签（经 prefs 直接合并）
    final bm = (data['bookmarks'] as List<dynamic>? ?? []);
    if (bm.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('bookmarks');
      final List<dynamic> merged = existing != null ? jsonDecode(existing) : [];
      final ids = merged.map((m) => m['id']).toSet();
      for (final b in bm) {
        if (!ids.contains(b['id'])) merged.add(b);
      }
      await prefs.setString('bookmarks', jsonEncode(merged));
    }
    // 历史
    final history = (data['history'] as List<dynamic>? ?? []);
    if (history.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('reading_history', jsonEncode(history));
    }
    return count;
  }
}
