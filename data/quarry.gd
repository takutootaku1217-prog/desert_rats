class_name QuarryDB
extends RefCounted
## 1地点だけの調整用初期値。広域マップ・新素材・既存採取効率の変更ではない。
const NAME := "街道脇の鉄鉱床"
const TRAVEL_DISTANCE := 1200.0
## 距離の差は、停車した拠点の斜路からの徒歩距離。
const POINTS := [
	{"id": "near", "group": "近場", "pos": Vector2(1080, 680), "amount": 12},
	{"id": "far_a", "group": "奥", "pos": Vector2(420, 630), "amount": 24},
	{"id": "far_b", "group": "奥", "pos": Vector2(250, 650), "amount": 24},
	{"id": "far_c", "group": "奥", "pos": Vector2(110, 610), "amount": 24},
]
