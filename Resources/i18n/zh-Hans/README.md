# jonwork-ios

Jonwork 是连接 Jonwork 工作区与 Pi 智能体会话的原生 iOS 客户端。项目使用 Swift、UIKit，并复用成熟的聊天、Markdown 和编辑器组件。

项目正在准备发布，尚未提交 App Store 审核。FlowDown 的 App Store、TestFlight、定价和服务入口不属于 Jonwork。

打开 `Jonwork.xcworkspace`，主 scheme 为 `Jonwork`。应用源码位于 `Jonwork/`，测试位于 `JonworkTests/`，扩展位于 `JonworkTranslationProvider/` 和 `JonworkWidgets/`。工具位于 `Resources/DevKit/scripts/`。保留的 `LandingPage/` 是上游网站参考，不作为 Jonwork 官网或上架素材。

通过根目录 Makefile 执行 `make package-resolve`、`make build-ios-simulator`、`make test-unit`、`make localization-check`、`make appstore-check`。严格发布检查为 `make appstore-check-strict`；签名、账号删除、审核资料、真机及 TestFlight 验收缺失时不能认定已具备上架条件。

支持入口：[GitHub Issues](https://github.com/xiz2680/jonwork-ios/issues)。公开问题中不要附带密码、令牌或私密会话。

源码遵循 [AGPL-3.0](../../../LICENSE)，保留原作者与第三方许可出处。详见[英文说明](../../../README.md)和[上架记录](../../../docs/APP_STORE_READINESS.md)。
