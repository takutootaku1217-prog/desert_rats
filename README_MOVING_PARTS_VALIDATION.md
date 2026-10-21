# 6 パーツ可動外装の検証記録

このファイルは、`fortress-moving-parts(1).zip` を使ったローカル隔離コピーの記録です。
通常版、`main`、旧 task-2/task-4、通常セーブは変更していません。

## 素材と実装範囲

`assets/fortress_moving/` には、提供された6素材（固定車体、車輪、屋根砲、クレーン、旗、ガレージシャッター）と元の `parts-manifest.json` を収録しています。独立デモ用の `project.godot` は取り込んでいません。

- 描画は Nearest のままです。車体・クレーン・閉じたシャッターは manifest の指定座標で描画します。
- 旗は同梱デモと同じ短い布帯の揺れだけを行います。
- 車輪は6輪すべてで移動距離/半径に連動して回転し、停止時は停止します。
- 砲塔は既存の発砲フィードバックに接続した全体画像の短い反動だけです。砲身分離、照準、クレーン関節、シャッター操作は追加していません。
- 内装、選択操作、セーブ形式は変更していません。既存操作を持たないクレーンとシャッターは表示サンプルです。

## 射撃実装の移植上の注意

インポート元はローカル識別子 `612a93c` の完全版 ZIP です。この ZIP には Git 履歴は含まれないため、`612a93c` をこのリポジトリの取得済みコミットとは扱いません。
旧作業ツリーの `shots` 乗算3行は取り込んでいません。インポート元の `fire_vehicle_weapon` は主砲・副砲を直接処理する構成へ変更済みで、副砲は単発のダメージと弾薬コストを維持します。これは既存の移植元テストが副砲の単発挙動を期待しているためです。Windows 4.7.2 の `test_vehicle_prototype.gd` でも、この挙動を実測しました。

## 実測結果

Windows Godot 4.7.2 で、次を実行しました。

- `tools/test_large_vehicle_layout.gd` — 成功
- `tools/test_large_vehicle_workers.gd` — 成功。3層の実到着座標と通常 AI への復帰を確認
- `tools/test_vehicle_prototype.gd` — 成功。O/I 表示切替、発砲フィードバック、単発の弾薬/ダメージコスト、セーブスナップショットを確認
- 通常レンダラ（OpenGL 3.3）で外装画面をキャプチャ — 成功

画面証拠は `artifacts/moving-parts-screens/` にあります。
`large-vehicle-exterior.png` は6輪・屋根砲・クレーン・旗・シャッターの合成表示、
`large-vehicle-customization.png` は既存の改造 UI です。
`large-vehicle-interior.png` は既存内装と実際の Worker 描画、`large-vehicle-exterior-flag-wave.png` は別フレームの旗描画です。

旗の波打ちはコード化され、通常レンダラで異なる2フレームを保存して確認しました。屋根砲は既存発砲時の全体画像反動を確認しましたが、独立した砲塔角度変更はゲーム状態・入力が存在しないため実装していません。PNG は動画ではないため、連続した再生録画は未作成です。

Godot が sandbox 内の `user://logs` と shader cache を作れない警告は出ましたが、各テストと PNG 出力は成功しました。これは Windows 4.7.2 の実測であり、同梱の Linux 4.6.3 記録とは区別します。

この作業ツリーはまだ detached HEAD のローカル隔離状態です。コミット、push、PR はしていません。
