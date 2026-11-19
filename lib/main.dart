import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'api/wenku8_api.dart';
import 'api/novel_catalog.dart';
import 'models/models.dart';
import 'pages/pages.dart';
import 'pages/settings.dart';
import 'services/services.dart';
import 'services/webdav.dart';
import 'ui/design_system.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Wenku8Api();
  final shelf = BookshelfService();
  await shelf.load();

  final cacheRoot = await _cacheRoot();
  final library = LocalLibraryService(api, ContentCache(cacheRoot));
  final settings = SettingsService();
  await settings.load();
  final prefsService = AppPrefsService();
  await prefsService.load();
  final webdav = WebDavService();
  await webdav.load();
  final tts = TtsService();

  runApp(Wenku8App(
    api: api,
    shelf: shelf,
    library: library,
    settings: settings,
    prefsService: prefsService,
    webdav: webdav,
    tts: tts,
  ));
}

Future<Directory> _cacheRoot() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}wenku8_cache');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

class Wenku8App extends StatelessWidget {
  final Wenku8Api api;
  final BookshelfService shelf;
  final LocalLibraryService library;
  final SettingsService settings;
  final AppPrefsService prefsService;
  final WebDavService webdav;
  final TtsService tts;
  const Wenku8App({
    super.key,
    required this.api,
    required this.shelf,
    required this.library,
    required this.settings,
    required this.prefsService,
    required this.webdav,
    required this.tts,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轻小说文库',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: CreamTokens.accent,
          brightness: Brightness.light,
          surface: CreamTokens.bgBase,
        ),
        scaffoldBackgroundColor: CreamTokens.bgBase,
        fontFamily: 'PingFang SC',
      ),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _tab = 0;
  NovelCatalog? _catalog;
  StreamSubscription? _prefsSub;
  AppPrefs _prefs = const AppPrefs();

  @override
  void initState() {
    super.initState();
    NovelCatalog.load().then((c) {
      if (mounted) setState(() => _catalog = c);
    }).catchError((_) {});
    final app = context.findAncestorWidgetOfExactType<Wenku8App>();
    if (app != null) {
      _prefs = app.prefsService.prefs;
      _prefsSub = app.prefsService.stream.listen((p) {
        if (mounted) setState(() => _prefs = p);
      });
    }
  }

  @override
  void dispose() {
    _prefsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final wide = size.width > 700; // iPad 横屏侧栏布局
    final app = context.findAncestorWidgetOfExactType<Wenku8App>()!;

    // 性能开关全局生效（M1 修复：玻璃折射开关接线）
    GlassPrefs.enabled =
        !_prefs.lowPerfMode && _prefs.glassEnabled && _prefs.blurEnabled;
    final noAnim = _prefs.lowPerfMode || !_prefs.animationsEnabled;

    final pages = [
      DiscoverPage(
          api: app.api,
          shelf: app.shelf,
          tts: app.tts,
          settingsService: app.settings),
      ShelfPage(
          shelf: app.shelf,
          library: app.library,
          api: app.api,
          tts: app.tts,
          settingsService: app.settings,
          catalog: _catalog),
      LibraryPage(
          library: app.library,
          shelf: app.shelf,
          api: app.api,
          tts: app.tts,
          settingsService: app.settings),
      SettingsPage(
        shelf: app.shelf,
        library: app.library,
        api: app.api,
        prefsService: app.prefsService,
        webdav: app.webdav,
        tts: app.tts,
        settingsService: app.settings,
      ),
    ];

    final body = wide
        ? Row(
            children: [
              CreamGlass(
                radius: BorderRadius.zero,
                child: NavigationRail(
                  backgroundColor: Colors.transparent,
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                        icon: Icon(Icons.explore_outlined),
                        selectedIcon: Icon(Icons.explore),
                        label: Text('发现')),
                    NavigationRailDestination(
                        icon: Icon(Icons.shelves),
                        selectedIcon: Icon(Icons.shelves),
                        label: Text('书架')),
                    NavigationRailDestination(
                        icon: Icon(Icons.library_books_outlined),
                        selectedIcon: Icon(Icons.library_books),
                        label: Text('本地书库')),
                    NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('设置')),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: CreamTokens.glassBorder),
              Expanded(
                // IndexedStack 保持各 tab 的 State（滚动位置、搜索结果不丢失）
                child: IndexedStack(index: _tab, children: pages),
              ),
            ],
          )
        : Scaffold(
            backgroundColor: Colors.transparent,
            body: IndexedStack(index: _tab, children: pages),
            bottomNavigationBar: CreamGlass(
              radius: BorderRadius.zero,
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore),
                      label: '发现'),
                  NavigationDestination(
                      icon: Icon(Icons.shelves),
                      label: '书架'),
                  NavigationDestination(
                      icon: Icon(Icons.library_books_outlined),
                      selectedIcon: Icon(Icons.library_books),
                      label: '本地书库'),
                  NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: '设置'),
                ],
              ),
            ),
          );

    // 奶白玻璃底 + 背景装饰（noAnim 时去渐变动效层）
    return Container(
      decoration: BoxDecoration(
        gradient: noAnim
            ? const LinearGradient(colors: [CreamTokens.bgBase, CreamTokens.bgBase])
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [CreamTokens.bgBase, CreamTokens.bgDeep],
              ),
      ),
      child: wide
          ? body
          : Scaffold(body: SafeArea(child: body)),
    );
  }
}
