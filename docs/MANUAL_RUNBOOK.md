# CI/CD 試點人工操作手冊

本手冊中的指令會變更 `fantasyjack99` GitHub 帳號及
`taicca-geminiapi` GCP 正式專案。請逐段確認後由管理員執行。不要把 Slack
Webhook、API Key 或任何密鑰貼進 terminal history、repo、PR 或 Cloud Build
substitution。

## 0. 執行前確認

1. 確認本機檔案已完成 review，特別是兩份 `cloudbuild-*.yaml`、
   `CODEOWNERS`、`.security/` 和 `scripts/security-gate/`。
2. 到 Vertex AI Model Garden 確認目前在 `asia-east1` 可用的輕量 Gemini
   Flash model ID。若 `gemini-flash-latest` 不可用，記下實際 ID，執行
   onboarding 時設定 `AI_MODEL`。
3. 確認管理員有 GitHub repo admin、GCP Project IAM Admin、Cloud Build
   Editor、Service Account Admin、Artifact Registry Admin 等所需權限。
4. 在 GCP Activity 頁開啟即時活動記錄，逐項核對腳本建立的資源。

預期結果：尚未建立或修改任何雲端資源；已知道要使用的 Vertex AI model ID。

## 1. 建立 private GitHub repo 並推送初始版本

到 GitHub 網頁右上角 `+` → **New repository**：

- Owner：`fantasyjack99`
- Repository name：`cicd-pilot-service`
- Visibility：**Private**
- 不要勾選 README、`.gitignore` 或 license 初始化

在本 repo 根目錄執行：

```bash
git remote add origin git@github.com:fantasyjack99/cicd-pilot-service.git
git branch -M main
git push -u origin main
```

預期結果：GitHub private repo 的 `main` 顯示本交付物；push 沒有包含憑證或
`.vertex-review.json`。此初始 push 發生在分支保護與 Trigger 建立前，不會部署。

## 2. 啟用 GCP APIs（專案一次性）

先用唯讀指令確認：

```bash
gcloud services list --enabled --project=taicca-geminiapi \
  --filter='config.name:(aiplatform.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com iam.googleapis.com run.googleapis.com secretmanager.googleapis.com)' \
  --format='value(config.name)'
```

缺少時才執行：

```bash
gcloud services enable \
  aiplatform.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  iam.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  --project=taicca-geminiapi
```

預期結果：六個 API 都列為 enabled；既有服務未被修改。

## 3. 安裝 Cloud Build GitHub App 與第 2 代連線

1. 開啟 Google Cloud Console，切換專案 `taicca-geminiapi`。
2. 進入 **Cloud Build → Repositories → 2nd gen**，Region 選
   `asia-east1`。
3. 選 **Create host connection → GitHub**，安裝/授權 Google Cloud Build
   GitHub App，只授權需要的 repo。
4. Connection name 填 `github-fantasyjack99`。
5. 在該 connection 下選 **Link repository**，連接
   `fantasyjack99/cicd-pilot-service`；repository resource name 填
   `cicd-pilot-service`。

以唯讀指令確認：

```bash
gcloud builds connections describe github-fantasyjack99 \
  --project=taicca-geminiapi --region=asia-east1
gcloud builds repositories describe cicd-pilot-service \
  --connection=github-fantasyjack99 \
  --project=taicca-geminiapi --region=asia-east1
```

預期結果：connection 狀態為 ready，repository 顯示正確 GitHub remote URI。

## 4. 執行 onboarding

先 review `docs/onboard-new-repo.sh`。使用預設 model 時執行：

```bash
./docs/onboard-new-repo.sh cicd-pilot-service asia-east1
```

若控制台顯示不同的 Flash model ID：

```bash
AI_MODEL='控制台顯示的-model-id' \
  ./docs/onboard-new-repo.sh cicd-pilot-service asia-east1
```

腳本會先做唯讀 preflight 並列出計畫；核對後輸入
`cicd-pilot-service` 才會寫入。它會：

- 建立或沿用 `asia-east1/cicd-services` Docker repository。
- 建立 `sa-cicd-pilot-service@taicca-geminiapi.iam.gserviceaccount.com`。
- 授予 Cloud Build SA Vertex AI、Artifact Registry、Cloud Run 所需角色。
- 只在該 Runtime SA 上授予 `roles/iam.serviceAccountUser`。
- 建立 `cicd-pilot-service-security-gate`（PR）與
  `cicd-pilot-service-deploy`（main push）兩個 Trigger。

預期結果：終端顯示 `Onboarding complete`；Cloud Build Triggers 畫面出現上述
兩項；Cloud Run 服務尚未建立。若任一同名 Trigger 已存在，腳本會停止而不覆寫。

## 5. 第一次測試 PR 與必要 Status Check

先用一個無風險改動觸發 PR：

```bash
git switch -c test/security-gate
# 編輯 README.md 加一行測試文字
git add README.md
git commit -m 'test: verify security gate'
git push -u origin test/security-gate
```

在 GitHub 建立指向 `main` 的 PR。到 PR 的 **Checks** 查看 Cloud Build check；
預期它對應 Trigger `cicd-pilot-service-security-gate`，並包含
`gitleaks-scan`、`vertex-ai-review`。GitHub 顯示名稱可能帶 App 前綴，請複製
畫面上的完整名稱，不要憑空輸入。

接著進入 repo **Settings → Branches → Add branch protection rule**：

- Branch name pattern：`main`
- 勾選 **Require a pull request before merging**
- Required approvals：至少 `1`
- 勾選 **Require review from Code Owners**
- 勾選 **Require status checks to pass before merging**
- 搜尋並選擇剛才 PR 實際出現、對應
  `cicd-pilot-service-security-gate` 的完整 check 名稱
- 建議勾選 **Require branches to be up to date before merging**
- 不啟用管理員強制套用/不要勾選 **Include administrators**，保留緊急例外；
  正常流程仍應 Retry，而不是繞過

預期結果：gate 未成功或 Code Owner 未核准時，協作者無法 Merge。

## 6. Merge、部署與健康檢查

1. 管理員核准測試 PR 後 Merge。
2. 到 **Cloud Build → History**，確認
   `cicd-pilot-service-deploy` 開始執行。
3. 確認順序為 Gitleaks → Vertex AI → Docker build → push →
   deploy candidate（0%）→ `/healthz` → promote traffic。
4. 到 **Artifact Registry → cicd-services**，確認 image tag 是該 commit 的
   `SHORT_SHA`。
5. 到 **Cloud Run → cicd-pilot-service → Revisions**，確認 candidate 通過後
   latest revision 收到 100% 流量。
6. 開啟 Cloud Run URL：`/` 應回傳
   `cicd-pilot-service is running`，`/healthz` 應回傳 HTTP 200 與 `ok`。

預期結果：只有健康檢查成功後才切換流量。若檢查失敗，build 失敗且舊 revision
仍持有正式流量。

## 7. 阻擋與誤判驗證

在獨立測試 PR 使用明顯的假測試模式驗證 Gitleaks；切勿提交真實密鑰。預期
Gitleaks 輸出經過 redaction、check failure、Merge 被鎖住。刪除測試字串後再
push，預期新的 check 通過。

以只會產生 LOW 建議的安全 diff 測試 Vertex AI：預期 check 通過，finding
摘要出現在 Cloud Build Log。HIGH/CRITICAL finding 則預期 check failure。
本試點不配置 GitHub 寫入 Token，所以 Medium/Low 不會自動建立 PR 留言。

若確認是誤判，到 **Cloud Build → History → 該 build → Retry**。Retry 仍會用
同一份規則重新判定；它不是白名單或略過機制。如果輸入與模型結果不變，預期仍
失敗，管理員不可藉 Retry 宣稱已通過。

## 8. Slack build 通知（選配、專案一次性）

使用 Slack 建立 Incoming Webhook，將 URL 存入 Secret Manager secret
`cicd-slack-webhook-url`。請依 Google 官方 Cloud Build Slack Notifier 安裝
流程部署 notifier；本 repo 提供：

- `templates/slack-notifier.yaml.tmpl`
- `templates/slack.json`

先把 YAML 中兩個 `PROJECT_ID` 替換成 `taicca-geminiapi`，並把 JSON 上傳到
YAML 指定的 GCS URI。Notifier 應訂閱 `cloud-builds` topic；filter 只通知部署
SUCCESS，以及所有 Trigger 的 FAILURE、TIMEOUT、CANCELLED，避免成功 PR 洗版。

預期結果：PR 阻擋、部署失敗和部署成功都會在 Slack 出現狀態、Trigger、Build
ID 與 Cloud Build Log 連結；Webhook 值只存在 Secret Manager。

## 9. 每服務密鑰與隔離驗證（需要時才做）

協作者用一次性連結交付值後，管理員執行：

```bash
./docs/add-secret.sh cicd-pilot-service example-secret-name
```

預期結果：輸入不回顯；Secret Manager 新增 secret/version；只有
`sa-cicd-pilot-service` 得到該 secret 的 accessor。以另一服務 Runtime SA
讀取它應得到 permission denied。不要把真實值放進 Cloud Build substitution。

## 10. 測試完成後切換正式設定

正式環境使用 connection `github` 且 Cloud Run private：

1. 在 `asia-east1` 建立/確認第 2 代 connection `github`，重新 link repo。
2. 在 Cloud Build Console 編輯兩個 Trigger，把 repository 改到
   `.../connections/github/repositories/cicd-pilot-service`。
3. 編輯 deploy Trigger substitution：`_PUBLIC_ACCESS=false`。
4. PR Trigger 仍須使用 `cloudbuild-pr-check.yaml` 的 **inline config**；不要改成
   從 PR branch 載入 build config。
5. 執行一次部署。`--no-allow-unauthenticated` 會移除公開呼叫，health check
   會改用 Cloud Build 身份的 ID Token。
6. 用未驗證 curl 呼叫正式 URL，預期 HTTP 403；由獲授權身份攜帶 ID Token
   呼叫 `/healthz`，預期 HTTP 200。

預期結果：兩個 Trigger 使用 `github` connection；Cloud Run 不再允許
`allUsers` 呼叫；private health check 與部署仍成功。

## 11. 完整驗收清單

- [ ] 協作者無 GCP 帳號、key 或 GitHub GCP secret。
- [ ] PR 無法修改實際執行的 inline gate 或 protected-main scanner。
- [ ] 未通過 gate 與 Code Owner review 時不可 Merge。
- [ ] Gitleaks 任一命中都阻擋且不顯示完整密鑰。
- [ ] Vertex AI 僅 HIGH/CRITICAL 阻擋，錯誤或格式異常時 fail closed。
- [ ] Main 會重跑兩層 gate。
- [ ] Artifact Registry image 使用 commit SHA tag。
- [ ] candidate 健康檢查前保持 0% 正式流量。
- [ ] 失敗不切流量，成功才 `--to-latest`。
- [ ] Slack 收到 build 終態（若已安裝 notifier）。
- [ ] 每個 Runtime SA 只能讀自己的 secrets。
