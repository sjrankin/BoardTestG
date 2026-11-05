class_name MainMalicious
extends MainScene

## The Malicious switches.

## Plays level `Index` (0 is "no level": the Settings board). Levels are 2D, so this switches to the 2D board.
## Attract Mode plays the board the Settings window shows (its size, colors and Blockers; the block shape is already shared),
## not a level's: turning it on starts a new game with those values.
func OnMaliciousToggled(Index: int, On: bool) -> void:
	Malicious[Index] = On
	GameSettings.Save(MaliciousKeys[Index], On)
	ApplyMalicious(Index)


func ApplyMalicious(Index: int) -> void:
	var On := Malicious[Index]
	match Index:
		0:
			SceneSetup.SetDarkSides(On)
			if not On:
				LightAngle = 0.0
				SceneSetup.Sun.rotation_degrees = SceneSetup.SunDirection
		1:
			Board2D.BlockersMove = On
		2:
			if not On and VeilShown:
				View.VeilOff()
				VeilShown = false
			VeilClock = 0.0
			VeilNext = VeilEvery
		3:
			Board2D.SetTurnLocked(On)
			Board3D.SetTurnLocked(On)
			if On:
				Bar.AutoRotateCheck.button_pressed = false
			Bar.AutoRotateCheck.disabled = On
		4:
			var Looks := Board2D.Styles
			Looks.Scrambled = On
			Looks.Reshuffle(ActiveGroups())
			Looks.RefreshColors()
		5:
			Board2D.Styles.Faded = On
			Board2D.Styles.RefreshColors()
		6:
			Board2D.Styles.AllWhite = On
			Board2D.Styles.RefreshColors()


## The veil comes down over every piece of one color: a color the goal still needs, if there is one, else any on the board.
func ShowVeil() -> void:
	var Kinds: Array[int] = Session.WantedKinds()
	if Kinds.is_empty():
		for Node in View.PieceNodes.values():
			if is_instance_valid(Node) and not Kinds.has(Node.get_meta("Kind")):
				Kinds.append(Node.get_meta("Kind"))
	if Kinds.is_empty():
		return
	View.VeilOn(Kinds.pick_random())
	VeilShown = true


func HideVeil() -> void:
	View.VeilOff()
	VeilShown = false


## Malicious, once a frame: the spinning light and the veil's timing.
func MaliciousStep(Delta: float) -> void:
	if Malicious[0]:
		LightAngle = fmod(LightAngle - TAU / LightPeriod * Delta, TAU)
		SceneSetup.Sun.rotation = Vector3(deg_to_rad(SceneSetup.SunDirection.x), deg_to_rad(SceneSetup.SunDirection.y) + LightAngle, 0.0)
	if Malicious[2] and Session.CanPlay() and not Bar.Overlay.visible and not Bar.TestOverlay.visible and not AttractGameOver:
		VeilClock += Delta
		if VeilClock >= VeilNext:
			if VeilShown:
				HideVeil()
			else:
				ShowVeil()
			VeilNext += VeilFor if VeilShown else VeilEvery - VeilFor
