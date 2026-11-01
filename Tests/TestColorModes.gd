extends SceneTree
## Headless checks of the Malicious color switches (swapped, drained, all white). Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://Tests/TestColorModes.gd

var Failures: int = 0


func Check(Condition: bool, Message: String) -> void:
	if not Condition:
		Failures += 1
		print("FAIL: ", Message)


func _init() -> void:
	var Looks := BlockStyles.new()
	for Kind in BlockStyles.Palette.size():
		Check(Looks.Shown[Kind] == BlockStyles.Palette[Kind] and Looks.Materials[Kind].albedo_color == BlockStyles.Palette[Kind], "real colors at the start")

	# Swapped: every group in play takes another group's color, no color twice; groups not in play are left alone.
	for Groups in range(3, 9):
		for Round in 20:
			Looks.Reshuffle(Groups)
			var Seen := {}
			for Kind in Groups:
				Check(Looks.Order[Kind] != Kind, "group %d is drawn in another group's color (%d groups)" % [Kind, Groups])
				Check(Looks.Order[Kind] < Groups, "only colors in play are used")
				Seen[Looks.Order[Kind]] = true
			Check(Seen.size() == Groups, "no two groups share a color (%d groups)" % Groups)
			for Kind in range(Groups, 8):
				Check(Looks.Order[Kind] == Kind, "groups out of play keep their own")
	Looks.Reshuffle(5)
	Looks.Scrambled = true
	Looks.RefreshColors()
	for Kind in 5:
		Check(Looks.Materials[Kind].albedo_color == BlockStyles.Palette[Looks.Order[Kind]], "the piece material shows the other group's color")
		Check(Looks.GlowHaloMaterials[Kind].albedo_color.r == BlockStyles.Palette[Looks.Order[Kind]].r, "so does the Glow halo")

	# Drained: nearly grey, still a little of the hue.
	Looks.Scrambled = false
	Looks.Faded = true
	Looks.RefreshColors()
	for Kind in 5:
		var Shown := Looks.Shown[Kind]
		var Spread := maxf(maxf(Shown.r, Shown.g), Shown.b) - minf(minf(Shown.r, Shown.g), Shown.b)
		var Real := BlockStyles.Palette[Kind]
		var RealSpread := maxf(maxf(Real.r, Real.g), Real.b) - minf(minf(Real.r, Real.g), Real.b)
		Check(Spread < RealSpread * 0.3 and Spread > 0.0, "group %d is drained of most of its color" % Kind)

	# White beats the rest.
	Looks.AllWhite = true
	Looks.Scrambled = true
	Looks.RefreshColors()
	for Kind in 8:
		Check(Looks.Shown[Kind] == Color.WHITE and Looks.Materials[Kind].albedo_color == Color.WHITE, "every group is white")

	# Off again: the real colors come back, on the shared materials too.
	Looks.AllWhite = false
	Looks.Scrambled = false
	Looks.Faded = false
	Looks.RefreshColors()
	for Kind in 8:
		Check(Looks.Shown[Kind] == BlockStyles.Palette[Kind] and Looks.Materials[Kind].albedo_color == BlockStyles.Palette[Kind], "real colors come back")
		Check(Looks.GlowHaloMaterials[Kind].albedo_color == Color(BlockStyles.Palette[Kind], 0.85), "and on the Glow halo")

	print("ALL PASS" if Failures == 0 else "%d FAILED" % Failures)
	quit(1 if Failures > 0 else 0)
