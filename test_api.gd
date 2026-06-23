@tool
extends EditorScript
func _run():
	var sm = AnimationNodeStateMachine.new()
	sm.add_node("TestAnim", AnimationNodeAnimation.new())
	for m in sm.get_method_list():
		if "node" in m.name or "state" in m.name:
			print(m.name)
