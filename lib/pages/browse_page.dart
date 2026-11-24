/// 分类浏览页：按标签筛选 + 排序 + 无限滚动；也用于作者书单展示
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/novel_catalog.dart';
import '../models/models.dart';
import 'book_detail_page.dart';

/// 模式：tag=按标签分类浏览, author=作者书单
class BrowsePage extends StatefulWidget {
  final String mode; // 'tag' | 'author'
  final String? initialTag;
  final String? author;

  const BrowsePage({super.key, required this.mode, this.initialTag, this.author});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  String? _selectedTag;
  String _sort = 'hot'; // hot / new / completed
  final _controller = ScrollController();
  List<CatalogEntry> _items = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _selectedTag = widget.initialTag;
    _controller.addListener(_onScroll);
    _reload();
  }

  void _onScroll() {
    if (_controller.position.pixels >= _controller.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _reload() {
    setState(() { _items = []; _page = 1; _hasMore = true; _loading = true; });
    _loadPage();
  }

  void _loadPage() {
    List<CatalogEntry> result;
    const pageSize = 60;
    if (widget.mode == 'author') {
      // 作者书单一次取完
      final all = NovelCatalog.instance.byAuthor(widget.author ?? '', limit: 500);
      result = all;
      _hasMore = false;
    } else {
      result = NovelCatalog.instance.listPage(
        sort: _sort,
        tag: _selectedTag,
        page: _page,
        pageSize: pageSize,
      );
      _hasMore = result.length == pageSize;
    }
    setState(() {
      _items.addAll(result);
      _loading = false;
      _page++;
    });
  }

  void _loadMore() {
    if (_loading || !_hasMore) return;
    _loading = true;
    _loadPage();
  }

  String get _title {
    if (widget.mode == 'author') return '作者：${widget.author ?? ''}';
    return _selectedTag == null ? '全部作品' : '分类：$_selectedTag';
  }

  @override
  Widget build(BuildContext context) {
    final tags = NovelCatalog.instance.tags;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          // 排序
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: (s) { _sort = s; _reload(); },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'hot', child: Text('按热度')),
              PopupMenuItem(value: 'new', child: Text('按最新')),
              PopupMenuItem(value: 'completed', child: Text('只看完结')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 标签筛选条（仅 tag 模式）
          if (widget.mode == 'tag')
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: _selectedTag == null,
                      onSelected: (_) { _selectedTag = null; _reload(); },
                    ),
                  ),
                  ...tags.map((t) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: _selectedTag == t,
                      onSelected: (_) { _selectedTag = t; _reload(); },
                    ),
                  )),
                ],
              ),
            ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(child: Text('没有找到作品', style: TextStyle(color: Colors.grey)))
                : GridView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 140,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _items.length + (_hasMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i >= _items.length) {
                        return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                      }
                      return _BrowseCard(_items[i]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BrowseCard extends StatelessWidget {
  final CatalogEntry entry;
  const _BrowseCard(this.entry);

  @override
  Widget build(BuildContext context) {
    final book = entry.toBook();
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => BookDetailPage(aid: entry.aid.toString(), book: book))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: book.coverUrl ?? '',
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) => const ColoredBox(
                    color: Color(0xFFE0E0E0),
                    child: Center(child: Icon(Icons.book, color: Colors.grey))),
                errorWidget: (_, __, ___) => const ColoredBox(
                    color: Color(0xFFE0E0E0),
                    child: Center(child: Icon(Icons.book, color: Colors.grey))),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
