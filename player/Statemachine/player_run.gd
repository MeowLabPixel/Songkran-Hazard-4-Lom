extends Motion

func _enter() -> void:
	print(name)
	owner.aim_bone_on(true)
	set_gun_anim()
	owner.anim.get(owner.anim_playback).travel("Run")	
	#gun_anim()
	if not owner.hitboxF.body_entered.is_connected(hitfront):
		owner.hitboxF.body_entered.connect(hitfront)
	if not owner.hitboxB.body_entered.is_connected(hitback):
		owner.hitboxB.body_entered.connect(hitback)


func _update(_delta:float) -> void:
	set_direction()
	calculate_velocity(owner.walk_speed,direction,_delta)
	owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", Vector2(input_dir.x, -input_dir.y))
	owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", Vector2(input_dir.x, -input_dir.y))
	#owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position").set(direction)

	if direction == Vector3.ZERO:
		finished.emit("Idle")
	if owner.HP <= 0:
			finished.emit("Die")

		
func _state_input(_event: InputEvent) -> void:
	if Input.is_action_pressed("quick_turn") and not owner.is_quick_turn:
		finished.emit("Quick_turn")
	if Input.is_action_pressed("sprint") and input_dir.y < -0.1:
		finished.emit("Sprint")
	if Input.is_action_pressed("Reload") :
		finished.emit("Reload")
	if Input.is_action_pressed("Gun1"):
		switch_gun(0)
	if Input.is_action_pressed("Gun2"):
		switch_gun(1)
	if Input.is_action_pressed("Gun3"):
		switch_gun(2)
	if Input.is_action_pressed("Takedown") and owner.is_near_stunt:
		owner.attempt_takedown()
		finished.emit("Takedown")
	if Input.is_action_pressed("aim") :
		finished.emit("Aim")

func hitfront(body: Area3D):
	if body.is_in_group("attack"):
		owner.Hit_info.bullet = body
		owner.Hit_info.location = "front"
		finished.emit("Get_hit")
func hitback(body: Area3D):
	if body.is_in_group("attack"):
		owner.Hit_info.bullet = body
		owner.Hit_info.location = "back"
		finished.emit("Get_hit")

func switch_gun(num:int):
	if owner.gun_controller:
		owner.gun_controller.switch_gun(num)
		set_gun_anim()
		#one shot anim

func set_gun_anim():
	if owner.gun_controller.current_gun.get_gun_name() == "Water pistol":
		owner.anim.set("parameters/Main/Run/conditions/pis",true)
		owner.anim.set("parameters/Main/Run/conditions/shot",false)
		if owner.anim.get("parameters/Main/Run/playback").get_current_node() != "Pis":
			owner.anim.get("parameters/Main/Run/playback").travel("Pis")
	elif owner.gun_controller.current_gun.get_gun_name() == "Water shotgun" or owner.gun_controller.current_gun.get_gun_name() == "Water sniper":
		owner.anim.set("parameters/Main/Run/conditions/pis",false)
		owner.anim.set("parameters/Main/Run/conditions/shot",true)
		if owner.anim.get("parameters/Main/Run/playback").get_current_node() != "Shot":
			owner.anim.get("parameters/Main/Run/playback").travel("Shot")
