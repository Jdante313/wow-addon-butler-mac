# 魔兽插件管家 · macOS

![tests](https://github.com/Jdante313/wow-addon-butler-mac/actions/workflows/tests.yml/badge.svg)

macOS 版的《魔兽世界》插件管理器。启动即进入已安装插件列表，支持多客户端切换、默认插件列表 + 分类/排序、精确/相似搜索结果分区、在线与本地 ZIP 安装，以及把插件和 WTF 角色配置保存成可迁移的 `.wowpack` 快照。

![搜索页](docs/curseforge-results.png)

## 下载

- [最新 Release](https://github.com/Jdante313/wow-addon-butler-mac/releases/latest)
- 当前版本：`2.1.8`，macOS 13.5+ / Apple Silicon
- 解压后把 `魔兽插件管家.app` 拖进「应用程序」即可

- 用户文档：[使用说明.md](使用说明.md)
- 产品说明（能做什么 / 不能做什么 / 适合谁）：[产品说明.md](产品说明.md)
- 应用产物：`dist/魔兽插件管家.app`
- 分发压缩包：`dist/魔兽插件管家-2.1.8-macOS-arm64.zip`
- 需要 macOS 13.5+ / Apple Silicon

## 开发

```bash
cd app
npm install      # 依赖只有 adm-zip
npm start        # http://127.0.0.1:17321
npm test         # 17 个后端测试
```

前端是原生 ES Modules + CSS，没有构建步骤。后端只依赖 `adm-zip`，数据保存在 `~/Library/Application Support/WowAddonButler`（可用 `WOW_BUTLER_DATA` 覆盖，测试时会自动隔离）。

## 构建

```bash
NODE_BIN=/path/to/node ./scripts/build-app.sh
```

脚本会：

1. 如果没有 `app/node_modules/adm-zip`，先自动 `npm install --omit=dev`；
2. 复制 `app/` 到 `.app/Contents/Resources/app`；
3. 把指定 Node 运行时复制到 `Resources/runtime/node`；
4. 生成 `AppIcon.icns`；
5. 用 `swiftc -target $(uname -m)-apple-macos13.5` 编译 `native/main.swift`；
6. ad-hoc 签名并打包 zip。

## 架构

- `native/main.swift`：AppKit + WKWebView 外壳。启动内置 Node（随机端口），读取 `WOW_BUTLER_READY` 后加载界面；关闭窗口时终止子进程，Node 侧还有父进程存活检查兜底。
- `app/server/`：本地 HTTP 服务。负责客户端检测、TOC 解析、插件分组、安装/更新/备份、本地 ZIP 安装、配置快照、WTF SavedVariables。
- `app/server/categories.js`：搜索页分类体系；CurseForge / 新手盒子映射到上游分类 ID，其他来源按关键词过滤。
- `app/renderer/`：单页界面，hash 路由。`#/installed`、`#/search`、`#/backup`、`#/settings`。
- 数据目录：`~/Library/Application Support/WowAddonButler`。日志：`logs/launcher.log`。

## 关键实现

- **客户端检测**：`/Applications/World of Warcraft`、用户目录、外接卷、Battle.net 默认安装路径；解析 `_retail_` / `_classic_` / `_forever_` 等目录和 `.flavor.info` / `.build.info`，即使 `Interface/AddOns` 还不存在也能识别。
- **默认来源**：只启用 Tukui。新手盒子、CurseForge、WoWInterface、GitHub 默认关闭；CurseForge 在设置页内提供申请入口、复制/保存说明和测试功能；Key 保存后切换为独立状态卡，需先「清除并更换」才能重新填写。
- **CurseForge 搜索**：不再发送已失效的 `classId=6`（当前 API 在该 class 下返回 0 条，但测试接口仍正常）；`gameId=1` 已足够限定 WoW 插件。
- **返回顶部**：搜索页滚动超过约 480px 后显示右下角浮动按钮，点击平滑回到顶部；有任务卡片时自动上移避让。
- **滚动自动加载**：搜索列表使用 IntersectionObserver 在接近底部时自动加载下一页，加载期间保留当前滚动位置；失败时底部提供重试。
- **不按版本硬过滤**：搜索结果不会因为插件没有标注当前客户端版本而被隐藏。插件明确列出兼容版本时，列表显示「支持 1.60 +N」标签（优先显示当前浏览版本，悬停/详情看全部），没有标注的不显示标签。
- **原生文件选择器**：设置目录、本地 ZIP、快照导入/导出共用 `osascript` 的 `choose file/folder/file name`；错误处理使用 `on error errMsg number errNum`，避免 `on error number -128` 在 AppleScript 中的语法错误。
- **浏览与搜索**：无关键词时直接拉取启用来源的插件列表；`version` / `category` / `sort` 参数由前端和 API 共用。版本筛选列出无限、正式服、泰坦重铸、经典旧世、探索赛季、熊猫人之谜、燃烧的远征、周年，按客户端大类显示；热度/更新/名称排序；有关键词时 `server/lib/match.js` 再分精确与相似两组。浏览版本与安装目标不一致时界面会提示。
- **本地 ZIP 安装**：`/api/install-local` + `tasks.startInstallLocal` 调用同一套 `installZip` 校验/备份流程，`managed.json` 记录 `source: local`，因此后续启停、备份、卸载、快照都可用。
- **配置快照**：`server/profiles.js` 生成 zip：`manifest.json`、`addons/<folder>.zip`、`wtf/WTF/...`。恢复时优先用内嵌插件包，缺失时回退到在线来源；恢复 WTF 前备份原文件。
- **安全**：zip 路径校验、`Interface/AddOns` 路径校验、游戏运行检测、卸载/覆盖前备份、配置路径越界拦截。

## 测试

```bash
cd app && node test/run-tests.js
```

覆盖：TOC 解析（含 BOM/UTF-16 与中文标题）、版本比较、分组、精确/模糊匹配、分类关键词、ZIP 安装与备份、本地 ZIP 安装任务、启停重命名、停用插件卸载、快照创建/预览/恢复、SavedVariables 过滤与写回、导入导出、多文件夹卸载。

## 已知限制

- 构建产物是 Apple Silicon 单架构；Intel Mac 需要用 x86_64 的 Node 重新构建。
- 应用未做 Developer ID 签名/公证，首次打开需右键 → 打开。
- 更新检查依赖来源返回的版本格式；TOC 版本不规范的插件可能显示“版本未知”。
- 分类过滤依赖各来源的分类或关键词；冷门插件可能被归到“全部插件”之外时漏检。
- 只备份 `WTF/Account/**/SavedVariables/*.lua`；不备份游戏本体、`Config.wtf` 和插件外的自定义文件。

## License

MIT。可免费使用、修改和分发；插件内容、图标及第三方平台内容的版权归各自作者/平台所有。
