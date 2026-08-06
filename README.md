# agency-agents

将 [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents) 的 140+ 专家角色封装为可自动调度的**角色推荐 Skill**。调用后自动分析当前任务，选出最合适的 1~3 个专家角色，让当前 Agent 立即以专家身份继续工作。

## 功能

- **自动角色调度**：关键词粗筛（词边界匹配，杜绝 `fix` 命中 `prefix` 类误触发）→ LLM 精排（最多 3 角色，强制职责边界）
- **双数据源**：在线拉取上游 255 个角色；离线使用本地 `roles-index.json` 缓存兜底
- **缓存式同步**：每次在线调用自动刷新缓存；`sync.ps1` 支持全量重建
- **中文体验**：`zh-overrides.json` 提供角色中文名/简介覆盖

## 文件结构

```
agency-agents/
├── SKILL.md                  # Skill 主文件（触发元数据 + 完整工作流）
├── tool-mappings.json        # 任务关键词 → 候选部门/角色 映射
├── roles-index.json          # 角色索引缓存（sync.ps1 自动生成，勿手改）
├── zh-overrides.json         # slug → 中文名/简介 覆盖（手动维护）
├── sync.ps1                  # 上游同步脚本（重建索引 + slug 校验）
├── tests/test_mapping.py     # 匹配算法回归测试
└── .github/workflows/sync.yml# 每周自动同步上游角色
```

## 安装（分享给他人）

Skill 为纯文件、零外部依赖，拷贝目录即可：

| 平台 | 目标目录 |
|------|---------|
| Trae CN | `%USERPROFILE%\.trae-cn\skills\agency-agents\` |
| CodeBuddy CN | `%USERPROFILE%\.codebuddy\skills\agency-agents\` |
| Codex | `%USERPROFILE%\.codex\skills\agency-agents\` |

```powershell
# 以 Trae CN 为例
Copy-Item -Recurse .\agency-agents "$env:USERPROFILE\.trae-cn\skills\"
```

重启 IDE 后自动识别。手动触发：`Use Skill: agency-agents`；自动触发：任务描述命中 description 中的场景关键词（代码审查、UI/UX、安全审计、测试等）。

## 使用

直接让 Agent 处理需要专业身份的任务即可，Skill 会自动：

1. 解析任务关键词与领域
2. 规则粗筛候选角色（`tool-mappings.json`）
3. LLM 精排 1~3 个角色（含职责、边界、理由）
4. 输出角色摘要并立即以专家身份继续执行

## 同步上游角色

```powershell
# 全量重建（clone 上游 → 解析 frontmatter → 合并中文覆盖 → 校验 slug）
powershell -ExecutionPolicy Bypass -File .\sync.ps1

# 网络不佳时可用镜像或本地副本：
powershell -File .\sync.ps1 -RepoUrl "https://github.com/msitarzewski/agency-agents"
```

仓库已配置 GitHub Actions 每周一自动同步 `roles-index.json`（见 `.github/workflows/sync.yml`）。

## 测试

```powershell
python .\tests\test_mapping.py   # 25 个匹配算法用例，验证误触发修复
```

## 常见问题

- **映射引用的角色不存在**：运行 `sync.ps1`，步骤 6 会校验 `tool-mappings.json` 中所有 slug 是否存在于索引
- **新增映射引用新角色**：同步后需在 `zh-overrides.json` 补充中文名，否则显示英文
- **github.com 访问不稳定**：`sync.ps1` 支持传入本地镜像路径（`-RepoUrl` 参数）

## 许可

本 Skill 是对上游 [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents) 的封装，角色数据版权归上游所有。
