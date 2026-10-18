class_name GameSettings
extends RefCounted
## What the game remembers between launches (the board's size, colors and Blockers, the block shape, the removal
## speed), kept in one small config file in the user's data folder.

const Path := "user://Settings.cfg"
const Section := "Game"


static func Load(Name: String, Default: Variant) -> Variant:
	var File := ConfigFile.new()
	if File.load(Path) != OK:
		return Default
	return File.get_value(Section, Name, Default)


static func Save(Name: String, Value: Variant) -> void:
	var File := ConfigFile.new()
	File.load(Path)
	File.set_value(Section, Name, Value)
	File.save(Path)
