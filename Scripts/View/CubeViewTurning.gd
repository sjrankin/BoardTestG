class_name CubeViewTurning
extends Node3D

## Draws a `CubeModel` as pieces standing over the surface of a box, taps and turns, and animates falls, refills and shuffles. The 3D
## counterpart of `BoardView`, with the same outside (signals, settings, `NewGame`, `HandleTapRay`, `AttractStep`, `ShuffleNow`, `Recenter`),
## so the scene can use either. Removed pieces go to a `FlyerSystem`, out of the face they were on; how pieces look comes from a `BlockStyles`.
##
## In the cube's own space it is centered on the node's origin, X right, Y up, Z toward the front. The node sits high enough that
## the cube clears the floor at any turn, and turns about its middle.
signal ScoreChanged(NewScore: int)

## A tap removed a group of `Size` pieces of color `Kind`.
signal GroupRemoved(Kind: int, Size: int)

signal BoardRebuilt

## Attract Mode only: after a drop no group of three or more is left to remove.
signal NoPlayableGroups

const Pitch := BlockStyles.Pitch

## How far the cube is turned about the vertical while the Malicious "turn and lock" setting is on (a corner toward the viewer).
const LockedYaw := PI / 4.0

const FallDuration := 0.35

const AutoYawRate := 0.3

const AutoTiltSwing := 0.55

const AutoTiltRate := 0.45

const ShuffleDuration := 0.7

const ShuffleLift := 2.0

const LightningLead := 0.2

## How far outside a piece's middle a bolt's end sits (the piece reaches about 0.46).
const BoltLift := 0.6

## Attract Mode turns the cube slowly about each of its three axes in turn: each axis takes its own sweeps, each a random angle
## (radians) over a random time (seconds), eased at both ends, so it is never fast (at most about 0.3 radians a second on average).
const SpinAngle := Vector2(0.5, 1.5)

const SpinDuration := Vector2(6.0, 14.0)

## A new piece falls in from this many cells above the cell it is created in, if that cell looks up at least this much (the dot of the
## cell's outward direction with up).
const ArrivalHeight := 4.0

const ArrivalMinUpward := 0.2

## How long a new piece with nothing to fall from takes to grow into place.
const GrowTime := 0.3

## Which way the camera is (from the cube), roughly: a recenter turns a face toward it.
const CameraDirection := Vector3(0, 0.3, 1)

## The Yaw and Tilt that turn each face (in `CubeModel.Faces` order) to face the camera.
const FaceTurns: Array[Vector2] = [Vector2(0, 0), Vector2(PI, 0), Vector2(PI / 2.0, 0), Vector2(-PI / 2.0, 0), Vector2(0, PI / 2.0), Vector2(0, -PI / 2.0)]

var Model: CubeModel

var Styles := BlockStyles.new()

var Flyers: FlyerSystem

## How fast removed pieces leave, as a multiple of the base launch speed. Set from the controls.
var RemovalSpeed: float = 1.0:
	set(Value):
		RemovalSpeed = Value
		if Flyers != null:
			Flyers.RemovalSpeed = Value

## The cube turns about its own middle: `Yaw` about the world's vertical, then `Tilt` about the cube's own X axis, then `Roll`
## about its own Z axis (the way it faces). Dragging turns yaw and tilt; roll is only turned by Attract Mode (and put back by Recenter).
var Yaw: float = 0.0

var Tilt: float = 0.0

var Roll: float = 0.0

var AutoRotate: bool = false

var AutoClock: float = 0.0

## Unused here (gravity on the cube is fixed per face); the scene sets it every frame for the 2D board.
var UserDown: Vector3 = Vector3.DOWN

var LightningEnabled: bool = true

var RemovalEffect: int = BoardView.RemovalEffects.FlyAway

var GameNumber: int = 0

## The cube has no Blockers, so there is nothing to zap.
var BlockerZapsEnabled: bool = true

var AttractActive: bool = false

## Whether Attract Mode also turns the cube slowly (random rotation). Set from the controls.
var AttractSpin: bool = true

var Busy: bool = false

## Malicious (Settings): the cube is held turned `LockedYaw` and cannot be turned; a veil hides every piece of color `VeilKind`
## (-1 = none). (The cube has no Blockers to move.)
var TurnLocked: bool = false

var VeilKind: int = -1

## The filter sheet while the veil is down.
var VeilSheet: Veil

## Set by `Main` while the game is not being played (a level won or lost): taps, shuffles and Attract Mode moves do nothing.
var InputLocked: bool = false

var PieceNodes: Dictionary = {}

## The joined shapes (see `CubeJoins`), and the ids of pieces that are not at rest (they have no joins).
var Joins := CubeJoins.new()

var MovingIds: Dictionary = {}

var WaitingForVacate: bool = false

var VacateClock: float = 0.0

var PendingTweens: int = 0

var PendingShuffles: int = 0

## How many in-place removal effects are still playing; a refill waits for them.
var InPlaceActive: int = 0

## One sweep in progress per axis (yaw, tilt, roll): {Delta, Duration, Elapsed, Applied}.
var Sweeps: Array[Dictionary] = []

## Where the cube is, how it is turned, and which way is down.

## Half the cube's diagonal: how far from its middle any part of it reaches.
func Radius() -> float:
	return 0.5 * Vector3(Model.Width, Model.Height, Model.Depth).length() * Pitch


## How far the camera should stand back to see the whole cube, and where it should look.
func FrameDistance() -> float:
	return Radius() * 2.7


func FrameMiddle() -> Vector3:
	return position


## The cube-space position of a cell's center; also right for cells just off the cube, where new pieces queue.
func CellPosition(Cell: Vector3i) -> Vector3:
	return Vector3((Cell.x - (Model.Width - 1) / 2.0) * Pitch, (Cell.y - (Model.Height - 1) / 2.0) * Pitch, (Cell.z - (Model.Depth - 1) / 2.0) * Pitch)


# MARK: Turning the cube
func ApplyRotation() -> void:
	basis = Basis(Vector3.UP, Yaw) * Basis(Vector3.RIGHT, Tilt) * Basis(Vector3.BACK, Roll)


## Malicious: turns the cube to `LockedYaw` and keeps it there (or lets the player turn it again).
func SetTurnLocked(On: bool) -> void:
	TurnLocked = On
	if not On:
		return
	if is_inside_tree():
		Recenter()
	else:
		Yaw = LockedYaw
		Tilt = 0.0
		Roll = 0.0
		ApplyRotation()


## A drag turns the cube with the pointer, in screen space, whatever way it is turned: sideways about the world's vertical, up and down
## about the screen's horizontal (the camera looks along -Z, so that is the world's X axis) - so a piece on the face you see follows the
## mouse or finger. (Yaw, tilt and roll are then read back from the turned cube.)
func RotateBy(DeltaYaw: float, DeltaTilt: float) -> void:
	if TurnLocked:
		return
	var Turned := Basis(Vector3.UP, DeltaYaw) * Basis(Vector3.RIGHT, DeltaTilt) * basis
	var Angles := Turned.orthonormalized().get_euler(EULER_ORDER_YXZ)
	Tilt = Angles.x
	Yaw = Angles.y
	Roll = Angles.z
	ApplyRotation()


## The face to bring to the camera: the one holding the most pieces (so a long thin box shows its big face); among equals, the one
## already nearest the camera, so the cube turns as little as it can.
func BestFace() -> int:
	var Most := 0
	for Face in 6:
		Most = maxi(Most, Model.PieceCountOnFace(Face))
	var Best := 0
	var BestAlignment := -INF
	for Face in 6:
		if Model.PieceCountOnFace(Face) != Most:
			continue
		var Alignment := (global_basis * Vector3(CubeModel.FaceNormals[Face])).dot(CameraDirection.normalized()) if is_inside_tree() else 0.0
		if Alignment > BestAlignment:
			BestAlignment = Alignment
			Best = Face
	return Best


## Turns the cube so the face with the most pieces faces the camera, the short way round.
func Recenter() -> void:
	var Face := BestFace()
	var Target: Vector2 = Vector2(LockedYaw, 0.0) if TurnLocked else FaceTurns[Face]
	Yaw = wrapf(Yaw, -PI, PI)
	Tilt = wrapf(Tilt, -PI, PI)
	var Turn := create_tween()
	Roll = wrapf(Roll, -PI, PI)
	Turn.tween_method(RecenterStep.bind(Yaw, Tilt, Target, Roll), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func RecenterStep(Progress: float, StartYaw: float, StartTilt: float, Target: Vector2, StartRoll: float) -> void:
	Roll = StartRoll + angle_difference(StartRoll, 0.0) * Progress
	Yaw = StartYaw + angle_difference(StartYaw, Target.x) * Progress
	Tilt = StartTilt + angle_difference(StartTilt, Target.y) * Progress
	ApplyRotation()


## Starts a new sweep of one axis: a random direction, angle and time.
func NewSweep() -> Dictionary:
	var Direction := 1.0 if randf() < 0.5 else -1.0
	return {"Delta": Direction * randf_range(SpinAngle.x, SpinAngle.y), "Duration": randf_range(SpinDuration.x, SpinDuration.y), "Elapsed": 0.0, "Applied": 0.0}


## Attract Mode's slow turning: each axis follows its own sweeps, added to whatever the cube is doing (a drag still turns it).
func SpinStep(Delta: float) -> void:
	if Sweeps.is_empty():
		for Axis in 3:
			Sweeps.append(NewSweep())
	var Turns := [0.0, 0.0, 0.0]
	for Axis in 3:
		var Sweep := Sweeps[Axis]
		Sweep["Elapsed"] += Delta
		var Progress := clampf(Sweep["Elapsed"] / Sweep["Duration"], 0.0, 1.0)
		var Eased: float = smoothstep(0.0, 1.0, Progress) * Sweep["Delta"]
		Turns[Axis] = Eased - Sweep["Applied"]
		Sweep["Applied"] = Eased
		if Progress >= 1.0:
			Sweeps[Axis] = NewSweep()
	Yaw = wrapf(Yaw + Turns[0], -PI, PI)
	Tilt = wrapf(Tilt + Turns[1], -PI, PI)
	Roll = wrapf(Roll + Turns[2], -PI, PI)
	ApplyRotation()


## Gravity in the cube's own space: world-down, however the cube is turned right now.
func Gravity() -> Vector3:
	return (global_basis.inverse() * Vector3.DOWN).normalized()
