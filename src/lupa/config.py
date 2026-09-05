"""Lupa 配置 — 服务商 URL 全部走配置文件，不硬编码（Q4 拍板）。

优先级：LUPA_HOME/config.json > 内置默认。
纯函数约束 #2：本模块不读 stdin / 不写 stdout。
"""
from __future__ import annotations

import json
from pathlib import Path

# 内置默认（首次运行时原样写入 config.json，用户可自行修改）
DEFAULT_CONFIG: dict = {
    "default_provider": "youdao",
    "providers": {
        "youdao": {
            "phonetic_url": (
                "https://dict.youdao.com/jsonapi?jsonversion=2&client=mobile"
                "&q={word}&dicts=%7B%22count%22%3A99%2C%22dicts%22%3A%5B%5B%22ec%22%5D%5D%7D"
            ),
            # {accent} = 1(英音) / 2(美音)
            "tts_url": "https://dict.youdao.com/dictvoice?audio={word}&type={accent}",
        }
    },
}

CONFIG_FILE = "config.json"


def load_config(data_home: str | Path) -> dict:
    """加载配置。文件不存在则写入默认配置后返回默认。"""
    home = Path(data_home)
    p = home / CONFIG_FILE
    if not p.exists():
        home.mkdir(parents=True, exist_ok=True)
        p.write_text(
            json.dumps(DEFAULT_CONFIG, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return dict(DEFAULT_CONFIG)
    user = json.loads(p.read_text(encoding="utf-8"))
    # 浅合并：用户文件只需写想覆盖的键
    merged = dict(DEFAULT_CONFIG)
    merged.update(user)
    return merged


def provider_config(config: dict, provider: str | None = None) -> dict:
    """取指定 provider 的 URL 模板。"""
    name = provider or config.get("default_provider", "youdao")
    providers = config.get("providers", {})
    if name not in providers:
        raise KeyError(f"配置中没有该 provider: {name}")
    return providers[name]
