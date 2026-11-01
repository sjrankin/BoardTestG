class_name BoardViewTurning
extends Node3D

## Draws a `BoardModel` as pieces standing in a vertical grid, taps and turns, and animates falls, refills and shuffles.
## Removed pieces are handed to a `FlyerSystem`; how pieces look comes from a `BlockStyles`.
##
## In the board's own space the board lies in the XY plane (z = 0), Row 0 at the top, centered on the node's origin.
## The node sits at the board's middle and turns about it.
signal ScoreChanged(NewScore: int)

## A tap removed a group of `Size` pieces of color `Kind`.
signal GroupRemoved(Kind: int, Size: int)

signal BoardRebuilt

## Attract Mode only: after a drop no group of three or more is left to remove.
signal NoPlayableGroups

const FallDuration := 0.35

## How far the board is turned about the vertical while the Malicious "turn and lock" setting is on.
const LockedYaw := PI / 4.0

## Auto Rotate: the turn about the vertical per second, and how far (and how fast) the board rocks to and fro.
## A full turn takes 23.7 s: not a whole multiple of (or a simple fraction of) the Malicious light's 15 s, so the two never fall into step.
const AutoYawPeriod := 23.7

const AutoYawRate := TAU / AutoYawPeriod

const AutoTiltSwing := 0.55

const AutoTiltRate := 0.45

const ShuffleDuration := 0.7

## How long lightning crackles across a group before its pieces fly out.
const LightningLead := 0.2

## How far toward the camera a shuffling piece arcs at the middle of its flight.
const ShuffleLift := 2.0

var Model: BoardModel

var Styles := BlockStyles.new()

var Flyers: FlyerSystem

## How fast removed pieces leave, as a multiple of the base launch speed. Set from the controls.
var RemovalSpeed: float = 1.0:
	set(Value):
		RemovalSpeed = Value
		if Flyers != null:
			Flyers.RemovalSpeed = Value

## The board turns about its own middle: `Yaw` about the world's vertical, then `Tilt` about the board's own
## horizontal axis (so no part of it ever dips below the floor). Gravity stays world-down whatever the angle.
var Yaw: float = 0.0

var Tilt: float = 0.0

var AutoRotate: bool = false

var AutoClock: float = 0.0

## Which way is down for the user: the camera's screen-down, in world space. Set every frame by the scene.
var UserDown: Vector3 = Vector3.DOWN

## Whether lightning plays across a group as it is cleared. Set from the controls.
var LightningEnabled: bool = true

## How removed pieces leave: Fly Away (pop out, fall, fade), Mini Me (burst into at least 10 fast small copies), Explode (shatter into
## flat shards, much faster), one of the three that play in place (`InPlaceRemoval`): Disappear, Spin and Shrink, Spin then Vanish, or
## Smoke (gone at once in a puff of smoke, `SmokeBurst`, which lasts as long as Explode's shards; also used when the board is dealt again).
## (New ones go on the end, so a remembered choice keeps meaning the same thing.) Set from the controls.
enum RemovalEffects { FlyAway, MiniMe, Explode, Disappear, SpinShrink, SpinVanish, Smoke }

var RemovalEffect: int = RemovalEffects.FlyAway

## Counts new games, so something waiting (the lightning) can tell the board it was waiting on has gone.
var GameNumber: int = 0

## Whether the Blockers throw off plasma zaps. Set from the controls.
var BlockerZapsEnabled: bool = true

var BlockerLights: Array[BlockerLight] = []

## The idle hint (see `IdleHint`), and whether Attract Mode is playing (no hints then). Set by the scene.
var Hint := IdleHint.new()

## The joins of the three joined shapes (see `JoinSystem`), and the ids of pieces that are not at rest (they have none).
var Joins := JoinSystem.new()

var MovingIds: Dictionary = {}

var AttractActive: bool = false

var Busy: bool = false

## Malicious (Settings): the board is held turned `LockedYaw` and cannot be turned; the Blockers move after every group; a veil
## hides every piece of color `VeilKind` (-1 = none).
var TurnLocked: bool = false

var BlockersMove: bool = false

var VeilKind: int = -1

## The filter sheet while the veil is down.
var VeilSheet: Veil

## Set by `Main` while the game is not being played (a level won or lost): taps, shuffles and Attract Mode moves do nothing.
var InputLocked: bool = false

var PieceNodes: Dictionary = {}

var WaitingForVacate: bool = false

var VacateClock: float = 0.0

var PendingTweens: int = 0

var PendingShuffles: int = 0

## How many in-place removal effects are still playing; a refill waits for them.
var InPlaceActive: int = 0

## Where the board is, how it is turned, and which way is down.

## Malicious: turns the board to `LockedYaw` and keeps it there (or lets the player turn it again).
func SetTurnLocked(On: bool) -> void:
	TurnLocked = On
	if not On:
		return
	if is_inside_tree():
		Recenter()
	else:
		Yaw = LockedYaw
		Tilt = 0.0
		ApplyRotation()


## The board-space position of a cell's center; also correct for cells just off the board, where new pieces queue.
func CellPosition(Col: int, Row: int) -> Vector3:
	return Vector3((Col - (Model.Width - 1) / 2.0) * BlockStyles.Pitch, (Model.Height / 2.0 - Row - 0.5) * BlockStyles.Pitch, 0.0)


## How far, on average, the cells of a group are from the bottom edge of the board when gravity pulls toward `Down`.
func AverageDistanceFromBottom(Group: Array, Down: Vector2i) -> float:
	var Total := 0.0
	for Cell in Group:
		if Down == Vector2i(0, 1):
			Total += Model.Height - 1 - Cell.y
		elif Down == Vector2i(0, -1):
			Total += Cell.y
		elif Down == Vector2i(1, 0):
			Total += Model.Width - 1 - Cell.x
		else:
			Total += Cell.x
	return Total / Group.size()


## How far the camera should stand back to see the whole board, and where it should look.
func FrameDistance() -> float:
	return maxf(Model.Width, Model.Height) * 2.5


func FrameMiddle() -> Vector3:
	return Vector3(0, Model.Height * 0.38, 0)


# MARK: Turning the board
func ApplyRotation() -> void:
	basis = Basis(Vector3.UP, Yaw) * Basis(Vector3.RIGHT, Tilt)


func RotateBy(DeltaYaw: float, DeltaTilt: float) -> void:
	if TurnLocked:
		return
	Yaw = wrapf(Yaw + DeltaYaw, -PI, PI)
	Tilt = wrapf(Tilt + DeltaTilt, -PI, PI)
	ApplyRotation()


## Turns the board back to face the camera, the short way round.
func Recenter() -> void:
	Yaw = wrapf(Yaw, -PI, PI)
	Tilt = wrapf(Tilt, -PI, PI)
	var Turn := create_tween()
	Turn.tween_method(RecenterStep.bind(Yaw, Tilt, LockedYaw if TurnLocked else 0.0), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func RecenterStep(Progress: float, StartYaw: float, StartTilt: float, TargetYaw: float) -> void:
	Yaw = StartYaw + angle_difference(StartYaw, TargetYaw) * Progress
	Tilt = lerpf(StartTilt, 0.0, Progress)
	ApplyRotation()


# MARK: Falling and refilling

## Gravity on the board is down as the user sees it, whatever way the board is turned: the camera's screen-down,
## taken into the board's own space and rounded to the nearest of the four grid directions.
func GravityFromUser() -> Vector2i:
	var Local := global_basis.inverse() * UserDown
	if maxf(absf(Local.x), absf(Local.y)) < 0.05:
		return Model.GravityDir
	if absf(Local.y) >= absf(Local.x):
		return Vector2i(0, 1) if Local.y < 0.0 else Vector2i(0, -1)
	return Vector2i(1, 0) if Local.x > 0.0 else Vector2i(-1, 0)
