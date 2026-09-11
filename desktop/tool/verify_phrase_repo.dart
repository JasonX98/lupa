// 验证短语集：建表 / 旧库迁移 / CRUD / 调度 / 统计 / 导出（临时库，不污染真实数据）。
// 用法: dart run tool/verify_phrase_repo.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/export/apkg.dart' as word_apkg show stableGuid;
import 'package:lupa/export/phrase_apkg.dart';
import 'package:lupa/export/phrase_csv.dart';
import 'package:lupa/notebook/scheduler.dart';
import 'package:lupa/phrase/repo.dart';
import 'package:lupa/phrase/scene_text.dart';

var failures = 0;

void check(String name, bool ok, {Object? detail}) {
  stdout.writeln('$name: ${ok ? "PASS" : "FAIL"}${detail == null ? "" : "  ($detail)"}');
  if (!ok) failures++;
}

Future<void> main() async {
  initDatabaseFactory();
  final tmp = await Directory.systemTemp.createTemp('lupa_phrase_verify_');
  final nbPath = p.absolute(p.join(tmp.path, 'notebook.sqlite'));

  // ================= 1.1 建表（fresh）=================
  await ensureNotebookDb(nbPath);
  final con0 = await databaseFactory.openDatabase(nbPath,
      options: OpenDatabaseOptions(singleInstance: false));
  final tables = (await con0.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"))
      .map((r) => r['name'] as String)
      .toSet();
  final meta0 = {
    for (final r in await con0.query('meta')) r['key'] as String: r['value']
  };
  await con0.close();
  check('1.1 三张短语表建好',
      tables.containsAll(['phrases', 'phrase_examples', 'phrase_review_log']));
  check('1.1 schema_version=2', meta0['schema_version'] == '2', detail: meta0);

  // ================= 2.1 addPhrase =================
  final id1 = await addPhrase(
    nbPath,
    const PhraseInput(
      phrase: 'bite the bullet',
      meaning: '咬紧牙关硬着头皮去做不情愿但必须做的事',
      lit: '咬子弹',
      origin: '战地手术典故',
      scene: '面对困难任务时',
      sceneTag: '口语',
      tags: '口语, 通用，书面',
      examples: [
        PhraseExample(en: 'I will just have to bite the bullet.', zh: '只能硬着头皮去了。'),
        PhraseExample(en: 'She bit the bullet and told him the truth.', zh: '她咬咬牙说了实话。'),
      ],
    ),
  );
  check('2.1 addPhrase 返回 id>0', id1 > 0, detail: id1);

  var dup = false;
  try {
    await addPhrase(nbPath,
        const PhraseInput(phrase: 'BITE THE BULLET', meaning: 'x'));
  } on PhraseExistsError {
    dup = true;
  }
  check('2.1 重复短语（忽略大小写）拒绝', dup);

  var noMeaning = false;
  try {
    await addPhrase(nbPath, const PhraseInput(phrase: 'x', meaning: '  '));
  } on PhraseValidationError {
    noMeaning = true;
  }
  check('2.1 缺核心释义拒绝', noMeaning);

  var noPhrase = false;
  try {
    await addPhrase(nbPath, const PhraseInput(phrase: ' ', meaning: 'y'));
  } on PhraseValidationError {
    noPhrase = true;
  }
  check('2.1 缺短语文本拒绝', noPhrase);

  // ================= 2.3 列表 / 筛选 / 详情 =================
  await addPhrase(nbPath,
      const PhraseInput(phrase: 'spill the beans', meaning: '泄露秘密', tags: '口语'));
  await addPhrase(nbPath,
      const PhraseInput(phrase: 'once in a blue moon', meaning: '千载难逢', tags: '通用'));

  final all = await listPhrases(nbPath);
  check('2.3 list 倒序（最新在前）', all.length == 3 && all.first.phrase == 'once in a blue moon',
      detail: all.map((e) => e.phrase).toList());
  check('2.3 例句数正确', all.firstWhere((e) => e.phrase == 'bite the bullet').exampleCount == 2);

  final spoken = await listPhrases(nbPath, tag: '口语');
  check('2.3 按 tag 筛选', spoken.length == 2, detail: spoken.map((e) => e.phrase).toList());

  final detail = await getPhrase(nbPath, id1);
  check('2.3 getPhrase 含例句', detail != null && detail.examples.length == 2);
  check('2.3 tags 规范化（去空格去重）',
      detail!.tags.join('|') == '口语|通用|书面', detail: detail.tags);
  final tagList = await phraseTags(nbPath);
  check('2.3 标签集合 phraseTags',
      tagList.toSet().containsAll(['口语', '通用', '书面']) && tagList.length == 3,
      detail: tagList);

  // ================= 2.4 调度 / 答题 / 统计 =================
  // 纯函数分级推进（与单词复习共用同一实现）
  check('2.4 nextInterval(7, Hard)=7 模糊保持当前档',
      nextInterval(7, easeHard) == 7);
  check('2.4 nextInterval(7, Easy)=30 简单前进两档',
      nextInterval(7, easeEasy) == 30);
  check('2.4 nextInterval(0, Easy)=7 新短语简单进第三档',
      nextInterval(0, easeEasy) == 7);

  final q1 = await answerPhrase(nbPath, id1, easeGood);
  check('2.4 新短语 Good => ivl=3（与 1 天短语同档）', q1.nextIvl == 3, detail: q1.nextIvl);
  final q2 = await answerPhrase(nbPath, id1, easeGood);
  check('2.4 间隔 3 Good => 7', q2.nextIvl == 7, detail: q2.nextIvl);
  final q3 = await answerPhrase(nbPath, id1, easeAgain);
  check('2.4 答错回第一档 => 1', q3.nextIvl == 1, detail: q3.nextIvl);
  final after = await getPhrase(nbPath, id1);
  check('2.4 答错 lapses=1', after!.lapses == 1, detail: after.lapses);

  final con1 = await databaseFactory.openDatabase(nbPath,
      options: OpenDatabaseOptions(singleInstance: false));
  final logCount = (await con1.rawQuery(
          'SELECT COUNT(*) c FROM phrase_review_log WHERE phrase_id = ?', [id1]))
      .first['c'];
  await con1.close();
  check('2.4 复习历史 3 条', logCount == 3, detail: logCount);

  final due = await duePhrases(nbPath);
  // id1 已复习（最后答错 => state=learn，下次到期在未来）=> 不在到期队列；另两条新短语到期
  check('2.4 到期队列只含到期的 2 条新短语', due.length == 2, detail: due.length);

  final s = await phraseStats(nbPath);
  check('2.4 统计 total=3', s['total'] == 3, detail: s);
  check('2.4 统计 new=2 / review=0（id1 最后答错）',
      s['new'] == 2 && s['review'] == 0, detail: s);
  check('2.4 统计 lapses=1', s['lapses'] == 1, detail: s);

  // 答对一条新短语后 review 计数 +1
  final spill = all.firstWhere((e) => e.phrase == 'spill the beans');
  await answerPhrase(nbPath, spill.id, easeGood);
  final s2 = await phraseStats(nbPath);
  check('2.4 答对后 review=1', s2['review'] == 1, detail: s2);

  // ================= 2.2 update / remove =================
  await updatePhrase(
    nbPath,
    id1,
    const PhraseInput(
      phrase: 'bite the bullet',
      meaning: '硬着头皮上（改）',
      lit: '咬子弹（改）',
      tags: '书面',
      examples: [PhraseExample(en: 'Only one example now.', zh: '只剩一条例句。')],
    ),
  );
  final updated = await getPhrase(nbPath, id1);
  check('2.2 update 字段生效', updated!.meaning == '硬着头皮上（改）');
  check('2.2 update 例句被替换为 1 条', updated.examples.length == 1);
  check('2.2 update 不动复习状态（state=1 ivl=1 lapses=1）',
      updated.state == 1 && updated.ivl == 1 && updated.lapses == 1,
      detail: '${updated.state}/${updated.ivl}/${updated.lapses}');

  var notFound = false;
  try {
    await updatePhrase(nbPath, 999999,
        const PhraseInput(phrase: 'ghost', meaning: 'm'));
  } on PhraseNotFoundError {
    notFound = true;
  }
  check('2.2 update 未找到报错', notFound);

  // ---- 多条使用场景：仍是单列 TEXT + '\n' 分隔（不新建表、无需迁移）----
  final sceneId = await addPhrase(
    nbPath,
    const PhraseInput(
      phrase: 'hear me out',
      meaning: '先别急着反驳，听我说完',
      scene: '争论 / 分歧时：对方正要反驳，先喊一句稳住局面\n'
          '分享大胆想法时：想发表不寻常观点前打预防针（如 "Hear me out, but I think..."）\n'
          '解释误会时：被误解，请求完整陈述',
    ),
  );
  final withScenes = await getPhrase(nbPath, sceneId);
  final readScenes = splitScenes(withScenes!.scene);
  check('1.2 三条场景原样落库（顺序不变）',
      readScenes.length == 3 &&
          readScenes.first.startsWith('争论') &&
          readScenes[1].contains('Hear me out') &&
          readScenes.last.startsWith('解释误会'),
      detail: readScenes.length);
  check('1.2 scene 单列以换行分隔',
      withScenes.scene.split('\n').length == 3, detail: withScenes.scene);

  // 归一化后改两条：不残留旧条、不产生空白分隔
  await updatePhrase(
    nbPath,
    sceneId,
    PhraseInput(
      phrase: 'hear me out',
      meaning: '先别急着反驳，听我说完',
      scene: joinScenes(['  改一  ', '', '  \t ', '改二']),
    ),
  );
  final afterSceneUpdate = await getPhrase(nbPath, sceneId);
  check('1.2 update 两条后不残留旧条',
      afterSceneUpdate!.scene == '改一\n改二', detail: afterSceneUpdate.scene);
  check('1.2 update 后拆条仍为 2',
      splitScenes(afterSceneUpdate.scene).length == 2);

  // 数据层兜底：绕过 UI 直接给 repo 传带空行/空白的原始文本，也必须被归一化
  await updatePhrase(
    nbPath,
    sceneId,
    const PhraseInput(
      phrase: 'hear me out',
      meaning: '先别急着反驳，听我说完',
      scene: '  甲  \n\n  \t\n乙\n',
    ),
  );
  final rawNormalized = await getPhrase(nbPath, sceneId);
  check('1.3 repo 层归一化空行（不依赖 UI 调用方）',
      rawNormalized!.scene == '甲\n乙', detail: rawNormalized.scene);
  await removePhrase(nbPath, sceneId);

  // 级联删除
  final okDel = await removePhrase(nbPath, id1);
  check('2.2 removePhrase=true', okDel);
  final con2 = await databaseFactory.openDatabase(nbPath,
      options: OpenDatabaseOptions(singleInstance: false));
  final exLeft = (await con2.rawQuery(
          'SELECT COUNT(*) c FROM phrase_examples WHERE phrase_id = ?', [id1]))
      .first['c'];
  final logLeft = (await con2.rawQuery(
          'SELECT COUNT(*) c FROM phrase_review_log WHERE phrase_id = ?', [id1]))
      .first['c'];
  await con2.close();
  check('2.2 级联删例句', exLeft == 0, detail: exLeft);
  check('2.2 级联删复习历史', logLeft == 0, detail: logLeft);
  check('2.2 重复移除=false', (await removePhrase(nbPath, id1)) == false);

  // ================= 3.1 / 3.2 导出 =================
  // 给剩余短语补一条例句 + 三条使用场景 + 多行典故，验证场景列表 / CSV 例句列
  const sceneLines = [
    '朋友追问时：不小心说漏了嘴',
    '新闻语境：记者 <提前> 抖出 & 内幕',
    '解释误会时：想坦白却又犹豫',
  ];
  const originText = '19 世纪酒吧：把豆子倒进锅里分豆子\n谁泄了密就少一份';
  await updatePhrase(
    nbPath,
    all.firstWhere((e) => e.phrase == 'spill the beans').id,
    PhraseInput(
      phrase: 'spill the beans',
      meaning: '泄露秘密',
      origin: originText,
      tags: '口语',
      scene: joinScenes(sceneLines),
      examples: const [PhraseExample(en: 'Tom spilled the beans.', zh: '汤姆说漏了嘴。')],
    ),
  );

  final apkgPath = p.join(tmp.path, 'phrases.apkg');
  final apkgReport = await exportPhraseApkg(nbPath, apkgPath);
  check('3.1 apkg 导出 2 条且文件非空',
      apkgReport.count == 2 && File(apkgPath).lengthSync() > 0, detail: apkgReport);
  check('3.1 短语 guid 与单词 guid 命名空间不同',
      phraseStableGuid('x') != word_apkg.stableGuid('x'));

  // 读回 apkg 内 collection.anki2 的字段（python 解 zip + sqlite，与 verify_export 同法）
  final apkgFields = await _readApkgFields(apkgPath, 'spill the beans');
  check('4.1 apkg 场景为 <ul class="scene-list"> + 3 个 <li>',
      apkgFields.scene.contains('<ul class="scene-list">') &&
          '<li>'.allMatches(apkgFields.scene).length == 3,
      detail: apkgFields.scene);
  check('4.1 apkg 字段 HTML 转义（< & 按字面显示）',
      apkgFields.scene.contains('&lt;提前&gt;') &&
          apkgFields.scene.contains('&amp;') &&
          !apkgFields.scene.contains('<提前>'),
      detail: apkgFields.scene);
  check('4.1 apkg 多行典故保留换行（<br>）',
      apkgFields.origin.contains('<br>') &&
          !apkgFields.origin.contains('\n'),
      detail: apkgFields.origin);
  check('4.1 apkg 卡片携带稳定 guid（重复导入更新同一张卡）',
      apkgFields.guid == phraseStableGuid('spill the beans'),
      detail: apkgFields.guid);

  final csvPath = p.join(tmp.path, 'phrases.csv');
  final csvReport = await exportPhraseCsv(nbPath, csvPath);
  final csvBytes = File(csvPath).readAsBytesSync();
  final csvText = File(csvPath).readAsStringSync();
  check('3.2 csv 导出 2 条', csvReport.count == 2, detail: csvReport);
  check('3.2 csv 带 BOM',
      csvBytes.length >= 3 &&
          csvBytes[0] == 0xEF &&
          csvBytes[1] == 0xBB &&
          csvBytes[2] == 0xBF,
      detail: csvBytes.take(3).toList());
  check('3.2 csv 表头正确', csvText.contains('phrase,lit,meaning,origin,scene,scene_tag,tags'));
  check('3.2 csv 含例句列内容', csvText.contains('Tom spilled the beans.'));
  check('4.2 csv 场景列按行保留三条',
      csvText.contains('"朋友追问时：不小心说漏了嘴\n新闻语境：记者 <提前> 抖出 & 内幕\n解释误会时：想坦白却又犹豫"'),
      detail: '多行单元格应被引号包裹');
  check('4.2 csv 场景列不被 HTML 转义（导出是纯文本）',
      csvText.contains('记者 <提前> 抖出 & 内幕') &&
          !csvText.contains('&lt;提前&gt;'));

  // ================= 3.3 按标签筛选导出（导出页短语集分组用）=================
  final oralApkgPath = p.join(tmp.path, 'phrases-oral.apkg');
  final oralReport = await exportPhraseApkg(nbPath, oralApkgPath, tag: '口语');
  final oralFields = await _readApkgFields(oralApkgPath, 'spill the beans');
  final otherFields = await _readApkgFields(oralApkgPath, 'once in a blue moon');
  check('3.3 按标签导出 apkg：只含该标签短语（笔记数 1/2）',
      oralReport.count == 1 && oralFields.noteCount == 1,
      detail: oralReport);
  check('3.3 按标签导出 apkg：读回命中该标签短语且不含另一条',
      oralFields.guid == phraseStableGuid('spill the beans') &&
          otherFields.guid.isEmpty,
      detail: '命中=${oralFields.guid} 另一条=${otherFields.guid}');

  final oralCsvPath = p.join(tmp.path, 'phrases-oral.csv');
  final oralCsvReport = await exportPhraseCsv(nbPath, oralCsvPath, tag: '口语');
  final oralCsvText = File(oralCsvPath).readAsStringSync();
  check('3.3 按标签导出 csv：只含该标签短语',
      oralCsvReport.count == 1 &&
          oralCsvText.contains('spill the beans') &&
          !oralCsvText.contains('once in a blue moon'),
      detail: oralCsvReport);

  // ================= 2.5 评分分级推进（端到端）=================
  // 独立新短语，避免影响上面的统计 / 导出断言
  final gradedId = await addPhrase(
    nbPath,
    const PhraseInput(phrase: 'break the ice', meaning: '打破僵局'),
  );
  final q4 = await answerPhrase(nbPath, gradedId, easeGood);
  check('2.5 新短语 记得 => 3（与 1 天短语同档）', q4.nextIvl == 3, detail: q4.nextIvl);
  final q5 = await answerPhrase(nbPath, gradedId, easeGood);
  check('2.5 间隔 3 记得 => 7', q5.nextIvl == 7, detail: q5.nextIvl);
  final q6 = await answerPhrase(nbPath, gradedId, easeHard);
  check('2.5 间隔 7 模糊 => 7 保持当前档', q6.nextIvl == 7, detail: q6.nextIvl);
  final q7 = await answerPhrase(nbPath, gradedId, easeEasy);
  check('2.5 间隔 7 简单 => 30 前进两档', q7.nextIvl == 30, detail: q7.nextIvl);
  final q8 = await answerPhrase(nbPath, gradedId, easeAgain);
  check('2.5 忘了 => 1 回第一档', q8.nextIvl == 1, detail: q8.nextIvl);

  // ================= 2.5b 撤销最近一次短语评分 =================
  Future<int> logCountOf(int pid) async {
    final c = await databaseFactory.openDatabase(nbPath,
        options: OpenDatabaseOptions(singleInstance: false));
    final n = (await c.rawQuery(
            'SELECT COUNT(*) c FROM phrase_review_log WHERE phrase_id = ?', [pid]))
        .first['c'] as int;
    await c.close();
    return n;
  }

  check('2.5b 撤销前 5 条历史', await logCountOf(gradedId) == 5);
  check('2.5b 撤销成功', await undoAnswerPhrase(nbPath, q8));
  final afterUndoPhrase = await getPhrase(nbPath, gradedId);
  check('2.5b 撤销后 ivl 回到 30',
      afterUndoPhrase!.ivl == 30, detail: afterUndoPhrase.ivl);
  check('2.5b 撤销后 reps 回到 4',
      afterUndoPhrase.reps == 4, detail: afterUndoPhrase.reps);
  check('2.5b 撤销后历史回到 4 条', await logCountOf(gradedId) == 4);
  // 不是最新一条 / 已回退过的回执 → 拒绝且无副作用
  check('2.5b 过期回执被拒', !(await undoAnswerPhrase(nbPath, q6)));
  check('2.5b 重复撤销被拒', !(await undoAnswerPhrase(nbPath, q8)));
  check('2.5b 被拒后历史仍为 4 条', await logCountOf(gradedId) == 4);

  // ================= 2.5c 按范围重置短语 =================
  final phrasePlan = await planPhraseReset(nbPath, all: true);
  check('2.5c 全量计划命中至少 1 条', phrasePlan.ids.isNotEmpty, detail: phrasePlan.ids.length);
  final appliedPhrase = await applyPhraseReset(nbPath, phrasePlan);
  check('2.5c 应用后删除历史行数与计划一致', appliedPhrase == phrasePlan.logRows,
      detail: '$appliedPhrase/${phrasePlan.logRows}');
  final statsReset = await phraseStats(nbPath);
  check('2.5c 重置后全部为新短语',
      statsReset['new'] == statsReset['total'] && statsReset['review'] == 0, detail: statsReset);
  check('2.5c 重置后历史清空', await logCountOf(gradedId) == 0);
  check('2.5c 重置后重新进入到期队列',
      (await duePhrases(nbPath)).length == statsReset['total'], detail: statsReset['total']);

  // ================= 1.2 旧库迁移（v1 -> v2）=================
  final tmp2 = await Directory.systemTemp.createTemp('lupa_phrase_mig_');
  final oldNb = p.absolute(p.join(tmp2.path, 'notebook.sqlite'));
  final dbOld = await databaseFactory.openDatabase(oldNb,
      options: OpenDatabaseOptions(singleInstance: false));
  await dbOld.execute('''
    CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, n_id TEXT UNIQUE NOT NULL, m_id INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL DEFAULT 0, tags TEXT NOT NULL DEFAULT '', flds TEXT NOT NULL, sfld TEXT NOT NULL, csum INTEGER NOT NULL DEFAULT 0, flags INTEGER NOT NULL DEFAULT 0, data TEXT NOT NULL DEFAULT '');
    CREATE TABLE cards (id INTEGER PRIMARY KEY AUTOINCREMENT, c_id TEXT UNIQUE NOT NULL, n_id INTEGER NOT NULL, did INTEGER NOT NULL DEFAULT 1, ord INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL DEFAULT 0, type INTEGER NOT NULL DEFAULT 0, queue INTEGER NOT NULL DEFAULT 0, due INTEGER NOT NULL, ivl INTEGER NOT NULL DEFAULT 0, factor INTEGER NOT NULL DEFAULT 0, reps INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0, left INTEGER NOT NULL DEFAULT 0, odue INTEGER NOT NULL DEFAULT 0, odid INTEGER NOT NULL DEFAULT 0, flags INTEGER NOT NULL DEFAULT 0, data TEXT NOT NULL DEFAULT '');
    CREATE TABLE revlog (id INTEGER PRIMARY KEY AUTOINCREMENT, r_id INTEGER NOT NULL, cid INTEGER NOT NULL, usn INTEGER NOT NULL DEFAULT 0, ease INTEGER NOT NULL, ivl INTEGER NOT NULL, last_ivl INTEGER NOT NULL, factor INTEGER NOT NULL, time INTEGER NOT NULL, type INTEGER NOT NULL);
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    INSERT INTO meta (key, value) VALUES ('schema_version', '1');
    INSERT INTO notes (n_id, m_id, mod, flds, sfld) VALUES ('1', 1, 0, 'abandon', 'abandon');
  ''');
  await dbOld.close();

  await ensureNotebookDb(oldNb);
  final dbMig = await databaseFactory.openDatabase(oldNb,
      options: OpenDatabaseOptions(singleInstance: false));
  final migTables = (await dbMig.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"))
      .map((r) => r['name'] as String)
      .toSet();
  final migMeta = {
    for (final r in await dbMig.query('meta')) r['key'] as String: r['value']
  };
  final wordNotes = (await dbMig.rawQuery('SELECT COUNT(*) c FROM notes')).first['c'];
  await dbMig.close();
  check('1.2 旧库补齐三表', migTables.containsAll(['phrases', 'phrase_examples', 'phrase_review_log']));
  check('1.2 旧库版本升到 2', migMeta['schema_version'] == '2', detail: migMeta);
  check('1.2 单词 notes 未受影响', wordNotes == 1, detail: wordNotes);

  await tmp.delete(recursive: true);
  await tmp2.delete(recursive: true);
  stdout.writeln(failures == 0 ? 'ALL PASS' : 'FAILURES: $failures');
}

/// apkg 里某条短语笔记的字段（已把真实换行换成 `\n` 两个字，便于按 ';;' 切分）。
class _ApkgFields {
  final int noteCount;
  final String guid;
  final String scene;
  final String origin;
  const _ApkgFields(this.noteCount, this.guid, this.scene, this.origin);
}

/// 读回 apkg：python 解 zip → `collection.anki2` → notes.flds（与 verify_export 同法）。
Future<_ApkgFields> _readApkgFields(String path, String phrase) async {
  const script = r'''
import sys
import zipfile, sqlite3, tempfile, os
z = zipfile.ZipFile(sys.argv[1])
tmp = tempfile.mktemp(suffix=".anki2")
open(tmp, "wb").write(z.read("collection.anki2"))
con = sqlite3.connect(tmp)
rows = con.execute("SELECT guid, flds FROM notes").fetchall()
con.close(); os.remove(tmp)
guid = scene = origin = ""
for (_guid, flds) in rows:
    parts = flds.split("\x1f")
    if parts and parts[0] == sys.argv[2]:
        guid = _guid
        origin = parts[3] if len(parts) > 3 else ""
        scene = parts[4] if len(parts) > 4 else ""
        break
print(";;".join([str(len(rows)), guid, scene.replace("\n", "\\n"), origin.replace("\n", "\\n")]))
''';
  final tmpScript = File(p.join(Directory.systemTemp.path, 'lupa_phrase_apkg_check.py'))
    ..writeAsStringSync(script);
  final result =
      await Process.run('python', ['-X', 'utf8', tmpScript.path, path, phrase],
          stdoutEncoding: utf8);
  await tmpScript.delete();
  final parts = result.stdout.toString().trim().split(';;');
  if (parts.length < 4) {
    return _ApkgFields(0, '', '解析失败: ${result.stdout}${result.stderr}', '');
  }
  return _ApkgFields(
      int.tryParse(parts[0]) ?? 0,
      parts[1],
      parts[2].replaceAll('\\n', '\n'),
      parts[3].replaceAll('\\n', '\n'));
}
