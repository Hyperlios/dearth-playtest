extends SceneTree
func _initialize():
 var dir=ProjectSettings.globalize_path('res://')
 var p=PCKPacker.new()
 p.pck_start(dir+'mobile.pck')
 for f in ['ui.gd','baseline_ui.gdc','baseline_ui.gd.remap']:
  p.add_file('res://mobile/'+f,dir+'mobile-src/'+f)
 p.flush()
 quit()
