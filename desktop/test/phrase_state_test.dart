// 短语集 AppState 层：CRUD 后列表/统计刷新、复习推进、导出（临时目录，不碰真实数据）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/phrase/repo.dart';
import 'package:lupa/state/app_state.dart';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_phrase_state_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

void main() {
  late Directory cfgHome;
  late Directory dataDir;

  setUp(() {
    cfgHome = _tmp('cfg');
    dataDir = _tmp('data');
    setConfigHomeOverride(cfgHome.path);
    setDataHomeOverride(dataDir.path);
  });

  tearDown(() {
    clearConfigHomeOverride();
    clearDataHomeOverride();
    cfgHome.deleteSync(recursive: true);
    dataDir.deleteSync(recursive: true);
  });

  Future<AppState> initState() async {
    File(p.join(cfgHome.path, configFile)).writeAsStringSync(json.encode({
      'default_provider': 'youdao',
      'providers': {'youdao': {'phonetic_url': 'u', 'tts_url': 't'}},
      'settings': {'theme': 'system'},
    }), encoding: utf8);
    final state = AppState();
    await state.init();
    return state;
  }

  test('4.1 addPhraseEntry 后列表 / 统计 / 标签刷新', () async {
    final state = await initState();
    expect(state.phraseEntries, isEmpty);
    expect(state.phraseStats['total'], 0);

    await state.addPhraseEntry(const PhraseInput(
      phrase: 'bite the bullet',
      meaning: '硬着头皮上',
      tags: '口语, 通用',
    ));

    expect(state.phraseEntries.length, 1);
    expect(state.phraseEntries.first.phrase, 'bite the bullet');
    expect(state.phraseStats['total'], 1);
    expect(state.phraseStats['new'], 1);
    expect(state.phraseTags, containsAll(['口语', '通用']));
  });

  test('4.1 updatePhraseEntry / removePhraseEntry 刷新列表', () async {
    final state = await initState();
    final id = await state.addPhraseEntry(
        const PhraseInput(phrase: 'spill the beans', meaning: '泄密'));

    await state.updatePhraseEntry(
        id, const PhraseInput(phrase: 'spill the beans', meaning: '泄露秘密'));
    expect(state.phraseEntries.first.meaning, '泄露秘密');

    expect(await state.removePhraseEntry(id), true);
    expect(state.phraseEntries, isEmpty);
    expect(state.phraseStats['total'], 0);
  });

  test('4.1 answerPhraseCard 推进调度并移出到期队列', () async {
    final state = await initState();
    final id = await state.addPhraseEntry(
        const PhraseInput(phrase: 'once in a blue moon', meaning: '千载难逢'));

    expect(state.phraseDue.length, 1);
    final rec = await state.answerPhraseCard(id, 3);
    expect(rec.nextIvl, 3); // 新短语记得：按「即将进入第一档」起步再前进一档

    await state.refresh();
    final e = state.phraseEntries.first;
    expect(e.state, 2); // review
    expect(e.ivl, 3);
    expect(e.reps, 1);
    expect(state.phraseDue, isEmpty); // 下次到期在未来
    expect(state.phraseStats['review'], 1);
  });

  test('4.1 exportPhraseApkgTo / exportPhraseCsvTo 产出文件', () async {
    final state = await initState();
    await state.addPhraseEntry(const PhraseInput(
      phrase: 'the elephant in the room',
      meaning: '房间里的大象',
      examples: [PhraseExample(en: 'Let us address it.', zh: '咱们直说吧。')],
    ));

    final apkg = await state.exportPhraseApkgTo(p.join(dataDir.path, 'p.apkg'));
    expect(apkg.count, 1);
    expect(File(apkg.path).existsSync(), true);
    expect(apkg.sizeBytes, greaterThan(0));

    final csv = await state.exportPhraseCsvTo(p.join(dataDir.path, 'p.csv'));
    expect(csv.count, 1);
    expect(File(csv.path).existsSync(), true);
  });
}
