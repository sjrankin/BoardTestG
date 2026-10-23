class_name GameMode
extends RefCounted
## How the player plays a game (not how a tap works): Zen has no limits, Timed gives a level a set time, Turn a set number
## of turns. The level says how much (`LevelDefinition.TimeCount`, `TurnCount`).

enum Kinds { Zen, Timed, Turn }

const Names: Array[String] = ["Zen", "Timed", "Turn"]
const Default := Kinds.Zen
