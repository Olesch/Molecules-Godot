class_name Cards
extends RefCounted
## Card definitions for character leveling. Pure data, no nodes.

enum Rarity { BASIC, RARE, SUPER }

static func _d(n: String, r: int, mx: int, desc: String, versus := false, risky := false, downside := "") -> Dictionary:
	return {"name": n, "rarity": r, "max": mx, "desc": desc, "versus_only": versus, "risky": risky, "downside": downside}


const LONG_VIEW := "long_view"
const DEMOLITION := "demolition"
const MINI_BOMBS := "mini_bombs"
const JOKER_SUPPLY := "joker_supply"
const HIGH_SCORER := "high_scorer"
const HEAVY_HITTER := "heavy_hitter"
const THICK_SKIN := "thick_skin"
const EFFICIENT_CLEANER := "efficient_cleaner"
const TIDY_START := "tidy_start"
const LUCKY_SHAPES := "lucky_shapes"
const FAST_LEARNER := "fast_learner"
const STASH := "stash"
const REROLL := "reroll"
const GARDENER := "gardener"
const COMBO_CHAIN := "combo_chain"
const OVERCHARGE := "overcharge"
const LIFELINE := "lifeline"
const SALVAGE := "salvage"
const SHIELD := "shield"
const COUNTERSTRIKE := "counterstrike"
const GLASS_CANNON := "glass_cannon"
const HOT_POTATO := "hot_potato"
const OVERCLOCK := "overclock"
const LOOSE_ENDS := "loose_ends"
const TWO_HAND := "two_hand"
const BIG_GAME := "big_game"

const _B := Rarity.BASIC
const _R := Rarity.RARE
const _S := Rarity.SUPER

static var DEFS: Dictionary = {
	LONG_VIEW: _d("Long View", _B, 4, "+1 preview atom per level (you start with 1)"),
	DEMOLITION: _d("Demolition", _B, 3, "+5% bomb chance per level"),
	MINI_BOMBS: _d("Mini Bombs", _B, 3, "Bombs can also appear on atoms with fewer connections: one fewer per level (only the most-connected atoms at the start)"),
	JOKER_SUPPLY: _d("Joker Supply", _B, 5, "+3% wildcard chance per level (none at the start)"),
	HIGH_SCORER: _d("High Scorer", _B, 5, "+10% points per level"),
	HEAVY_HITTER: _d("Heavy Hitter", _B, 5, "+10% attack per level", true),
	THICK_SKIN: _d("Thick Skin", _B, 2, "Stray landing cap -1 per turn", true),
	EFFICIENT_CLEANER: _d("Efficient Cleaner", _B, 3, "Clears cancel +50% more incoming strays", true),
	TIDY_START: _d("Tidy Start", _B, 3, "3 fewer preplaced atoms at start"),
	LUCKY_SHAPES: _d("Lucky Shapes", _B, 3, "Cross atoms half as likely"),
	FAST_LEARNER: _d("Fast Learner", _B, 5, "+10% XP per level"),
	STASH: _d("Stash", _R, 1, "Hold slot: swap current atom with a stored one"),
	REROLL: _d("Reroll", _R, 1, "Discard the current atom, recharges every 4 placements"),
	GARDENER: _d("Gardener", _R, 1, "Each clear removes one random stray atom", true),
	COMBO_CHAIN: _d("Combo Chain", _R, 1, "Clearing again within 3 placements gives x1.5 points"),
	OVERCHARGE: _d("Overcharge", _R, 1, "A molecule of 4+ atoms puts a free bomb first in queue"),
	LIFELINE: _d("Lifeline", _R, 1, "At 78%+ board fill the next atom becomes a wildcard (4 placement cooldown)"),
	SALVAGE: _d("Salvage", _R, 1, "Atoms wiped by blasts score 1 point each and count double for attack"),
	SHIELD: _d("Shield", _R, 1, "Every 4th placement incoming strays are held back", true),
	COUNTERSTRIKE: _d("Counterstrike", _R, 1, "When strays land on you, send 1 back", true),
	GLASS_CANNON: _d("Glass Cannon", _R, 1, "+50% attack", true, true, "+25% incoming strays (rounded up)"),
	HOT_POTATO: _d("Hot Potato", _R, 1, "+8% bomb chance", false, true, "-7% wildcard chance"),
	OVERCLOCK: _d("Overclock", _R, 1, "+15% points", false, true, "Preview shows 1 fewer atom (none at the start)"),
	LOOSE_ENDS: _d("Loose Ends", _S, 1, "A molecule of 3+ atoms clears with up to 1 open connection left"),
	TWO_HAND: _d("Two-Hand", _S, 1, "Hold two atoms and choose: swap current and next"),
	BIG_GAME: _d("Big Game", _S, 1, "Molecules need 3+ atoms to clear, but score x2", false, false,
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
