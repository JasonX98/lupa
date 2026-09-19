// 词性解析纯函数测试。用例取自真实 dict.sqlite 的 translation 原文。
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/ai/pos.dart';

void main() {
  group('parsePos：多词性词', () {
    test('record 解析出 4 组且保持释义行顺序', () {
      const t = 'n. 记录, 履历, 档案, 审判记录, 最高纪录, 唱片\n'
          'vt. 记录, 记载, 标明, 将...录音\n'
          'vi. 记录, 录音, 可被录音\n'
          'a. 创纪录的';
      expect(parsePos(t), ['n.', 'vt.', 'vi.', 'a.']);
    });

    test('serene 解析出 a. 与 n.', () {
      expect(parsePos('a. 宁静的, 沉着的, 安详的, 晴朗的\nn. 晴朗, 平静'),
          ['a.', 'n.']);
    });

    test('present 解析出 4 组', () {
      const t = 'n. 现在, 礼品, 瞄准\n'
          'a. 现在的, 出席的\n'
          'vt. 介绍, 赠与, 提出, 呈现, 上演\n'
          'vi. 举枪瞄准';
      expect(parsePos(t), ['n.', 'a.', 'vt.', 'vi.']);
    });
  });

  group('parsePos：0 组的来源（无词性前缀）', () {
    test('Mr：第一行无前缀、第二行领域标签，均为 0 组', () {
      expect(parsePos('先生\n[计] 存储器回收程序, 多重请求'), isEmpty);
    });

    test('online：只有领域标签行', () {
      expect(parsePos('[计] 联机'), isEmpty);
    });

    test('空字符串与纯空白', () {
      expect(parsePos(''), isEmpty);
      expect(parsePos('   \n\n  \t '), isEmpty);
    });
  });

  group('parsePos：前缀与正文的边界', () {
    test('前缀后面紧跟领域标签、无空格也能取到词性', () {
      expect(parsePos('n. [棒](投手投出的)快球'), ['n.']);
    });

    test('前缀在行中夹带领域标签不影响取词性', () {
      expect(parsePos('n. [法]归寡妇所得的亡夫遗产的三分之一；[商]（商品的）三等品'),
          ['n.']);
    });

    test('CRLF：a 的词条含 \\r\\n，行尾 \\r 不影响解析', () {
      expect(parsePos('第一个字母 A; 一个; 第一的\r\nart. [计] 累加器, 加法器'),
          ['art.']);
    });

    test('一行里的第二个 token 不被当作词性（只看行首）', () {
      expect(parsePos('vt. 见 n. 条'), ['vt.']);
    });
  });

  group('parsePos：白名单边界', () {
    test('interj. 是 6 字母 token，必须能取到', () {
      expect(parsePos('interj. 喂, 嘿'), ['interj.']);
    });

    test('art. 与 pref. 在白名单内（全量统计发现的缺口）', () {
      expect(parsePos('art. 那'), ['art.']);
      expect(parsePos('pref. 宏'), ['pref.']);
    });

    test('na. 刻意不在白名单：未在词库出现过的 token 不当词性', () {
      expect(posWhitelist.contains('na.'), isFalse);
      expect(parsePos('na. 洪水'), isEmpty);
    });

    test('大小写不折叠：N. 不在白名单', () {
      expect(parsePos('N. 记录'), isEmpty);
    });

    test('白名单外的字母 token（形如词性但不是）被丢弃', () {
      expect(parsePos('zzz. 乱码'), isEmpty);
      expect(parsePos('e.g. 例如'), isEmpty);
    });

    test('无句点的行首字母不算词性', () {
      expect(parsePos('n 记录'), isEmpty);
    });
  });

  group('parsePos：去重与顺序', () {
    test('同一词性重复出现只收一次，且位置取首次出现处', () {
      expect(parsePos('n. 甲\nv. 乙\nn. 丙'), ['n.', 'v.']);
    });

    test('空白行不产生空词性', () {
      expect(parsePos('n. 甲\n\n   \nvt. 乙'), ['n.', 'vt.']);
    });
  });

  group('posWhitelist 契约', () {
    test('恰好 18 种，且全部以句点结尾、长度不超过 6 字母 + 句点', () {
      expect(posWhitelist.length, 18);
      for (final t in posWhitelist) {
        expect(t.endsWith('.'), isTrue, reason: t);
        expect(t.length, lessThanOrEqualTo(7), reason: t);
      }
    });
  });

  group('enrichMode：三类分流（实测构成 full 28492 / degraded 1417 / none 91）', () {
    test('解析出词性 -> full', () {
      expect(enrichMode('record', 'n. 记录\nvt. 记录'), EnrichMode.full);
      expect(enrichMode('serene', 'a. 宁静的\nn. 晴朗'), EnrichMode.full);
    });

    test('0 组且全小写 -> degraded（内容词，降级补齐）', () {
      expect(enrichMode('online', '[计] 联机'), EnrichMode.degraded);
      expect(enrichMode('funding', '[经] 债务转期'), EnrichMode.degraded);
      expect(enrichMode('etc', '及其他, 等等'), EnrichMode.degraded);
      expect(enrichMode('download', '[计] 下载'), EnrichMode.degraded);
    });

    test('0 组且含大写 -> none（缩写/专名，不发起请求）', () {
      expect(enrichMode('Mr', '先生\n[计] 存储器回收程序'), EnrichMode.none);
      expect(enrichMode('TV', '电视\n[计] 电视, 转移向量'), EnrichMode.none);
      expect(enrichMode('DNA', '脱氧核糖核酸'), EnrichMode.none);
      expect(enrichMode('Palestinian', '[经] 巴勒斯坦的'), EnrichMode.none);
    });

    test('有词性时优先 full，大写与否不影响', () {
      // 词库里没有这种组合，但契约要明确：词性优先于大小写判定
      expect(enrichMode('DNA', 'n. 脱氧核糖核酸'), EnrichMode.full);
    });

    test('全大写缩写且无词性 -> none', () {
      expect(enrichMode('HMO', '[医] 健康维护组织'), EnrichMode.none);
    });
  });
}
