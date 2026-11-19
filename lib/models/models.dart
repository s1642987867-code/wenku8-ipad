/// 数据模型。
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 书籍。
class Book {
  final String aid; // wenku8 书籍 id
  final String title;
  final String author;
  final String? coverUrl; // img.wenku8.com 封面
  final String? intro; // 简介
  final String? status; // 已完结/连载中
  final String? lastUpdate; // 最近更新
  final int? hits; // 点击
  final int? pushes; // 推荐
  final List<String> catalogs; // 分类
  final String? pubAgent; // 文库代理/出版信息

  const Book({
    required this.aid,
    required this.title,
    required this.author,
    this.coverUrl,
    this.intro,
    this.status,
    this.lastUpdate,
    this.hits,
    this.pushes,
    this.catalogs = const [],
    this.pubAgent,
  });

  Book copyWith({
    String? title,
    String? author,
    String? coverUrl,
    String? intro,
    String? status,
    String? lastUpdate,
    int? hits,
    int? pushes,
    List<String>? catalogs,
    String? pubAgent,
  }) =>
      Book(
        aid: aid,
        title: title ?? this.title,
        author: author ?? this.author,
        coverUrl: coverUrl ?? this.coverUrl,
        intro: intro ?? this.intro,
        status: status ?? this.status,
        lastUpdate: lastUpdate ?? this.lastUpdate,
        hits: hits ?? this.hits,
        pushes: pushes ?? this.pushes,
        catalogs: catalogs ?? this.catalogs,
        pubAgent: pubAgent ?? this.pubAgent,
      );

  Map<String, dynamic> toJson() => {
        'aid': aid,
        'title': title,
        'author': author,
        'coverUrl': coverUrl,
        'intro': intro,
        'status': status,
        'lastUpdate': lastUpdate,
        'hits': hits,
        'pushes': pushes,
        'catalogs': catalogs,
        'pubAgent': pubAgent,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        aid: j['aid'] as String,
        title: j['title'] as String,
        author: j['author'] as String? ?? '',
        coverUrl: j['coverUrl'] as String?,
        intro: j['intro'] as String?,
        status: j['status'] as String?,
        lastUpdate: j['lastUpdate'] as String?,
        hits: (j['hits'] as num?)?.toInt(),
        pushes: (j['pushes'] as num?)?.toInt(),
        catalogs: (j['catalogs'] as List?)?.cast<String>() ?? const [],
        pubAgent: j['pubAgent'] as String?,
      );

  String encode() => jsonEncode(toJson());
  static Book decode(String s) => Book.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// 卷 / 章节树节点。
class Volume {
  final String vid;
  final String title;
  final List<Chapter> chapters;
  const Volume({required this.vid, required this.title, required this.chapters});
}

/// 章节。
class Chapter {
  final String aid;
  final String cid;
  final String title;
  final String? volumeTitle;
  int? startLine; // 全本 TXT 解析用（起始行）
  int? endLine; // 结束行（不含）
  Chapter({
    required this.aid,
    required this.cid,
    required this.title,
    this.volumeTitle,
  });

  Map<String, dynamic> toJson() =>
      {'aid': aid, 'cid': cid, 'title': title, 'volumeTitle': volumeTitle};
  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        aid: j['aid'] as String,
        cid: j['cid'] as String,
        title: j['title'] as String,
        volumeTitle: j['volumeTitle'] as String?,
      );
}

/// 书架条目（含阅读进度）。
class ShelfEntry {
  final Book book;
  final String? lastCid;
  final String? lastChapterTitle;
  final int? lastChapterIdx; // 全局章序（M1：跨 cid 体系续读兜底）
  final int lastPosition; // 字符偏移或页码
  final int lastReadAt; // epoch ms
  ShelfEntry({
    required this.book,
    this.lastCid,
    this.lastChapterTitle,
    this.lastChapterIdx,
    this.lastPosition = 0,
    required this.lastReadAt,
  });

  ShelfEntry copyWith({
    String? lastCid,
    String? lastChapterTitle,
    int? lastChapterIdx,
    int? lastPosition,
    int? lastReadAt,
    bool clearChapterIdx = false,
  }) =>
      ShelfEntry(
        book: book,
        lastCid: lastCid ?? this.lastCid,
        lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
        lastChapterIdx: clearChapterIdx ? null : (lastChapterIdx ?? this.lastChapterIdx),
        lastPosition: lastPosition ?? this.lastPosition,
        lastReadAt: lastReadAt ?? this.lastReadAt,
      );

  Map<String, dynamic> toJson() => {
        'book': book.toJson(),
        'lastCid': lastCid,
        'lastChapterTitle': lastChapterTitle,
        'lastChapterIdx': lastChapterIdx,
        'lastPosition': lastPosition,
        'lastReadAt': lastReadAt,
      };
  factory ShelfEntry.fromJson(Map<String, dynamic> j) => ShelfEntry(
        book: Book.fromJson(j['book'] as Map<String, dynamic>),
        lastCid: j['lastCid'] as String?,
        lastChapterTitle: j['lastChapterTitle'] as String?,
        lastChapterIdx: (j['lastChapterIdx'] as num?)?.toInt(),
        lastPosition: (j['lastPosition'] as num?)?.toInt() ?? 0,
        lastReadAt: (j['lastReadAt'] as num?)?.toInt() ?? 0,
      );
}

/// 应用级设置（性能开关 / TTS / WebDAV 由各自服务持久化）。
class AppPrefs {
  final bool glassEnabled; // 玻璃折射（BackdropFilter）
  final bool blurEnabled; // 模糊
  final bool animationsEnabled; // 动效
  final bool lowPerfMode; // 低性能设备模式（全部关闭）
  const AppPrefs({
    this.glassEnabled = true,
    this.blurEnabled = true,
    this.animationsEnabled = true,
    this.lowPerfMode = false,
  });

  AppPrefs copyWith({
    bool? glassEnabled,
    bool? blurEnabled,
    bool? animationsEnabled,
    bool? lowPerfMode,
  }) =>
      AppPrefs(
        glassEnabled: glassEnabled ?? this.glassEnabled,
        blurEnabled: blurEnabled ?? this.blurEnabled,
        animationsEnabled: animationsEnabled ?? this.animationsEnabled,
        lowPerfMode: lowPerfMode ?? this.lowPerfMode,
      );

  Map<String, dynamic> toJson() => {
        'glass': glassEnabled,
        'blur': blurEnabled,
        'anim': animationsEnabled,
        'lowPerf': lowPerfMode,
      };

  factory AppPrefs.fromJson(Map<String, dynamic> j) => AppPrefs(
        glassEnabled: j['glass'] as bool? ?? true,
        blurEnabled: j['blur'] as bool? ?? true,
        animationsEnabled: j['anim'] as bool? ?? true,
        lowPerfMode: j['lowPerf'] as bool? ?? false,
      );
}

/// 应用偏好持久化。
class AppPrefsService {
  static const _key = 'app_prefs_v1';
  AppPrefs _prefs = const AppPrefs();
  AppPrefs get prefs => _prefs;
  final _ctrl = StreamController<AppPrefs>.broadcast();
  Stream<AppPrefs> get stream => _ctrl.stream;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw != null) {
        _prefs = AppPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _ctrl.add(_prefs);
      }
    } catch (_) {
      _prefs = const AppPrefs();
    }
  }

  Future<void> update(AppPrefs p) async {
    _prefs = p;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(p.toJson()));
    _ctrl.add(p);
  }
}

/// 书签。
class Bookmark {
  final String aid;
  final String cid;
  final String chapterTitle;
  final String excerpt; // 书签定位处文本摘要
  final int paragraphIndex;
  final int createdAt; // epoch ms
  const Bookmark({
    required this.aid,
    required this.cid,
    required this.chapterTitle,
    required this.excerpt,
    required this.paragraphIndex,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'aid': aid,
        'cid': cid,
        'chapterTitle': chapterTitle,
        'excerpt': excerpt,
        'paragraphIndex': paragraphIndex,
        'createdAt': createdAt,
      };
  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        aid: j['aid'] as String,
        cid: j['cid'] as String,
        chapterTitle: j['chapterTitle'] as String? ?? '',
        excerpt: j['excerpt'] as String? ?? '',
        paragraphIndex: (j['paragraphIndex'] as num?)?.toInt() ?? 0,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// 书签存取（SharedPreferences，按书聚合）。
class BookmarkService {
  static const _key = 'bookmarks_v1';
  List<Bookmark> _items = [];
  List<Bookmark> get items => List.unmodifiable(_items);

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items = list
            .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // minor5 修复：JSON 损坏时忽略，书签功能仍可用（新写入会覆盖坏数据）
      _items = [];
    }
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  List<Bookmark> forBook(String aid) =>
      _items.where((b) => b.aid == aid).toList();

  bool has(String aid, String cid, int paragraphIndex) =>
      _items.any((b) => b.aid == aid && b.cid == cid && b.paragraphIndex == paragraphIndex);

  Future<void> add(Bookmark bm) async {
    _items.removeWhere((b) =>
        b.aid == bm.aid && b.cid == bm.cid && b.paragraphIndex == bm.paragraphIndex);
    _items.insert(0, bm);
    await _save();
  }

  Future<void> remove(String aid, String cid, int paragraphIndex) async {
    _items.removeWhere((b) =>
        b.aid == aid && b.cid == cid && b.paragraphIndex == paragraphIndex);
    await _save();
  }
}

/// 阅读模式。
enum ReaderMode { scroll, horizontalPage, verticalPage, twoPage }

/// 阅读设置。
class ReaderSettings {
  final double fontSize;
  final double lineHeight;
  final ReaderMode mode;
  final String fontFamily;
  final String theme; // paper / cream / dark
  const ReaderSettings({
    this.fontSize = 19,
    this.lineHeight = 1.8,
    this.mode = ReaderMode.horizontalPage,
    this.fontFamily = 'Songti',
    this.theme = 'cream',
  });

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderMode? mode,
    String? fontFamily,
    String? theme,
  }) =>
      ReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        mode: mode ?? this.mode,
        fontFamily: fontFamily ?? this.fontFamily,
        theme: theme ?? this.theme,
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'mode': mode.index,
        'fontFamily': fontFamily,
        'theme': theme,
      };
  factory ReaderSettings.fromJson(Map<String, dynamic> j) => ReaderSettings(
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 19,
        lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.8,
        mode: ReaderMode.values[((j['mode'] as num?)?.toInt() ?? 1)
            .clamp(0, ReaderMode.values.length - 1)],
        fontFamily: j['fontFamily'] as String? ?? 'Songti',
        theme: j['theme'] as String? ?? 'cream',
      );
}
