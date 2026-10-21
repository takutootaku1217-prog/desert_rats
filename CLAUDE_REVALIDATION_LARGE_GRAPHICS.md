# Claudeへ：大型グラフィック修正版の4.7.2再検証

ユーザーから、この修正版一式を `gpt/large-fortress-graphics-validation` にコミットしてpushする指示を受領した共有版です。**mainは変更・統合しないでください。**

## 取得と対象の固定

リポジトリ：`https://github.com/takutootaku1217-prog/desert_rats`

ブランチ：`gpt/large-fortress-graphics-validation`

以前の `4a06a96d90bf26c8197eea79aaa90619be4d7b88` から進んだ共有コミットを取得し、完了報告で渡された新しい完全SHAと照合してください。既存mainや既存セーブを使わず、対象SHAからの隔離cloneまたは検証用checkout、新規セーブで確認します。開始時のHEAD、作業ツリー、実際のGodot実行ファイルの `--version` を記録してください。取得や起動ができなければ、実行できた範囲と実エラーを報告し、成功扱いにしないでください。

## 修正済みの点

- `scripts/main.gd` の `fire_vehicle_weapon` から、表示文だけに残った未定義 `shots` 参照を除去。主砲30/弾薬2、副砲11/弾薬1の単発処理は維持し、武器数値は推測変更していません。
- `data/large_vehicle_layout.gd` の上下昇降経路は、どちらも内装に描かれたシャフト **world x=550** を使用します。内装画像を変えなくても経路側で修正されています。
- 採用した工房型ドット外装・6輪・小型砲は `assets/fortress_pixel/`。新しい素材はすでに実ゲームへ組み込まれており、スクショだけの共有ではありません。
- 車輪は内外装で6輪を共用。移動距離÷半径で回転します。砲は装備状態に応じて描画し、反動・砲口発光を持ちます。
- 初期中型の走行上限200、文字化け、部屋変更の重ね絵/完成表示も修正を含みます。
- 内装画像は従来のものです。新しい外装と内装の画風・全体形状はまだ異なります。採用原画のUI全体や仮数値は実装していません。

## こちらで実際に確認した範囲

Linux Godot **4.6.3.stable.official.7d41c59c4** / Xvfb / OpenGL Compatibility / Mesa llvmpipe / Dummy Audio。4.7.2やWindowsでの成功とは区別してください。

最終の専用3件：`test_large_vehicle_layout.gd` / `test_large_vehicle_workers.gd` / `test_vehicle_prototype.gd` 成功。

最終の公式5件：import / view / save_game / weapon / startup 成功。`source_changed_during_run=false`。その後のゲームソースと採用素材のハッシュ一致も確認しました。全coreの最終一括検査ではありません。

## Godot 4.7.2でお願いしたいこと

1. 新規importと通常起動。`shots` を含む構文エラー/スクリプトエラーがないか。
2. 車両カスタマイズで大型/強化大型へ変更し、新しい6輪外装が読み込まれるか。外装O/内装Iの切替。入力はOS実入力・Viewportイベント・直接呼出しを区別。
3. 実描画でタイヤの車体接続/接地、主砲と副砲の取付位置、砲身の重なり、発射時の表示を再確認。
4. 内装のはしごと登る位置が一致するか。3人の上層到着 (184,246)/(408,246)/(654,246) と、巡回終了後の通常AIの運搬・加工、地上往復。
5. 専用3テストと、公式ハーネスでの表示・セーブ・武器・起動を再実行。必要な追加検査は範囲を明示。

旧テストは引数を省くと異なる世界fixtureで失敗するため、公式ハーネスを使ってください。weaponの旧2失敗は、基準mainでも引数なしだと再現しましたが、指定の `legacy-world-test` では基準main/修正版とも成功しています。

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . -s res://tools/test_large_vehicle_layout.gd
godot --headless --path . -s res://tools/test_large_vehicle_workers.gd
godot --headless --path . -s res://tools/test_vehicle_prototype.gd
python tools/run_checks.py --godot /absolute/path/to/Godot-4.7.2 --check view --check save_game --check weapon --check startup --output-dir /absolute/path/outside-repository
```

Windowsの場合は実際のGodot exeとPythonのパス、隔離APPDATAを使用。ハーネス自体もWindowsの保存先を隔離します。上記の `godot` はコマンド例であり、4.7.2を名乗る別実行ファイルを決め打ちしないでください。

## コード・素材・証跡の場所

- 採用素材：`assets/fortress_pixel/armored-body.png` / `wheel.png` / `roof-gun.png`
- 採用原画・制作条件：`art_sources/approved_fortress/`
- 最新反映記録：`docs/採用外装_反映検証_2026-10-21.md`
- 最新ゲーム外装：`docs/pixel-exterior-evidence-2026-10-21/exterior.png`
- 内装と実Worker：`docs/pixel-exterior-evidence-2026-10-21/interior-arrivals.png`
- 最新の公式結果：`docs/pixel-exterior-evidence-2026-10-21/official/results.json`
- 最新の専用結果：`docs/pixel-exterior-evidence-2026-10-21/focused/results.json`
- 旧配置の修正経緯・途中の失敗ログ：`docs/大型グラフィック_修正検証_2026-10-21.md` と `docs/large-graphics-fix-evidence-2026-10-21/`

報告は **コードを読んで判断したこと／実際に動かして確認したこと／未確認** を分け、対象の完全SHA、エンジン版、画像と結果ログを添えてください。main統合や通常セーブの置き換えは行いません。通常版・他の試作コピーへ変更を広げないでください。
