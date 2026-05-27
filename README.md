# AudioSettings

一个 macOS 原生音频设置工具，使用 SwiftUI 与 CoreAudio 实现。

## 功能

- 展示当前系统默认输入设备与输出设备
- 展示系统可用输入设备与输出设备
- 将当前默认输入/输出设备保存到 JSON 配置文件
- 从配置文件读取设备 UID，并写回为系统默认输入/输出设备

## 图标

App 图标资源位于：

```text
Assets/AppIcon/AudioSettings.icns
```

## 打包与运行

```bash
./Scripts/build_app.sh
open dist/AudioSettings.app
```

生成的标准 macOS App 位于：

```text
dist/AudioSettings.app
```

### 构建脚本说明

`Scripts/build_app.sh` 会执行以下步骤：

1. 使用 `swift build -c release` 生成 release 可执行文件。
2. 创建标准 macOS App 目录结构：`dist/AudioSettings.app/Contents`。
3. 将可执行文件复制到 `Contents/MacOS/AudioSettings`。
4. 将图标复制到 `Contents/Resources/AudioSettings.icns`。
5. 生成 `Info.plist`，包含应用名、Bundle ID、版本号、图标和最低系统版本。
6. 使用本地 ad-hoc 签名：`codesign --force --sign -`。

脚本只写入项目内的 `dist/` 目录和 SwiftPM 的 `.build/` 目录，不会安装 App，也不会修改系统目录。生成的 App 未做 Apple Developer ID 签名和 notarization，仅用于本机或可信环境运行。

## 配置文件

配置文件写入当前用户目录：

```text
~/Library/Application Support/AudioSettings/devices.json
```

也可以在菜单栏 `AudioSettings -> 设置...` 中选择自定义配置文件路径。自定义路径必须以 `.json` 结尾，避免误覆盖非配置文件。

恢复配置时，如果保存的设备未连接，应用会提示设备不存在。

## 隐私与安全检查

当前实现的隐私与安全边界：

- 不访问网络，不上传任何数据。
- 不录音，不读取麦克风音频内容。
- 只通过 CoreAudio 读取音频设备名称、设备 UID、当前默认输入/输出设备，并在用户操作时切换默认设备。
- 配置文件只保存在本机，内容包括输入/输出设备名称、设备 UID 和保存时间。
- 自定义配置路径保存在 `UserDefaults` 中；实际配置仍是本机 JSON 文件。
- 自定义配置文件路径限制为 `.json`，降低误覆盖其他文件的风险。
- 打包脚本使用固定项目路径构建，不执行下载、安装或远程脚本。

已知注意事项：

- 设备 UID 可能包含硬件厂商、设备型号或序列信息，配置文件不应提交到公共仓库。
- App 使用 ad-hoc 签名，适合本地使用；如果要分发给他人，应使用 Developer ID 签名并 notarize。
