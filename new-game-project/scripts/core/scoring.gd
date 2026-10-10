class_name Scoring
extends RefCounted
## Points and attack strength for a cleared molecule.

## The first atom of a molecule is worth 1 point, the second 2, the third 3, the fourth 4
## and every further atom 5.
const MAX_ATOM_POINTS := 5


## Points of the n-th atom (counting from 1) of a molecule.
static func atom_points(n: int) -> int:
	return clampi(n, 0, MAX_ATOM_POINTS)


## Points of a molecule with this many atoms. Atoms wiped by a bomb blast are not part of
## the molecule and score nothing (unless a card says otherwise).
static func points(molecule_size: int) -> int:
	if molecule_size <= 0:
		return 0
	var shown := mini(molecule_size, MAX_ATOM_POINTS)
	return (shown * (shown + 1)) / 2 + (molecule_size - shown) * MAX_ATOM_POINTS


## In versus, every this many points scored send one stray atom to the opponent.
const POINTS_PER_ATTACK := 25
