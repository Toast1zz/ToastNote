# 发布流程

ToastNote 通过 GitHub Releases 分发，用 [Sparkle 2](https://sparkle-project.org) 自动更新。更新包用 EdDSA 签名，私钥只存在 GitHub Actions 的 secret 里。

## 一次性准备

### 1. 生成更新签名密钥

在任意一台 Mac 上，用 Sparkle 自带的工具（构建一次后在 `build/Release/SourcePackages/artifacts/sparkle/Sparkle/bin/`，或从 Sparkle 的 Release 页面下载）：

```bash
./generate_keys            # 把私钥存进钥匙串，并打印公钥
./generate_keys -x private-key.txt   # 导出私钥，只用来填进 secret，随后删除
```

把得到的密钥填进仓库的 Secrets（Settings → Secrets and variables → Actions）：

| Secret | 内容 | 必需 |
|---|---|---|
| `SPARKLE_PUBLIC_KEY` | 公钥（打印出来的那一行） | 是，否则构建里没有更新功能 |
| `SPARKLE_PRIVATE_KEY` | 导出的私钥文件内容 | 是，用来给更新包签名、生成 `appcast.xml` |

### 2. 仓库名

更新源地址是 `https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`。`<owner>/<repo>` 在 GitHub Actions 里自动取自 `github.repository`；本地构建里是占位符 `OWNER/ToastNote`（见 `project.yml` 的 `GITHUB_REPOSITORY`），本地构建也没有公钥，所以不会启用更新。

### 3. 可选：签名与公证

没有 Apple 开发者账号也能发布，只是应用是 ad-hoc 签名、没有公证。有账号后再补这些 Secrets，流程会自动启用签名和公证：

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE_P12` | Developer ID Application 证书（.p12）的 base64 |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 的密码 |
| `MACOS_CODE_SIGN_IDENTITY` | 例如 `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_APP_PASSWORD` | `notarytool` 用的账号、团队 ID、App 专用密码 |

## 发一个版本

```bash
git tag v1.0.0
git push origin v1.0.0
```

`release.yml` 会依次：跑测试 → 构建 Release → 打 DMG（`scripts/build-dmg.sh`）→（有证书时）公证并装订 → 生成并签名 `appcast.xml` → 创建 GitHub Release，附上 DMG 和 `appcast.xml`。

版本号取自标签（`v1.0.0` → `1.0.0`），构建号取自 Actions 的运行序号。

## 本地打包

```bash
bash scripts/build-dmg.sh      # 输出 build/ToastNote-<版本>.dmg，并打印体积
```

预算：DMG 小于 15 MB，.app 小于 30 MB（spec 第 3 节）。

## 未签名构建怎么打开

没有公证的构建，首次打开时 macOS 会拦截。在访达里**右键点击 ToastNote.app → 打开 → 再点“打开”**。之后就可以正常启动。
