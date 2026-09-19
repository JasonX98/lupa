/// Lupa 版本号 —— 以 `desktop/pubspec.yaml` 的 `version` 为唯一事实源（x.y.z）。
///
/// 这个常量是设置页脚显示的值，也是写进生词本库 `meta.lupa_version` 的值
/// （见 notebook_db.dart 的 _stampAppVersion）。
///
/// 它**必须**与 pubspec.yaml 一致 —— 手抄常量必然漂移，所以有
/// test/version_test.dart 读 pubspec.yaml 做断言。发版时两处一起改。
const String lupaVersion = '0.3.0';
