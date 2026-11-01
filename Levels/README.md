# Level files

Levels are plain JSON, read when the game starts (and again from Settings > Game > Reload Levels).

`PrimaryLevelIndex.json` lists the level files, in play order; level N is the Nth level of all the files together:

```json
{ "Version": 1, "Files": ["Classic.json", "Irregular.json", "Countdown.json"] }
```

The game reads `PrimaryLevelIndex.json` from its Levels folder (`user://Levels/`, which Settings > Game > Copy Levels fills with
copies of these files) if that has one, otherwise from the built-in `res://Levels/`. A problem in a file (bad JSON, a missing field,
an unplayable map) drops that level, is printed to the console and is counted under the Level list in Settings; other levels still load.

## A level file

```json
{
  "Version": 1,
  "Name": "My Levels",
  "Levels": [
	{
	  "Id": "Mine 1",
	  "Name": "Fuse",
	  "Difficulty": 3,
	  "Colors": 4,
	  "Goals": [ { "Group": 0, "Remove": 12 }, { "Group": 2, "Remove": 9 } ],
	  "Turns": 21,
	  "Time": 21,
	  "Shape": "Rounded Cube",
	  "RemovalEffect": "Puff of Smoke",
	  "Legend": { "a": { "Group": 1, "Count": 3 }, "b": { "Count": 2 } },
	  "Map": [
		"#######",
		"#a###a#",
		"###B###",
		"#b###b#",
        "#######"
	  ]
	}
  ]
}
```

| Field | Meaning |
|---|---|
| `Id` | Unique name; the difficulty test's results are kept under it. Default: file name + place in the file. |
| `Name` | Shown in the Level list and at the top of the screen. Default: "Level N". |
| `Difficulty` | 1 to 10, the starting value (the difficulty test replaces it with a measured one). Default: the level's number, at most 10. |
| `Colors` | 3 to 8 groups (colors) dealt. Required. |
| `Goals` | Required. Each `{ "Group": color, "Remove": pieces }`; groups are numbered as the colors are: 0 red, 1 green, 2 blue, 3 cyan, 4 yellow, 5 magenta. |
| `Turns` / `Time` | Turns allowed in Turn mode, seconds in Timed mode. Left out, they are worked out from the goal and the board size. |
| `Shape` | Optional piece shape by name (Cube, Sphere, Cone, Cylinder, Glow, Rounded Cube, Joined Cubes, Joined Spheres, Joined Cylinders, Joined Glow). |
| `RemovalEffect` | Optional: Fly Away, Mini Me, Explode, Disappear, Spin and Shrink, Spin then Vanish, Puff of Smoke. |
| `Map` | Required. One text row per board row, top first; 3 to 20 cells each way; a short row is finished with gaps. Gaps can be anywhere (in the middle, or splitting the board into separate areas of play); at least three open cells must touch somewhere, so a group can form. |
| `Flow` | Optional. Rows of text like the map, giving the way pieces move in each cell (below). |
| `Links` | Optional. Cells whose pieces go to a cell somewhere else (below). |
| `Legend` | Optional. Adds symbols to the map (below). |

`Shape` and `RemovalEffect` are the level's choice; the player's Settings win when "Use my Block Shape / Removal Effect, not the level's" is on.

### Map symbols

Built in: `.` a gap (nothing there, as in an irregular board), `#` a piece of a random group, `B` a Blocker. The Legend adds more; a key is
one character, and its value is `{ "Type": "Gap" | "Blocker" | "Piece", "Group": n, "Count": n }`. A value with a `Group` or `Count` and no `Type`
is a Piece. `Group` left out means a random group; `Count` left out (or 0) means no countdown.

### Countdowns

A piece with a `Count` shows the number on it. Every time a group touching it along a side is removed, the number goes down by one (once per
group, however many of the group's pieces touch it); at 0 the piece is removed with the level's removal effect. A tap on the piece's own group
removes it outright. A Blocker has no count and never counts down. A piece removed by its countdown counts toward the goal (it is a piece of its group
that was removed) but is not a turn, and does not itself count its neighbours down.

### Gaps, separate areas and flow

A gap (`.`) can be anywhere. A gap at the top of a column (as gravity points) is open air that new pieces fall through; a gap in the
middle of a column stops pieces falling through it (the cells under it are fed from the side, or by their own source if the level has a `Flow`).
Areas of play that do not touch are fine; pieces and groups stay inside their own area, a shuffle mixes all of them.

Without `Flow` or `Links`, every column falls with gravity and new pieces come in from the top edge. With either, the level has its own flow:

- `Flow` is a list of rows, the same size as the map. Each character is the way the piece in that cell moves while the cell ahead is empty:
  `v` down, `^` up, `<` left, `>` right; `.`, `-` or a space means "no direction for this cell". A row can be shorter.
- **All or nothing.** A flow overrides the board's gravity, so it must cover every open cell: each cell that is not a gap or a Blocker needs a
  direction (or a link). If even one open cell is left without, the whole `Flow` and `Links` are ignored (a note appears under the Level list in
  Settings) and the level plays as if it had none. Gaps and Blockers need no direction; what you write on them is not used.
- The directions are fixed on the board: they do not turn with gravity, however the board is turned.
- A cell nothing flows into is a source: whenever it is empty a new piece appears there, falling in from the cell behind it. So a column
  of `^` is fed at its bottom, and the cells just under a gap in the middle of a column are fed right there.
- A piece with a Blocker straight ahead goes round it diagonally, as on an ordinary board.
- `Links` is a list of `{ "From": [col, row], "To": [col, row] }` (0-based, both on open cells). The piece in `From` moves to `To` instead of
  into the cell ahead, wherever `To` is, so one column can feed another. One link per cell (a linked cell needs no direction of its own); `To` stops being a source if it has nothing else flowing in.
- A flow that loops back on itself (as written) is refused when the level is read.
