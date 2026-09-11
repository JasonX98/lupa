// 单元测试：使用场景文本归一化纯函数（splitScenes / joinScenes）。
// 契约见 openspec/changes/phrase-scene-list：一条场景 = 一行，'\n' 只出现在条与条之间。
import 'package:flutter_test/flutter_test.dart';
import 'package:lupa/phrase/scene_text.dart';

void main() {
  test('6.1 空字符串拆出 0 条', () {
    expect(splitScenes(''), isEmpty);
  });

  test('6.1 仅空白拆出 0 条', () {
    expect(splitScenes('   '), isEmpty);
    expect(splitScenes('\n\n  \n\t\n'), isEmpty);
  });

  test('6.1 首尾空行与连续空行被丢弃', () {
    expect(splitScenes('\n\na\n\n\nb\n\n'), ['a', 'b']);
  });

  test('6.1 正常三条保持顺序与内容', () {
    const raw = '争论 / 分歧时：对方正要反驳，先喊一句稳住局面\n'
        '分享大胆想法时：想发表不寻常观点前打预防针（如 "Hear me out, but I think..."）\n'
        '解释误会时：被误解，请求完整陈述';
    final scenes = splitScenes(raw);
    expect(scenes.length, 3);
    expect(scenes.first, '争论 / 分歧时：对方正要反驳，先喊一句稳住局面');
    expect(scenes[1], contains('Hear me out'));
    expect(scenes.last, '解释误会时：被误解，请求完整陈述');
  });

  test('6.1 逐条 trim（含 CRLF 与首尾空格）', () {
    expect(splitScenes('  a  \r\n\tb\t\r\n'), ['a', 'b']);
  });

  test('6.1 join 丢弃空白条目', () {
    expect(joinScenes(['a', '', '   ', 'b']), 'a\nb');
    expect(joinScenes(const <String>[]), '');
  });

  test('6.1 join 把条目内换行拆分（输入换行即分条）', () {
    expect(joinScenes(['a\nb']), 'a\nb');
    expect(joinScenes(['a\n\nb']), 'a\nb');
    expect(joinScenes(['  a\r\nb  ']), 'a\nb');
  });

  test('6.1 join -> split 往返无损', () {
    const raw = 'a\nb\nc';
    expect(joinScenes(splitScenes(raw)), raw);
    expect(splitScenes(joinScenes(['x', 'y', 'z'])), ['x', 'y', 'z']);
  });
}
