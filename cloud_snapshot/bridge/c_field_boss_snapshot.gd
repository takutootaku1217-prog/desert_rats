extends RefCounted
## Narrow complete-save extension for one independent encounter, not outposts.
static func valid(s, world: Dictionary) -> bool:
	if not s.is_region_boss():
		if s.encounter_id!="" or not s.encounter_entry.is_empty() or s.outpost_enabled or not s.outpost_enemies.is_empty() or not s.outpost_cleared or s.outpost_retreats!=0:return false
		for a in s.actors.values():
			if a.combat_target!="" or a.state in ["outpost_move","outpost_wait","combat"] or a.resume_state in ["outpost_move","outpost_wait","combat"]:return false
		return true
	if not s.outpost_enabled or not s.mine_path_engineering or s.outpost_retreats<0:return false
	if not FirstRegionCompletion.enemy_record_valid({"enemies":s.outpost_enemies,"cleared":s.outpost_cleared},s.actors.size()):return false
	if not world.get("region_completion") is Dictionary:return false
	if world.region_completion.encounters.get(s.encounter_id,{})!=s.encounter_entry:return false
	var e:Dictionary=s.outpost_enemies[FirstRegionCompletion.BOSS_ID]
	if e.dead and (e.engager!="" or e.target!=""):return false
	if e.engager!="":
		if not s.actors.has(e.engager):return false
		var a:Dictionary=s.actors[e.engager]
		if a.down or a.hp<=FieldOperations.RETREAT_HP or a.role!="escort" or a.state not in ["outpost_move","combat","safe_wait"] or (a.state=="safe_wait" and a.resume_state!="outpost_move") or a.combat_target!=e.id:return false
	if e.target!="":
		if not s.actors.has(e.target) or not s._outpost_actor_can_be_targeted(e.target,e):return false
	for id in s.actors:
		var a:Dictionary=s.actors[id]
		# Old complete saves bypass the new entry loadout check. Do not resume
		# an assigned cart escort whose combat approach has no safe return.
		# Nonparticipants and already-returned actors keep their existing owners.
		if a.role=="escort" and a.work_support==GameData.Item.HANDCART:
			var intent:bool=a.combat_target!="" or a.state in ["outpost_move","combat"] or (a.state=="safe_wait" and a.resume_state in ["outpost_move","combat"])
			intent=intent or (s.phase=="local" and not s.outpost_cleared and (a.state=="escort" or (a.state=="safe_wait" and a.resume_state=="")))
			var safely_returned:bool=Vector2(a.x,a.y).distance_to(s.parking_anchor())<=0.1 and a.state in ["idle","injured_wait","rescue_treatment"]
			if intent or (a.entry_hp>FieldOperations.RETREAT_HP and not safely_returned):return false
		if a.combat_target!="" and (a.combat_target!=e.id or e.engager!=id or e.dead):return false
		if a.state in ["outpost_move","combat"]:
			if a.role!="escort" or a.down or a.hp<=FieldOperations.RETREAT_HP:return false
			if not s.outpost_cleared and (a.combat_target!=e.id or e.engager!=id):return false
		if a.state=="outpost_wait" and (a.role!="harvest" or s.outpost_cleared):return false
	return true

static func combat_plan(s, a: Dictionary, p: Dictionary) -> Array:
	if not s.is_region_boss() or a.role!="escort" or a.combat_target!=FirstRegionCompletion.BOSS_ID:return []
	if p.get("combat_target")!=a.combat_target or not p.get("combat_destination") is Vector2 or not p.combat_destination.is_finite():return []
	# The enemy can have moved since this path was issued. Retain its bounded
	# issued destination; never treat arbitrary current coordinates as a new path.
	if p.combat_destination.distance_to(FirstRegionCompletion.BOSS_HOME)>Enemy.TERRITORY+Enemy.SIGHT:return []
	return [s.BYPASS if a.route=="bypass" else s.GATE,s.OUTPOST_COVER,p.combat_destination]
