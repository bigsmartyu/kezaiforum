# 设置说明

本页列出仓库中已经公开的配置项。真实域名、密码、隧道令牌、服务器私钥和用户资料不要提交到仓库。

## 1. 插件设置

文件：`plugin/innox-lan/config/settings.yml`

| 设置 | 默认值 | 作用 |
|---|---:|---|
| `innox_lan_enabled` | `true` | 启用自定义登记页、成员编号和品牌入口 |
| `innox_ai_moderation_enabled` | `true` | 启用帖子、回复和触发式聊天审核 |
| `innox_ai_moderation_url` | `http://172.17.0.1:11435/api/generate` | 审核模型的内部请求地址 |
| `innox_ai_moderation_model` | `qwen3guard:0.6b` | 审核模型名称 |
| `innox_ai_moderation_timeout_seconds` | `10` | 单次审核最长等待秒数，可设 2 至 30 |
| `innox_anonymous_category_id` | `0` | 允许匿名发帖的板块编号；`0` 表示未指定 |
| `innox_ai_chat_enabled` | `true` | 启用公开聊天室里的科仔 AI 助手 |
| `innox_ai_chat_url` | `http://172.17.0.1:11435/api/chat` | 聊天模型的内部请求地址 |
| `innox_ai_chat_model` | `qwen3:0.6b` | 聊天模型名称 |
| `innox_ai_chat_bot_username` | `kezai_ai` | 聊天助手的账号名 |
| `innox_ai_chat_timeout_seconds` | `20` | 单次回复最长等待秒数，可设 5 至 60 |

启动触发器：

- `@kezai_ai`
- `科仔AI`
- `科仔助手`

## 2. 社区初始化设置

文件：`server/harden_community.rb`

| 设置 | 当前值 | 说明 |
|---|---:|---|
| 社区标题 | `科仔交流社区` | 页面和浏览器标题 |
| 必须登录 | `true` | 未登录成员不能直接浏览论坛 |
| 只允许邀请注册 | `true` | 关闭普通公开注册入口 |
| 保存登录状态 | `true` | 避免每次重新登录 |
| 最长登录时间 | `8760` 小时 | 约一年 |
| 新成员密码最短长度 | `8` | 至少包含字母和数字 |
| 管理员密码最短长度 | `20` | 管理员账号使用更高要求 |
| 新成员前几次发帖审核 | `2` | 降低新账号首轮风险 |
| 单地址新账号上限 | `3` | 限制批量注册 |
| 每分钟登录尝试上限 | `5` | 降低密码猜测风险 |
| 每小时登录尝试上限 | `20` | 降低持续猜测风险 |
| 新成员链接上限 | `2` | 控制新账号引流 |
| 新成员嵌入媒体上限 | `2` | 控制新账号大图或视频 |
| 新成员单帖提及上限 | `3` | 降低批量打扰 |
| 公开资料隐藏 | `true` | 未登录用户不能查看成员资料 |

初始化脚本还会创建社区守则，并设置 21 条直接拦截词和 6 条人工复核词。词表位于 `server/harden_community.rb`，部署到自己的社区前应按实际使用场景复核。

## 3. Discourse 容器配置

文件：`server/app.yml`

需要按你的环境替换：

| 项目 | 示例值 | 说明 |
|---|---|---|
| `DISCOURSE_HOSTNAME` | `kezaiforum.xyz` | 你的正式域名 |
| `DISCOURSE_DEVELOPER_EMAILS` | `admin@example.com` | 管理员联系邮箱 |
| `DISCOURSE_DEFAULT_LOCALE` | `zh_CN` | 默认语言 |
| `DISCOURSE_SKIP_EMAIL_SETUP` | `1` | 本项目不使用邮件激活 |
| 插件挂载路径 | `/var/www/discourse/plugins/innox-lan` | 容器内插件目录 |

## 4. 公网通道

示例文件：`server/cloudflared-config.example.yml`

需要自行填写三类内容：

- `tunnel`：你的正式通道编号；
- `credentials-file`：你自己的凭证文件位置；
- `hostname`：你的正式域名。

真实配置文件 `server/cloudflared-config.yml` 已被 `.gitignore` 排除。不要把通道凭证、访问令牌或服务器私钥上传到仓库。

## 5. 本地审核与聊天模型

默认配置假设 Discourse 容器可以通过 `172.17.0.1:11435` 访问宿主机上的模型服务。若你的网络结构不同，请同时修改：

- `innox_ai_moderation_url`
- `innox_ai_chat_url`

建议模型服务只监听本机或容器内部地址，不直接暴露到公网。

## 6. 安卓应用地址

文件：`android/app/src/main/java/group/innoxsz/forum/MainActivity.java`

应用内有两个需要按部署环境替换的地址：

- `PUBLIC_BASE_URL`：公网论坛地址；
- `LAN_BASE_URL`：办公室内网备用地址。

当前源码中的域名和内网地址是原项目示例，不应视为所有部署都适用的默认值。

## 7. 敏感信息清单

以下内容绝不能提交：

- 管理员密码和测试账号密码；
- Cloudflare Tunnel 凭证和令牌；
- SSH 私钥、证书私钥、访问令牌；
- 真实成员姓名、办公室、电话、证件、头像和聊天记录；
- 服务器地址清单、备份文件和未脱敏日志；
- 含有登录信息的页面预览和浏览器状态文件。
