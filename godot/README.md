# 荒年 · 网页试玩

基于 2026-10-05 Windows 试玩包的原始游戏内容，使用 Godot 4.7.2 官方单线程 Web 运行时。

## GitHub Pages

发布来源：main 分支，根目录 /。`.nojekyll` 保证直接发布静态文件。

在线试玩：https://hyperlios.github.io/dearth-playtest/godot/
本目录部署在仓库的 `godot/`，根目录的旧版网页保留。

全部游戏文件使用相对路径，兼容 GitHub Pages 的仓库子路径。
首次加载约 110 MB，建议使用 Wi-Fi；iPhone 横屏、Safari 打开。
iPhone 自动启用横屏手机界面：44 px 主按钮、独立抽屉、可滚动详情与中文字体。已通过桌面触摸模拟和 WebKit 检查，仍未完成 iPhone 真机验收。

## 文件说明

- `index.html` / `loader.js`：加载页面、触摸说明、竖屏提示。
- `godot.js` / `godot.audio*.js`：官方 Godot 网页运行时。仅替换 Wasm 下载入口以读取压缩分片。
- `assets.json` / `pack-*.bin` / `wasm-*.bin`：SHA256 校验清单与压缩资源片段。片段最大 8 MiB。
- `licenses/`：Godot 与字体第三方许可。

原始游戏包内容未改动；只有浏览器窗口模式与触摸模拟兼容设置。
加载层另含 Godot 4.7.2 索引缓冲上传兼容修正：通过 WebGL2 COPY_WRITE_BUFFER 更新索引数据，并保留原有绑定，避免 ARRAY_BUFFER 类型冲突。浏览器绘制告警与绑定/数据读回均已验证。
GitHub Pages 托管的是游戏网页，朋友无需 GitHub 登录或安装 Godot。


## iPhone 适配补丁（2026-10-10）

- `mobile.pck`：只包含手机 UI 补丁及原试玩版 UI 基类，原始 Windows PCK 和规则不变。
- `mobile-src/ui.gd`：大按钮、资源栏、商店/种子/温室抽屉、种子点选、滚动模态、手机取景。
- `mobile-src/boot.gd` / `boot.tscn`：通过 `override.cfg` 指向启动场景，替换展示层；发行版不依赖编辑器专用的 `--script` 参数。
- `mobile-src/baseline_ui.gdc`：从 2026-10-05 原始 PCK 提取的 UI，保持本次试玩版本一致。不要直接混入当前桌面主工程的新规则/UI。
- `mobile-src/build.gd`：在本目录执行 Godot `--headless --path . --script mobile-src/build.gd` 可重建补丁。
- 不使用系统字体来渲染正式 UI；加载包内 NotoSansSC，特殊导航符号用中文按钮代替。
- Safari 安全区由页面留白处理；Godot 的逻辑坐标跟随实际内容区，像素密度最多 2 倍。
- 通过 `?qa=1` 可读取 `window.dearthQA` 的只读几何与缺字诊断；不提供改变经济/进度的接口。

原有桌面玩法与存档路径保留。当前仍为横屏试玩，未完成真机性能和完整 40 夜验收。
