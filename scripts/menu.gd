extends Control


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_option_pressed() -> void:
	pass
