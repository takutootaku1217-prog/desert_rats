extends Node
## Normal entry owns the first-region profile; direct Main remains diagnostic.
func _ready() -> void:
	var new_game_confirmed := SaveUI.skip_start_once
	# Main's SaveUI consumes this once. Only this wrapper opens the startup menu,
	# after Main has completed world.setup and all field/UI initialization.
	SaveUI.skip_start_once = true
	var game = preload("res://scenes/main.tscn").instantiate()
	game.first_region_a_pilot = true
	add_child(game)
	if not new_game_confirmed and not SaveGame.disabled:
		game.save_ui.open_start()
