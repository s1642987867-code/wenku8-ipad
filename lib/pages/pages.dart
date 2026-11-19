/// 页面：发现 / 书架 / 本地书库 / 详情 / 阅读 / 听书。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/wenku8_api.dart';
import '../api/novel_catalog.dart';
import '../api/web_scraper.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../ui/design_system.dart';
import '../ui/reader.dart';

// ---------------- 发现页（wenku8 全站目录 + 纪念站风格陈列书架） ----------------

class DiscoverPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final TtsService? tts;
  final SettingsService? settingsService;
  const DiscoverPage(
      {super.key,
      required this.api,
      required this.shelf,
      this.tts,
      this.settingsService});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _ctrl = TextEditingController();
  NovelCatalog? _catalog;
  List<CatalogEntry>? _results;
  String? _error;
  late PageController _shelfCtrl;
  int _shelfPage = 0;
  int _totalShelfPages = 1;
  String? _activeTag; // 标签筛选
  CatalogSort _sort = CatalogSort.popular;
  String? _activePublisher; // 文库筛选
  bool _completeOnly = false; // 只看完结

  static const int _booksPerShelf = 9; // 每个陈列架 9 册（8 脊 + 1 立起）

  @override
  void initState() {
    super.initState();
    _shelfCtrl = PageController();
    _loadCatalog();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _shelfCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final c = await NovelCatalog.load();
      if (!mounted) return;
      setState(() => _catalog = c);
      _updateShelfPages();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '目录加载失败：$e');
    }
  }

  void _updateShelfPages() {
    final c = _catalog;
    if (c == null) return;
    final prev = _shelfPage;
    if (_results != null) {
      _totalShelfPages =
          (_results!.length / _booksPerShelf).ceil().clamp(1, 1 << 30);
    } else {
      final n = c.countOf(
          tag: _activeTag,
          publish: _activePublisher,
          completedOnly: _completeOnly);
      _totalShelfPages = (n / _booksPerShelf).ceil().clamp(1, 1 << 30);
    }
    if (_shelfPage >= _totalShelfPages) _shelfPage = _totalShelfPages - 1;
    if (_shelfPage < 0) _shelfPage = 0;
    // C1 修复：同步 PageController，避免筛选/搜索后像素偏移越界
    if (prev != _shelfPage && _shelfCtrl.hasClients) {
      _shelfCtrl.jumpToPage(_shelfPage);
    }
  }

  /// 缓存当前筛选下的书目池（m8：避免每页翻页全量重建）。
  List<CatalogEntry>? _poolCache;

  List<CatalogEntry> _currentPool() {
    final c = _catalog;
    if (c == null) return const [];
    if (_results != null) return _results!;
    return _poolCache ??= c.listPage(
      sort: _sort,
      tag: _activeTag,
      publish: _activePublisher,
      completedOnly: _completeOnly,
      pageSize: 1 << 30,
    );
  }

  void _invalidatePool() => _poolCache = null;

  /// 当前陈列架第 [page] 组书目。
  List<CatalogEntry> _shelfBooks(int page) {
    final pool = _currentPool();
    final start = page * _booksPerShelf;
    if (start >= pool.length) return const [];
    return pool.sublist(start, (start + _booksPerShelf).clamp(0, pool.length));
  }

  void _doSearch() {
    final kw = _ctrl.text.trim();
    final c = _catalog;
    if (kw.isEmpty || c == null) return;
    final r = c.search(kw, limit: 200);
    setState(() {
      _results = r;
      _shelfPage = 0;
      _activeTag = null;
      _activePublisher = null;
      _completeOnly = false;
      _sort = CatalogSort.popular;
      _invalidatePool();
      _error = r.isEmpty ? '全站 ${c.length} 本中未找到「$kw」' : null;
    });
    _updateShelfPages();
  }

  void _clearSearch() {
    setState(() {
      _results = null;
      _error = null;
      _shelfPage = 0;
      _invalidatePool();
    });
    _updateShelfPages();
  }

  void _pickTag(String? tag) {
    setState(() {
      _activeTag = tag;
      _results = null;
      _error = null;
      _shelfPage = 0;
      _invalidatePool();
    });
    _updateShelfPages();
  }

  /// 打开完整筛选面板（分类 / 排行 / 出版文库）。
  Future<void> _openFilterSheet() async {
    final c = _catalog;
    if (c == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CreamTokens.bgBase,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _FilterSheet(
        catalog: c,
        currentSort: _sort,
        currentTag: _activeTag,
        currentPublisher: _activePublisher,
        completeOnly: _completeOnly,
        onApply: (sort, tag, pub, complete) {
          Navigator.of(sheetCtx).pop();
          setState(() {
            _sort = sort;
            _activeTag = tag;
            _activePublisher = pub;
            _completeOnly = complete;
            _results = null;
            _error = null;
            _shelfPage = 0;
            _invalidatePool();
          });
          _updateShelfPages();
        },
      ),
    );
  }

  void _openDetail(CatalogEntry e) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookDetailPage(
        api: widget.api,
        shelf: widget.shelf,
        tts: widget.tts,
        settingsService: widget.settingsService,
        book: e.toBook(),
      ),
    ));
  }

  Color _spineColor(int aid) {
    // 黑白为主的档案风：深浅灰 + 少量深色调
    final palette = const [
      Color(0xFF2F2B27), // 墨黑
      Color(0xFF4A4440), // 深炭
      Color(0xFF6E6259), // 暖灰
      Color(0xFF8C5A4A), // 砖红（点缀）
      Color(0xFF3D5247), // 墨绿（点缀）
      Color(0xFF41506B), // 藏蓝（点缀）
      Color(0xFF5A524B), // 灰褐
      Color(0xFF71655B), // 浅褐
    ];
    return palette[aid % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = _catalog;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBrandHeader(),
          const SizedBox(height: 14),
          _buildSearchBar(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          if (_activeTag != null ||
              _results != null ||
              _activePublisher != null ||
              _completeOnly ||
              _sort != CatalogSort.popular)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (_sort != CatalogSort.popular)
                    _chip(
                        '排序：${switch (_sort) {
                          CatalogSort.update => '最近更新',
                          CatalogSort.length => '字数最多',
                          _ => '默认',
                        }}',
                        () {
                      setState(() => _sort = CatalogSort.popular);
                      _invalidatePool();
                      _updateShelfPages();
                    }),
                  if (_activePublisher != null)
                    _chip('文库：$_activePublisher', () {
                      setState(() => _activePublisher = null);
                      _invalidatePool();
                      _updateShelfPages();
                    }),
                  if (_completeOnly)
                    _chip('只看完结', () {
                      setState(() => _completeOnly = false);
                      _invalidatePool();
                      _updateShelfPages();
                    }),
                  if (_activeTag != null)
                    _chip('标签：$_activeTag', () => _pickTag(null)),
                  if (_results != null)
                    _chip(
                        '搜索：${_ctrl.text} (${_results!.length})', _clearSearch),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (c == null)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(child: _buildShelfArea(c)),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onRemove) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: CreamTokens.ink)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 14, color: CreamTokens.inkSoft),
            ),
          ],
        ),
      );

  /// 品牌头：方形黑标 "W8" + 轻小说文库 + 英文副题 + 右侧搜索图标。
  Widget _buildBrandHeader() => Row(
        children: [
          Container(
            width: 44,
            height: 44,
            color: Colors.black,
            alignment: Alignment.center,
            child: const Text('W8',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('轻小说文库',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        fontFamily: 'Songti',
                        letterSpacing: 2)),
                SizedBox(height: 2),
                Text('WENKU8 / READING ARCHIVE',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 3,
                        color: CreamTokens.inkSoft)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black54),
            onPressed: () {
              // m4 修复：收起键盘并执行搜索（原 new FocusNode() 泄漏）
              FocusScope.of(context).unfocus();
              _doSearch();
            },
          ),
        ],
      );

  Widget _buildSearchBar() => Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x1A000000)),
              ),
              child: TextField(
                controller: _ctrl,
                onSubmitted: (_) => _doSearch(),
                decoration: const InputDecoration(
                  hintText: '搜索书名 / 作者 / 标签 · 全站 3892 本',
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(color: CreamTokens.ink, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _doSearch,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ),
          ),
        ],
      );

  /// 陈列区：若干层陈列架（PageView 翻页） + 热门标签 + 翻页指示器。
  Widget _buildShelfArea(NovelCatalog c) {
    final tags = c.allTags(limit: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 区块标题：01 / CATALOG —— 最近更新 / 标签名 + 筛选按钮
        Row(
          children: [
            Text(_activeTag != null ? '02 / TAG' : '01 / CATALOG',
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: CreamTokens.inkSoft,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(width: 40, height: 1, color: CreamTokens.glassBorder),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _results != null
                    ? '搜索结果'
                    : (_activeTag ?? '最近更新'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    fontFamily: 'Songti'),
              ),
            ),
            // 排行直达
            PopupMenuButton<CatalogSort>(
              tooltip: '排行',
              icon: const Icon(Icons.leaderboard_outlined,
                  size: 20, color: Colors.black54),
              onSelected: (s) {
                setState(() => _sort = s);
                _invalidatePool();
                _updateShelfPages();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: CatalogSort.popular, child: Text('默认书序')),
                PopupMenuItem(value: CatalogSort.update, child: Text('最近更新')),
                PopupMenuItem(value: CatalogSort.length, child: Text('字数最多')),
              ],
            ),
            // 筛选面板
            IconButton(
              tooltip: '筛选',
              icon: Icon(
                Icons.tune,
                size: 20,
                color: (_activeTag != null ||
                        _activePublisher != null ||
                        _completeOnly)
                    ? Colors.black
                    : Colors.black54,
              ),
              onPressed: _openFilterSheet,
            ),
            if (_totalShelfPages > 1)
              Text('${_shelfPage + 1} / $_totalShelfPages',
                  style: const TextStyle(
                      fontSize: 11, color: CreamTokens.inkSoft)),
          ],
        ),
        const SizedBox(height: 10),
        // 陈列架翻页
        Expanded(
          child: PageView.builder(
            controller: _shelfCtrl,
            itemCount: _totalShelfPages,
            onPageChanged: (i) => setState(() => _shelfPage = i),
            itemBuilder: (context, page) {
              final books = _shelfBooks(page);
              if (books.isEmpty) {
                return const Center(
                    child: Text('没有更多了',
                        style: TextStyle(color: CreamTokens.inkSoft)));
              }
              // 每架 9 本：第 4 本立起（index 4），其余作书脊
              final upright = 4.clamp(0, books.length - 1);
              final displayBooks = [
                for (var i = 0; i < books.length; i++)
                  DisplayBook(
                    aid: '${books[i].aid}',
                    title: books[i].title,
                    author: books[i].author,
                    coverUrl: NovelCatalog.coverUrl(books[i].aid),
                    spineColor: _spineColor(books[i].aid),
                  ),
              ];
              return DisplayShelf(
                books: displayBooks,
                uprightIndex: upright,
                onBookTap: (b) {
                  final aid = int.tryParse(b.aid);
                  final e = aid == null ? null : c.byAid(aid);
                  if (e != null) _openDetail(e);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // 翻页控制
        if (_totalShelfPages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _shelfPage > 0
                    ? () => _shelfCtrl.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                    '${(_shelfPage + 1).toString().padLeft(2, '0')} / ${_totalShelfPages.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: CreamTokens.inkSoft,
                        letterSpacing: 2)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _shelfPage < _totalShelfPages - 1
                    ? () => _shelfCtrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut)
                    : null,
              ),
            ],
          ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _results != null || _activeTag != null
                ? '已经到底了'
                : '全站共 ${c.length} 本 · 点书可查看详情',
            style: const TextStyle(
                fontSize: 11, color: CreamTokens.inkSoft, letterSpacing: 1),
          ),
        ),
        const SizedBox(height: 10),
        // 热门标签
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (t, n) in tags)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text('$t · $n',
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: _activeTag == t
                        ? Colors.black
                        : Colors.white,
                    labelStyle: TextStyle(
                        fontSize: 11,
                        color: _activeTag == t
                            ? Colors.white
                            : CreamTokens.ink),
                    side: const BorderSide(color: Color(0x1A000000)),
                    onPressed: () => _pickTag(t),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: const Text('全部标签',
                      style: TextStyle(fontSize: 11)),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x1A000000)),
                  onPressed: () => _pickTag(null), // 清除并交给筛选面板
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- 筛选面板 ----------------

class _FilterSheet extends StatefulWidget {
  final NovelCatalog catalog;
  final CatalogSort currentSort;
  final String? currentTag;
  final String? currentPublisher;
  final bool completeOnly;
  final void Function(CatalogSort, String?, String?, bool) onApply;
  const _FilterSheet({
    required this.catalog,
    required this.currentSort,
    required this.currentTag,
    required this.currentPublisher,
    required this.completeOnly,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late CatalogSort _sort = widget.currentSort;
  late String? _tag = widget.currentTag;
  late String? _pub = widget.currentPublisher;
  late bool _complete = widget.completeOnly;

  Widget _section(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: CreamTokens.inkSoft,
                    fontWeight: FontWeight.w600)),
          ),
          child,
          const SizedBox(height: 14),
        ],
      );

  Widget _choiceChips<T>({
    required List<(T?, String)> options,
    required T? current,
    required void Function(T?) onPick,
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (v, label) in options)
            ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: current == v,
              onSelected: (_) => onPick(current == v ? null : v),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.catalog;
    final publishers = c.allPublishers(limit: 18);
    final tags = c.allTags(limit: 40);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('筛选',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Songti',
                          letterSpacing: 2)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => widget.onApply(
                        CatalogSort.popular, null, null, false),
                    child: const Text('重置'),
                  ),
                ],
              ),
              _section(
                '排行',
                _choiceChips<CatalogSort>(
                  options: const [
                    (CatalogSort.popular, '默认书序'),
                    (CatalogSort.update, '最近更新'),
                    (CatalogSort.length, '字数最多'),
                  ],
                  current: _sort,
                  onPick: (v) => setState(() => _sort = v ?? CatalogSort.popular),
                ),
              ),
              _section(
                '出版文库',
                _choiceChips<String>(
                  options: [
                    for (final (p, n) in publishers) (p, '$p · $n'),
                  ],
                  current: _pub,
                  onPick: (v) => setState(() => _pub = v),
                ),
              ),
              _section(
                '标签',
                _choiceChips<String>(
                  options: [
                    for (final (t, n) in tags) (t, '$t · $n'),
                  ],
                  current: _tag,
                  onPick: (v) => setState(() => _tag = v),
                ),
              ),
              _section(
                '状态',
                Row(
                  children: [
                    Switch(
                      value: _complete,
                      onChanged: (v) => setState(() => _complete = v),
                    ),
                    const Text('只看完结',
                        style:
                            TextStyle(fontSize: 13, color: CreamTokens.ink)),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.black),
                  onPressed: () => widget.onApply(_sort, _tag, _pub, _complete),
                  child: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- 书单页（分类/排行/文库/作者/标签 书籍列表） ----------------

/// 书单页数据源。四选一：catalogFilter（分类/排行/文库）、author、tag、search。
class CatalogListPage extends StatelessWidget {
  final NovelCatalog catalog;
  final String title;
  final String serial; // 左上角编号，如 03 / RANK
  final CatalogFilter? filter;
  final String? author;
  final String? tag;
  final String? searchKeyword;
  final Wenku8Api api;
  final BookshelfService shelf;
  final TtsService? tts;
  final SettingsService? settingsService;

  const CatalogListPage({
    super.key,
    required this.catalog,
    required this.title,
    required this.serial,
    required this.api,
    required this.shelf,
    this.filter,
    this.author,
    this.tag,
    this.searchKeyword,
    this.tts,
    this.settingsService,
  });

  List<CatalogEntry> get _entries {
    if (author != null) {
      final n = normalizeCjk(author!);
      return catalog.entries
          .where((e) => normalizeCjk(e.author) == n)
          .toList()
        ..sort((a, b) => (b.lastUpdate ?? '').compareTo(a.lastUpdate ?? ''));
    }
    if (tag != null) {
      final n = normalizeCjk(tag!);
      return catalog.entries
          .where((e) => e.tags.any((t) => normalizeCjk(t) == n))
          .toList()
        ..sort((a, b) => (b.lastUpdate ?? '').compareTo(a.lastUpdate ?? ''));
    }
    if (searchKeyword != null) return catalog.search(searchKeyword!, limit: 500);
    final f = filter!;
    return catalog.listPage(
      sort: f.sort,
      tag: f.tag,
      publish: f.publish,
      status: f.status,
      pageSize: 1 << 30,
    );
  }

  void _openDetail(BuildContext context, CatalogEntry e) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookDetailPage(
        api: api,
        shelf: shelf,
        tts: tts,
        settingsService: settingsService,
        book: e.toBook(),
        catalog: catalog,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: CreamTokens.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        title: Text('$serial   $title',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                fontFamily: 'Songti')),
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text('没有符合条件的书',
                  style: TextStyle(color: CreamTokens.inkSoft)))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ArchiveCard(
                    serial: 'A-${e.aid}',
                    title: e.title,
                    subtitle:
                        '${e.author} · ${e.status} · ${e.publish.isEmpty ? "未知文库" : e.publish}',
                    tags: e.tags.take(4).toList(),
                    onTap: () => _openDetail(context, e),
                  ),
                );
              },
            ),
    );
  }
}

/// 分类筛选描述。
class CatalogFilter {
  final CatalogSort sort;
  final String? tag;
  final String? publish;
  final String? status;
  const CatalogFilter({this.sort = CatalogSort.popular, this.tag, this.publish, this.status});
}

// ---------------- 书架页 ----------------

class ShelfPage extends StatelessWidget {
  final BookshelfService shelf;
  final LocalLibraryService library;
  final Wenku8Api api;
  final TtsService? tts;
  final SettingsService? settingsService;
  // P5UEDGK 风格：书架可切换「立体书架 / 列表」视图
  final NovelCatalog? catalog;
  const ShelfPage({
    super.key,
    required this.shelf,
    required this.library,
    required this.api,
    this.tts,
    this.settingsService,
    this.catalog,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShelfEntry>>(
      stream: shelf.stream,
      initialData: shelf.entries,
      builder: (context, snap) {
        final entries = snap.data ?? [];
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const ArchiveHeader(title: '书架', note: '阅读进度 · 立体陈列'),
              const SizedBox(height: 16),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text('书架空空如也，去「发现」找几本书吧',
                            style: TextStyle(color: CreamTokens.inkSoft)))
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            for (var start = 0;
                                start < entries.length;
                                start += 6)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: BookshelfLayer(
                                  books: [
                                    for (var i = start;
                                        i < (start + 6).clamp(0, entries.length);
                                        i++)
                                      ShelfBook(
                                        aid: entries[i].book.aid,
                                        title: entries[i].book.title,
                                        progressNote: entries[i].lastChapterTitle,
                                      ),
                                  ],
                                  onBookTap: (b) => _open(context, b.aid),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 点书：有进度直接续读（P5UEDGK「点书直接续读」），否则进详情页。
  /// M4 修复：无进度时直接用本地 entry.book 打开详情页（不再先下载全本 TXT）；
  /// 续读下载失败时降级到详情页而非报错终止。
  Future<void> _open(BuildContext context, String aid) async {
    final entry = shelf.get(aid);
    if (entry == null) return;
    if (entry.lastCid == null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookDetailPage(
          api: api,
          shelf: shelf,
          library: library,
          tts: tts,
          settingsService: settingsService,
          book: entry.book,
          catalog: catalog,
        ),
      ));
      return;
    }
    try {
      final (book, volumes) = await api.bookDetail(aid);
      if (!context.mounted) return;
      final flat = [for (final v in volumes) ...v.chapters];
      // M1 修复：cid 命中优先，否则按章序兜底（跨 cid 体系不丢进度）
      Chapter? resume;
      for (final c in flat) {
        if (c.cid == entry.lastCid) resume = c;
      }
      resume ??= (entry.lastChapterIdx != null &&
              entry.lastChapterIdx! < flat.length &&
              entry.lastChapterIdx! >= 0)
          ? flat[entry.lastChapterIdx!]
          : flat.firstOrNull;
      if (resume == null) throw Wenku8Exception('本书未解析出章节');
      // 续读章节是网页格式（w 前缀）→ 附带爬虫实例
      final needScraper = resume.cid.startsWith('w') ? WebScraper() : null;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReaderPage(
          api: api,
          shelf: shelf,
          book: book,
          chapter: resume!,
          volumes: volumes,
          library: library,
          tts: tts,
          settingsService: settingsService,
          scraper: needScraper,
        ),
      ));
    } catch (txtErr) {
      // 双源降级：TXT 通道失败 → 网页爬虫目录续读
      if (int.tryParse(aid) != null) {
        try {
          final scraper = WebScraper();
          final (book, volumes) = await scraper.toc(aid);
          if (!context.mounted) return;
          final flat = [for (final v in volumes) ...v.chapters];
          // M1 修复：cid 命中优先，否则按章序兜底
          Chapter? resume;
          for (final c in flat) {
            if (c.cid == entry.lastCid) resume = c;
          }
          resume ??= (entry.lastChapterIdx != null &&
                  entry.lastChapterIdx! < flat.length &&
                  entry.lastChapterIdx! >= 0)
              ? flat[entry.lastChapterIdx!]
              : flat.firstOrNull;
          final target = resume;
          if (target != null) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReaderPage(
                api: api,
                shelf: shelf,
                book: book,
                chapter: target,
                volumes: volumes,
                library: library,
                tts: tts,
                settingsService: settingsService,
                scraper: scraper,
              ),
            ));
            return;
          }
        } catch (_) {/* 落到详情页降级 */}
      }
      // 降级：打开详情页
      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookDetailPage(
          api: api,
          shelf: shelf,
          library: library,
          tts: tts,
          settingsService: settingsService,
          book: entry.book,
          catalog: catalog,
        ),
      ));
    }
  }
}

// ---------------- 本地书库页 ----------------

class LibraryPage extends StatefulWidget {
  final LocalLibraryService library;
  final BookshelfService shelf;
  final Wenku8Api api;
  final TtsService? tts;
  final SettingsService? settingsService;
  const LibraryPage({
    super.key,
    required this.library,
    required this.shelf,
    required this.api,
    this.tts,
    this.settingsService,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int? _size;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  void _refreshSize() {
    widget.library.sizeBytes().then((v) {
      if (!mounted) return;
      setState(() => _size = v);
    });
  }

  @override
  void didUpdateWidget(LibraryPage old) {
    super.didUpdateWidget(old);
    _refreshSize();
  }

  String _fmt(int? bytes) {
    if (bytes == null) return '…';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    // m5 修复：用 StreamBuilder 跟随书架变化（IndexedStack 下 State 不再销毁重建）
    return StreamBuilder<List<ShelfEntry>>(
      stream: widget.shelf.stream,
      builder: (context, snap) {
        final entries = snap.data ?? widget.shelf.entries;
        // 阅读历史 = 书架按 lastReadAt 倒序
        final history = entries.toList()
          ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
          const ArchiveHeader(title: '本地书库', note: '离线缓存 · 阅读历史 · 缓存管理'),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('缓存占用 ${_fmt(_size)}',
                  style: const TextStyle(
                      color: CreamTokens.inkSoft, fontSize: 12)),
              const Spacer(),
              // 清空全部缓存
              TextButton.icon(
                onPressed: _size == null || _size == 0
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('清空全部缓存'),
                            content: const Text('将删除所有离线章节（阅读进度保留），确定？'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('清空')),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await widget.library.cache.clearAll();
                          _refreshSize();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('缓存已清空')));
                          }
                        }
                      },
                icon: const Icon(Icons.delete_sweep, size: 16),
                label: const Text('清空缓存', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 阅读历史区
          if (history.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('阅读历史',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: CreamTokens.ink)),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 84,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: history.length,
                itemBuilder: (context, i) {
                  final e = history[i];
                  final dt = DateTime.fromMillisecondsSinceEpoch(e.lastReadAt);
                  return Container(
                    width: 150,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CreamTokens.glassBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: CreamTokens.ink)),
                        const Spacer(),
                        Text('${e.lastChapterTitle ?? "未开始"}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10, color: CreamTokens.inkSoft)),
                        Text(
                            '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}',
                            style: const TextStyle(
                                fontSize: 9, color: CreamTokens.inkSoft)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: ListView(
              children: [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ArchiveCard(
                      serial: 'L-${e.book.aid}',
                      title: e.book.title,
                      subtitle:
                          '最后阅读：${e.lastChapterTitle ?? '未开始'}',
                      tags: const ['离线'],
                      trailing: IconButton(
                        tooltip: '清除本书缓存',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await widget.library.removeBook(e.book.aid);
                          _refreshSize();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('已清除《${e.book.title}》缓存')));
                          }
                        },
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookDetailPage(
                            api: widget.api,
                            shelf: widget.shelf,
                            library: widget.library,
                            tts: widget.tts,
                            settingsService: widget.settingsService,
                            book: e.book,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
          ),
        );
      },
    );
  }
}

// ---------------- 详情页 ----------------

class BookDetailPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final LocalLibraryService? library;
  final TtsService? tts;
  final SettingsService? settingsService;
  final Book book;
  final NovelCatalog? catalog; // 有目录时支持作者/标签书单跳转
  const BookDetailPage({
    super.key,
    required this.api,
    required this.shelf,
    this.library,
    this.tts,
    this.settingsService,
    required this.book,
    this.catalog,
  });

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  Book? _detail;
  List<Volume>? _volumes;
  String? _error;
  DownloadProgress? _dlProgress;
  WebScraper? _scraper; // TXT 通道失败时的在线降级源

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 在线双源：TXT 通道失败时自动降级到网页爬虫目录（无需登录，实测可用）
    try {
      final (book, volumes) = await widget.api.bookDetail(widget.book.aid);
      if (!mounted) return;
      setState(() {
        _detail = book;
        _volumes = volumes;
      });
    } catch (e) {
      if (int.tryParse(widget.book.aid) != null) {
        try {
          final scraper = WebScraper();
          final (book, volumes) = await scraper.toc(widget.book.aid);
          if (!mounted) return;
          setState(() {
            _detail = book;
            _volumes = volumes;
            _scraper = scraper;
          });
          return;
        } catch (_) {/* 双源都失败 */}
      }
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _downloadAll() async {
    if (widget.library == null || _volumes == null) return;
    await widget.library!.downloadBook(_detail ?? widget.book, _volumes!,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _dlProgress = p);
        });
    if (!mounted) return;
    setState(() => _dlProgress = null);
  }

  @override
  Widget build(BuildContext context) {
    final b = _detail ?? widget.book;
    // M3 修复：封面 URL 保持入口稳定，避免 _load 后换 URL 引起闪烁/黑块
    final coverUrl = widget.book.coverUrl ?? _detail?.coverUrl;
    return Scaffold(
      backgroundColor: CreamTokens.bgBase,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                BackButton(onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: ArchiveHeader(title: b.title, note: '档案编号 A-${b.aid}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 档案头部：封面 + 元信息（黑白档案风）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 96,
                  height: 132,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0x22000000)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x2E000000),
                          blurRadius: 10,
                          offset: Offset(2, 4)),
                    ],
                  ),
                  child: coverUrl != null
                      ? Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF2B2B2B),
                            alignment: Alignment.center,
                            child: Text(
                              b.title,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Songti'),
                            ),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 作者可点击 → 作者书单
                      GestureDetector(
                        onTap: widget.catalog == null
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CatalogListPage(
                                      catalog: widget.catalog!,
                                      title: '${b.author} 的作品',
                                      serial: 'A / AUTHOR',
                                      author: b.author,
                                      api: widget.api,
                                      shelf: widget.shelf,
                                      tts: widget.tts,
                                      settingsService: widget.settingsService,
                                    ),
                                  ),
                                ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                  '${b.author.isEmpty ? "佚名" : b.author}  ·  ${b.status ?? "未知"}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: widget.catalog == null
                                          ? CreamTokens.ink
                                          : Colors.black,
                                      decoration: widget.catalog == null
                                          ? TextDecoration.none
                                          : TextDecoration.underline)),
                            ),
                            if (widget.catalog != null) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_ios,
                                  size: 10, color: CreamTokens.inkSoft),
                            ],
                          ],
                        ),
                      ),
                      // 文库可点击
                      if (b.pubAgent != null && b.pubAgent!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('文库：${b.pubAgent}',
                              style: const TextStyle(
                                  fontSize: 12, color: CreamTokens.inkSoft)),
                        ),
                      // 标签可点击 → 标签书单
                      if (b.catalogs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in b.catalogs.take(6))
                                GestureDetector(
                                  onTap: widget.catalog == null
                                      ? null
                                      : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => CatalogListPage(
                                                catalog: widget.catalog!,
                                                title: '标签：$t',
                                                serial: 'T / TAG',
                                                tag: t,
                                                api: widget.api,
                                                shelf: widget.shelf,
                                                tts: widget.tts,
                                                settingsService:
                                                    widget.settingsService,
                                              ),
                                            ),
                                          ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(t,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            letterSpacing: 1)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (b.intro != null && b.intro!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            b.intro!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: CreamTokens.inkSoft,
                                height: 1.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: CreamTokens.accent),
                  onPressed: (_volumes == null ||
                          _volumes!.every((v) => v.chapters.isEmpty))
                      ? null
                      : () {
                          try {
                            _openReader(context, firstChapterOf(_volumes!));
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('开始阅读'),
                ),
                OutlinedButton.icon(
                  onPressed: _volumes == null ? null : _downloadAll,
                  icon: const Icon(Icons.download),
                  label: Text(_dlProgress == null
                      ? '整本离线'
                      : '下载 ${(_dlProgress!.ratio * 100).toStringAsFixed(0)}%'),
                ),
                StreamBuilder<TtsState>(
                  // M3 修复：使用全局注入的 tts 实例（原来 _tts 从未赋值，恒为 null）
                  stream: widget.tts?.stateStream ?? const Stream.empty(),
                  builder: (context, s) => OutlinedButton.icon(
                    onPressed: (_volumes == null ||
                            _volumes!.every((v) => v.chapters.isEmpty))
                        ? null
                        : () {
                            try {
                              _listen(context, firstChapterOf(_volumes!));
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          },
                    icon: Icon(s.data == TtsState.playing
                        ? Icons.pause_circle
                        : Icons.graphic_eq),
                    label: const Text('在线听书'),
                  ),
                ),
              ],
            ),
            if (_dlProgress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _dlProgress!.ratio),
            ],
            const SizedBox(height: 12),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: _volumes == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        for (final v in _volumes!) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(v.title,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: CreamTokens.ink,
                                    fontFamily: 'Songti')),
                          ),
                          for (final c in v.chapters)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.description_outlined,
                                  size: 18, color: CreamTokens.inkSoft),
                              title: Text(c.title,
                                  style: const TextStyle(
                                      fontSize: 14, color: CreamTokens.ink)),
                              onTap: () => _openReader(context, c),
                              trailing: FutureBuilder<bool>(
                                future: widget.library != null
                                    ? widget.library!.cache
                                        .exists(c.aid, c.cid)
                                    : Future.value(false),
                                builder: (_, s) => s.data == true
                                    ? const Icon(Icons.offline_pin,
                                        size: 16, color: CreamTokens.accent)
                                    : const SizedBox(width: 16),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Chapter firstChapterOf(List<Volume> vols) {
    final entry = widget.shelf.get(widget.book.aid);
    if (entry?.lastCid != null) {
      for (final v in vols) {
        for (final c in v.chapters) {
          if (c.cid == entry!.lastCid) return c;
        }
      }
    }
    for (final v in vols) {
      if (v.chapters.isNotEmpty) return v.chapters.first;
    }
    throw Wenku8Exception('本书未解析出任何章节，无法阅读');
  }

  void _openReader(BuildContext context, Chapter chapter) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderPage(
        api: widget.api,
        shelf: widget.shelf,
        book: _detail ?? widget.book,
        chapter: chapter,
        volumes: _volumes ?? const [],
        library: widget.library,
        tts: widget.tts,
        settingsService: widget.settingsService,
        scraper: _scraper,
      ),
    ));
  }

  void _listen(BuildContext context, Chapter chapter) {
    _openReader(context, chapter);
  }
}

// ---------------- 章内查找弹层 ----------------

class _ChapterSearchSheet extends StatefulWidget {
  final List<String> paragraphs;
  const _ChapterSearchSheet({required this.paragraphs});

  @override
  State<_ChapterSearchSheet> createState() => _ChapterSearchSheetState();
}

class _ChapterSearchSheetState extends State<_ChapterSearchSheet> {
  final _ctrl = TextEditingController();
  List<(int, String)> _hits = [];
  String _lastKw = '';

  void _run(String kw) {
    final k = kw.trim();
    if (k.isEmpty) {
      setState(() {
        _hits = [];
        _lastKw = k;
      });
      return;
    }
    final nk = normalizeCjk(k.toLowerCase());
    final out = <(int, String)>[];
    for (var i = 0; i < widget.paragraphs.length; i++) {
      final p = widget.paragraphs[i];
      if (normalizeCjk(p.toLowerCase()).contains(nk)) {
        out.add((i, p));
        if (out.length >= 100) break;
      }
    }
    setState(() {
      _hits = out;
      _lastKw = k;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: _run,
            decoration: InputDecoration(
              hintText: '本章内查找…（简繁均可）',
              prefixIcon: const Icon(Icons.search),
              suffixText: _lastKw.isEmpty
                  ? null
                  : '${_hits.length} 处',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          if (_hits.isNotEmpty)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _hits.length,
                itemBuilder: (context, i) {
                  final (idx, p) = _hits[i];
                  return ListTile(
                    dense: true,
                    leading: Text('P${idx + 1}',
                        style: const TextStyle(
                            fontSize: 11, color: CreamTokens.inkSoft)),
                    title: _highlight(p, _lastKw),
                    onTap: () => Navigator.pop(context, idx),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 返回带高亮 span 的 Text.rich —— 用 TextSpan 简单实现。
  Text _highlight(String p, String kw) {
    if (kw.isEmpty) return Text(p);
    final lower = normalizeCjk(p.toLowerCase());
    final nk = normalizeCjk(kw.toLowerCase());
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final hit = lower.indexOf(nk, start);
      if (hit < 0) {
        spans.add(TextSpan(text: p.substring(start)));
        break;
      }
      // 归一化后长度可能与原文不同，取原文等长近似（中文一对一映射为主）
      spans.add(TextSpan(text: p.substring(start, hit)));
      spans.add(TextSpan(
          text: p.substring(hit,
              (hit + nk.length).clamp(0, p.length)),
          style: const TextStyle(
              backgroundColor: Color(0x33B4884A),
              fontWeight: FontWeight.w700)));
      start = hit + nk.length;
      if (spans.length > 40) {
        // M9 修复：截断后补上剩余文本，不再丢尾
        spans.add(TextSpan(text: p.substring(start.clamp(0, p.length))));
        break;
      }
    }
    return Text.rich(TextSpan(
        style: const TextStyle(fontSize: 13, color: CreamTokens.ink),
        children: spans));
  }
}

// ---------------- 章内查找弹层结束 ----------------

// ---------------- 阅读页（含听书控制） ----------------

class ReaderPage extends StatefulWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final Book book;
  final Chapter chapter;
  final List<Volume> volumes;
  final LocalLibraryService? library;
  final TtsService? tts;
  final SettingsService? settingsService;
  final WebScraper? scraper; // 在线网页爬虫（w 前缀章节）
  const ReaderPage({
    super.key,
    required this.api,
    required this.shelf,
    required this.book,
    required this.chapter,
    required this.volumes,
    this.library,
    this.tts,
    this.settingsService,
    this.scraper,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String? _content;
  String? _error;
  late Chapter _chapter = widget.chapter;
  // M4 修复：初始值取持久化设置
  late ReaderSettings _settings = _loadSettings();
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  int? _visibleParagraph; // 当前可见段（加书签用，不触发跳段）
  int? _bookmarkJumpTarget; // 书签/查找跳段目标（消费后清空）
  BookmarkService? _bookmarkSvc;
  WebScraper? _scraper; // 在线网页爬虫（w 前缀章节用）

  ReaderSettings _loadSettings() {
    final s = widget.settingsService;
    return s != null ? s.settings : const ReaderSettings();
  }

  void _updateSettings(ReaderSettings s) {
    setState(() => _settings = s);
    widget.settingsService?.update(s);
  }
  int _loadSeq = 0; // 章节加载竞态防护（M1）

  @override
  void initState() {
    super.initState();
    // 在线章节（w 前缀 cid）或详情页降级传入的爬虫实例
    _scraper = widget.scraper ??
        (widget.chapter.cid.startsWith('w') ? WebScraper() : null);
    _loadChapter();
    _initBookmarks();
  }

  Future<void> _initBookmarks() async {
    final svc = BookmarkService();
    await svc.load();
    if (!mounted) return;
    setState(() => _bookmarkSvc = svc);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  // ------- 睡眠定时 -------
  void _pickSleepTimer() {
    final options = <(int, String)>[
      (5, '5 分钟'),
      (15, '15 分钟'),
      (30, '30 分钟'),
      (60, '60 分钟'),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CreamTokens.bgBase,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sleepTimer != null)
              ListTile(
                leading: const Icon(Icons.timer_off),
                title: Text('取消定时（剩余 ${_sleepRemaining!.inMinutes} 分钟）'),
                onTap: () {
                  Navigator.pop(ctx);
                  _cancelSleep();
                },
              ),
            for (final (m, label) in options)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text('分钟后停止：$label'),
                onTap: () {
                  Navigator.pop(ctx);
                  _startSleep(Duration(minutes: m));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _startSleep(Duration d) {
    _sleepTimer?.cancel();
    setState(() => _sleepRemaining = d);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final remain = d - Duration(seconds: t.tick.toInt());
      if (remain <= Duration.zero) {
        t.cancel();
        _sleepTimer = null;
        widget.tts?.stop();
        if (mounted) setState(() => _sleepRemaining = null);
      } else {
        setState(() => _sleepRemaining = remain);
      }
    });
  }

  void _cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    setState(() => _sleepRemaining = null);
  }

  // ------- 书签 -------
  Future<void> _addBookmark() async {
    final svc = _bookmarkSvc;
    if (svc == null || _content == null) return;
    final ps = paragraphs(_content!);
    // C2 修复：空章节直接提示，避免 clamp(0,-1) 崩溃
    if (ps.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本页没有可定位的段落')));
      return;
    }
    final idx = (_visibleParagraph ?? 0).clamp(0, ps.length - 1);
    final excerpt = ps[idx];
    final bm = Bookmark(
      aid: _chapter.aid,
      cid: _chapter.cid,
      chapterTitle: _chapter.title,
      excerpt: excerpt.length > 60 ? '${excerpt.substring(0, 60)}…' : excerpt,
      paragraphIndex: idx,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await svc.add(bm);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('书签已加：第 ${idx + 1} 段')));
    setState(() {});
  }

  void _showBookmarks() {
    final svc = _bookmarkSvc;
    if (svc == null) return;
    final items = svc.forBook(widget.book.aid);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CreamTokens.bgBase,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: Text('本书还没有书签',
                          style: TextStyle(color: CreamTokens.inkSoft))),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('书签',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Songti')),
                    ),
                    for (final bm in items)
                      ListTile(
                        leading: const Icon(Icons.bookmark, color: CreamTokens.accent),
                        title: Text(bm.excerpt,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${bm.chapterTitle} · 段 ${bm.paragraphIndex + 1}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          // minor6 修复：删除后留在弹层内刷新
                          onPressed: () async {
                            await svc.remove(bm.aid, bm.cid, bm.paragraphIndex);
                            setSheet(() {
                              items.remove(bm);
                            });
                            if (mounted) setState(() {});
                          },
                        ),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          if (bm.cid != _chapter.cid) {
                            final flat = [
                              for (final v in widget.volumes) ...v.chapters
                            ];
                            final target =
                                flat.where((c) => c.cid == bm.cid).firstOrNull;
                            if (target != null) {
                              // M8 修复：换章时携带段索引
                              setState(() => _bookmarkJumpTarget = bm.paragraphIndex);
                              _jumpTo(target);
                            }
                          } else {
                            // M2 修复：通过跳段通道定位
                            setState(() => _bookmarkJumpTarget = bm.paragraphIndex);
                          }
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  // ------- 章内查找 -------
  Future<void> _showSearch() async {
    if (_content == null) return;
    final ps = paragraphs(_content!);
    final idx = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: CreamTokens.bgBase,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: _ChapterSearchSheet(paragraphs: ps),
        ),
      ),
    );
    // M3 修复：点击搜索结果后真正跳段
    if (idx != null && mounted) {
      setState(() => _bookmarkJumpTarget = idx);
    }
  }

  Future<void> _loadChapter() async {
    final seq = ++_loadSeq;
    final chapter = _chapter; // 快照，防快速切换串章
    setState(() {
      _content = null;
      _error = null;
    });
    // 离线优先
    if (widget.library != null) {
      final cached = await widget.library!.cache.get(chapter.aid, chapter.cid);
      if (!mounted || seq != _loadSeq) return;
      if (cached != null) {
        setState(() => _content = cached);
        // M2 修复：缓存命中也保存进度（M1：双写章序）
        await widget.shelf.addOrUpdate(widget.book,
            lastCid: chapter.cid,
            lastChapterTitle: chapter.title,
            lastChapterIdx: _flatIndexOf(chapter));
        return;
      }
    }
    try {
      String text;
      // 在线双源：wenku8 数字 aid 且 cid 是网页格式（w 前缀）→ 网页爬虫逐章抓取；
      // 否则走全本 TXT 通道（老路径）。两者成功后均落缓存（离线可读）。
      final isWebChapter = chapter.cid.startsWith('w') &&
          int.tryParse(chapter.aid) != null;
      // M3 修复：w 章节必须有爬虫，兜底实例化防「章节不存在」
      final scraper = _scraper ??
          (isWebChapter ? (_scraper = WebScraper()) : null);
      if (isWebChapter && scraper != null) {
        text = await scraper.chapter(chapter.aid, chapter.cid);
      } else {
        text = await widget.api.chapterContent(chapter.aid, chapter.cid);
      }
      if (!mounted || seq != _loadSeq) return;
      if (widget.library != null) {
        await widget.library!.cache.put(chapter.aid, chapter.cid, text);
      }
      setState(() => _content = text);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _error = e.toString());
    }
    // 记录进度（M1：双写章序）
    await widget.shelf.addOrUpdate(widget.book,
        lastCid: chapter.cid,
        lastChapterTitle: chapter.title,
        lastChapterIdx: _flatIndexOf(chapter));
  }

  /// 章在 widget.volumes 中的全局序（跨 cid 体系续读兜底）。
  int? _flatIndexOf(Chapter c) {
    var i = 0;
    for (final v in widget.volumes) {
      for (final ch in v.chapters) {
        if (ch.cid == c.cid) return i;
        i++;
      }
    }
    return null;
  }

  void _jumpTo(Chapter c) {
    setState(() {
      _chapter = c;
      _visibleParagraph = null;
    });
    _loadChapter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CreamTokens.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: CreamTokens.ink,
        title: Text(_chapter.title,
            style: const TextStyle(
                fontSize: 16,
                color: CreamTokens.ink,
                fontWeight: FontWeight.w600)),
        actions: [
          // 睡眠定时
          IconButton(
            tooltip: _sleepRemaining != null
                ? '睡眠定时 剩余${_sleepRemaining!.inMinutes.clamp(1, 999)}分'
                : '睡眠定时',
            onPressed: widget.tts == null ? null : _pickSleepTimer,
            icon: Icon(_sleepRemaining != null
                ? Icons.timer
                : Icons.timer_outlined),
          ),
          // 书签
          IconButton(
            tooltip: '书签',
            onPressed: _bookmarkSvc == null ? null : _showBookmarks,
            icon: const Icon(Icons.bookmark_border),
          ),
          // 添加书签（当前段）
          IconButton(
            tooltip: '加书签',
            onPressed: _content == null ? null : _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          // 章内查找
          IconButton(
            tooltip: '章内查找',
            onPressed: _content == null ? null : _showSearch,
            icon: const Icon(Icons.search),
          ),
          if (widget.tts != null)
            IconButton(
              tooltip: '听书',
              onPressed: () async {
                final tts = widget.tts!;
                if (_content == null) return;
                if (tts.state == TtsState.playing) {
                  await tts.pause();
                } else {
                  await tts.playChapter(
                      _chapter.aid, _chapter.cid, _content!);
                }
                setState(() {});
              },
              icon: const Icon(Icons.graphic_eq),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _content == null
              ? const Center(child: CircularProgressIndicator())
              : ReaderView(
                  title: _chapter.title,
                  content: _content!,
                  settings: _settings,
                  onSettingsChanged: _updateSettings,
                  onPrevChapter: () => _step(-1),
                  onNextChapter: () => _step(1),
                  aid: widget.book.aid,
                  cid: _chapter.cid,
                  bookmarkService: _bookmarkSvc,
                  onParagraphVisible: (i) {
                    // M2 修复：纯记录，不回灌 initialParagraph（避免重建时误跳）
                    _visibleParagraph = i;
                  },
                  initialParagraph: _bookmarkJumpTarget,
                ),
    );
  }

  void _step(int dir) {
    final flat = [
      for (final v in widget.volumes) ...v.chapters
    ];
    final idx = flat.indexWhere((c) => c.cid == _chapter.cid);
    final next = idx + dir;
    if (next >= 0 && next < flat.length) {
      _jumpTo(flat[next]);
    }
  }
}
