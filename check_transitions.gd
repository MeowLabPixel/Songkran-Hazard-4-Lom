extends SceneTree
func _init():
    var scene = load('res://scenes/enemy/MMeleeZom.tscn')
    var tree = scene.instantiate().get_node('ZombieModel/AnimationTree')
    var root_sm = tree.tree_root
    var hit_sm = root_sm.get_node('hit')
    var takedown_sm = hit_sm.get_node('hit_takedown')
    for i in range(takedown_sm.get_transition_count()):
        var from = takedown_sm.get_transition_from(i)
        var to = takedown_sm.get_transition_to(i)
        var t = takedown_sm.get_transition(i)
        var mode = 'AtEnd' if t.switch_mode == 2 else ('Immediate' if t.switch_mode == 0 else 'Sync')
        var auto = 'Auto' if t.advance_mode == 2 else 'Disabled'
        print(from, ' -> ', to, ' (', mode, ', ', auto, ')')
    quit()

