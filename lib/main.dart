/// 主入口
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';

import 'api/novel_catalog.dart';
import 'src/gbk.dart';
import 'pages/main_page.dart';
import 'services/local_import.dart';
import 'services/services.dart';
import 'services/webdav_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Wenku8App());
}

class Wenku8App extends StatefulWidget {
  const Wenku8App({super.key});
  @override
  State<Wenku8App> createState() => _Wenku8AppState();
}

class _Wenku8AppState extends State<Wenku8App> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 加载 GBK 映射表
    final gbkBytes = await rootBundle.load('assets/gbk_map.bin');
    initGbkMap(gbkBytes.buffer.asUint8List());

    // 加载本地目录
    await NovelCatalog.instance.load();

    // 加载服务
    await Future.wait([
      ShelfService.instance.load(),
      BookmarkService.instance.load(),
      SettingsService.instance.load(),
      AuthService.instance.load(),
      LocalLibraryService.instance.load(),
      WebDavService.instance.load(),
    ]);

    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轻小说文库',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _ready ? const MainPage() : const _SplashScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book, size: 64, color: Color(0xFF6750A4)),
            SizedBox(height: 16),
            Text('轻小说文库', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
