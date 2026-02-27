## Temporary simplified main menu - loads level_01 directly
## This bypasses the broken GameManager to test the game

extends Control

func _ready() -> void:
	# Simple UI
	var label = Label.new()
	label.text = "The Symmetry Vaults - Test Version"
	label.position = Vector2(400, 200)
	add_child(label)

	var start_btn = Button.new()
	start_btn.text = "Start Game (Load Level 1)"
	start_btn.position = Vector2(500, 400)
	start_btn.size = Vector2(280, 52)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

	print("[SimpleMenu] Ready!")

func _on_start_pressed() -> void:
	print("[SimpleMenu] Loading level_scene.tscn directly...")
	# Load level scene directly - bypasses broken GameManager
	get_tree().change_scene_to_file("res://src/game/level_scene.tscn")
