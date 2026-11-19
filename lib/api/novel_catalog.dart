/// 全站书目目录：来自 wenku8 全站元数据快照（assets/data/novel_catalog.json，
/// 3892 本：aid/标题/作者/文库/状态/字数/最后更新/最新章节/标签/简介），
/// 封面走 jsdelivr CDN（github 镜像 wenku8_novel_list/cover/cover_{aid}.jpg）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// 简体→繁体最小映射（覆盖 wenku8 标签/标题高频异体字，M2 修复：
/// 用户输入简体"后宫"也能命中繁体"後宮"）。
const Map<String, String> _s2t = {
  '宫': '宮', '后': '後', '发': '發', '轻': '輕', '学': '學',
  '园': '園', '卫': '衛', '术': '術', '历': '歷', '钟': '鐘',
  '杀': '殺', '戏': '戲', '欢': '歡', '态': '態', '记': '記',
  '异': '異', '变': '變', '体': '體', '龙': '龍', '凤': '鳳',
  '剑': '劍', '战': '戰', '争': '爭',
  '传': '傳', '说': '說', '话': '話', '语': '語', '读': '讀',
  '书': '書', '图': '圖', '画': '畫', '间': '間', '门': '門',
  '问': '問', '开': '開', '关': '關', '东': '東', '车': '車',
  '马': '馬', '鸟': '鳥', '鱼': '魚', '贝': '貝', '见': '見',
  '观': '觀', '爱': '愛', '恋': '戀', '务': '務', '兰': '蘭',
  '梦': '夢', '实': '實', '现': '現', '电': '電', '机': '機',
  '云': '雲', '风': '風', '飞': '飛', '习': '習', '条': '條',
  '级': '級', '红': '紅', '绿': '綠', '蓝': '藍', '黄': '黃',
  '银': '銀', '铁': '鐵', '钢': '鋼', '炼': '煉',
  '补': '補', '结': '結', '婚': '婚',
  '双': '雙', '单': '單', '兽': '獸', '猫': '貓', '犬': '犬',
  '艺': '藝', '师': '師', '圣': '聖', '职': '職',
  '业': '業', '组': '組', '织': '織', '队': '隊', '军': '軍',
  '网': '網', '络': '絡', '游': '遊', '剧': '劇',
  '场': '場', '环': '環', '选': '選', '择': '擇', '经': '經',
  '济': '濟', '设': '設', '备': '備', '库': '庫',
  '史': '史', '录': '錄', '计': '計', '划': '劃',
};

/// 归一化：简→繁（用于与繁体数据集比对）。
String normalizeCjk(String s) {
  final buf = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    buf.write(_s2t[c] ?? c);
  }
  return buf.toString();
}

/// 顶层解析函数（compute 要求，M1 修复：4MB JSON 移出主 isolate）。
List<CatalogEntry> _parseEntries(String raw) {
  final data = jsonDecode(raw) as List<dynamic>;
  final out = <CatalogEntry>[];
  for (final item in data) {
    final e = CatalogEntry.fromJson(item as Map<String, dynamic>);
    if (e.aid > 0 && e.title.isNotEmpty) out.add(e);
  }
  return out;
}

class NovelCatalog {
  /// jsdelivr 封面 CDN（2025-06 快照，含全站 3892 张封面）。
  static String coverUrl(int aid) =>
      'https://cdn.jsdelivr.net/gh/yuusukealmal/wenku8_novel_list@main/cover/cover_$aid.jpg';

  /// jsdelivr 上的目录 JSON（应用内置一份 + 此处在线兜底刷新可选）。
  static const String catalogUrl =
      'https://cdn.jsdelivr.net/gh/yuusukealmal/wenku8_novel_list@main/novel.json';

  final List<CatalogEntry> entries;
  final Map<int, CatalogEntry> _byAid;

  NovelCatalog._(this.entries)
      : _byAid = {
          for (final e in entries) e.aid: e,
        };

  static NovelCatalog? _instance;

  /// 加载内置目录（单例）。M1 修复：jsonDecode 放到后台 isolate。
  static Future<NovelCatalog> load() async {
    final cached = _instance;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/data/novel_catalog.json',
        cache: false);
    final entries = await compute(_parseEntries, raw);
    _instance = NovelCatalog._(entries);
    return _instance!;
  }

  int get length => entries.length;

  CatalogEntry? byAid(int aid) => _byAid[aid];

  /// 关键词搜索：标题/作者/标签/文库 全字段包含匹配（简繁归一化）。
  List<CatalogEntry> search(String keyword, {int limit = 50}) {
    final kw = normalizeCjk(keyword.trim().toLowerCase());
    if (kw.isEmpty) return const [];
    final scored = <(CatalogEntry, int)>[];
    for (final e in entries) {
      var score = 0;
      final title = normalizeCjk(e.title.toLowerCase());
      final author = normalizeCjk(e.author.toLowerCase());
      if (title == kw) {
        score = 100;
      } else if (title.startsWith(kw)) {
        score = 80;
      } else if (title.contains(kw)) {
        score = 60;
      } else if (author.contains(kw)) {
        score = 40;
      } else if (e.tags
          .any((t) => normalizeCjk(t.toLowerCase()).contains(kw))) {
        score = 20;
      } else if (normalizeCjk(e.publish.toLowerCase()).contains(kw)) {
        score = 10;
      }
      if (score > 0) scored.add((e, score));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      return b.$1.aid.compareTo(a.$1.aid); // 同分新 aid 优先
    });
    return scored.take(limit).map((x) => x.$1).toList();
  }

  /// 分类列表页数据：按筛选维度取一页。
  /// [sort]: popular(默认顺序) / update(最近更新) / length(字数) / complete(完结)
  /// [tag]: 标签过滤（如 "后宫"、"青春"）；[publish]: 文库过滤（如 "电击文库"）
  List<CatalogEntry> listPage({
    CatalogSort sort = CatalogSort.popular,
    String? tag,
    String? publish,
    String? status,
    bool completedOnly = false,
    int page = 1,
    int pageSize = 24,
  }) {
    var pool = entries;
    if (tag != null && tag.isNotEmpty) {
      final nTag = normalizeCjk(tag);
      pool =
          pool.where((e) => e.tags.any((t) => normalizeCjk(t) == nTag)).toList();
    }
    if (publish != null && publish.isNotEmpty) {
      pool = pool.where((e) => e.publish == publish).toList();
    }
    if (completedOnly || status != null && status.isNotEmpty) {
      pool = pool
          .where((e) =>
              (completedOnly || status == null || status.isEmpty || e.completed) &&
              (status == null || status.isEmpty || e.status == status))
          .toList();
    }
    final sorted = switch (sort) {
      CatalogSort.update => pool.toList()
        ..sort((a, b) => (b.lastUpdate ?? '').compareTo(a.lastUpdate ?? '')),
      CatalogSort.length => pool.toList()
        ..sort((a, b) => b.length.compareTo(a.length)),
      CatalogSort.popular => pool, // 快照原序（aid 序，近似老作品在前）
    };
    final start = (page - 1) * pageSize;
    final s = start < 0 ? 0 : start; // m1 防御：page<=0
    if (s >= sorted.length) return const [];
    return sorted.sublist(s, (s + pageSize).clamp(s, sorted.length));
  }

  int countOf(
      {String? tag,
      String? publish,
      String? status,
      bool completedOnly = false}) {
    var pool = entries;
    if (tag != null && tag.isNotEmpty) {
      final nTag = normalizeCjk(tag);
      pool =
          pool.where((e) => e.tags.any((t) => normalizeCjk(t) == nTag)).toList();
    }
    if (publish != null && publish.isNotEmpty) {
      pool = pool.where((e) => e.publish == publish).toList();
    }
    if (status != null && status.isNotEmpty) {
      pool = pool.where((e) => e.status == status).toList();
    }
    if (completedOnly) {
      pool = pool.where((e) => e.completed).toList();
    }
    return pool.length;
  }

  /// 所有标签按使用量降序。
  List<(String, int)> allTags({int limit = 40}) {
    final counts = <String, int>{};
    for (final e in entries) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final list = counts.entries.map((x) => (x.key, x.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(limit).toList();
  }

  /// 所有文库（出版社）按藏量降序。
  List<(String, int)> allPublishers({int limit = 24}) {
    final counts = <String, int>{};
    for (final e in entries) {
      if (e.publish.isNotEmpty) counts[e.publish] = (counts[e.publish] ?? 0) + 1;
    }
    final list = counts.entries.map((x) => (x.key, x.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(limit).toList();
  }

  /// "最近更新" 精选（发现页默认陈列）：lastUpdate 最近的前 N 本。
  List<CatalogEntry> recent({int count = 96}) {
    final pool = entries.toList()
      ..sort((a, b) => (b.lastUpdate ?? '').compareTo(a.lastUpdate ?? ''));
    return pool.take(count).toList();
  }
}

enum CatalogSort { popular, update, length }

/// 目录条目（对齐 wenku8_novel_list 的 novel.json 字段）。
class CatalogEntry {
  final int aid;
  final String title;
  final String author;
  final String publish;
  final String status;
  final int length;
  final String? lastUpdate;
  final String? lastSection;
  final List<String> tags;
  final String description;

  const CatalogEntry({
    required this.aid,
    required this.title,
    required this.author,
    required this.publish,
    required this.status,
    required this.length,
    this.lastUpdate,
    this.lastSection,
    required this.tags,
    required this.description,
  });

  bool get completed => status.contains('完'); // m3：兼容 已完成/完結 等写法

  /// 转 Book 供详情页/书架复用。
  Book toBook() => Book(
        aid: '$aid',
        title: title,
        author: author,
        coverUrl: NovelCatalog.coverUrl(aid),
        status: status,
        intro: description,
        catalogs: tags,
        pubAgent: publish,
        lastUpdate: lastUpdate,
      );

  factory CatalogEntry.fromJson(Map<String, dynamic> j) {
    int aid = 0;
    final rawAid = j['aid'];
    if (rawAid is int) aid = rawAid;
    if (rawAid is String) aid = int.tryParse(rawAid) ?? 0;
    int length = 0;
    final rawLen = j['length'];
    if (rawLen is int) length = rawLen;
    if (rawLen is String) length = int.tryParse(rawLen) ?? 0;
    return CatalogEntry(
      aid: aid,
      title: (j['title'] as String? ?? '').trim(),
      author: (j['author'] as String? ?? '').trim(),
      publish: (j['publish'] as String? ?? '').trim(),
      status: (j['status'] as String? ?? '').trim(),
      length: length,
      lastUpdate: j['last_update'] as String?,
      lastSection: j['last_section'] as String?,
      tags: (j['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((t) => t.isNotEmpty) // m2：过滤空标签
          .toList(),
      description: (j['description'] as String? ?? '').trim(),
    );
  }
}
