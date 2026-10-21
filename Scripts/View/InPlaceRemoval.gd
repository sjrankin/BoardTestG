class_name InPlaceRemoval
extends RefCounted
## The removal effects that play where the piece stands, instead of flying out (see `BoardView.RemovalEffects`):
##
## - Disappear: the piece is gone at once.
## - Spin and Shrink: it spins about its own middle on a random axis while shrinking to nothing, over `Duration`.
## - Spin then Vanish: it spins the same way, at full size, for `Duration`, then is gone.
##
## The piece stays in its cell while it plays, so a refill waits for it (the view counts the effects still playing).

const Duration := 0.5
## How many full turns the spin makes over the effect.
const Turns := 1.5


## Plays `Effect` (a `BoardView.RemovalEffects` value) on `Piece`, a piece already taken off the board, then frees it and calls
## `Done`. `Owner` runs the animation (it is stopped if the owner leaves the scene).
static func Play(Owner: Node, Piece: Node3D, Effect: int, Done: Callable) -> void:
	if Effect == BoardView.RemovalEffects.Disappear:
		Piece.queue_free()
		Done.call()
		return
	var Axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if Axis.length() < 0.05:
		Axis = Vector3.UP
	var Turn := Owner.create_tween()
	Turn.tween_method(Step.bind(Piece, Axis.normalized(), Effect == BoardView.RemovalEffects.SpinShrink), 0.0, 1.0, Duration)
	Turn.tween_callback(Finish.bind(Piece, Done))


static func Step(Progress: float, Piece: Node3D, Axis: Vector3, Shrinks: bool) -> void:
	if not is_instance_valid(Piece):
		return
	var Size := maxf(1.0 - Progress, 0.001) if Shrinks else 1.0
	Piece.basis = Basis(Axis, TAU * Turns * Progress).scaled(Vector3.ONE * Size)


static func Finish(Piece: Node3D, Done: Callable) -> void:
	if is_instance_valid(Piece):
		Piece.queue_free()
	Done.call()
