import 'package:flutter/material.dart';

import 'engine.dart';

/// 一个文件系统浏览条目
class FSEntry {
  final String path;
  final bool isDir;
  String get name => path.split('/').last.isEmpty ? path : path.split('/').last;
  FSEntry(this.path, this.isDir);
}

/// 用 root 能力浏览文件系统并选择一个路径(文件或目录), 选后返回真实绝对路径。
class FilePickerPage extends StatefulWidget {
  /// 起始目录
  final String initialPath;

  /// true=只能选目录(输出目录用); false=选文件(固件路径用)
  final bool pickDir;

  /// 可选: 只显示这些后缀的文件(小写, 带点, 如 '.img')
  final List<String> extensions;

  const FilePickerPage({
    super.key,
    this.initialPath = '/storage/emulated/0',
    this.pickDir = false,
    this.extensions = const [],
  });

  @override
  State<FilePickerPage> createState() => _FilePickerPageState();

  /// 弹出选择器, 返回选中的路径(取消返回 null)
  static Future<String?> pick(BuildContext context,
      {String initialPath = '/storage/emulated/0',
      bool pickDir = false,
      List<String> extensions = const []}) {
    return Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => FilePickerPage(
        initialPath: initialPath,
        pickDir: pickDir,
        extensions: extensions,
      ),
    ));
  }
}

class _FilePickerPageState extends State<FilePickerPage> {
  late String _current = widget.initialPath;
  List<FSEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(_current);
  }

  Future<void> _load(String path) async {
    setState(() {
      _current = path;
      _loading = true;
      _error = null;
    });
    final lines = await NativeBridge.listDir(path);
    if (!mounted) return;
    if (lines.length == 1 && lines.first.startsWith('ERR')) {
      setState(() {
        _loading = false;
        _error = lines.first.substring(4);
      });
      return;
    }
    final entries = <FSEntry>[];
    for (final l in lines) {
      final isDir = l.startsWith('D|');
      final p = l.substring(2);
      if (p.isEmpty || p == '/') continue;
      if (p.endsWith('/*')) continue; // glob 未匹配的残留
      final name = p.split('/').last;
      if (name == '.' || name == '..') continue;
      if (!isDir && !widget.pickDir && widget.extensions.isNotEmpty) {
        final lower = name.toLowerCase();
        if (!widget.extensions.any((e) => lower.endsWith(e))) continue;
      }
      entries.add(FSEntry(p, isDir));
    }
    // 目录在前, 再按名称排序(目录/文件各自排序)
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _goUp() {
    final idx = _current.lastIndexOf('/');
    if (idx <= 0) return; // 已在根
    final parent = _current.substring(0, idx);
    _load(parent);
  }

  void _select(FSEntry e) {
    if (e.isDir && !widget.pickDir) {
      // 选文件模式点目录 -> 进入
      _load(e.path);
      return;
    }
    Navigator.of(context).pop(e.path);
  }

  void _selectCurrentDir() {
    if (!widget.pickDir) return;
    Navigator.of(context).pop(_current);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickDir ? '选择输出目录' : '选择固件文件'),
        actions: [
          if (widget.pickDir)
            TextButton(
                onPressed: _selectCurrentDir,
                child: const Text('选此目录')),
          IconButton(icon: const Icon(Icons.folder_special), onPressed: () => _load('/storage/emulated/0'), tooltip: '回到存储根'),
        ],
      ),
      body: Column(
        children: [
          // 当前路径栏 + 返回上级
          Container(
            color: Colors.black.withOpacity(0.4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _current.split('/').length > 2 ? _goUp : null,
                    tooltip: '上级目录'),
                Expanded(
                  child: SelectableText(_current,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('⚠ $_error', style: const TextStyle(color: Colors.orange)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _load(_current),
                    child: ListView(
                      children: [
                        if (_entries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('(空目录)', textAlign: TextAlign.center),
                          ),
                        for (final e in _entries)
                          ListTile(
                            leading: Icon(e.isDir ? Icons.folder : Icons.insert_drive_file,
                                color: e.isDir ? Colors.amber : Colors.blueGrey),
                            title: Text(e.name, overflow: TextOverflow.ellipsis),
                            trailing: e.isDir ? const Icon(Icons.chevron_right) : null,
                            onTap: () => _select(e),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
