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

## Node 订阅服务

从仓库根目录进入服务目录运行回归测试。网页测试使用本机 Chrome 或由 `CHROMIUM_EXECUTABLE` 指定的 Chromium。

```sh
cd services/subscriptions
npm ci
npm test
npm run test:web
```

启动、Studio 插件同步和部署入口见 [订阅服务说明](../services/subscriptions/README.md)。

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

## Studio 订阅控制回归

服务端 `tests/test_studio.py` 使用独立临时数据库，覆盖凭据方向、离线、命令白名单、电脑确认后返回新配置、配置冲突、单 Studio 连接、过期命令及请求大小限制。Flutter 的 `test/studio_test.dart` 覆盖离线说明、版本化启停、等待确认和冲突时保留草稿。Android 的 `StudioControlTest` 使用本地模拟 HTTP 服务验证 UTF-8 响应、认证、写操作和禁止跟随重定向。

相关检查仍使用上面的 `python -m unittest discover -s tests -v`、`flutter analyze`、`flutter test`、`:app:testDebugUnitTest :app:lintDebug`。Studio 仓库的 `npm test` 与 `npm run test:ui` 包含控制模块单元测试及真实 Electron 任务处理器联动测试；后者使用模拟中转和独立临时数据，不连接日常手机或生产服务器。

上线验证需同时更新服务器、Studio 和 App，在 Studio 选择叮咚渠道后，从手机「Studio 订阅」测试保存并在电脑确认。自动测试与本地构建不等同于真实服务器/手机联调或长期后台稳定性验证。

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

## 服务器账号回归

Flutter `platform_accounts_test.dart` 覆盖复用原生已保存连接、不出现独立地址或配对码表单、显示服务端验证结果和 HTTPS 失败；`connection_settings_test.dart` 覆盖已保存密钥的原生查看入口且不回填表单。Android `PlatformAccountsTest` 覆盖同主机 HTTPS 推导、认证和禁止重定向；`PlatformLoginFeedbackTest` 覆盖登录 Cookie 到达、验证进度和错误保留。

Node 仓库 `npm test` 覆盖配对权限隔离、替换旧码、成功/失败提交后均不可重用、未配置中转凭据时关闭账号入口及加密存储。生产验证需移除手机本机 Node 的 ADB reverse，检查公网证书、真实手机授权、服务器读取及容器重启后恢复；不要用本机结果替代这些步骤。

## 任务驱动流程与表单检查

- `subscriptions_test.dart` 覆盖服务器插件 → 保存并开启任务 → 显示依赖账号 → 暂停后移除账号需求；插件名称和字段由服务端响应驱动。
- `platform_accounts_test.dart` 覆盖无任务时不显示登录、依赖任务名称展示、复用原生已保存连接。
- Node `subscriptions.test.mjs` 覆盖任务持久化、插件缺失、revision 冲突、账号等待、共享依赖、调度、去重和发送响应丢失后的同 ID 重试；HTTP 测试验证订阅 API 认证与插件目录；B 站会话替换失败后恢复原可用账号，避免打断现有任务。
- App 自有表单已检查设置、新服务器任务、旧 Studio 编辑、下拉菜单、复选框/开关、日期时间选择和确认弹窗。Flutter 统一填充、边框、聚焦、错误、禁用、圆角和菜单样式；Android 登录授权/密钥查看使用同一原生对话框主题。平台官方网页和系统权限界面由各自系统控制，不接管官方账号输入。
- 真机验证使用公网服务器和实际手机操作创建任务；应核对服务端采集、推送、手机落盘回执、重复检查不重复发送、暂停后的账号需求和重启持久化。仅 mock 测试不能替代此验证。

## Node 插件订阅回归

`subscription_editor_test.dart` 检查 Studio 贴吧复合字段序列化；`subscriptions_test.dart` 检查任务列表进入、插件选择、保存与账号依赖。原生登录反馈测试覆盖 B 站/X/小红书各自的必要 Cookie。Node 项目中的 npm test 执行复用的 Studio 回归与真实 Node 子进程协议测试，生产平台验证码不在自动化测试范围内。

统一选择组件位于 `mobile/lib/ui/selection_sheet.dart`。`subscription_editor_test.dart` 还覆盖底部面板在大字体下滚动、取消多选不修改原值、旧版来源选择和占用限制，以及在汇总编辑中创建来源后保留草稿并使用新 revision 保存。Node 汇总测试覆盖旧版 seen 去重与 Studio 状态一起提交、发送失败后重启原样重试、待发来源和重复归属保护。

HTTPS 升级回归：Flutter 验证同主机升级可保留空白密钥输入、跨主机/端口/降级不允许复用；Android `RelayEndpointTest` 验证相同边界与稳定消息命名空间。2026-11-17 真机开启 VPN、关闭服务器直连时，HTTP 握手在 Nginx 入口缺失 Upgrade 且返回 404；切换为可信 HTTPS 后 WSS 返回 101，测试消息收到手机持久化回执。真机也完成创建暂停 X 来源、加入包含旧 B 站任务的暂停汇总、保存并核对公网状态；临时任务已删除。该验证不代表所有代理节点或长期后台状态都已覆盖。
