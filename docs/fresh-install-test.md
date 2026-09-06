# 全新安装测试

启动窗口修复包含在 v0.2.2 中。测试时请使用 GitHub Releases 的 v0.2.2（或更新版本）安装包，或本地新构建的 `dist/Pastecap.dmg`。

## 推荐：使用新的 macOS 标准用户

1. 在系统设置 → 用户与群组中创建专门测试的标准用户，并退出当前用户后登录测试用户。
2. 将本地新构建的 DMG 复制到 `/Users/Shared`，供测试用户访问。
3. 在测试用户中打开 DMG，将 Pastecap 拖到该用户的 `~/Applications` 文件夹（不存在则创建）。推出 DMG。
4. 从 Finder 双击安装后的 Pastecap.app，不用 Xcode 或开发目录中的 App。
5. 确认启动后只有菜单栏图标，不自动弹出偏好设置。点击菜单栏图标，再点击齿轮，应能打开设置并通过“完成”关闭。
6. 默认登录启动应关闭，历史上限应为 20。剪贴板监控可能立即收录测试用户当前的剪贴板内容，因此历史不一定始终为零。
7. 首次截图应请求屏幕录制权限；只给这份 App 授权。退出并重新打开 App，再验证截图。
8. 退出并再次打开 App，确认设置窗口不自动出现、截图权限继续有效。

新 macOS 用户隔离旧账号的偏好、剪贴板历史和屏幕录制授权。正式下载体验（Gatekeeper、下载隔离属性）需在新版本发布后，用浏览器下载该版本 DMG 再测；本地产物只能覆盖安装和应用行为。

## 在当前账号重置（会移除旧配置和权限）

先在 Pastecap 设置中关闭“登录时自动打开”，退出所有 Pastecap 实例并停止 Xcode 调试。为避免丢失历史，建议把以下目录移到备份文件夹，而非直接删除：

- `~/Library/Application Support/Pastecap`：历史与缓存图片。
- `~/Library/Saved Application State/com.wwm.Pastecap.savedState`：旧窗口恢复状态（可能不存在）。

如需保留偏好，可先执行：

```sh
defaults export com.wwm.Pastecap ~/Desktop/Pastecap-preferences-backup.plist
```

然后重置配置和屏幕录制授权：

```sh
defaults delete com.wwm.Pastecap
tccutil reset ScreenCapture com.wwm.Pastecap
```

提示偏好域不存在表示该项已经清空。上述操作不删除已导出到 `~/Pictures/Pastecap` 或自定义目录的截图。将旧安装包移到废纸篓，按上面的安装流程测试新的 DMG；测试期间不要运行其他同 Bundle ID 的开发版或旧版本。
