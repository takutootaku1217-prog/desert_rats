class_name CanyonCrewViews
extends Node2D
## Presentation-only human crew. The route session remains the sole source of
## work, cargo and movement; these sprites only mirror its current actors.

const IDLE := preload("res://assets/canyon_recovery/v2/crew_idle.png")
const WALK := preload("res://assets/canyon_recovery/v2/crew_walk.png")
const HARVEST := preload("res://assets/canyon_recovery/v2/crew_harvest.png")
const CARRY := preload("res://assets/canyon_recovery/v2/crew_carry.png")
## This is the existing, transparent work-support item.  It is deliberately
## kept as an independent sprite so the session snapshot remains the only
## source of equipment and the normal v2 worker can be swapped later.
const HAUL_FRAME := preload("res://assets/resources/item_haul_frame.png")

## v3 is deliberately one-worker, replaceable verification art. Every walk
## cell is 64×64 with the same foot anchor; this avoids the v2 pose swap's
## differing transparent-bottom offsets while keeping normal crew unchanged.
const WALK_FRAMES := {
	"west": [
		preload("res://assets/canyon_recovery/v3/walk_west_0.png"),
		preload("res://assets/canyon_recovery/v3/walk_west_1.png"),
		preload("res://assets/canyon_recovery/v3/walk_west_2.png"),
		preload("res://assets/canyon_recovery/v3/walk_west_3.png"),
	],
	"northwest": [
		preload("res://assets/canyon_recovery/v3/walk_northwest_0.png"),
		preload("res://assets/canyon_recovery/v3/walk_northwest_1.png"),
		preload("res://assets/canyon_recovery/v3/walk_northwest_2.png"),
		preload("res://assets/canyon_recovery/v3/walk_northwest_3.png"),
	],
	"southeast": [
		preload("res://assets/canyon_recovery/v3/walk_southeast_0.png"),
		preload("res://assets/canyon_recovery/v3/walk_southeast_1.png"),
		preload("res://assets/canyon_recovery/v3/walk_southeast_2.png"),
		preload("res://assets/canyon_recovery/v3/walk_southeast_3.png"),
	],
	"east": [
		preload("res://assets/canyon_recovery/v3/walk_east_0.png"),
		preload("res://assets/canyon_recovery/v3/walk_east_1.png"),
		preload("res://assets/canyon_recovery/v3/walk_east_2.png"),
		preload("res://assets/canyon_recovery/v3/walk_east_3.png"),
	],
}
const CARRY_FRAMES := {
	"northwest": [
		preload("res://assets/canyon_recovery/v3/carry_northwest_0.png"),
		preload("res://assets/canyon_recovery/v3/carry_northwest_1.png"),
		preload("res://assets/canyon_recovery/v3/carry_northwest_2.png"),
		preload("res://assets/canyon_recovery/v3/carry_northwest_3.png"),
	],
	"southeast": [
		preload("res://assets/canyon_recovery/v3/carry_southeast_0.png"),
		preload("res://assets/canyon_recovery/v3/carry_southeast_1.png"),
		preload("res://assets/canyon_recovery/v3/carry_southeast_2.png"),
		preload("res://assets/canyon_recovery/v3/carry_southeast_3.png"),
	],
	"east": [
		preload("res://assets/canyon_recovery/v3/carry_east_0.png"),
		preload("res://assets/canyon_recovery/v3/carry_east_1.png"),
		preload("res://assets/canyon_recovery/v3/carry_east_2.png"),
		preload("res://assets/canyon_recovery/v3/carry_east_3.png"),
	],
}
const HARVEST_FRAMES := [
	preload("res://assets/canyon_recovery/v3/harvest_0.png"),
	preload("res://assets/canyon_recovery/v3/harvest_1.png"),
	preload("res://assets/canyon_recovery/v3/harvest_2.png"),
	preload("res://assets/canyon_recovery/v3/harvest_3.png"),
]
const UNLOAD_FRAMES := [
	preload("res://assets/canyon_recovery/v3/unload_0.png"),
	preload("res://assets/canyon_recovery/v3/unload_1.png"),
	preload("res://assets/canyon_recovery/v3/unload_2.png"),
	preload("res://assets/canyon_recovery/v3/unload_3.png"),
]
const STANDARD_FOOT_ANCHOR := Vector2(32.0, 60.0)
## The unload frames include their small crate to make cargo placement legible.
## These anchors are the worker boot contact within their 96×72 canvases.
const UNLOAD_FOOT_ANCHORS := [Vector2(34.0, 64.0), Vector2(33.0, 64.0), Vector2(31.0, 64.0), Vector2(31.0, 64.0)]
const MOVING_STATES := ["to_resource", "to_relay", "to_base", "to_base_empty", "injured_return", "outpost_move", "escort", "rescue_move", "rescue_return"]
## v2 canvases have different transparent bottoms. These anchors are their
## measured visible boot baselines, not the texture-rectangle centers.
const STANDARD_V2_FOOT_ANCHORS := {
	"idle": Vector2(28.0, 52.0),
	"walk": Vector2(28.0, 49.0),
	"harvest": Vector2(32.0, 55.0),
	"carry": Vector2(28.0, 50.0),
}

var _views: Dictionary = {}
var _support_views: Dictionary = {}
var _presentation: Dictionary = {}
var _animation_seconds := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	refresh()

## CanyonRecoveryHub calls this with the same delta the adapter passes to the
## session. It advances art only; it never writes actor/session data.
func advance(delta: float) -> void:
	_animation_seconds += maxf(delta, 0.0)

func refresh() -> void:
	var hub: CanyonRecoveryHub = get_parent() as CanyonRecoveryHub
	if hub == null or hub.session == null:
		return
	var single_demo: bool = hub.session.has_method("is_single_worker_demo") and bool(hub.session.call("is_single_worker_demo"))
	var tracked_id := str(hub.session.call("tracked_worker_id")) if single_demo else ""
	var live := {}
	var live_support := {}
	for raw_actor_id in hub.session.actors:
		var actor_id := str(raw_actor_id)
		var actor: Dictionary = hub.session.actors[raw_actor_id]
		if single_demo and bool(actor.get("presentation_hidden", false)):
			continue
		live[actor_id] = true
		var sprite: Sprite2D = _views.get(actor_id, null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			sprite = Sprite2D.new()
			sprite.name = "CrewView_" + actor_id.replace(":", "_")
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_index = 0
			_views[actor_id] = sprite
			add_child(sprite)
		if single_demo and actor_id == tracked_id:
			_refresh_tracked(sprite, actor_id, actor, hub)
		else:
			if _refresh_standard(sprite, actor_id, actor, hub):
				live_support[actor_id] = true
	for actor_id in _views.keys():
		if live.has(actor_id):
			continue
		var stale: Sprite2D = _views[actor_id] as Sprite2D
		if is_instance_valid(stale):
			stale.queue_free()
		_views.erase(actor_id)
		_presentation.erase(actor_id)
	for actor_id in _support_views.keys():
		if live_support.has(actor_id):
			continue
		var stale_support: Sprite2D = _support_views[actor_id] as Sprite2D
		if is_instance_valid(stale_support):
			stale_support.queue_free()
		_support_views.erase(actor_id)

## Returns true only when this normal-mode actor owns an independently drawn
## support sprite.  All equipment decisions are read from the immutable
## RouteSession actor snapshot; no game Worker is consulted or changed here.
func _refresh_standard(sprite: Sprite2D, actor_id: String, actor: Dictionary, hub: CanyonRecoveryHub) -> bool:
	var foot := hub.presentation_point_for_actor(actor) if hub.has_method("presentation_point_for_actor") else hub.map_point(Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0))))
	var prior: Dictionary = _presentation.get(actor_id, {})
	var prior_foot: Vector2 = prior.get("foot_point", foot)
	var delta := foot - prior_foot
	var direction := str(prior.get("direction", "west"))
	if delta.length() > 0.05:
		direction = _direction_from_screen_delta(delta)
	var state := str(actor.get("state", ""))
	var carrying := int(actor.get("carry_n", 0)) > 0
	var moving := state in MOVING_STATES and delta.length() > 0.05
	var key := sprite_key_for(actor)
	var texture := texture_for_key(key)
	var foot_anchor: Vector2 = STANDARD_V2_FOOT_ANCHORS.get(key, STANDARD_V2_FOOT_ANCHORS["idle"])
	var visual_kind := key
	var frame_index := 0
	var frame_name := "v2_%s_0" % key
	var motion_asset := "v2"
	## The existing v3 carry bank has no west direction and its unload art was
	## composed for the single-demo service dock. Only normal harvest-role walk
	## and harvest use the complete, shared-anchor v3 material in this slice.
	if str(actor.get("role", "")) == "harvest" and not carrying:
		if state == "harvesting":
			visual_kind = "harvest"
			frame_index = int(floor(_animation_seconds * 8.0)) % HARVEST_FRAMES.size()
			frame_name = "harvest_%d" % frame_index
			texture = HARVEST_FRAMES[frame_index]
			foot_anchor = STANDARD_FOOT_ANCHOR
			motion_asset = "v3"
		elif moving:
			visual_kind = "walk"
			var walk_frames: Array = _directional_frames(WALK_FRAMES, direction, "west")
			frame_index = int(floor(_animation_seconds * 9.0)) % walk_frames.size()
			frame_name = "walk_%s_%d" % [direction, frame_index]
			texture = walk_frames[frame_index]
			foot_anchor = STANDARD_FOOT_ANCHOR
			motion_asset = "v3"
	sprite.centered = false
	if sprite.texture != texture:
		sprite.texture = texture
	sprite.position = foot - foot_anchor
	sprite.visible = not bool(actor.get("dead", false))
	var support_enabled := int(actor.get("work_support", -1)) == GameData.Item.HAUL_FRAME and sprite.visible
	var support: Sprite2D = _support_views.get(actor_id, null) as Sprite2D
	if support_enabled:
		if support == null or not is_instance_valid(support):
			support = Sprite2D.new()
			support.name = "SupportView_" + actor_id.replace(":", "_")
			support.centered = true
			support.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# The frame sits behind the worker but stays in the same actor layer,
			# retaining the hub's building/vehicle foreground ordering.
			support.z_index = -1
			support.texture = HAUL_FRAME
			support.scale = Vector2.ONE
			_support_views[actor_id] = support
			add_child(support)
		support.position = (foot + Vector2(-12.0, -28.0)).round()
		support.visible = true
	_presentation[actor_id] = {
		"actor_id": actor_id,
		"state": state,
		"sprite_key": key,
		"visual_kind": visual_kind,
		"motion_asset": motion_asset,
		"frame_index": frame_index,
		"frame_name": frame_name,
		"direction": direction,
		"moving": moving,
		"foot_point": foot,
		"foot_anchor": foot_anchor,
		"cargo_visible": carrying,
		"sprite_position": sprite.position,
		"sprite_scale": sprite.scale,
		"texture_path": texture.resource_path if texture != null else "",
		"support_item": int(actor.get("work_support", -1)) if support_enabled else -1,
		"support_visible": support_enabled,
		"support_texture_path": HAUL_FRAME.resource_path if support_enabled else "",
		"support_position": support.position if support_enabled and support != null else Vector2.ZERO,
		"support_scale": support.scale if support_enabled and support != null else Vector2.ZERO,
		"support_z_index": support.z_index if support_enabled and support != null else 0,
	}
	return support_enabled

func _refresh_tracked(sprite: Sprite2D, actor_id: String, actor: Dictionary, hub: CanyonRecoveryHub) -> void:
	var foot := hub.presentation_point_for_actor(actor) if hub.has_method("presentation_point_for_actor") else hub.map_point(Vector2(float(actor.get("x", 0.0)), float(actor.get("y", 0.0))))
	var prior: Dictionary = _presentation.get(actor_id, {})
	var prior_foot: Vector2 = prior.get("foot_point", foot)
	var delta := foot - prior_foot
	var direction := str(prior.get("direction", "west"))
	if delta.length() > 0.05:
		direction = _direction_from_screen_delta(delta)
	var state := str(actor.get("state", ""))
	var carrying: bool = int(actor.get("carry_n", 0)) > 0
	var moving: bool = state in MOVING_STATES and delta.length() > 0.05
	var visual_kind := "idle"
	var frame_index := 0
	var frame_name := "idle_west_0"
	# The focused worker never falls back to the smaller v2 idle canvas: its
	# standing frame uses the same v3 baseline as every animated walk frame.
	var texture: Texture2D = WALK_FRAMES["west"][0]
	var foot_anchor := STANDARD_FOOT_ANCHOR
	if state == "harvesting":
		visual_kind = "harvest"
		frame_index = int(floor(_animation_seconds * 8.0)) % HARVEST_FRAMES.size()
		frame_name = "harvest_%d" % frame_index
		texture = HARVEST_FRAMES[frame_index]
	elif state == "dock_wait" and carrying:
		visual_kind = "unload"
		# The final empty-hands source frame is reserved for the next
		# session-authoritative frame, after _update_dock clears carry_n.
		frame_index = int(floor(_animation_seconds * 10.0)) % 3
		frame_name = "unload_%d" % frame_index
		texture = UNLOAD_FRAMES[frame_index]
		foot_anchor = UNLOAD_FOOT_ANCHORS[frame_index]
	elif state == "safe_wait" and carrying:
		visual_kind = "carry"
		var waiting_carry_frames: Array = _directional_frames(CARRY_FRAMES, direction, "southeast")
		frame_name = "carry_%s_0" % direction
		texture = waiting_carry_frames[0]
	elif carrying:
		visual_kind = "carry"
		var carry_frames: Array = _directional_frames(CARRY_FRAMES, direction, "southeast")
		frame_index = int(floor(_animation_seconds * 9.0)) % carry_frames.size() if moving else 0
		frame_name = "carry_%s_%d" % [direction, frame_index]
		texture = carry_frames[frame_index]
	elif moving:
		visual_kind = "walk"
		var walk_frames: Array = _directional_frames(WALK_FRAMES, direction, "west")
		frame_index = int(floor(_animation_seconds * 9.0)) % walk_frames.size()
		frame_name = "walk_%s_%d" % [direction, frame_index]
		texture = walk_frames[frame_index]
	sprite.centered = false
	sprite.texture = texture
	sprite.position = foot - foot_anchor
	sprite.visible = not bool(actor.get("dead", false))
	_presentation[actor_id] = {
		"actor_id": actor_id,
		"state": state,
		"direction": direction,
		"visual_kind": visual_kind,
		"frame_index": frame_index,
		"frame_name": frame_name,
		"foot_point": foot,
		"foot_anchor": foot_anchor,
		"sprite_scale": sprite.scale,
		"sprite_position": sprite.position,
		"moving": moving,
		"cargo_visible": carrying,
		"texture_path": texture.resource_path if texture != null else "",
	}

func _directional_frames(bank: Dictionary, direction: String, fallback: String) -> Array:
	if bank.has(direction):
		return bank[direction]
	return bank[fallback]

func _direction_from_screen_delta(delta: Vector2) -> String:
	if absf(delta.x) >= absf(delta.y) * 1.8:
		return "east" if delta.x > 0.0 else "west"
	if delta.x <= 0.0 and delta.y <= 0.0:
		return "northwest"
	if delta.x >= 0.0 and delta.y >= 0.0:
		return "southeast"
	return "east" if delta.x > 0.0 else "west"

func view_count() -> int:
	return _views.size()

func support_view_count() -> int:
	return _support_views.size()

## Test/capture-only readback. It mirrors the render choice and is never fed
## back into the route session.
func debug_snapshot(actor_id: String) -> Dictionary:
	return Dictionary(_presentation.get(actor_id, {})).duplicate(true)

func sprite_key_for(actor: Dictionary) -> String:
	var state := str(actor.get("state", ""))
	if int(actor.get("carry_n", 0)) > 0 or state in ["rescue_hold", "rescue_return"]:
		return "carry"
	if state == "harvesting":
		return "harvest"
	if state in ["to_resource", "to_relay", "to_base", "to_base_empty", "dock_wait", "injured_return", "outpost_move", "escort", "rescue_move", "rescue_return"]:
		return "walk"
	return "idle"

func texture_for_key(key: String) -> Texture2D:
	match key:
		"walk":
			return WALK
		"harvest":
			return HARVEST
		"carry":
			return CARRY
		_:
			return IDLE
