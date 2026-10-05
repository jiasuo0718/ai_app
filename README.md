# AI 聊天客户端

仿微信 UI 的 AI 多角色聊天 App，支持多家大模型 API 接入、角色卡管理、多会话、语音消息。

## 功能

- 仿微信聊天界面（绿色气泡、语音条、表情面板）
- 角色卡管理：自定义头像、名称、人设提示词、开场白、TTS 音色
- 多会话：每个会话绑定一个角色，支持新建/删除
- 语音消息：按住录音、AI 语音回复（TTS 合成）、点击播放
- 多家 API：豆包/OpenAI/DeepSeek/通义千问/自定义，OpenAI 兼容格式
- 本地存储：所有数据保存在手机本地，无需服务器

## 快速开始

### 云编译（推荐，无需本地环境）

1. 将本项目上传到 Flutter 云编译平台
2. 执行 `flutter pub get`
3. 构建 APK（release 已关闭混淆和资源压缩，避免闪退）

### 本地编译

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## 使用步骤

1. 打开 App → 底部「设置」→「API配置」→ 点 + 添加
2. 选择服务商（豆包/OpenAI等），填入 API Key、模型名
3. 底部「角色」→ 点 + 创建角色卡，填写人设提示词
4. 底部「聊天」→ 点 + 新建会话，选择角色，开始聊天

## 豆包 API 配置

- LLM 地址：`https://ark.cn-beijing.volces.com/api/v3`
- 模型：如 `doubao-pro-32k`（需在火山引擎方舟平台创建推理接入点）
- TTS 地址：`https://openspeech.bytedance.com/api/v1/tts`
- TTS 音色：如 `zh_female_qingxin`

## 项目结构

```
lib/
├── main.dart                    # 入口
├── models/                      # 数据模型
│   ├── api_config.dart          # API配置 + 用户设置
│   ├── character.dart           # 角色卡
│   ├── chat_message.dart        # 聊天消息
│   └── conversation.dart        # 会话
├── services/                    # 业务服务
│   ├── storage_service.dart     # 本地存储(SharedPreferences)
│   ├── llm_service.dart         # 大模型API调用
│   └── tts_service.dart         # 语音合成
├── widgets/                     # UI组件
│   ├── message_bubble.dart      # 微信消息气泡
│   └── voice_bubble.dart        # 语音气泡
└── pages/                       # 页面
    ├── chat_page.dart           # 聊天页(核心)
    ├── conversation_list_page.dart  # 会话列表
    ├── character_list_page.dart # 角色卡列表
    ├── character_edit_page.dart # 角色卡编辑
    ├── api_config_page.dart     # API配置管理
    └── settings_page.dart       # 设置页
```

## 注意事项

- Release 构建已关闭 `minifyEnabled` 和 `shrinkResources`，避免 Flutter so 库崩溃和图标丢失
- API Key 存储在本地 SharedPreferences，生产环境建议通过后端中转
- 语音录音需要麦克风权限，首次使用会请求授权
