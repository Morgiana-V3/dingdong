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

## FastAPI 消息中转

```sh
cd services/relay
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
```

## Node 插件引擎（`services/engine`）

从仓库根目录进入服务目录运行回归测试和插件校验：

```sh
cd services/engine
npm install
npm run typecheck
npm test
npm run plugin:create my-plugin "示例插件"
npm run plugin:test ./plugins/bilibili-feed
npm run plugin:test ./plugins/rss-watch
npm run plugin:test ./plugins/ai-web-digest
```

插件编写规范见 [插件开发指南](PLUGIN_GUIDE.md)，部署说明见 [引擎服务说明](../services/engine/README.md)。

## 发送与模板工具

从仓库根目录执行，无需第三方依赖。

```sh
python -m unittest discover -s tools/tests -v
python tools/render.py posts examples/templates/posts.json examples/posts.html
```

生成的 HTML 已加入忽略规则，仓库只保存模板输入和最小可用示例。

## 链接与网络回归

Flutter 文档测试验证 App 链接、新窗口链接和协议相对链接可由阅读页接管，同时拒绝脚本、文件与任意 intent。Android `ExternalLinksTest` 验证精确原帖 ID、可信包名、分享参数和网页回退；`RelayNetworkTest` 验证默认系统路由、物理网络选择及不绑定整个进程。`connection_settings_test.dart` 验证直连开关需要保存且不会清空已存凭据。

`SavedConnectionProbe` 是需明确开启的 Android instrumentation 诊断，仅用于用户已授权的当前设备/服务器。它不清空数据，不输出密钥或正文，不确认接收消息；暂时停止本机接收服务后比较系统、无 HTTP 代理和直连 Wi-Fi 的健康检查/WebSocket，结束后恢复原本启用的服务。仅安装测试 APK，不通过 Flutter 集成测试重装日常 App：先构建 `:app:assembleDebugAndroidTest`，安装 `app-debug-androidTest.apk` 后运行 `adb -s DEVICE shell am instrument -w -e class app.dingdong.dingdong.SavedConnectionProbe -e probeSavedConnection true app.dingdong.dingdong.test/androidx.test.runner.AndroidJUnitRunner`。未传 `probeSavedConnection=true` 时跳过。手机拒绝 USB 安装时，应等待用户解除限制，不绕过安装保护。

## 引擎与通用凭据回归

- Flutter `subscriptions_test.dart` 覆盖动态插件列表、任务启停与凭据需求联动；`subscription_editor_test.dart` 覆盖通用 `stringList / textarea / number / boolean` 表单原语与汇总来源选择；`platform_accounts_test.dart` 覆盖通用 `web-cookie` 认证元数据透传与无任务时不展示登录入口。
- Android `PlatformAccountsTest` 覆盖同主机 HTTPS 推导、公网 HTTPS 登录地址校验（拒绝内网/非 HTTPS）、认证与禁止重定向；`PlatformLoginFeedbackTest` 覆盖任意插件声明的 `requiredCookies` 检测与状态流转。
- Node `services/engine/tests/` 覆盖 Cordis 插件目录动态加载与错误隔离、全部通用字段校验与 `secret` 脱敏、Outbox 原子重试、`AuthExpiredError` 过期提醒、HTTP 鉴权、409 版本冲突与一次性配对码隔离。

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

## 0.2.0 验证范围

完成去 Studio 化与插件化重构后，通过 Flutter 静态分析、46 项 Flutter 测试、Android 原生单元测试、5 项 Python 发送工具测试、4 项 Relay 测试、5 项 Engine 测试以及 3 个内置官方插件（`bilibili-feed`、`rss-watch`、`ai-web-digest`）的 `plugin:test` 校验。

真机实测与公网 Docker Compose + Nginx 联调需在真实设备和服务器环境单独核对，不将单元测试等同于真实网络/长期后台稳定性证明。
