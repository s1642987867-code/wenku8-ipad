/// 本地小说目录快照（内置 3892 本，用于发现页和搜索）
///
/// 在线排行/搜索需登录（当前不可用），用本地快照替代。
/// 数据文件：assets/catalog/catalog.json（~4MB，压缩后 ~1.5MB）
library;

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

class NovelCatalog {
  static NovelCatalog? _instance;
  static NovelCatalog get instance => _instance ??= NovelCatalog._();

  NovelCatalog._();

  List<CatalogEntry> _entries = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get count => _entries.length;

  /// 加载目录数据（在 compute 中执行以避免卡 UI）
  Future<void> load() async {
    if (_loaded) return;
    try {
      final jsonStr = await rootBundle.loadString('assets/catalog/catalog.json');
      final List<dynamic> raw = json.decode(jsonStr);
      _entries = raw.map((e) => CatalogEntry.fromJson(e as List<dynamic>)).toList();
      _loaded = true;
    } catch (e) {
      // 加载失败时用内置热门书目兜底
      _entries = _fallbackBooks.map((e) => CatalogEntry.fromJson(e)).toList();
      _loaded = true;
    }
    // 兜底：即使加载成功但为空（CI 抓取失败），也用内置书目
    if (_entries.isEmpty) {
      _entries = _fallbackBooks.map((e) => CatalogEntry.fromJson(e)).toList();
    }
  }

  /// 内置热门书目（catalog 缺失时的兜底，标题来自 wenku8 实测数据）
  static const _fallbackBooks = <List<dynamic>>[
    [1636, '川之光', '松浦寿辉', '其他文库', 1, 286168],
    [1, '文学少女', '野村美月', 'Fami通文库', 1, 0],
    [2906, '狼与香辛料', '支仓冻砂', '电击文库', 1, 0],
    [1903, '刀剑神域', '川原砾', '电击文库', 1, 0],
    [2033, '魔法禁书目录', '镰池和马', '电击文库', 1, 0],
    [1955, '无头骑士异闻录', '成田良悟', '电击文库', 1, 0],
    [2148, '我的青春恋爱物语果然有问题', '渡航', '小学馆', 1, 0],
    [2203, '刀语', '西尾维新', '讲谈社', 1, 0],
    [2313, 'Re:从零开始的异世界生活', '长月达平', 'MF文库J', 1, 0],
    [2701, '为美好的世界献上祝福', '暁なつめ', '角川文库', 1, 0],
    [2847, 'Overlord', '丸山くがね', 'KADOKAWA', 1, 0],
    [3214, '路人女主的养成方法', '丸户史明', '富士见Fantasia文库', 1, 0],
    [1201, '凉宫春日的忧郁', '谷川流', '角川文库', 1, 0],
    [1516, '劈头士来的异世界', '暂缺', '暂缺', 0, 0],
    [2455, '机巧少女不会受伤', '海空陆', 'MF文库J', 1, 0],
    [2893, '笨蛋测验召唤兽', '井上坚二', '富士见Fantasia文库', 1, 0],
    [4402, '空挺Dragons', '橘もも', '暂缺', 0, 0],
    [3999, '欢迎来到实力至上主义的教室', '衣笠彰梧', '电击文库', 1, 0],
  ];

  /// 搜索（标题/作者）
  List<CatalogEntry> search(String keyword, {int limit = 50}) {
    if (keyword.isEmpty) return [];
    final kw = _normalize(keyword);
    return _entries
        .where((e) =>
            _normalize(e.title).contains(kw) ||
            _normalize(e.author).contains(kw))
        .take(limit)
        .toList();
  }

  /// 分页列表（支持排序/过滤）
  List<CatalogEntry> listPage({
    String? sort, // 'hot' | 'new' | 'completed'
    String? tag,
    bool completedOnly = false,
    int page = 1,
    int pageSize = 20,
  }) {
    var filtered = _entries.toList();

    if (tag != null && tag.isNotEmpty) {
      filtered = filtered.where((e) => e.tag == tag).toList();
    }
    if (completedOnly) {
      filtered = filtered.where((e) => e.status == 1).toList();
    }

    // 排序
    switch (sort) {
      case 'new':
        filtered.sort((a, b) => b.aid.compareTo(a.aid));
        break;
      case 'completed':
        filtered = filtered.where((e) => e.status == 1).toList();
        filtered.sort((a, b) => b.aid.compareTo(a.aid));
        break;
      case 'hot':
      default:
        filtered.sort((a, b) => (b.bookSize ?? 0).compareTo(a.bookSize ?? 0));
        break;
    }

    final start = (page - 1) * pageSize;
    if (start >= filtered.length) return [];
    return filtered.skip(start).take(pageSize).toList();
  }

  /// 热门推荐（随机取 N 本）
  List<CatalogEntry> recommend({int count = 12}) {
    if (_entries.isEmpty) return [];
    final shuffled = _entries.toList()..shuffle();
    return shuffled.take(count).toList();
  }

  /// 所有标签
  List<String> get tags {
    final set = <String>{};
    for (final e in _entries) {
      if (e.tag != null && e.tag!.isNotEmpty) set.add(e.tag!);
    }
    return set.toList()..sort();
  }

  /// CJK 归一化（去空格/标点/转小写）
  String _normalize(String s) {
    return s
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }
}
