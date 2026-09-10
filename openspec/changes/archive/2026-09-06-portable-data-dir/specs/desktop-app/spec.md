## ADDED Requirements

### Requirement: 默认数据目录
系统 SHALL 在未设置 `LUPA_HOME` 环境变量时，将数据目录默认为可执行文件所在目录下的 `lupa_data/`；若设置了 `LUPA_HOME`，则以其为准。系统 SHALL 不再回退到用户主目录下的 `~/.lupa`。

#### Scenario: 未设环境变量时使用便携目录
- **WHEN** 用户未设置 `LUPA_HOME` 环境变量并启动应用
- **THEN** 系统在可执行文件旁的 `lupa_data/` 目录读写词库与生词本数据

#### Scenario: 环境变量优先
- **WHEN** 用户设置了 `LUPA_HOME` 环境变量
- **THEN** 系统在该环境变量指向的目录读写数据

#### Scenario: 无 `~/.lupa` 回退
- **WHEN** 用户未设置 `LUPA_HOME` 且可执行文件旁没有 `lupa_data/`
- **THEN** 系统不在用户主目录的 `~/.lupa` 下读写数据，而是在 `lupa_data/` 按需创建目录
