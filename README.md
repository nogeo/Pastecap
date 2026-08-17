# Pastecap

Native macOS 14+ menu bar clipboard history and screenshot utility.

Clipboard history and screenshots stay on this Mac. Password managers that mark copies as concealed or transient are not recorded.

## Build

```sh
swift build
scripts/run-tests.sh
scripts/build-dmg.sh   # writes dist/Pastecap.dmg
```

## GitHub Release 安装包

推一个 `v` 开头的 tag，GitHub Actions 会编译 `Pastecap.dmg` 并挂到 [Releases](https://github.com/nogeo/Pastecap/releases)：

```sh
git tag v1.2.0
git push origin v1.2.0
```

也可以本机打好后，在 GitHub 仓库的 **Releases → Draft a new release** 里手动上传 `dist/Pastecap.dmg`。

## Website DMG (Developer ID + notarization)

Local builds are ad-hoc signed. A downloadable DMG needs a paid Apple Developer account:

1. Install a **Developer ID Application** certificate in Keychain.
2. Store notarization credentials once:

```sh
xcrun notarytool store-credentials pastecap
```

3. Build, sign, notarize, and staple:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=pastecap \
scripts/build-dmg.sh
```

The result is `dist/Pastecap.dmg`. Users drag it to Applications; Gatekeeper accepts a stapled Developer ID signature without disabling SIP or using `xattr`.

Screen Recording permission is tied to the code signature. After switching from ad-hoc to Developer ID, grant the permission once; it should survive later notarized updates that keep the same Team ID.

Default shortcuts: `Shift-Command-V` for clipboard history, `Option-Command-A` for screenshot capture.

Screenshots behave like WeChat's: drag to select, then keep adjusting in place — drag inside the region to move it, drag the 8 handles to resize, drag outside to start over, annotate with the toolbar, `Enter` to copy and finish, `Esc` to cancel. A magnifier with pixel color is shown while selecting/resizing. Picking an annotation tool expands a second toolbar row with stroke colors and thin/medium/thick widths (width maps to font size for text and block size for mosaic); the choice is remembered across screenshots.

## Screen Recording permission

Screenshots require the Screen Recording permission (系统设置 › 隐私与安全性 › 屏幕录制). When the grant is missing or has been invalidated, Pastecap shows an alert with a button that opens that settings pane; after enabling it, relaunch Pastecap for the grant to take effect.

Builds are ad-hoc signed, so macOS may drop the grant after every rebuild or app update. If screenshots stop working after updating, re-enable the permission when the alert appears.

`swift run` is fine for developing clipboard history and hotkeys, but screen capture permission does not behave for the raw executable: TCC attributes the grant to the terminal app and every rebuild changes the binary. Verify screenshots from the built `Pastecap.app` instead.
