extends Node
var mobile_ui_script
func _ready():
 if not ProjectSettings.load_resource_pack('res://mobile.pck'):
  push_error('Mobile UI patch could not load')
  get_tree().quit(1)
  return
 mobile_ui_script=load('res://mobile/ui.gd')
 call_deferred('_start_game')
func _start_game():
 var game=load('res://scenes/main.tscn').instantiate()
 get_tree().root.add_child(game)
 get_tree().current_scene=game
 var old_ui=game.ui
 game.remove_child(old_ui)
 old_ui.queue_free()
 var ui=mobile_ui_script.new()
 game.ui=ui
 ui.setup(game)
 game.add_child(ui)
 ui.sync()
 ui.show_title(FileAccess.file_exists(game.SAVE_PATH))
 queue_free()
