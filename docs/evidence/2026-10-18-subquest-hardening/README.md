# 反復サブクエスト修正の証跡（2026-10-18）

## 対象コード

- code commit: `508f24ac958bce5756ccdf3f8d683aa3838cd6d1`
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`
- full core: 62/62 PASS, 650.219 s, `source_changed_during_run=false`
- full-core result: `C:\Users\user\AppData\Local\Temp\desert-rats-core-2026-10-18-final\20261017T175947Z-tizakz2o\results.json`

## 回帰・実測

- `test_town.gd`: 地上の回収荷物、East Sands の停泊限定、容量待ち、負傷中断と現地断念、保存復元、配達の停車引渡し、燃料前渡し（満タン・部分空き・取消/再受注）を確認。
- `test_field_operations.gd`: 地上の敵は甲板の回収役を止めず、地上に降りた担当者だけを止めることを確認。
- `test_field_ui.gd` / `test_crew_detail.gd`: フィールド進捗・停止理由、断念導線、仲間パネルの専用荷物表示を確認。
- `test_town_flow.gd -- --cash-only`: 通常資源を枯渇、採取/狩猟OFF、Cr/燃料0から seed 811–813 を各配達3周・回収3周。全パーツ修理を報酬から実購入し、順序逆転でも同値を確認。
  - seed 811: 85 Cr / fuel 51.67 / parts 100,100,100 / speed 9999
  - seed 812: 72 Cr / fuel 51.91 / parts 100,100,100 / speed 9999
  - seed 813: 54 Cr / fuel 35.82 / parts 100,100,100 / speed 9999（開始時 drive=0, speed=15。初回報酬で修理）

順序差の原因は視覚演出 `weather_fx` がゲームプレイ用グローバル乱数を消費していたこと。演出専用 `RandomNumberGenerator` へ分離した。

## GUI証跡

PNG はWindows Godot 4.7.2 / OpenGL Compatibility の実描画（Viewport注入）で生成した。OS入力は統合UI自動化がWindowsアプリを列挙できなかったため未確認。

- `mission-status.png`: 配達の「交易村で停車して引渡し」表示と2D地上の回収荷物
- `field-controls.png`: フィールド操作と回収断念導線
- `handcart-equipment.png`, `three-creatures.png`, `cycle-upgrades.png`: 既存2D画面の回帰確認

## 保存隔離

WindowsではGodotが `APPDATA` を使うため、検証ランナーもrunごとの `APPDATA` / `LOCALAPPDATA` を隔離するよう修正した。既存ユーザーセーブは変更していない。
