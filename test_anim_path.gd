extends SceneTree
func _init():
    var scene = load('res://scenes/enemy/MMeleeZom.tscn').instantiate()
    var ap = scene.get_node('AnimationPlayer')
    if ap:
        var anim = ap.get_animation(ap.get_animation_list()[0])
        print('Track path 0: ', anim.track_get_path(0))
    quit()
