# 通常C採掘：同じ右上ボタンで帰還

## 対象と変更
基準 f4ca577b384b1b2fd43325bdf60062bbfc79455b、公開候補枝 codex/quarry-return-ready-20261115（検証は同一製品差分の独立作業枝で実施）。入口 cloud_snapshot/project.godot。原clone・既存セーブ・GitHubは変更しない。

右上の既存ボタンを、通常C（is_mine_path_engineering）でも「帰還準備→帰還準備中→帰還→横視点」にする。任意前哨地を維持、地域ボスと旧診断モードを除外。押下時action/session/clock固定・明示二度目の操作・容量確認/取消/再確認・既存commitを再利用。資源/数値/保存形式の変更なし。

## 仕様再確認
今回Notionの採用企画（最終編集11/1）、詳細02（11/1）、差分06（11/9）を再取得。採取中断→呼戻し→帰還確認→出発、荷物の所在数量保持、車体固定停車と整合。容量不足の具体確認文言はNotion正式指定とはせず、既存コードの契約を保持。

## TDDと検証
Linux Godot 4.7.2.stable.official.ed1daf0bf、専用XDG_DATA_HOME/FLUID_TEST_HOME。ログは作業場所の兄弟quarry-return-evidenceに保全。
- 先行RED: 通常Cの表示・右上確定・搬入で期待の5失敗。
- GREEN最終: test_quarry_return_flow.gd 23検査成功。自然なsession採掘/搬送、準備押下のready昇格禁止、保存画面/旧session/clock/hidden/gameover/load拒否、容量不足取消/容量変化再確認、別クリックで帰還、二重搬入なし。
- 最初のlocal→recallはhold境界用にbutton_down signalとrequest_recall APIを使用。最後の確定は合成Viewport pointer。容量境界では明示的にFOODを注入/回収。通常生存一周やOS入力の証拠ではない。
- 初期fixtureでレイアウト待ち不足があり追加待機で修正。確定後に破棄されたadapterを診断printで読んだ失敗も除去。失敗ログを保持し成功へ数えない。
- 既存test_first_region_mine_arrival_gate成功（変更前baseline）。
- 関係回帰成功: mine_path_ui、c_outpost_entry_v3、region_boss_return（38）、field_survival_clock_v3、c_field_save_ui（46）。
- c_field_save_ui単独はproducer保存不在で1失敗。正規producer c_field_active_owners（45成功）→同HOMEのconsumer再実行で成功。初回失敗も保全。
- git diff --check成功。独立read-only reviewerで製品欠陥指摘なし。親が別コピーで独立再実行予定。

## runnerの制限
標準tools/run_checks.py coreを試したが移行snapshotに旧root向けスクリプトが欠落。69 records中import/startupの2のみ成功、67失敗。初回はimportの新UID生成でsource_changed=true。UID固定後再実行はsource_changed=false、42.794秒、同じ欠落。全体合格ではない。正しいrun_prototype_checks.py全体は今回は未実施、今回指定の関係回帰を実行。

欠落/失敗check名: journey, journey_ui, journey_flow, town, town_flow, town_ui, production_recovery, production_reservations, order_flow, production_ui, hunt_bounds, auto_craft_guard, developer_mode, developer_enabled, artscale, tool_progression, tool_flow, first_cycle, field_operations, manual_combat, field_ui, ecosystem, first_cycle_flow, navigation_bar, batch_crafting, batch_ui, batch_flow, haul_support, haul_ui, haul_flow, facility_packing, packing_flow, world_map, world_flow, world_boundaries, world_fauna, world_scenery, world_reencounter, save_namespace, save_game, save_ui, save_progression, checkpoint, mission_respawn, field_rescue, inventory_discard, clarity_ui, cargo_accounting, cargo_escape_ui, progression, weapon, weapon_ui, equipment_ui, packed_equipment, quarry, gather, cargo, items, item_icon_refresh, crew_status, life_actions, tool_management, cargo_reservations, consumption_loop, trouble_loop, loop_vanilla, loop_normal

## 未検証と受渡
OS実マウス、Windows、通常新規→地域突破の全体一周は未検証。GUI目視は親担当。GitHub push/既存枝統合なし。生成UIDのうち新テスト以外はコミットせず証拠領域へ退避。

公開候補では新テストをrun_prototype_checks.pyのTESTSへ一度だけ登録。registryの重複・対象ファイルの存在・Python構文を検査。全prototype suiteの再実行はしていない。製品コード・テスト本体は検証済み差分と同一。
