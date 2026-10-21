# 採用外装：工房型の移動拠点

2026-10-21、ユーザーの「これいいねえ これに変更！」により、このフォルダの `approved-exterior-mockup.png` を外装の採用基準とした。

この画像の採用は、画面内の積載200・費用500Crなどの仮数値や、新しい改造UI全体の実装を決定するものではない。今回は外装・車輪・砲の見た目だけを検証版へ反映した。

## 使用する素材

- `assets/fortress_pixel/armored-body.png`：装甲・小窓・クレーン・アンテナ・車体。砲とタイヤを含まない。
- `assets/fortress_pixel/wheel.png`：回転用タイヤ。採用画像の6輪配置として描画し、内外装で共用する。
- `assets/fortress_pixel/roof-gun.png`：装備状態に応じて表示する小型砲。主砲と副砲は大きさを変えて使用。

内装画像の新作・全体の画風統一は今回の対象ではない。既存の内装切替・仲間の歩行・施設配置を保持している。透過PNGは組み込みImageGenで生成した原本をそのまま保存し、透明余白だけをGodotの描画用regionで除いている。座標は `data/large_vehicle_layout.gd` の `PIXEL_*` を参照。

生成時の最終プロンプト、参照元、SHA256は `generation-record.json` に記録。前の外装素材も回収可能な状態で残している。
