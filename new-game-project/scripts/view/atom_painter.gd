class_name AtomPainter
extends RefCounted
## Draws one atom (stubs, body, wildcard sockets, bomb ring) on any CanvasItem.

## Plain atoms are all blue whatever their connection count; bombs and wildcards stand out.
const ATOM_COLOR := Color("4a90d9")
const BOMB_COLOR := Color("2b2f38")


## Wildcards cycle through the rainbow; `phase` (0..1) offsets the hue so neighbours differ.
static func rainbow(phase := 0.0) -> Color:
	return Color.from_hsv(fmod(Time.get_ticks_msec() / 1000.0 * 1.5 + phase, 1.0), 0.7, 1.0)


static func color(atom: int, phase := 0.0) -> Color:
	if Atoms.is_wild(atom):
		return rainbow(phase)
	if Atoms.is_bomb(atom):
		return BOMB_COLOR
	return ATOM_COLOR


## cell is the board cell used to tell open from bonded stubs; pass (-1,-1) or a null board
## to draw all stubs neutral. unit is the pixel size of one cell.
static func draw(canvas: CanvasItem, center: Vector2, mask: int, alpha: float, scale: float, unit: float, board: Board, cell: Vector2i, topology: Topology = null) -> void:
	var topo := topology if topology != null else Topology.square()
	var on_board := board != null and board.in_bounds(cell)
	for dir in topo.dir_count:
		if mask & (1 << dir):
			var open := on_board and not board.is_bonded(cell, dir)
			var col := Palette.BAD if open else Palette.TEXT
			col.a = alpha
			var tip := center + topo.dir_vector(dir) * (unit * 0.5 * scale)
			canvas.draw_line(center, tip, col, 8.0 * scale * unit / 72.0)
	var body := color(mask, (center.x + center.y) * 0.003)
	body.a = alpha
	canvas.draw_circle(center, unit * 0.27 * scale, body)
	if Atoms.is_wild(mask):
		# One socket per direction: lit when a neighbour's connection is plugged into the wildcard.
		for dir in topo.dir_count:
			var lit := on_board and board.is_linked(cell, dir)
			var dot := Palette.TEXT if lit else rainbow((center.x + center.y) * 0.003).darkened(0.5)
			dot.a = alpha
			canvas.draw_circle(center + topo.dir_vector(dir) * unit * 0.4 * scale, unit * 0.07 * scale, dot)
		var core := Color.WHITE
		core.a = alpha
		canvas.draw_arc(center, unit * 0.16 * scale, 0.0, TAU, 20, core, 3.0 * scale * unit / 72.0)
	if Atoms.is_bomb(mask):
		var ring := Palette.ORANGE
		ring.a = alpha
		canvas.draw_arc(center, unit * 0.27 * scale, 0.0, TAU, 24, ring, 4.0 * scale * unit / 72.0)
		canvas.draw_circle(center, unit * 0.09 * scale, ring)
		canvas.draw_line(center + Vector2(0, -unit * 0.27) * scale, center + Vector2(unit * 0.1, -unit * 0.4) * scale, ring, 3.0 * scale * unit / 72.0)
