# -*- coding: utf-8 -*-
"""
agency-agents 匹配算法测试。
按 SKILL.md 定义的算法实现（keywords_en 词边界 + 可选复数 s；keywords_zh 中文子串），
验证误触发修复（词边界替代裸子串）与关键词收窄效果。

用法: python tests/test_mapping.py
"""
import json
import os
import re
import sys

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPPINGS_PATH = os.path.join(SKILL_DIR, "tool-mappings.json")


def load_mappings():
    with open(MAPPINGS_PATH, encoding="utf-8-sig") as f:
        return json.load(f)["mappings"]


def match(text, mappings):
    """与 SKILL.md 匹配算法一致：英文词边界正则 + 中文子串。"""
    hits = []
    for entry in mappings:
        en_hit = any(
            re.search(r"\b" + re.escape(kw) + r"s?\b", text, re.IGNORECASE)
            for kw in entry.get("keywords_en", [])
        )
        zh_hit = any(kw in text for kw in entry.get("keywords_zh", []))
        if en_hit or zh_hit:
            hits.extend(entry["roles"])
    return sorted(set(hits))


# (描述, 输入文本, 期望必含 role, 期望必不含 role 列表)
CASES = [
    # ---- 正向命中 ----
    ("代码审查命中", "请帮我 review 这个 PR", "code-reviewer", []),
    ("bug 修复命中", "修复 create 流程里的一个 bug", "test-automation-engineer", ["code-reviewer"]),
    ("api+性能命中", "优化一下 api 接口的响应性能", "performance-benchmarker", []),
    ("部署命中", "把这个服务部署到 k8s 集群", "devops-automator", []),
    ("财务模型命中", "帮我做一个财务模型和估值分析", "financial-analyst", []),
    ("UI 设计命中", "帮我设计一个移动端的登录页面", "ui-designer", []),
    ("测试命中", "跑一遍测试用例并检查覆盖率", "test-automation-engineer", []),
    ("roadmap 命中", "整理一下产品 roadmap 和需求优先级", "product-manager", []),
    ("重构命中", "把这段遗留代码重构一下", "code-reviewer", []),
    ("文档命中", "给这个模块写一份使用文档", "technical-writer", []),
    ("agent 编排命中", "用 multi-agent 编排一个调研流程", "agents-orchestrator", []),
    ("skill 命中", "帮我优化这个 skill 的匹配逻辑", "prompt-engineer", []),
    ("cr 缩写命中", "把 CR 里提的意见都处理掉", "code-reviewer", []),
    # ---- 负向：误触发修复验证（旧裸子串会误命中，新词边界必须不命中）----
    ("preview 不命中 review", "preview 一下最新的改动效果", "UNUSED", ["code-reviewer"]),
    ("prefix 不命中 fix", "prefix 和 suffix 的命名规范", "UNUSED", ["test-automation-engineer"]),
    ("latest 不命中 test", "latest 版本有什么变化", "UNUSED", ["test-automation-engineer"]),
    ("capital 不命中 api", "capital 是哪个国家的首都", "UNUSED", ["api-tester"]),
    ("therapist 不命中 api", "我认识一位 therapist", "UNUSED", ["api-tester"]),
    ("create 不命中 cr/review", "create 一个新的项目", "UNUSED", ["code-reviewer"]),
    ("fixture 不命中 fix", "这个 fixture 文件怎么用", "UNUSED", ["test-automation-engineer"]),
    ("hotfix 不误杀 fix", "发一个 hotfix 紧急修复", "test-automation-engineer", []),
    ("复数 tests 命中", "run the tests now", "test-automation-engineer", []),
    ("model 不误触发 finance", "这个 LLM 模型效果如何", "UNUSED", ["financial-analyst"]),
    ("agent 单字不命中编排", "这是个通用 agent", "UNUSED", ["agents-orchestrator"]),
    # ---- 空文本 ----
    ("无关键词返回空", "你好", "UNUSED", []),
]


def run():
    mappings = load_mappings()
    passed = failed = 0
    for desc, text, must_have, must_not_have in CASES:
        roles = match(text, mappings)
        ok = True
        if must_have != "UNUSED" and must_have not in roles:
            ok = False
        bad = [r for r in must_not_have if r in roles]
        if bad:
            ok = False
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {desc}: 命中={roles}")
        if not ok:
            print(f"       期望必含={must_have}, 期望不含={must_not_have}")
            failed += 1
        else:
            passed += 1

    print(f"\n结果: {passed} 通过, {failed} 失败 / 共 {passed + failed} 用例")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(run())
