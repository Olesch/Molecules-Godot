class_name Cards
extends RefCounted
## Card definitions for character leveling. Pure data, no nodes.

enum Rarity { BASIC, RARE, SUPER }

static func _d(n: String, r: int, mx: int, desc: String, versus := false, risky := false, downside := "") -> Dictionary:
	return {"name": n, "rarity": r, "max": mx, "desc": desc, "versus_only": versus, "risky": risky, "downside": downside}


const _B := Rarity.BASIC
const _R := Rarity.RARE
const _S := Rarity.SUPER

static var DEFS: Dictionary = {
	"long_view": _d("Long View", _B, 2, "+1 queue atom per level"),
	"demolition": _d("Demolition", _B, 3, "+2% bomb chance per level"),
	"joker_supply": _d("Joker Supply", _B, 5, "+2% wildcard chance per level"),
	"high_scorer": _d("High Scorer", _B, 5, "+10% points per level"),
	"heavy_hitter": _d("Heavy Hitter", _B, 5, "+10% attack per level", true),
	"thick_skin": _d("Thick Skin", _B, 2, "Stray landing cap -1 per turn", true),
	"efficient_cleaner": _d("Efficient Cleaner", _B, 3, "Clears cancel +50% more incoming strays", true),
	"tidy_start": _d("Tidy Start", _B, 3, "3 fewer preplaced atoms at start"),
	"lucky_shapes": _d("Lucky Shapes", _B, 3, "Cross atoms half as likely"),
	"fast_learner": _d("Fast Learner", _B, 5, "+10% XP per level"),
	"stash": _d("Stash", _R, 1, "Hold slot: swap current atom with a stored one"),
	"reroll": _d("Reroll", _R, 1, "Discard the current atom, recharges every 4 placements"),
	"gardener": _d("Gardener", _R, 1, "Each clear removes one random stray atom", true),
	"combo_chain": _d("Combo Chain", _R, 1, "Clearing again within 3 placements gives x1.5 points"),
	"overcharge": _d("Overcharge", _R, 1, "A molecule of 4+ atoms puts a free bomb first in queue"),
	"lifeline": _d("Lifeline", _R, 1, "At 78%+ board fill the next atom becomes a wildcard (4 placement cooldown)"),
	"salvage": _d("Salvage", _R, 1, "Blast victims count double for points and attack"),
	"shield": _d("Shield", _R, 1, "Every 4th placement incoming strays are held back", true),
	"counterstrike": _d("Counterstrike", _R, 1, "When strays land on you, send 1 back", true),
	"glass_cannon": _d("Glass Cannon", _R, 1, "+50% attack", true, true, "+25% incoming strays (rounded up)"),
	"hot_potato": _d("Hot Potato", _R, 1, "+8% bomb chance", false, true, "-7% wildcard chance"),
	"overclock": _d("Overclock", _R, 1, "+15% points", false, true, "Queue shows 2 fewer atoms (min 2)"),
	"loose_ends": _d("Loose Ends", _S, 1, "A molecule of 3+ atoms clears with up to 1 open connection left"),
	"two_hand": _d("Two-Hand", _S, 1, "Hold two atoms and choose: swap current and next"),
	"big_game": _d("Big Game", _S, 1, "Molecules need 3+ atoms to clear, but score x2", false, false,
		"2-atom molecules block their cells!"),
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for k in DEFS.keys():
		out.append(k)
	return out


static func describe(id: String, owned: int) -> Dictionary:
	var d := get_def(id)
	if d.is_empty():
		return {}
	return {
		"id": id, "name": d.name, "desc": d.desc, "rarity": d.rarity, "risky": d.risky,
		"downside": d.downside, "owned": owned, "max": d.max, "versus_only": d.versus_only,
	}
