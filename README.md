# 轻小说文库 · iPad 阅读器

基于 [wenku8reader](https://github.com/15dd/wenku8reader)、[light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android)、[Wenku8_Flutter](https://github.com/P5UEDGK/Wenku8_Flutter) 的设计思路，数据全部来自**轻小说文库**网站及 light-novel-library 的 API 实现。

## 功能

- **书籍发现**：关键字搜索、分类浏览
- **书架管理**：收藏、阅读进度、最近阅读
- **本地书库**：章节离线缓存，可完全离线阅读
- **离线阅读**：阅读器自动优先读缓存
- **在线听书**：系统 TTS 朗读正文（在线/离线均可）
- **阅读器四种模式**：滚动 / 横排翻页 / 竖排翻页 / 大屏对页（iPad 横屏双页）

## 设计语言

- 奶白玻璃材质（Flutter `BackdropFilter` + 奶白半透明层）
- 档案式排版（衬线标题、编号、分割线、档案卡片）
- 立体书架（多层渐变阴影书板 + 倾斜投影书脊）

## 运行（iPad）

```bash
flutter pub get
flutter run -d <ipad-id>     # 或 flutter build ios --release
```

## 打包 .ipa（未签名，供企业签/侧载工具重签）

在 macOS 上（项目根目录）：

```bash
bash build_ipa.sh
```

产出 `build/ios/ipa/轻小说文库.ipa` —— **未签名包**，内含裸 `Payload/Runner.app`，无 embedded.mobileprovision，专为外部签名方案准备：

- **企业签服务**：直接上传此 ipa，由服务方用企业证书重签后分发
- **TrollStore**：免签直接安装
- **自签工具**（爱思助手 / Sideloadly / AltStore）：导入此 ipa 重签后安装

注：iOS 构建（ARM64 编译）必须在 macOS + Xcode 环境完成；本脚本只产出未签名包，不涉及任何 Apple 证书。

## 结构

```
lib/
  api/        wenku8 接口（GBK 编码、认证、搜索、详情、目录、正文）
  models/     Book / Chapter / Bookmark
  services/   bookshelf, local library(离线缓存), tts, settings
  pages/      discover / shelf / library / reader / player
  widgets/    glass(奶白玻璃), archive(档案排版), bookshelf(立体书架)
```

## 账号

在应用内「我的 → 文库账号」输入 wenku8 用户名/密码；不登录时搜索与正文浏览也可用（站点允许的范围）。
