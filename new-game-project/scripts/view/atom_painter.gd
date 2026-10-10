class_name AtomPainter
extends RefCounted
## Draws one atom (stubs, body, wildcard sockets, bomb ring) on any CanvasItem.

const COLORS: Array[Color] = [
	Color("6ab04c"), # 1 connection
	Color("4a90d9"), # 2
	Color("e0a030"), # 3
	Color("c0504d"), # 4
]
const BOMB_COLOR := Color("2b2f38")


static func color(atom: int) -> Color:
	if Atoms.is_wild(atom):
		return Palette.PURPLE
	if Atoms.is_bomb(atom):
		return BOMB_COLOR
	return COLORS[Atoms.connection_count(atom) - 1]


## cell is the board cell used to tell open from bonded stubs; pass (-1,-1) or a null board
## to draw all stubs neutral. unit is the pixel size of one cell.
static func draw(canvas: CanvasItem, center: Vector2, mask: int, alpha: float, scale: float, unit: float, board: Board, cell: Vector2i) -> void:
	var on_board := board != null and board.in_bounds(cell)
	for dir in 4:
		if mask & (1 << dir):
			var open := on_board and not board.is_bonded(cell, dir)
			var col := Palette.BAD if open else Palette.TEXT
			col.a = alpha
			var tip := center + Vector2(Atoms.OFFSETS[dir]) * (unit * 0.5 * scale)
			canvas.draw_line(center, tip, col, 8.0 * scale * unit / 72.0)
	var body := color(mask)
	body.a = alpha
	canvas.draw_circle(center, unit * 0.27 * scale, body)
	if Atoms.is_wild(mask):
		# Four sockets: lit when a neighbour's connection is plugged into the wildcard.
		for dir in 4:
			var lit := on_board and board.is_linked(cell, dir)
			var dot := Palette.TEXT if lit else Palette.PURPLE.darkened(0.45)
			dot.a = alpha
			canvas.draw_circle(center + Vector2(Atoms.OFFSETS[dir]) * unit * 0.4 * scale, unit * 0.07 * scale, dot)
		var core := Color.WHITE
		core.a = alpha
		canvas.draw_arc(center, unit * 0.16 * scale, 0.0, TAU, 20, core, 3.0 * scale * unit / 72.0)
	if Atoms.is_bomb(mask):
		var ring := Palette.ORANGE
		ring.a = alpha
		canvas.draw_arc(center, unit * 0.27 * scale, 0.0, TAU, 24, ring, 4.0 * scale * unit / 72.0)
		canvas.draw_circle(center, unit * 0.09 * scale, ring)
		canvas.draw_line(center + Vector2(0, -unit * 0.27) * scale, center + Vector2(unit * 0.1, -unit * 0.4) * scale, ring, 3.0 * scale * unit / 72.0)
