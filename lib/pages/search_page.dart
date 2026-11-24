/// 搜索页：本地目录快照搜索
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/novel_catalog.dart';
import '../models/models.dart';
import 'book_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<CatalogEntry> _results = [];
  bool _searched = false;

  void _doSearch(String kw) {
    setState(() {
      _results = NovelCatalog.instance.search(kw, limit: 100);
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: '搜索书名或作者...',
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); setState(() { _results = []; _searched = false; }); })
                : null,
          ),
          onChanged: (v) => setState(() {}),
          onSubmitted: _doSearch,
          autofocus: true,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _doSearch(_controller.text)),
        ],
      ),
      body: !_searched
          ? Center(child: Text('输入关键词搜索\n共 ${NovelCatalog.instance.count} 本书籍', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)))
          : _results.isEmpty
              ? const Center(child: Text('未找到相关书籍', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final e = _results[i];
                    final book = e.toBook();
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: book.coverUrl ?? '',
                          width: 50,
                          height: 70,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const SizedBox(width: 50, height: 70, child: ColoredBox(color: Color(0xFFE0E0E0))),
                          errorWidget: (_, __, ___) => const SizedBox(width: 50, height: 70, child: ColoredBox(color: Color(0xFFE0E0E0))),
                        ),
                      ),
                      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${book.author}${book.category != null ? ' · ${book.category}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => BookDetailPage(aid: book.aid, book: book))),
                    );
                  },
                ),
    );
  }
}
