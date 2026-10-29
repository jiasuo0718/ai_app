import 'package:flutter/material.dart';

import 'engine.dart';
import 'file_picker.dart';

void main() => runApp(const FwSurgeryApp());

class FwSurgeryApp extends StatelessWidget {
  const FwSurgeryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '固件手术刀',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _fwPathCtrl = TextEditingController(text: '/storage/emulated/0/Download/system.img');
  final _outDirCtrl = TextEditingController(text: '/storage/emulated/0/AEmulatorFw/out');
  final _logs = <String>[];
  final _scroll = ScrollController();
  bool? _rootOk;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _checkRoot();
  }

  /// 带"打开文件夹选择"按钮的路径输入框
  Widget _pathField(TextEditingController ctrl, String label,
      {required bool pickDir, List<String> extensions = const []}) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: pickDir ? '选择目录' : '选择文件',
          onPressed: () async {
            final picked = await FilePickerPage.pick(context,
                initialPath: '/storage/emulated/0',
                pickDir: pickDir,
                extensions: extensions);
            if (picked != null) ctrl.text = picked;
          },
        ),
      ],
    );
  }

  Future<void> _checkRoot() async {
    final ok = await NativeBridge.checkRoot();
    setState(() => _rootOk = ok);
  }

  void _log(String line) {
    setState(() => _logs.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    _logs.clear();
    final engine = FirmwareSurgeryEngine(onLog: _log);
    final out = await engine.runPipeline(
      firmwarePath: _fwPathCtrl.text.trim(),
      outDir: _outDirCtrl.text.trim(),
    );
    _log(out == null ? '== 手术未完成 ==' : '== 完成: $out ==');
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('固件手术刀')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(_rootOk == true ? Icons.verified_user : Icons.gpp_maybe,
                  color: _rootOk == true ? Colors.green : Colors.orange),
              title: Text(_rootOk == null ? '检查 root...' : (_rootOk! ? 'root 正常' : '未 root')),
              subtitle: const Text('固件手术刀需 root 在本地拆包/改/重打包'),
              trailing: IconButton(
                  onPressed: _checkRoot, icon: const Icon(Icons.refresh), tooltip: '重查'),
            ),
          ),
          const SizedBox(height: 12),
          _pathField(
            _fwPathCtrl,
            '固件路径 (选 .img / payload 文件)',
            pickDir: false,
            extensions: const ['.img', '.bin', '.ozip', '.gz', '.zip'],
          ),
          const SizedBox(height: 8),
          _pathField(
            _outDirCtrl,
            '输出目录',
            pickDir: true,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.content_cut),
            label: Text(_running ? '手术中...' : '开始手术'),
          ),
          const SizedBox(height: 16),
          const Text('流水线: 拆包 → 手术(ColorOS 关 OPPO 组件/调 props/精简) → 重打包 → system.img'),
          const SizedBox(height: 8),
          Card(
            color: Colors.black.withOpacity(0.7),
            child: Container(
              height: 320,
              padding: const EdgeInsets.all(8),
              child: Scrollbar(
                controller: _scroll,
                child: ListView(
                  controller: _scroll,
                  children: [
                    for (final l in _logs) SelectableText(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
