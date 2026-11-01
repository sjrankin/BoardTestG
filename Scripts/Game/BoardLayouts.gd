class_name BoardLayouts
extends RefCounted
## The shapes of the irregular 2D boards. A layout is a picture of the board, one string per row, top row first: `#` is a cell,
## `.` is a gap (nothing there, not even a Blocker). The cells of a layout are all connected along their sides (the test checks it).
## A layout is to an irregular board what a width and height are to a rectangular one: `Size` and `Gaps` turn it into the numbers
## `BoardModel` and `LevelDefinition` take, so levels and Settings > Board > Layout use them the same way.

const Cell := "#"
const Gap := "."

## Name -> rows. Index 0 of `Names` is the plain rectangle (no layout); `Names[1..]` are these, in this order.
const Rows: Dictionary = {
	"Diamond": [
		"....#....",
		"...###...",
		"..#####..",
		".#######.",
		"#########",
		".#######.",
		"..#####..",
		"...###...",
		"....#....",
	],
	"Cross": [
		"...###...",
		"...###...",
		"...###...",
		"#########",
		"#########",
		"#########",
		"...###...",
		"...###...",
		"...###...",
	],
	"Hourglass": [
		"#########",
		".#######.",
		"..#####..",
		"...###...",
		"...###...",
		"...###...",
		"..#####..",
		".#######.",
		"#########",
	],
	"Heart": [
		".###.###.",
		"#########",
		"#########",
		"#########",
		".#######.",
		"..#####..",
		"...###...",
		"....#....",
	],
	"Ring": [
		"#########",
		"#########",
		"#########",
		"###...###",
		"###...###",
		"###...###",
		"#########",
		"#########",
		"#########",
	],
	"Octagon": [
		"..####..",
		".######.",
		"########",
		"########",
		"########",
		"########",
		".######.",
		"..####..",
	],
}

const Rectangle := "Rectangle"

## "Rectangle" first, then every layout, for the Settings picker. A saved choice is an index into this list.
static func Names() -> Array[String]:
	var Result: Array[String] = [Rectangle]
	for Name in Rows:
		Result.append(Name)
	return Result


static func Has(Name: String) -> bool:
	return Rows.has(Name)


## Columns x rows of the layout's rectangle.
static func Size(Name: String) -> Vector2i:
	var Picture: Array = Rows[Name]
	return Vector2i((Picture[0] as String).length(), Picture.size())


## The gap cells of the layout (x = Col, y = Row), in the form `BoardModel` and `LevelDefinition.PresetGaps` take.
static func Gaps(Name: String) -> Array[Vector3i]:
	var Result: Array[Vector3i] = []
	if not Rows.has(Name):
		return Result
	var Picture: Array = Rows[Name]
	for Row in Picture.size():
		var Line: String = Picture[Row]
		for Col in Line.length():
			if Line[Col] != Cell:
				Result.append(Vector3i(Col, Row, 0))
	return Result


## How many cells (pieces and Blockers) the layout has.
static func CellCount(Name: String) -> int:
	var Size2 := Size(Name)
	return Size2.x * Size2.y - Gaps(Name).size()
