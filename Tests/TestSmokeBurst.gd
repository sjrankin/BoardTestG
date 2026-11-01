extends SceneTree
## Headless checks of the Puff of Smoke removal effect: how long it lasts, how it fades, and what the board does when it is chosen. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://Tests/TestSmokeBurst.gd

var Failures: int = 0
var Started: bool = false


func Check(Condition: bool, Message: String) -> void:
	if not Condition:
		Failures += 1
		print("FAIL: ", Message)


## The burst itself: one puff set per piece, a life that matches Explode's shards, and a fade that ends at exactly nothing.
func TestBurst() -> void:
	Check(is_equal_approx(SmokeBurst.DissipationTime, 1.9), "the smoke takes 1.9 s to clear")
	Check(SmokeBurst.DissipationTime > FlyerSystem.RestAge + FlyerSystem.FadeDuration, "the smoke outlasts a typical Explode shard")
	# Nearly solid soon after the start (not a faint smudge), then thinning.
	Check(SmokeBurst.OpacityAt(0.05) > 0.85, "puffs are nearly opaque just after the start")
	Check(SmokeBurst.MinStrength >= 0.85, "even the weakest puff is strong")
	var Where := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var Colors := PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var Parent := Node3D.new()
	root.add_child(Parent)
	var Burst := SmokeBurst.Play(Parent, Where, Colors, 2.0)
	Check(Burst != null, "a burst is made")
	Check(Burst.multimesh.instance_count == 3 * SmokeBurst.PuffsPerPiece, "%d puffs per piece" % SmokeBurst.PuffsPerPiece)
	Check(Burst.get_parent() == Parent, "the burst is a child of the node it is given")
	# A small group keeps every puff; a big group gets fewer per piece, never fewer than the minimum, and always at least one per piece.
	Check(SmokeBurst.PuffsFor(1) == SmokeBurst.PuffsPerPiece and SmokeBurst.PuffsFor(SmokeBurst.FullDensityPieces) == SmokeBurst.PuffsPerPiece, "a small group gets every puff")
	Check(SmokeBurst.PuffsFor(12) < SmokeBurst.PuffsPerPiece, "a bigger group gets fewer puffs per piece")
	Check(SmokeBurst.PuffsFor(500) == SmokeBurst.MinPuffsPerPiece, "a huge group gets the minimum per piece")
	var Prev := SmokeBurst.PuffsPerPiece
	var Steady := true
	for Count in range(1, 200):
		var Now := SmokeBurst.PuffsFor(Count)
		Steady = Steady and Now <= Prev and Now >= SmokeBurst.MinPuffsPerPiece
		Prev = Now
	Check(Steady, "puffs per piece never grow with the size of the group")
	var Big := PackedVector3Array()
	var BigColors := PackedColorArray()
	for Index in 30:
		Big.append(Vector3(Index, 0, 0))
		BigColors.append(Color.RED)
	var BigBurst := SmokeBurst.Play(Parent, Big, BigColors, 2.0)
	Check(BigBurst.multimesh.instance_count == 30 * SmokeBurst.PuffsFor(30), "a big group's burst has its smaller share of puffs")
	Check(BigBurst.multimesh.instance_count < 30 * SmokeBurst.PuffsPerPiece, "a big group's burst is lighter than full density")
	BigBurst.queue_free()
	Check(SmokeBurst.Play(Parent, PackedVector3Array(), PackedColorArray(), 2.0) == null, "nothing to cover makes no burst")
	# With a way out given, every puff of that piece starts in front of its face and billows outward, so it is not hidden behind the
	# neighbouring pieces (whose faces are 0.46 cells from the piece's middle).
	var Out := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var Lifted := SmokeBurst.Play(Parent, Where, Colors, 2.0, Out)
	var FrontMost := INF
	var Billows := true
	for Index in Lifted.Starts.size():
		FrontMost = minf(FrontMost, Lifted.Starts[Index].z)
		Billows = Billows and Lifted.Paths[Index].z >= SmokeBurst.Billow.x - 0.0001
	Check(FrontMost >= SmokeBurst.FrontLift - SmokeBurst.Scatter - 0.0001, "puffs start out in front of the face")
	Check(FrontMost > 0.46, "puffs start in front of the neighbours' faces")
	Check(Billows, "puffs billow outward")
	Lifted.queue_free()
	# Clear at the very start, so the puffs fade in and do not pop; visible soon after; thinning all the way to nothing at the end.
	Check(SmokeBurst.OpacityAt(0.0) == 0.0, "puffs start clear")
	Check(SmokeBurst.OpacityAt(0.25) > 0.1, "puffs are visible a quarter of the way through")
	Check(SmokeBurst.OpacityAt(0.5) > SmokeBurst.OpacityAt(0.99), "puffs thin out")
	Check(SmokeBurst.OpacityAt(0.75) < SmokeBurst.OpacityAt(0.5), "puffs keep thinning")
	Check(SmokeBurst.OpacityAt(1.0) == 0.0, "puffs are clear at the end of the life")
	Check(SmokeBurst.OpacityAt(0.5) <= SmokeBurst.Opacity, "puffs are never more opaque than the limit")
	Check(SmokeBurst.SpreadAt(0.0) == 0.0 and SmokeBurst.SpreadAt(1.0) == 1.0, "spreading runs from 0 to 1")
	Check(SmokeBurst.SpreadAt(0.5) > 0.5, "spreading is quick at first")
	var Early := Burst.PuffAt(0, 0.0)
	var Late := Burst.PuffAt(0, 0.75)
	Check(Late.origin.y > Early.origin.y + 0.05, "puffs rise")
	Check(Late.basis.x.length() > Early.basis.x.length(), "puffs swell")
	# Time passing, through `Advance`: still going before the end, freed at the end.
	Burst.Advance(0.5)
	Check(not Burst.is_queued_for_deletion(), "the burst is still going a quarter of the way through")
	Burst.Advance(1.0)
	Burst.Advance(0.49)
	Check(not Burst.is_queued_for_deletion(), "the burst is not freed before its life is over")
	Burst.Advance(0.02)
	Check(Burst.is_queued_for_deletion(), "the burst is freed at the end of its life")
	Parent.queue_free()


## Replace: the pieces are freed at once and the smoke lasts as long as Explode's shards do, shorter when pieces are removed faster.
func TestReplace() -> void:
	var Parent := Node3D.new()
	root.add_child(Parent)
	var Pieces: Array[Dictionary] = []
	for Index in 4:
		var Node := Node3D.new()
		Node.position = Vector3(Index, 0, 0)
		Parent.add_child(Node)
		Pieces.append({"Node": Node, "Kind": Index % 2})
	var Palette: Array[Color] = [Color.RED, Color.BLUE]
	SmokeBurst.Replace(Parent, Pieces, Palette, 1.0)
	for Entry in Pieces:
		Check((Entry["Node"] as Node).is_queued_for_deletion(), "a piece is freed at once")
	var Burst: SmokeBurst
	for Child in Parent.get_children():
		if Child is SmokeBurst:
			Burst = Child
	Check(Burst != null, "one burst covers the pieces")
	Check(is_equal_approx(Burst.Life, SmokeBurst.DissipationTime), "at speed 1 the smoke lasts the dissipation time")
	var Faster: Array[Dictionary] = []
	var Extra := Node3D.new()
	Parent.add_child(Extra)
	Faster.append({"Node": Extra, "Kind": 0})
	SmokeBurst.Replace(Parent, Faster, Palette, 2.0)
	var Quick: SmokeBurst
	for Child in Parent.get_children():
		if Child is SmokeBurst and Child != Burst:
			Quick = Child
	Check(Quick != null and is_equal_approx(Quick.Life, SmokeBurst.DissipationTime / 2.0), "at double speed the smoke clears in half the time")
	Parent.queue_free()


## The 2D board with Smoke chosen: a removed group leaves a burst and no flyers, and the refill does not wait for the smoke.
func TestBoard() -> void:
	var View := BoardView.new()
	root.add_child(View)
	View.LightningEnabled = false
	View.RemovalEffect = BoardView.RemovalEffects.Smoke
	View.NewGame(8, 8, 4, 0)
	var Group: Array = View.Model.PlayableGroups()[0]
	var Before: int = View.PieceNodes.size()
	View.TapCell((Group[0] as Vector2i).x, (Group[0] as Vector2i).y)
	await create_timer(0.0).timeout
	Check(View.PieceNodes.size() == Before - Group.size(), "the group's pieces are off the board")
	var Bursts := 0
	for Child in View.Flyers.get_children():
		if Child is SmokeBurst:
			Bursts += 1
	Check(Bursts == 1, "one burst for the group (found %d)" % Bursts)
	for Child in View.Flyers.get_children():
		if Child is SmokeBurst:
			var Nearest := INF
			for Start in (Child as SmokeBurst).Starts:
				Nearest = minf(Nearest, (Start as Vector3).z)
			Check(Nearest > 0.46, "the group's smoke starts in front of the board's face (nearest puff at z %.2f)" % Nearest)
	Check(View.Flyers.Flyers.is_empty(), "nothing flies")
	Check(View.InPlaceActive == 0, "no in-place effect is holding the refill")
	await create_timer(0.3).timeout
	Check(not View.WaitingForVacate, "the refill did not wait for the smoke")
	var Smoke: SmokeBurst
	for Child in View.Flyers.get_children():
		if Child is SmokeBurst:
			Smoke = Child
	Check(Smoke != null and not Smoke.is_queued_for_deletion(), "the smoke is still there while the pieces fall in")
	View.NewGame(8, 8, 4, 0)
	await process_frame
	await process_frame
	var Left := 0
	for Child in View.Flyers.get_children():
		if Child is SmokeBurst and not Child.is_queued_for_deletion():
			Left += 1
	Check(Left == 0, "a new game clears the smoke")
	View.queue_free()


## No move left and no shuffle can make one: the board is dealt again, and the old pieces leave in smoke (without Smoke, at once).
func TestRedeal(Effect: int) -> void:
	var View := BoardView.new()
	root.add_child(View)
	View.LightningEnabled = false
	View.RemovalEffect = Effect
	View.NewGame(4, 4, 8, 0)
	# Sixteen cells and eight colors, two of each at most: no group of three can ever form, so every shuffle fails and the
	# board is dealt again.
	for Col in 4:
		for Row in 4:
			View.Model.SetPiece(Col, Row, View.Model.NewPiece((Col + Row * 4) % 8))
	var Old := View.PieceNodes.size()
	View.Recover()
	var Bursts := 0
	for Child in View.Flyers.get_children():
		if Child is SmokeBurst:
			Bursts += 1
	if Effect == BoardView.RemovalEffects.Smoke:
		Check(Bursts == 1, "a redeal leaves one burst over the old pieces (found %d)" % Bursts)
	else:
		Check(Bursts == 0, "without Smoke a redeal makes no smoke")
	Check(Old > 0, "there were pieces to replace")
	View.queue_free()


## A board switched out of the scene (Settings > Board Type) while the lightning played still sends its pieces away afterwards. That must
## not touch the scene (no viewport, no world positions): the pieces are just freed, whichever effect is chosen. This used to be a
## script error ("Cannot call method 'get_camera_3d' on a null value") that stopped the game in the editor.
func TestSwitchedOut(Effect: int) -> void:
	var Flat := BoardView.new()
	root.add_child(Flat)
	Flat.LightningEnabled = false
	Flat.RemovalEffect = Effect
	Flat.NewGame(6, 6, 4, 0)
	var Leaving: Array[Dictionary] = []
	for Id in Flat.PieceNodes.keys().slice(0, 3):
		Leaving.append({"Node": Flat.PieceNodes[Id], "Kind": 1})
	root.remove_child(Flat)
	Flat.SendFlying(Leaving)
	for Entry in Leaving:
		Check((Entry["Node"] as Node).is_queued_for_deletion(), "a 2D piece is freed when its board was switched out (effect %d)" % Effect)
	Check(not Flat.WaitingForVacate, "a switched-out board does not wait to refill")
	var Burst := 0
	for Child in Flat.Flyers.get_children():
		if Child is SmokeBurst:
			Burst += 1
	Check(Burst == 0, "no smoke is made for a switched-out board")
	Flat.free()
	var Box := CubeView.new()
	root.add_child(Box)
	Box.LightningEnabled = false
	Box.RemovalEffect = Effect
	Box.NewGame(5, 4, 5, 4)
	var CubeLeaving: Array[Dictionary] = []
	for Id in Box.PieceNodes.keys().slice(0, 3):
		CubeLeaving.append({"Node": Box.PieceNodes[Id], "Kind": 1, "Out": Vector3.BACK})
	root.remove_child(Box)
	Box.SendFlying(CubeLeaving)
	for Entry in CubeLeaving:
		Check((Entry["Node"] as Node).is_queued_for_deletion(), "a cube piece is freed when its cube was switched out (effect %d)" % Effect)
	Box.free()


## The smoke rises exactly against the way pieces fall: along the given up vector, whatever it is, and on each board along the opposite
## of that board's own gravity (the 2D board's follows its tilt; the cube's is the world's, however the cube is turned).
func TestRise() -> void:
	var Where := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	var Colors := PackedColorArray([Color.RED, Color.RED, Color.RED, Color.RED])
	var Facing := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var Parent := Node3D.new()
	root.add_child(Parent)
	for Up in [Vector3.UP, Vector3(1, 0, 0), Vector3(1, 1, 0).normalized(), Vector3(0, -0.6, 0.8).normalized()]:
		# Billowing is along the way out; take a way out at right angles to this up so the rise can be read off cleanly.
		var Out := PackedVector3Array()
		for Index in Where.size():
			Out.append(Up.cross(Vector3.RIGHT if absf(Up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized())
		var Burst := SmokeBurst.Play(Parent, Where, Colors, 2.0, Out, Up)
		var Along := true
		for Path in Burst.Paths:
			var Rise := (Path as Vector3).dot(Up)
			Along = Along and Rise >= SmokeBurst.Rise.x - 0.0001 and Rise <= SmokeBurst.Rise.y + 0.0001
		Check(Along, "every puff rises by %s-%s along the up vector %s" % [SmokeBurst.Rise.x, SmokeBurst.Rise.y, Up])
		Burst.queue_free()
	var Default := SmokeBurst.Play(Parent, Where, Colors, 2.0, Facing)
	var Straight := true
	for Path in Default.Paths:
		Straight = Straight and (Path as Vector3).y >= SmokeBurst.Rise.x - 0.0001 and (Path as Vector3).y <= SmokeBurst.Rise.y + 0.0001
	Check(Straight, "with no up vector given the smoke rises against world gravity")
	Default.queue_free()
	# The 2D board, tilted: smoke rises along the board's own up (against its own gravity), which is not the world's up.
	var Flat := BoardView.new()
	root.add_child(Flat)
	Flat.LightningEnabled = false
	Flat.RemovalEffect = BoardView.RemovalEffects.Smoke
	Flat.NewGame(8, 8, 4, 0)
	Check(Flat.SmokeUp().dot(Vector3.UP) > 0.999, "an upright board's smoke rises against world gravity")
	Flat.Tilt = 0.6
	Flat.ApplyRotation()
	var BoardUp := Flat.global_basis.y.normalized()
	Check(Flat.SmokeUp().dot(BoardUp) > 0.999, "a tilted board's smoke rises along the board's own up")
	Check(Flat.SmokeUp().dot(Vector3.UP) < 0.95, "...which is not the world's up when the board is tilted")
	var Group: Array = Flat.Model.PlayableGroups()[0]
	Flat.TapCell((Group[0] as Vector2i).x, (Group[0] as Vector2i).y)
	var Seen := false
	for Child in Flat.Flyers.get_children():
		if Child is SmokeBurst:
			Seen = true
			var OnBoard := true
			for Path in (Child as SmokeBurst).Paths:
				var Rise := (Path as Vector3).dot(BoardUp)
				OnBoard = OnBoard and Rise >= SmokeBurst.Rise.x - 0.0001 and Rise <= SmokeBurst.Rise.y + 0.0001
			Check(OnBoard, "the puffs of a tilted board's removal rise along the board's up")
	Check(Seen, "the tilted board made a burst")
	Flat.free()
	# The cube: the world's gravity, so smoke always rises against world down, however the cube is turned.
	var Box := CubeView.new()
	root.add_child(Box)
	Box.NewGame(5, 4, 5, 4)
	for Turn in [Vector3(0, 0, 0), Vector3(0.7, 0.4, 0.0), Vector3(-2.0, 1.0, 0.5), Vector3(3.0, -0.8, 1.2)]:
		Box.Yaw = Turn.x
		Box.Tilt = Turn.y
		Box.Roll = Turn.z
		Box.ApplyRotation()
		Check(Box.SmokeUp().dot(Vector3.UP) > 0.9999, "the cube's smoke rises against world gravity at turn %s" % [Turn])
	Box.free()
	Parent.queue_free()


func _process(_Delta: float) -> bool:
	if not Started:
		Started = true
		Run()
	return false


func Run() -> void:
	TestBurst()
	TestReplace()
	TestRise()
	await TestBoard()
	TestRedeal(BoardView.RemovalEffects.Smoke)
	TestRedeal(BoardView.RemovalEffects.Disappear)
	for Effect in BoardView.RemovalEffects.values():
		TestSwitchedOut(Effect)
	print("ALL PASS" if Failures == 0 else "%d FAILURES" % Failures)
	quit(Failures)
