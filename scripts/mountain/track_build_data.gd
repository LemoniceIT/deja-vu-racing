extends RefCounted

var centerline := PackedVector3Array()
var lots: Array[Dictionary] = []

# Terrain samples shared with both vegetation builders.
var terrain_min := Vector2.ZERO
var terrain_max := Vector2.ZERO
var terrain_columns: int = 0
var terrain_rows: int = 0
var terrain_heights := PackedFloat32Array()

# Both vegetation passes populate the same tree-spacing grid.
var vegetation_grid := {}
var nature_cache := {}
