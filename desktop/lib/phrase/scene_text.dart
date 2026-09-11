// 短语「使用场景」文本归一化 —— 纯函数，无 UI / 无 IO。
//
// 约定（openspec/changes/phrase-scene-list）：一条场景 = 一行；多条场景在
// `phrases.scene` 单一 TEXT 列中以 '\n' 分隔。拆条与合并必须成对使用，
// 任何来源的文本在写入前都要先归一化，避免空条目与空白分隔。
//
// 该不变式被三处依赖，改动前先看这三处：
//   1) 表单：N 个场景行 <-> joinScenes
//   2) 详情 / 复习：分条展示
//   3) Anki 导出：<ul><li> 列表项（分错即会多出/少掉列表项）

/// 把存储文本拆成场景条目：逐条 trim、丢弃空白条目、保持顺序。
///
/// '\r\n' 由 trim 一并去掉；空行不产生空条目（幽灵场景）。
List<String> splitScenes(String raw) {
  final out = <String>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// 把场景条目合并为存储文本：逐条 trim、丢弃空白条目、以 '\n' 连接。
///
/// 条目内部若含换行，按「输入换行即分条」拆成多条，保证不变量成立。
String joinScenes(Iterable<String> scenes) => splitScenes(scenes.join('\n')).join('\n');
