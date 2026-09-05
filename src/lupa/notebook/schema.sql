-- ============================================================================
-- Lupa / 璐帕 — 用户生词本 + 媒体缓存 schema (v1)
--
-- 跨语言友好约束 #1：本文件仅使用 SQLite >= 3.38 标准 SQL。
--   - 不使用 JSON1 扩展、STRICT 表、RETURNING 子句、WITHOUT ROWID、
--     virtual table、generated columns、窗口函数（SQLite 3.25+ 标准除外）
--   - 兼容目标：Python sqlite3 (3.39+)、Flutter sqflite (3.39+)
--   - 如确需上述特性，必须在此文件顶部注释「此处需 SQLite >= X.Y」
--     并在 README 中说明 Flutter 端兼容情况。
--
-- 设计原则：
--   - notes / cards / revlog 三表结构抄自 Anki schema11.sql（行业事实标准），
--     以便导出 .apkg 时字段直接复用。
--   - 复习历史与卡片状态分离（revlog 单独成表），便于调算法与导出。
--   - media_cache 三表用三段式缓存键 (provider:word:format)，
--     便于切换音标/TTS 服务商而无需迁移数据（跨语言友好约束 #3）。
--   - 所有主键用 INTEGER 自增，对外 ID 用 TEXT（Anki 风格 hex / uuid），
--     便于 Python 与 Flutter 双向读写。
-- ============================================================================

-- ----- Anki 兼容三表 -----

CREATE TABLE notes (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    n_id          TEXT    UNIQUE NOT NULL,
    m_id          INTEGER NOT NULL,
    mod           INTEGER NOT NULL,
    usn           INTEGER NOT NULL DEFAULT 0,
    tags          TEXT    NOT NULL DEFAULT '',
    flds          TEXT    NOT NULL,
    sfld          TEXT    NOT NULL,
    csum          INTEGER NOT NULL DEFAULT 0,
    flags         INTEGER NOT NULL DEFAULT 0,
    data          TEXT    NOT NULL DEFAULT ''
);

CREATE INDEX idx_notes_sfld ON notes(sfld);
CREATE INDEX idx_notes_csum ON notes(csum);

CREATE TABLE cards (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    c_id          TEXT    UNIQUE NOT NULL,
    n_id          INTEGER NOT NULL,
    did           INTEGER NOT NULL DEFAULT 1,
    ord           INTEGER NOT NULL,
    mod           INTEGER NOT NULL,
    usn           INTEGER NOT NULL DEFAULT 0,
    type          INTEGER NOT NULL DEFAULT 0,   -- CardType
    queue         INTEGER NOT NULL DEFAULT 0,   -- CardQueue
    due           INTEGER NOT NULL,
    ivl           INTEGER NOT NULL DEFAULT 0,
    factor        INTEGER NOT NULL DEFAULT 0,
    reps          INTEGER NOT NULL DEFAULT 0,
    lapses        INTEGER NOT NULL DEFAULT 0,
    left          INTEGER NOT NULL DEFAULT 0,
    odue          INTEGER NOT NULL DEFAULT 0,
    odid          INTEGER NOT NULL DEFAULT 0,
    flags         INTEGER NOT NULL DEFAULT 0,
    data          TEXT    NOT NULL DEFAULT '',
    FOREIGN KEY (n_id) REFERENCES notes(id) ON DELETE CASCADE
);

CREATE INDEX idx_cards_n_id       ON cards(n_id);
CREATE INDEX idx_cards_did_due    ON cards(did, due);
CREATE INDEX idx_cards_queue      ON cards(queue);

CREATE TABLE revlog (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    r_id          INTEGER NOT NULL,
    cid           INTEGER NOT NULL,
    usn           INTEGER NOT NULL DEFAULT 0,
    ease          INTEGER NOT NULL,
    ivl           INTEGER NOT NULL,
    last_ivl      INTEGER NOT NULL,
    factor        INTEGER NOT NULL,
    time          INTEGER NOT NULL,
    type          INTEGER NOT NULL  -- RevlogReviewKind
);

CREATE INDEX idx_revlog_cid  ON revlog(cid);
CREATE INDEX idx_revlog_r_id ON revlog(r_id);

-- ----- Lupa 专属三表 -----

CREATE TABLE phonetic_cache (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    cache_key     TEXT    UNIQUE NOT NULL,    -- 三段式: provider:word:fmt
    word          TEXT    NOT NULL,
    provider      TEXT    NOT NULL,
    fmt           TEXT    NOT NULL,
    url           TEXT    NOT NULL,
    phonetic      TEXT    NOT NULL,
    fetched_at    INTEGER NOT NULL,
    hit_count     INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_phonetic_key  ON phonetic_cache(cache_key);
CREATE INDEX idx_phonetic_word ON phonetic_cache(word);

CREATE TABLE audio_cache (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    cache_key     TEXT    UNIQUE NOT NULL,    -- 三段式: provider:word:fmt
    word          TEXT    NOT NULL,
    provider      TEXT    NOT NULL,
    fmt           TEXT    NOT NULL,
    url           TEXT    NOT NULL,
    blob          BLOB    NOT NULL,
    size_bytes    INTEGER NOT NULL,
    fetched_at    INTEGER NOT NULL,
    hit_count     INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_audio_key  ON audio_cache(cache_key);
CREATE INDEX idx_audio_word ON audio_cache(word);

CREATE TABLE ai_cache (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    cache_key       TEXT    UNIQUE NOT NULL,  -- 三段式: provider:word:feature
    word            TEXT    NOT NULL,
    provider        TEXT    NOT NULL,
    feature         TEXT    NOT NULL,
    prompt_version  INTEGER NOT NULL,
    payload         TEXT    NOT NULL,
    fetched_at      INTEGER NOT NULL,
    hit_count       INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_ai_key  ON ai_cache(cache_key);
CREATE INDEX idx_ai_word ON ai_cache(word);

-- ----- meta 表 -----

CREATE TABLE meta (
    key    TEXT PRIMARY KEY,
    value  TEXT NOT NULL
);

INSERT INTO meta (key, value) VALUES ('schema_version', '1');
INSERT INTO meta (key, value) VALUES ('lupa_version', '0.1.0');
INSERT INTO meta (key, value) VALUES ('created_at', strftime('%s', 'now'));
