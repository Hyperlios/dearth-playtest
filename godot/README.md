# 荒年 · 网页试玩

基于 2026-10-05 Windows 试玩包的原始游戏内容，使用 Godot 4.7.2 官方单线程 Web 运行时。

## GitHub Pages

发布来源：main 分支，根目录 /。`.nojekyll` 保证直接发布静态文件。

在线试玩：https://hyperlios.github.io/dearth-playtest/godot/
本目录部署在仓库的 `godot/`，根目录的旧版网页保留。

全部游戏文件使用相对路径，兼容 GitHub Pages 的仓库子路径。
首次加载约 110 MB，建议使用 Wi-Fi；iPhone 横屏、Safari 打开。
这次沿用电脑试玩版界面，未完成 iPhone 真机验收。

## 文件说明

- `index.html` / `loader.js`：加载页面、触摸说明、竖屏提示。
- `godot.js` / `godot.audio*.js`：官方 Godot 网页运行时。仅替换 Wasm 下载入口以读取压缩分片。
- `assets.json` / `pack-*.bin` / `wasm-*.bin`：SHA256 校验清单与压缩资源片段。片段最大 8 MiB。
- `licenses/`：Godot 与字体第三方许可。

原始游戏包内容未改动；只有浏览器窗口模式与触摸模拟兼容设置。
加载层另含 Godot 4.7.2 索引缓冲上传兼容修正：通过 WebGL2 COPY_WRITE_BUFFER 更新索引数据，并保留原有绑定，避免 ARRAY_BUFFER 类型冲突。浏览器绘制告警与绑定/数据读回均已验证。
GitHub Pages 托管的是游戏网页，朋友无需 GitHub 登录或安装 Godot。
