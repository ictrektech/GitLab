## GitLab VOS 应用

按设备选择 CPU profile：AMD64 选择 `amd`，ARM64 选择 `arm`，均无需 NVIDIA runtime。
Runner 是独立的可选部署，GPU 作业由 Runner 主机配置。

数据目录支持选择 NAS 公共目录或宿主机路径，行为与 Model Hub 的路径选择一致。
应用使用其中的 `gitlab/config`、`gitlab/data`、`gitlab/logs` 子目录保存配置、加密密钥、仓库、上传文件和日志。
PostgreSQL 复用必需依赖 PGV，在其中创建独立的 `gitlabhq_production` 数据库和非超级用户 `gitlab`。
GitLab 内置 PostgreSQL 已关闭；Redis 目前仍由 GitLab 独立管理。
初始化任务安装必要扩展；数据库专用密码保存在 `gitlab/config/vos-db-password`，不写入源码或日志。
保留目录的权限和所有者；迁移时须先停机，并同时备份 PGV 中的 GitLab 数据库以及本应用的配置、密钥和文件。
已有数据库所属角色不匹配或丢失保存的凭据时会停止初始化，不会覆盖其他应用的数据。

外部访问地址须填写浏览器和 Git 客户端可达的固定 VOS HTTPS 地址，以 `/app/com.ictrek.gitlab` 结尾。
浏览器及 Git 客户端需信任 VOS 证书。首次启动初始化可能需要数分钟。

从 VOS 菜单进入后，应用验证 VOS 身份并建立独立的 GitLab 本地账号。
账号绑定使用稳定用户标识，不依据显示名或邮箱关联；VOS 名称或角色不会自动赋予 GitLab 管理员或项目权限。
首版使用保留的占位邮箱，通知联系邮箱须另行设置并验证。
保留 GitLab 本地管理员登录以供管理和恢复。

Git 命令行使用 GitLab 个人访问令牌或 SSH 密钥，网页单点登录不会自动授权 Git 命令行。
目前 VOS 退出、禁用或删除用户尚不会同步撤销已有 GitLab 会话、访问令牌和 SSH 密钥。
需要立即停权时，还须在 GitLab 中阻止对应账号。

此为开发包，正式使用前须在目标 VOS 版本完成验证。
