# 开发与验证

## 环境

- Flutter 3.41.5 / Dart 3.11.3（已验证版本）。
- Android SDK、JDK 17 或符合当前 Gradle/Android Gradle Plugin 要求的 JDK。
- Python 3.13（服务端 Docker 镜像与当前验证环境）。
- Docker Engine 与 Compose 插件用于服务器部署。

不要提交 `local.properties`、私密 `.env`、签名文件、数据库或构建产物。Gradle Wrapper 脚本和 JAR 保留在仓库；Flutter、Python 依赖的版本文件也保留。

## Flutter

从仓库根目录进入 `mobile`：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

常规 `flutter test` 只执行 `mobile/test/` 中的回归测试，不操作真实手机。APK 路径见根目录 README。

## Android 原生

在 `mobile/android` 执行：

```powershell
.\gradlew.bat :app:testDebugUnitTest :app:lintDebug
```

Linux / macOS 使用 `./gradlew`。原生回归测试覆盖数据库迁移、全文搜索、删除撤销与去重、备份恢复及异常回滚；真实 WebView 的绘制时序需要设备检查。

Windows 下如果 Lint 报 `local.properties` 的 `PropertyEscape`，检查 SDK 路径中的盘符冒号和反斜杠转义；修正本地配置后执行 `:app:lintAnalyzeDebug --rerun :app:lintDebug`，不要关闭该检查。此文件不会提交仓库。

## Python

服务端：

```sh
cd server
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
```

发送与模板工具：从仓库根目录执行，无需第三方依赖。

```sh
python -m unittest discover -s tools/tests -v
python tools/render.py posts examples/templates/posts.json examples/posts.html
```

生成的 HTML 已加入忽略规则，仓库只保存模板输入和最小可用示例。

## 独立设备集成测试

`mobile/integration_test/delivery_test.dart` 验证真实收发、幂等重试、离线补收、后台接收和本地管理。配套 `tools/testing/device_fixture.py` 是正式测试夹具，不是生产服务。

使用专门的模拟器或可清空的测试设备；Flutter 集成测试可能重装测试应用。不要选择日常保存消息的手机，也不要使用生产接收密钥，避免替代日常手机的连接。

1. 启动独立测试服务器，使用两个不同的随机密钥和项目外的临时数据库。
2. 在项目外创建测试 `.env`，包含与该服务器一致的 `DINGDONG_SEND_TOKEN` 和 `DINGDONG_READ_TOKEN`。
3. 确保 `adb` 在 PATH 中；将夹具端口转发给指定设备：

```sh
adb -s DEVICE_ID reverse tcp:18679 tcp:18679
```

4. 从仓库根目录启动夹具。下列路径和端点均替换为本次测试值：

```sh
python tools/testing/device_fixture.py --env-file /path/to/test.env --endpoint http://TEST_SERVER:8080 --device DEVICE_ID --output /path/to/test-output
```

夹具仅监听电脑的 `127.0.0.1:18679`。如果服务器也运行在本机，可另外转发服务器端口，并将 endpoint 填为设备能够访问的对应地址。

5. 另一个终端进入 `mobile`：

```sh
flutter test integration_test/delivery_test.dart -d DEVICE_ID
```

测试后停止测试夹具和服务器，清理临时配置与 ADB 反向转发。重新执行 `flutter build apk --debug` 后再交付 APK，避免把集成测试入口当作正常应用安装包。

## 0.1.0 验证范围

整理版本时通过 Flutter 静态分析、14 项 Flutter 测试、6 项 Android 测试、5 项 Python 工具测试、4 项服务端测试，以及 Android Lint 和调试构建。Lint 有 15 条建议性警告，无错误。

设备验证记录包括独立 Android 35 模拟器的收发/备份恢复，以及小米 17 Pro 的 HTML 首帧准备后右侧滑入、返回和再次打开。此次仓库整理不将此前的设备结果描述为重新执行全部端到端验证。

尚未覆盖全部 WebView 版本、所有复杂 HTML/CSS、小米整夜锁屏/Doze、真实网络切换及正式签名发布。提交前按实际改动选择相关检查，记录未完成项，不将构建通过等同于功能全部验证。
