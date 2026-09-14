# cicd-pilot-service

這是 GitHub 協作者程式碼經雙層資安檢查後部署到 GCP Cloud Run 的試點
repo。服務本身只有 `/` 與 `/healthz`；重點是驗證 PR gate、Artifact
Registry、零流量 candidate 與通過健康檢查後的流量切換。

## 文件

- [系統架構規格](docs/system-spec.md)
- [人工建置與驗證手冊](docs/MANUAL_RUNBOOK.md)
- [新 repo onboarding 腳本](docs/onboard-new-repo.sh)
- [服務密鑰建立腳本](docs/add-secret.sh)

## 已確認的試點設定

| 設定 | 試點值 | 正式值/做法 |
|---|---|---|
| GCP project | `taicca-geminiapi` | 不變 |
| Region | `asia-east1` | 依服務確認 |
| GitHub connection | `github-fantasyjack99` | 測試完成後改為 `github` |
| Artifact Registry | `cicd-services` | 共用 repository |
| Cloud Run access | public | 正式環境設為 private |
| PR Medium/Low 結果 | GitHub Check 與 Cloud Build Log | 不使用額外 GitHub Token |
| 通知 | Cloud Build Slack Notifier 範本 | 由管理員一次性安裝 |

`_AI_MODEL` 沒有在程式碼中鎖定版本；預設佔位值為
`gemini-flash-latest`。執行 onboarding 前，務必在 Vertex AI 控制台確認它是
目前實際可用的輕量 Gemini Flash model ID，必要時以 `AI_MODEL` 環境變數覆寫。

## 安全界線

本 repo 內的腳本會建立或修改真實 GCP 資源，但本次產製過程沒有執行它們。
任何人或未來的 Codex session 都必須先 review
`docs/MANUAL_RUNBOOK.md`，再由管理員逐步執行。不要自動執行 onboarding、
Secret Manager、Trigger、Cloud Run 或 IAM 指令；不要自動建立 GitHub repo、push、
PR 或分支保護；不要讀取或輸出真實密鑰。

PR Trigger 使用內嵌 build config，並從受保護的 `main` 載入掃描器。這避免
協作者在 PR 內修改 gate 後，讓未經信任的掃描腳本以 Cloud Build 身份執行。
因此更新 `cloudbuild-pr-check.yaml` 後，也必須由管理員同步更新 Trigger 的
inline config。

## 本機靜態檢查

本機不需要啟動服務或 Docker。可執行：

```bash
bash -n docs/onboard-new-repo.sh docs/add-secret.sh
sh -n scripts/security-gate/run_gitleaks.sh
python3 -m py_compile app/main.py scripts/security-gate/run_vertex_review.py
```

若環境已安裝 `shellcheck` 與 `yamllint`，另執行：

```bash
shellcheck docs/*.sh scripts/security-gate/*.sh
yamllint cloudbuild-pr-check.yaml cloudbuild-deploy.yaml templates/slack-notifier.yaml.tmpl
```

