# 叮咚项目约定

- 开始工作前阅读 `README.md`、`docs/architecture.md` 和 `docs/development.md`。
- Flutter 客户端位于 `mobile/`，Android 后台接收、SQLite、备份和首帧同步使用 Kotlin。`services/relay/` 是 FastAPI 消息中转。`services/subscriptions/` 是 Node 订阅服务和管理台。两套服务各有 Docker Compose 配置。
- 按职责组织代码，使用清楚的业务名称，不做无关重写。Dart 执行 `dart format`，Kotlin 和 Python 使用 4 空格缩进；分支和异常处理展开，避免一行多条语句。
- 界面使用普通中文、Material 组件和统一主题。近白背景、橙色强调、深色跟随系统；不加入营销横幅或虚假默认消息。
- 正文成功保存到手机后才能确认接收；服务端确认后清除正文并保留去重记录。变更协议和持久化字段时保持兼容。
- 保留 HTML 作者 CSS；禁止页面脚本、页面可访问的原生 JS 桥、表单提交和任意文件读取。外部资源默认不加载，内嵌图片支持离线。
- 帖子从右侧滑入，先等待真实首帧就绪；不把 `onPageFinished` 或固定延迟当作画面已经绘制完成。保持同一 WebView，支持取消准备和系统减少动画设置。
- 不把密钥、SSH 资料、用户正文、数据库、截图、APK 或现场调试日志提交 Git。示例只使用明确的虚构数据，实际配置使用被忽略的环境变量文件。
- 保留正式回归测试。调试产物放项目外，不将临时设备配置编译到 App。
- 按 `docs/development.md` 运行相关检查。报告区分已验证和未验证范围，不把短时测试当作整夜后台稳定性证明。
