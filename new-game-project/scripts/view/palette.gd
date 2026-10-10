class_name Palette
extends RefCounted
## Shared UI colours, so every screen uses the same values.

const BG := Color("1e2229")
const PANEL := Color("272c35")
const FIELD := Color("2a303a")
const DISABLED := Color("2f353f")
const GRID := Color("353b46")
const TEXT := Color("e8ecf1")
const DIM := Color("8f98a8")
const BAD := Color("ff5d5d")
const GOOD := Color("6ab04c")
const BLUE := Color("4a90d9")
const PURPLE := Color("b07cff")
const ORANGE := Color("ff9a3c")
const RED := Color("c0504d")
const GOLD := Color("ffe27a")

## Indexed by Cards.Rarity.
const RARITY: Array[Color] = [BLUE, PURPLE, ORANGE]
