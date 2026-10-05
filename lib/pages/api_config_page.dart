import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/api_config.dart';
import '../services/storage_service.dart';
import '../services/llm_service.dart';

/// API配置管理页
class ApiConfigPage extends StatefulWidget {
  final StorageService storage;

  const ApiConfigPage({super.key, required this.storage});

  @override
  State<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends State<ApiConfigPage> {
  List<ApiConfig> _configs = [];
  final _uuid = const Uuid();
  final _llm = LlmService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _configs = widget.storage.getApiConfigs());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEDED),
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('API配置'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addConfig),
        ],
      ),
      body: _configs.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _configs.length,
              itemBuilder: (ctx, idx) => _buildCard(_configs[idx]),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.api_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('还没有API配置', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('点击右上角 + 添加API密钥',
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCard(ApiConfig cfg) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF07C160).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(cfg.providerLabel,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF07C160))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(cfg.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (cfg.isDefault)
                  const Text('默认',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
              ],
            ),
            const SizedBox(height: 8),
            Text('模型: ${cfg.model}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text('地址: ${cfg.baseUrl}',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _testConnection(cfg),
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text('测试'),
                ),
                TextButton.icon(
                  onPressed: () => _editConfig(cfg),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: () => _toggleDefault(cfg),
                  icon: Icon(
                      cfg.isDefault ? Icons.star : Icons.star_border,
                      size: 18,
                      color: cfg.isDefault ? Colors.orange : null),
                  label: Text(cfg.isDefault ? '已设默认' : '设为默认'),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteConfig(cfg),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection(ApiConfig cfg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在测试连接...')),
    );
    final ok = await _llm.testConnection(cfg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '连接成功' : '连接失败，请检查配置')),
    );
  }

  Future<void> _toggleDefault(ApiConfig cfg) async {
    final updated = ApiConfig(
      id: cfg.id,
      name: cfg.name,
      provider: cfg.provider,
      baseUrl: cfg.baseUrl,
      apiKey: cfg.apiKey,
      model: cfg.model,
      ttsBaseUrl: cfg.ttsBaseUrl,
      ttsApiKey: cfg.ttsApiKey,
      ttsVoiceId: cfg.ttsVoiceId,
      isDefault: !cfg.isDefault,
      createdAt: cfg.createdAt,
    );
    await widget.storage.upsertApiConfig(updated);
    _loadData();
  }

  Future<void> _deleteConfig(ApiConfig cfg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定删除「${cfg.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await widget.storage.deleteApiConfig(cfg.id);
      _loadData();
    }
  }

  void _addConfig() {
    _editConfig(null);
  }

  void _editConfig(ApiConfig? cfg) {
    showDialog(
      context: context,
      builder: (ctx) => _ConfigDialog(
        config: cfg,
        storage: widget.storage,
        onSaved: _loadData,
      ),
    );
  }
}

/// 配置编辑对话框
class _ConfigDialog extends StatefulWidget {
  final ApiConfig? config;
  final StorageService storage;
  final VoidCallback onSaved;

  const _ConfigDialog({
    required this.config,
    required this.storage,
    required this.onSaved,
  });

  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _keyCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _ttsUrlCtrl;
  late TextEditingController _ttsKeyCtrl;
  late TextEditingController _ttsVoiceCtrl;
  late ApiProvider _provider;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _urlCtrl = TextEditingController(
        text: c?.baseUrl ?? 'https://ark.cn-beijing.volces.com/api/v3');
    _keyCtrl = TextEditingController(text: c?.apiKey ?? '');
    _modelCtrl = TextEditingController(text: c?.model ?? 'doubao-pro-32k');
    _ttsUrlCtrl = TextEditingController(
        text: c?.ttsBaseUrl ?? 'https://openspeech.bytedance.com/api/v1/tts');
    _ttsKeyCtrl = TextEditingController(text: c?.ttsApiKey ?? '');
    _ttsVoiceCtrl =
        TextEditingController(text: c?.ttsVoiceId ?? 'zh_female_qingxin');
    _provider = c?.provider ?? ApiProvider.doubao;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _ttsUrlCtrl.dispose();
    _ttsKeyCtrl.dispose();
    _ttsVoiceCtrl.dispose();
    super.dispose();
  }

  void _fillPreset(ApiProvider p) {
    setState(() {
      _provider = p;
      switch (p) {
        case ApiProvider.doubao:
          _urlCtrl.text = 'https://ark.cn-beijing.volces.com/api/v3';
          _modelCtrl.text = 'doubao-pro-32k';
          _ttsUrlCtrl.text = 'https://openspeech.bytedance.com/api/v1/tts';
          _ttsVoiceCtrl.text = 'zh_female_qingxin';
          break;
        case ApiProvider.openai:
          _urlCtrl.text = 'https://api.openai.com/v1';
          _modelCtrl.text = 'gpt-4o-mini';
          _ttsUrlCtrl.text = 'https://api.openai.com/v1/audio/speech';
          _ttsVoiceCtrl.text = 'alloy';
          break;
        case ApiProvider.deepseek:
          _urlCtrl.text = 'https://api.deepseek.com/v1';
          _modelCtrl.text = 'deepseek-chat';
          break;
        case ApiProvider.qwen:
          _urlCtrl.text = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
          _modelCtrl.text = 'qwen-turbo';
          break;
        case ApiProvider.custom:
          break;
      }
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _urlCtrl.text.trim().isEmpty ||
        _keyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写名称、地址和密钥')),
      );
      return;
    }
    final isNew = widget.config == null;
    final cfg = ApiConfig(
      id: widget.config?.id ?? _uuid.v4(),
      name: _nameCtrl.text.trim(),
      provider: _provider,
      baseUrl: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      ttsBaseUrl: _ttsUrlCtrl.text.trim().isEmpty
          ? null
          : _ttsUrlCtrl.text.trim(),
      ttsApiKey:
          _ttsKeyCtrl.text.trim().isEmpty ? null : _ttsKeyCtrl.text.trim(),
      ttsVoiceId:
          _ttsVoiceCtrl.text.trim().isEmpty ? null : _ttsVoiceCtrl.text.trim(),
      isDefault: widget.config?.isDefault ?? false,
      createdAt: widget.config?.createdAt ?? DateTime.now(),
    );
    await widget.storage.upsertApiConfig(cfg);
    if (isNew && widget.storage.getApiConfigs().length == 1) {
      // 第一个配置自动设为默认
      final first = widget.storage.getApiConfigs().first;
      await widget.storage.upsertApiConfig(ApiConfig(
        id: first.id,
        name: first.name,
        provider: first.provider,
        baseUrl: first.baseUrl,
        apiKey: first.apiKey,
        model: first.model,
        ttsBaseUrl: first.ttsBaseUrl,
        ttsApiKey: first.ttsApiKey,
        ttsVoiceId: first.ttsVoiceId,
        isDefault: true,
        createdAt: first.createdAt,
      ));
    }
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.config == null ? '添加API配置' : '编辑API配置'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 服务商快捷选择
              Wrap(
                spacing: 8,
                children: ApiProvider.values.map((p) {
                  return ChoiceChip(
                    label: Text(p.name),
                    selected: _provider == p,
                    onSelected: (_) => _fillPreset(p),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                      labelText: '配置名称', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: _keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'API Key', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                      labelText: '模型名称', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('TTS语音配置（可选）',
                      style: TextStyle(fontWeight: FontWeight.w500))),
              const SizedBox(height: 8),
              TextField(
                  controller: _ttsUrlCtrl,
                  decoration: const InputDecoration(
                      labelText: 'TTS接口地址',
                      border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: _ttsKeyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'TTS密钥（不填则共用API Key）',
                      border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: _ttsVoiceCtrl,
                  decoration: const InputDecoration(
                      labelText: '默认音色ID',
                      border: OutlineInputBorder())),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF07C160)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
