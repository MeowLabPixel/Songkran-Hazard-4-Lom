extends Motion

var D

func _enter() -> void:
	print(name)
	owner.aim_bone_on(true)
	owner.anim.get(owner.anim_playback).travel("Run")	
	if not owner.hitboxF.body_entered.is_connected(hitfront):
		owner.hitboxF.body_entered.connect(hitfront)
	if not owner.hitboxB.body_entered.is_connected(hitback):
		owner.hitboxB.body_entered.connect(hitback)
	owner.anim.set("parameters/Main/Run/Pis/TimeScale/scale",2.0)
	owner.anim.set("parameters/Main/Run/Shot/TimeScale/scale",2.0)
	
	var camera_node = owner.get_node_or_null("Camera")
	if camera_node and camera_node.has_method("enter_sprint"):
		camera_node.enter_sprint()


func _update(_delta:float) -> void:
	set_direction()
	if input_dir.y >= -0.1:
		finished.emit("Run")
		return
	calculate_velocity(owner.run_speed,direction,_delta)
	
	owner.anim.set("parameters/Main/Run/Pis/BlendSpace2D/blend_position", Vector2(input_dir.x, -input_dir.y))
	owner.anim.set("parameters/Main/Run/Shot/BlendSpace2D/blend_position", Vector2(input_dir.x, -input_dir.y))
	#owner.anim.get("parameters/Main/Run/Pis/BlendSpace2D/blend_position").set(direction)
	D=_delta
	if direction == Vector3.ZERO:
		finished.emit("Idle")
	if owner.HP <= 0:
		finished.emit("Die")
		
func _exit() -> void:
	owner.anim.set("parameters/Main/Run/Pis/TimeScale/scale",1.0)
	owner.anim.set("parameters/Main/Run/Shot/TimeScale/scale",1.0)
	
	var camera_node = owner.get_node_or_null("Camera")
	if camera_node and camera_node.has_method("exit_sprint"):
		camera_node.exit_sprint()
	
	
func _state_input(event: InputEvent) -> void:
	if Input.is_action_pressed("quick_turn") and not owner.is_quick_turn:
		finished.emit("Quick_turn")
	if Input.is_action_just_released("sprint"):
		finished.emit("Run")
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
