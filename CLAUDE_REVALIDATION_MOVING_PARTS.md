# Claude 再検証依頼：6 パーツ大型外装

対象コードは `5b441c55188bbe43e07eb4e7aa4fbbb57726e503`（検証ブランチ
`gpt/large-fortress-graphics-validation`）です。`main` や通常セーブは変更しないでください。

## 確認済みの Windows 実測

Godot 4.7.2 / OpenGL 3.3 で `test_large_vehicle_layout.gd`、
`test_large_vehicle_workers.gd`、`test_vehicle_prototype.gd` が成功しました。
同じ環境で内装、外装、改造 UI の PNG を `artifacts/moving-parts-screens/` に出力しました。
この実測は、同梱されていた Linux Godot 4.6.3 の記録とは別です。

## 今回の差分

- `assets/fortress_moving/` の固定車体、6輪、屋根砲、クレーン、旗、シャッターを manifest の領域・pivot に従い合成します。
- 車輪は移動距離/半径に連動し、停止時に止まります。旗は短い布帯の波だけを描画します。
- 砲塔は既存の発砲フィードバックによる全体画像反動だけです。独立照準角、砲身分離、クレーン関節、シャッター操作は未実装です。
- 内装・選択・セーブ形式は保持しています。`612a93c` はインポート元 ZIP のローカル識別で、Git 履歴として取得したコミットではありません。
- 副砲はインポート元の単発ダメージ/弾薬コストを維持しています。旧 `shots` 乗算を機械的に戻していません。

## 再確認してほしい点

1. O/I 切替後に外装と内装が崩れず、3階のはしご経路が x=550 を通ること。
2. 6輪の位置、旗の揺れ、発砲時の屋根砲全体反動、静止時の車輪停止。
3. 改造 UI、既存の副砲単発コスト、セーブ/復元が維持されること。

Windows sandbox では `user://logs` と shader cache を作れない警告が出ますが、上記テストと PNG 出力は成功しています。実マウス操作・連続動画・独立砲塔角操作は未確認です。
