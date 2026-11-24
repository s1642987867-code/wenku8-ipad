/// 发现页：推荐 / 排行 / 分类（基于本地目录快照）
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/linovelib_api.dart';
import '../api/novel_catalog.dart';
import '../models/models.dart';
import 'book_detail_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('发现'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: '推荐'),
            Tab(text: '排行'),
            Tab(text: '分类'),
            Tab(text: '哔哩·月榜'),
          ]),
        ),
        body: const TabBarView(children: [
          _RecommendTab(),
          _RankingTab(),
          _CategoryTab(),
          _LinovelibTab(),
        ]),
      ),
    );
  }
}

/// 哔哩轻小说排行榜 Tab（在线抓取 linovelib.com）
class _LinovelibTab extends StatefulWidget {
  const _LinovelibTab();
  @override
  State<_LinovelibTab> createState() => _LinovelibTabState();
}

class _LinovelibTabState extends State<_LinovelibTab> {
  final _lino = LinovelibApi();
  List<Book>? _books;
  String? _error;
  String _period = 'monthvisit';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _books = null; _error = null; });
    try {
      final books = await _lino.ranking(period: _period);
      setState(() { _books = books; });
    } catch (e) {
      setState(() { _error = '哔哩轻小说排行加载失败：\n$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _chip('月榜', 'monthvisit'),
              _chip('周榜', 'weekvisit'),
              _chip('总榜', 'allvisit'),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orange))))
              : _books == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _books!.length,
                        itemBuilder: (ctx, i) => ListTile(
                          leading: Text('${i + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: i < 3 ? Colors.orange : Colors.grey)),
                          title: Text(_books![i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => BookDetailPage(aid: _books![i].aid, book: _books![i]))),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _chip(String label, String period) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _period == period,
        onSelected: (_) { setState(() => _period = period); _load(); },
      ),
    );
  }
}

class _RecommendTab extends StatelessWidget {
  const _RecommendTab();
  @override
  Widget build(BuildContext context) {
    final books = NovelCatalog.instance.recommend(count: 18);
    return _BookGrid(books.map((e) => e.toBook()).toList());
  }
}

class _RankingTab extends StatefulWidget {
  const _RankingTab();
  @override
  State<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<_RankingTab> {
  String _sort = 'hot';
  int _page = 1;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      setState(() => _page++);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books = <Book>[];
    for (var p = 1; p <= _page; p++) {
      books.addAll(NovelCatalog.instance.listPage(sort: _sort, page: p).map((e) => e.toBook()));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _sortChip('热门', 'hot'),
              _sortChip('新作', 'new'),
              _sortChip('完结', 'completed'),
            ],
          ),
        ),
        Expanded(child: _BookGrid(books, controller: _scrollController)),
      ],
    );
  }

  Widget _sortChip(String label, String sort) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _sort == sort,
        onSelected: (_) => setState(() { _sort = sort; _page = 1; }),
      ),
    );
  }
}

class _CategoryTab extends StatefulWidget {
  const _CategoryTab();
  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab> {
  String? _selectedTag;
  int _page = 1;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        setState(() => _page++);
      }
    });
    _selectedTag = NovelCatalog.instance.tags.isNotEmpty ? NovelCatalog.instance.tags.first : null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tags = NovelCatalog.instance.tags;
    final books = <Book>[];
    if (_selectedTag != null) {
      for (var p = 1; p <= _page; p++) {
        books.addAll(NovelCatalog.instance
            .listPage(tag: _selectedTag, page: p)
            .map((e) => e.toBook()));
      }
    }
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: ListView.builder(
            itemCount: tags.length,
            itemBuilder: (ctx, i) {
              final tag = tags[i];
              return ListTile(
                title: Text(tag),
                selected: tag == _selectedTag,
                onTap: () => setState(() { _selectedTag = tag; _page = 1; }),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _BookGrid(books, controller: _scrollController)),
      ],
    );
  }
}

/// 书籍网格组件
class _BookGrid extends StatelessWidget {
  final List<Book> books;
  final ScrollController? controller;
  const _BookGrid(this.books, {this.controller});

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const Center(child: Text('暂无数据', style: TextStyle(color: Colors.grey)));
    }
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (ctx, i) => _BookCard(books[i]),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  const _BookCard(this.book);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => BookDetailPage(aid: book.aid, book: book))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: book.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: book.coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const ColoredBox(
                          color: Color(0xFFE0E0E0),
                          child: Center(child: Icon(Icons.book, color: Colors.grey))),
                      errorWidget: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFE0E0E0),
                          child: Center(child: Icon(Icons.book, color: Colors.grey))),
                    )
                  : const ColoredBox(
                      color: Color(0xFFE0E0E0),
                      child: Center(child: Icon(Icons.book, color: Colors.grey))),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
