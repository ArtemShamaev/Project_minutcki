extends SceneTree
func _init():
	for d in ["res://scripts/core/", "res://scripts/render/", "res://scripts/world/", "res://scripts/ui/", "res://scripts/"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				var s = load(d + f)
				if s == null or not s.can_instantiate():
					print("BROKEN: ", d + f)
	print("check done")
	quit()
