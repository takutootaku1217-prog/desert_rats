extends RefCounted
## C owns ground growth until a validated return. Entry quantities never change.
const WAIT_REASON := "通常資源の再生待ち"

static func add_metadata(resource: Dictionary, row: Dictionary) -> void:
	if not row.has("regeneration"): return
	resource["entry_regeneration"] = row.regeneration.duplicate(true)
	resource["regeneration"] = row.regeneration.duplicate(true)
	resource["regenerated"] = 0

static func tick(s) -> void:
	var grew := false
	for r in s.resources.values():
		if not r.has("regeneration"): continue
		var before: int = r.remaining
		r.remaining = ResourceRegeneration.settle(r.regeneration, before, s.entry_director_elapsed + s.elapsed, false)
		r.regenerated += r.remaining - before
		grew = grew or r.remaining > before
	if not grew or s.phase != "local" or s.capacity_paused: return
	for id in s.actors:
		var a: Dictionary = s.actors[id]
		# This precise wait reason is assigned only at a failed resource claim.
		# Recall, injury, treatment, rescue and expiry idle states never qualify.
		if a.state != "idle" or a.get("wait_reason") != WAIT_REASON or a.down or a.hp <= FieldOperations.RETREAT_HP or a.role not in ["harvest", "solo"]: continue
		if not s.rescue_ledger.case_for(id).is_empty() or s.expired_recovery.owns(id) or s.rescue_approach.has_mine_return(id): continue
		a.state = "to_resource"
		a.wait_reason = ""
		s._refresh_actor_path(id)

static func total(s) -> int:
	var result := 0
	for r in s.resources.values(): result += int(r.get("regenerated",0))
	return result

static func valid_resource(r: Dictionary, now: float) -> bool:
	if not r.has("regeneration"):
		return not r.has("entry_regeneration") and not r.has("regenerated")
	if not r.get("initial") is int or not r.get("remaining") is int or not r.get("regenerated") is int or r.regenerated < 0: return false
	if not ResourceRegeneration.valid(r.get("entry_regeneration"),r.initial,now) or not ResourceRegeneration.valid(r.regeneration,r.remaining,now): return false
	if r.regeneration.capacity != r.entry_regeneration.capacity or r.regeneration.last < r.entry_regeneration.last: return false
	if r.regeneration.revision != r.entry_regeneration.revision + r.regenerated: return false
	var available_time := now - float(r.entry_regeneration.last) + float(r.entry_regeneration.credit)
	return float(r.regenerated) * ResourceRegeneration.SECONDS_PER_UNIT + float(r.regeneration.credit) <= available_time + 0.00001

static func matches_entry(r: Dictionary, row: Dictionary) -> bool:
	if r.has("regeneration"):
		return row.get("regeneration") == r.entry_regeneration and row.data.get("max_amount") == r.regeneration.capacity
	return not row.has("regeneration")

static func migrate_legacy(data: Dictionary, sources: Dictionary, now: float) -> Dictionary:
	var copy := data.duplicate(true)
	if not copy.get("resources") is Dictionary: return {}
	var expected := {}
	for id in sources:
		var row: Dictionary = sources[id]
		if row.type != "gather": continue
		if row.data.remaining > 0: expected[id] = true
		if row.data.remaining > 0:
			var r = copy.resources.get(id)
			if not r is Dictionary or r.size() != 5 or not r.get("initial") is int or not r.get("remaining") is int: return {}
			if r.initial != row.data.remaining or r.remaining < 0 or r.remaining > r.initial: return {}
	for id in copy.resources:
		if not expected.has(id): return {}
	for id in sources:
		var row: Dictionary = sources[id]
		if not row.has("regeneration"): continue
		if not copy.resources.has(id):
			copy.resources[id] = {"item":row.data.item,"kind":row.data.kind,"initial":0,"remaining":0,"reservation":""}
		add_metadata(copy.resources[id],row)
		# Legacy progress was finite. Start at saved game time, not entry time.
		copy.resources[id].regeneration.last = now
	copy.schema = 10
	return copy

# JSON-only fixture compatibility. Complete-file snapshots never call this;
# their typed Variant DTO and strict integer checks remain unchanged.
static func normalize_fixture_resources(resources: Dictionary) -> bool:
	for r in resources.values():
		if not r is Dictionary: return false
		if not r.has("regeneration"): continue
		for key in ["initial","remaining","regenerated"]:
			if not _normalize_integer(r,key): return false
		for key in ["regeneration","entry_regeneration"]:
			if not r.get(key) is Dictionary: return false
			for integer in ["version","capacity","revision"]:
				if not _normalize_integer(r[key],integer): return false
	return true

static func _normalize_integer(row: Dictionary, key: String) -> bool:
	var value = row.get(key)
	if not ResourceRegeneration.number(value) or float(value) != float(int(value)): return false
	row[key] = int(value)
	return true

static func mark_legacy_waiters(s) -> void:
	if s.phase != "local" or s.total_source_remaining() != 0 or s.capacity_paused: return
	for id in s.actors:
		var a: Dictionary = s.actors[id]
		if a.state != "idle" or a.role != "harvest" or a.get("wait_reason","") != "" or a.down or a.hp <= FieldOperations.RETREAT_HP: continue
		if a.get("expired_self_return",false) or a.get("rescue_mine_return",false) or not s.rescue_ledger.case_for(id).is_empty() or s.expired_recovery.owns(id) or s.rescue_approach.has_mine_return(id):continue
		a.wait_reason = WAIT_REASON
