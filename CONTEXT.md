# CI/CD 治理語彙

本文件定義這個部署工具的治理用語，避免把「有執行資安掃描」與「GitHub 已強制審核」混為一談。

## Language

**核心開發模式（Phase 1）**:
僅核心且已受信任的開發人員可存取 repo，GitHub 不強制分支保護、審核或 Code Owner 核准。
_Avoid_: 無安全管制、關閉資安掃描

**協作者治理模式（Phase 2）**:
Repo 開放給非核心成員後，由 GitHub 強制保護 `main`、必要狀態檢查、必要審核與 Code Owner 核准。
_Avoid_: 只有管理層才能開發、關閉核心開發權限

**PR 資安檢查**:
PR 開啟或更新時執行的 Gitleaks 與 Vertex AI 掃描；Phase 1 提供開發回饋，Phase 2 則是合併必要條件。
_Avoid_: 部署關卡

**部署關卡**:
`main` 收到新 commit 後由 Cloud Build 重新執行的雙層掃描；任一層失敗就停止建置與部署。
_Avoid_: PR 資安檢查

**治理藍圖**:
Phase 1 保留在 repo 中、供 Phase 2 啟用的 `CODEOWNERS` 與管理規格；藍圖本身不代表 GitHub 已強制審核。
_Avoid_: 已啟用的 Code Owner 保護
