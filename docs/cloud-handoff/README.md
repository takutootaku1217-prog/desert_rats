# クラウド間の安全な引継ぎ

対象は `cloud/migration-20261112` の `fb3494915dd621d5feccc2ed2718bf3947bacd4c`。ゲーム入口は `cloud_snapshot/project.godot`。旧mainを再開対象にしない。

## 今回の設計

GitHubに短い担当状態を保存し、通常のfast-forward pushで比較と更新を一体に行う。同じ保存済み状態からの二重取得は片方を拒否する。元の担当が停止し保存を完了した後だけ次の担当が取得する。時間切れだけで担当を奪わず、停止の確認ができない場合は保留する。

共有する情報は対象ブランチ・完全なソースSHA・担当・作業範囲・変更点・未完了・検査結果・次の担当に絞る。個人情報、認証情報、モデルの生ログは含めない。

公式の利用枠情報が取得できる場合は全適用窓を確認し、残り10％以下なら新しい作業を開始しない。値が欠落・古い・reset後に未取得・制限警告ありの場合も開始しない。テスト用の値では実モデルを起動しない。追加クレジット・API課金・権限設定を変更しない。

方式はGitHubを使う協調的な排他制御とする。同じコピーを制御外から編集する行為まで禁止できる仕組みではない。常駐スケジューラーと実モデルの自動起動は、認証と公式クラウド実行履歴を確認できるまで有効にしない。

## 受入条件

1. 指定SHAと1180ファイルの公開manifestを照合し、既存コピー・ブランチ・資料・セーブを保持する。
2. 残り10％境界、unknown、古い値、警告、二重取得、前担当未停止をテストで拒否する。
3. 別プロセスの小規模workerで起動→進捗保存→停止確認→交代→受取確認を行い、GitHub上の実SHAを照合する。
4. 移行候補を隔離コピー・保存領域でGodot実行し、バージョンと実行範囲を記録する。
5. 模擬交代、実モデル交代、実際の上限到達、恒久的なクラウド予定実行の結果を区別する。

## 認証と実行環境

2026-11-14の実確認: GitHub読取・権限メタデータは成功、Claude CLI 2.1.311は未認証。Codex CLIはChatGPTログイン済みと表示するが、公式 `account/rateLimits/read` は401で、残量は不明。接続の詳細は `connection-evidence.json`。本人のClaude予定タスクHistoryへアクセスできていないため、以前の予定が走らなかった原因は未確定。

移行候補の新規検証は `runtime-evidence.json`。Linux Godot 4.7.2で既存5ケース185 assertionsと隔離import・入口120フレーム起動が成功。1180ファイルのmanifestは実行前後一致。全103ケース・通常GUI・Windows・長期収支の合格には広げない。

GitHubは保存場所であり、GPTやClaudeを動かす実行機械ではない。開始済みのクラウドタスクと、恒久的に次のタスクを起動するスケジューラーも別に確認する。

Claude CLIは本人が公式の `claude auth login --claudeai` で認証する。ブラウザログインだけでは別環境のCLI認証済みとしない。認証コード・APIキー・OAuthトークン・Cookieをリポジトリやチャットに保存しない。現在の接続状態は実行記録で確認する。

Claudeのクラウド予定タスクは公式のRoutines詳細のHistoryで確認する。未実行の原因を、ログイン・利用資格・組織設定・利用枠・対象repo・実行履歴から切り分ける。ChatGPT側の予定一覧でClaude側の履歴を代用しない。

## 制御の実行と再開

制御本体は `tools/cloud_handoff.py`、検査は `python3 tools/test_cloud_handoff.py -v`。現在のworkerは**固定の数値進捗を作る模擬プロセスだけ**で、GPT・Claudeや任意コマンドを起動する機能は有効にしていない。

保存済み状態は [専用状態ブランチ](https://github.com/takutootaku1217-prog/desert_rats/tree/cloud/handoff-state-20261114) の `state.json`。作業用コードは [新規ソースブランチ](https://github.com/takutootaku1217-prog/desert_rats/tree/cloud/handoff-safe-20261114)。実行前は必ずリモートから状態を取得する。

```sh
python3 tools/cloud_handoff.py --repo . inspect
```

出力の `commit` が次の操作の `--expected`。`state.source_sha` と同じコミットをチェックアウトし、`source_branch` のGitHub先端も一致することが必要。ゲームと実行中の制御コードにローカル差分があれば拒否する。sourceブランチが進んだら古い状態で開始せず、旧担当と未共有変更を確認したうえで、新しいタスク用の状態ブランチを作る。

初回の初期化例（既存の状態は初期化し直さない）:

```sh
python3 tools/cloud_handoff.py --repo . init \
  --task-id cloud-handoff-20261114 \
  --source-branch cloud/handoff-safe-20261114 \
  --source-sha <GitHubに保存済みのソース完全SHA>
```

今回の模擬交代例:

```sh
python3 tools/cloud_handoff.py --repo . probe \
  --expected <inspectの状態コミット> --source-sha <state.source_sha> \
  --owner gpt-mock --next-owner claude-mock --stop warning
# 別の同一版チェックアウトでinspectし、phase=stoppedと停止receiptを確認する
python3 tools/cloud_handoff.py --repo . probe \
  --expected <引継ぎ保存後の状態コミット> --source-sha <同じstate.source_sha> \
  --owner claude-mock --complete
```

`claimed` / `running`、通信結果が不明、supervisor異常終了の場合、再実行や時刻だけで権利を奪わない。元環境の担当・子プロセスの停止と保存状況を確認できるまで待機する。CLIに強制解除はない。制御外からの同時編集や、実モデルが起動する一般的な子孫プロセスの停止は今回の模擬worker検証範囲に含めない。

利用枠の正規化は公式Codex `account/rateLimits/read` とClaude statusline形式に対応するが、常駐の取得・監視・実モデル自動交代には未接続。CLIの `claim` は状態取得だけでworkerを開始しない。模擬証拠は実モデルの開始許可に使えない。上限まで消費する実験はしない。

GitHub runnerの確認用は [専用CIブランチ](https://github.com/takutootaku1217-prog/desert_rats/tree/cloud/handoff-ci-probe-20261114)。公開repoの標準 `ubuntu-latest`、`contents: read`、短時間の模擬検査だけを使う。artifact・cache・有料runner・モデルを使わない。権限拒否時は権限を広げず未実行と記録する。根拠: [GitHub Actions課金](https://docs.github.com/en/billing/concepts/product-billing/github-actions)。CI成功も実モデル交代や恒久的スケジュールの証明にはしない。

この文書・計画・接続記録は実行前の準備時点の記録。実行後の短い結果は状態ブランチとGitHub Actionsの当該runを照合する。毎回長い報告書は追加せず、対象SHA・変更点・未完了・検査結果・次の担当を短く残す。

## 参照

- https://code.claude.com/docs/en/authentication
- https://code.claude.com/docs/en/statusline#rate-limit-usage
- https://code.claude.com/docs/en/agent-sdk/typescript#sdkratelimitevent
- https://code.claude.com/docs/en/routines
- https://developers.openai.com/codex/app-server/
- Notion開発入口・検証台帳は2026-11-14に取得。11/9時点の内容にある過去版の合格は今回の移行候補へ転用しない。今回のユーザー指定SHAを優先し、Notionは変更していない。
