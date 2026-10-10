class_name Progression
extends RefCounted
## Character level, XP and pending card picks.

const SUPER_EVERY := 5
const MAX_RARE_CARDS := 4
const OFFER_SIZE := 3

var level := 1
var xp := 0
var mods := Modifiers.new()
var pick_levels: Array[int] = []


static func xp_needed(for_level: int) -> int:
	return 20 + 12 * for_level


func add_xp(base_points: int) -> int:
	xp += roundi(base_points * mods.xp_mult())
	var gained := 0
	while xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		pick_levels.append(level)
		gained += 1
	return gained


func has_pending_pick() -> bool:
	return not pick_levels.is_empty()


func _owned_with(rarity: int) -> int:
	var n := 0
	for id in mods.stacks.keys():
		if int(Cards.get_def(id).get("rarity", -1)) == rarity:
			n += int(mods.stacks[id])
	return n


func roll_offer(rng: RandomNumberGenerator, versus: bool) -> Array[String]:
	var lvl: int = pick_levels[0] if not pick_levels.is_empty() else level
	var pools := {Cards.Rarity.BASIC: [], Cards.Rarity.RARE: [], Cards.Rarity.SUPER: []}
	var rare_full := _owned_with(Cards.Rarity.RARE) >= MAX_RARE_CARDS
	var have_super := _owned_with(Cards.Rarity.SUPER) > 0
	for id in Cards.all_ids():
		var d := Cards.get_def(id)
		if mods.count(id) >= int(d.max):
			continue
		if d.versus_only and not versus:
			continue
		if d.rarity == Cards.Rarity.RARE and rare_full:
			continue
		if d.rarity == Cards.Rarity.SUPER and (have_super or lvl < SUPER_EVERY):
			continue
		pools[d.rarity].append(id)
	var out: Array[String] = []
	if lvl % SUPER_EVERY == 0 and not pools[Cards.Rarity.SUPER].is_empty():
		_take(pools[Cards.Rarity.SUPER], rng, out)
	while out.size() < OFFER_SIZE:
		var order: Array = _rarity_order(lvl, rng)
		var got := false
		for r in order:
			if not pools[r].is_empty():
				_take(pools[r], rng, out)
				got = true
				break
		if not got:
			break
	# Shuffle so a guaranteed super is not always first.
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out


func _take(pool: Array, rng: RandomNumberGenerator, out: Array[String]) -> void:
	var i := rng.randi_range(0, pool.size() - 1)
	out.append(pool[i])
	pool.remove_at(i)


## Preferred rarity first (weighted roll), then fallbacks.
func _rarity_order(lvl: int, rng: RandomNumberGenerator) -> Array:
	var B := Cards.Rarity.BASIC
	var R := Cards.Rarity.RARE
	var S := Cards.Rarity.SUPER
	var roll := rng.randf()
	if lvl < 3:
		return [B, R]
	if lvl < 5:
		return [R, B] if roll < 0.2 else [B, R]
	if roll < 0.05:
		return [S, R, B]
	if roll < 0.40:
		return [R, B, S]
	return [B, R, S]


func pick(id: String) -> bool:
	if pick_levels.is_empty() or not mods.add(id):
		return false
	pick_levels.pop_front()
	return true


func reset() -> void:
	level = 1
	xp = 0
	mods = Modifiers.new()
	pick_levels = []


func to_dict() -> Dictionary:
	return {"level": level, "xp": xp, "mods": mods.to_dict(), "pick_levels": pick_levels.duplicate()}


static func from_dict(d) -> Progression:
	var p := Progression.new()
	if typeof(d) != TYPE_DICTIONARY:
		return p
	var lv = d.get("level", 1)
	var x = d.get("xp", 0)
	if typeof(lv) == TYPE_INT or typeof(lv) == TYPE_FLOAT:
		p.level = clampi(int(lv), 1, 999)
	if typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT:
		p.xp = maxi(0, int(x))
	p.mods = Modifiers.from_dict(d.get("mods", {}))
	var pl = d.get("pick_levels", [])
	if typeof(pl) == TYPE_ARRAY:
		for v in pl:
			if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and p.pick_levels.size() < 100:
				p.pick_levels.append(clampi(int(v), 1, 999))
	return p


func save_to(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return OK


static func load_from(path: String) -> Progression:
	if not FileAccess.file_exists(path):
		return Progression.new()
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return Progression.new()
	return from_dict(json.data)
