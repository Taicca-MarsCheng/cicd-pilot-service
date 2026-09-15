# cicd-pilot-service

這是 GitHub 協作者程式碼經雙層資安檢查後部署到 GCP Cloud Run 的試點
repo。服務本身只有 `/` 與 `/healthz`；重點是驗證 PR gate、Artifact
Registry、零流量 candidate 與通過健康檢查後的流量切換。

本段文字用於第一次試點 PR，驗證 Gitleaks 與 Vertex AI security gate。

## 文件

- [系統架構規格](docs/system-spec.md)
- [人工建置與驗證手冊](docs/MANUAL_RUNBOOK.md)
- [新 repo onboarding 腳本](docs/onboard-new-repo.sh)
- [PR gate 更新/修復腳本](docs/update-security-gate.sh)
- [服務密鑰建立腳本](docs/add-secret.sh)

## 已確認的試點設定

| 設定 | 試點值 | 正式值/做法 |
|---|---|---|
| GCP project | `taicca-geminiapi` | 不變 |
| Region | `asia-east1` | 依服務確認 |
| GitHub account | `Taicca-MarsCheng` | 試點 repo owner |
| GitHub connection | `github-taicca-marscheng` | 測試完成後改為 `github` |
| Artifact Registry | `cicd-services` | 共用 repository |
| Cloud Run access | public | 正式環境設為 private |
| PR Medium/Low 結果 | GitHub Check 與 Cloud Build Log | 不使用額外 GitHub Token |
| 通知 | Cloud Build Slack Notifier 範本 | 由管理員一次性安裝 |

AI 審查與 Cloud Run 部署區域分開設定。目前 onboarding 預設使用
`gemini-3.1-flash-lite` 與 `global` 端點，Cloud Run 仍部署在
`asia-east1`。模型生命週期變更時，可用 `AI_MODEL` 與
`AI_LOCATION` 環境變數更新 Trigger substitution，不需改審查邏輯。

## 安全界線

本 repo 內的腳本會建立或修改真實 GCP 資源，但本次產製過程沒有執行它們。
任何人或未來的 Codex session 都必須先 review
`docs/MANUAL_RUNBOOK.md`，再由管理員逐步執行。不要自動執行 onboarding、
Secret Manager、Trigger、Cloud Run 或 IAM 指令；不要自動建立 GitHub repo、push、
PR 或分支保護；不要讀取或輸出真實密鑰。

PR Trigger 使用內嵌 build config，並從受保護的 `main` 載入掃描器。這避免
協作者在 PR 內修改 gate 後，讓未經信任的掃描腳本以 Cloud Build 身份執行。
因 Trigger 預設只 checkout 單一 commit，每個 repo 需配置一把唯讀 GitHub
Deploy Key，用來取得 base branch 與完整 diff；私鑰只存在 Secret Manager，
並只開放給該 Trigger 的 Build Service Account。
因此更新 `cloudbuild-pr-check.yaml` 後，也必須由管理員同步更新 Trigger 的
inline config；可使用 `docs/update-security-gate.sh`。

## 本機靜態檢查

本機不需要啟動服務或 Docker。可執行：

```bash
bash -n docs/onboard-new-repo.sh docs/update-security-gate.sh docs/add-secret.sh
sh -n scripts/security-gate/run_gitleaks.sh
python3 -m py_compile app/main.py scripts/security-gate/run_vertex_review.py
python3 -m unittest discover -s tests -v
```

若環境已安裝 `shellcheck` 與 `yamllint`，另執行：

```bash
shellcheck docs/*.sh scripts/security-gate/*.sh
yamllint cloudbuild-pr-check.yaml cloudbuild-deploy.yaml templates/slack-notifier.yaml.tmpl
```
