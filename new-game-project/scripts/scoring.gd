class_name Scoring
extends RefCounted
## Points and attack strength for a cleared molecule.

## Hard limit on stray atoms that can land on a board in one turn.
const GARBAGE_PER_TURN := 5


static func triangle(n: int) -> int:
	return (n * (n + 1)) >> 1


## Triangle number for the molecule, plus 1 per atom wiped by a bomb blast.
static func points(molecule_size: int, blasted: int) -> int:
	if molecule_size <= 0:
		return 0
	return triangle(molecule_size) + blasted


## Stray atoms sent to the opponent: one fewer than the molecule size, plus one per blast victim.
static func attack(molecule_size: int, blasted: int) -> int:
	if molecule_size <= 0:
		return 0
	return molecule_size - 1 + blasted
