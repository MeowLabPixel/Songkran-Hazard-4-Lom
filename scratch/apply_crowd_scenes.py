import os

def update_file(path, replacements):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    for target, replacement in replacements:
        if target not in content:
            print(f"ERROR: Target not found in {path}:\n{repr(target[:80])}...")
            return False
        content = content.replace(target, replacement, 1)

    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp_path, path)
    print(f"SUCCESS: Updated {path}")
    return True

crowd_gd_replacements = [
    # 1. Add model scene exports
    (
"""@export var male_model_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model.tscn")
@export var female_model_scene: PackedScene = null  # Coming soon!""",
"""@export var male_model_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model.tscn")
@export var male_model_balloon_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model_Balloon.tscn")
@export var male_model_gun_scene: PackedScene = preload("res://scenes/Crowds/crowd_male_model_Gun.tscn")
@export var female_model_scene: PackedScene = null  # Coming soon!"""
    ),
    # 2. Add balloon spawn controls
    (
"""@export var min_gun_spacing: float = 6.0: ## Minimum distance between crowd members equipped with water guns
\tset(val):
\t\tif is_equal_approx(min_gun_spacing, val):
\t\t\treturn
\t\tmin_gun_spacing = val
\t\t_on_setting_changed()

@export_group("Seed & Randomization")""",
"""@export var min_gun_spacing: float = 6.0: ## Minimum distance between crowd members equipped with water guns
\tset(val):
\t\tif is_equal_approx(min_gun_spacing, val):
\t\t\treturn
\t\tmin_gun_spacing = val
\t\t_on_setting_changed()
@export var enable_balloon_spawn: bool = true:
\tset(val):
\t\tif enable_balloon_spawn == val:
\t\t\treturn
\t\tenable_balloon_spawn = val
\t\t_on_setting_changed()
@export_range(0.0, 1.0) var balloon_spawn_chance: float = 0.25:
\tset(val):
\t\tif is_equal_approx(balloon_spawn_chance, val):
\t\t\treturn
\t\tballoon_spawn_chance = val
\t\t_on_setting_changed()

@export_group("Seed & Randomization")"""
    ),
    # 3. Pre-instantiation role selection in _setup_crowd()
    (
"""\t\tvar spawn_pos: Vector3 = spawn_info.position
\t\tvar member: Node3D = null
\t\tvar chosen_model_type: int = 0

\t\tif i == 0 and existing_male:
\t\t\tmember = existing_male
\t\t\tmember.visible = true
\t\t\tchosen_model_type = 0
\t\telse:
\t\t\tvar candidate_scenes: Array[PackedScene] = []
\t\t\tif enable_male_crowd and male_model_scene:
\t\t\t\tcandidate_scenes.append(male_model_scene)
\t\t\tif enable_female_crowd and female_model_scene:
\t\t\t\tcandidate_scenes.append(female_model_scene)

\t\t\tif candidate_scenes.is_empty():
\t\t\t\tif male_model_scene:
\t\t\t\t\tcandidate_scenes.append(male_model_scene)
\t\t\t\telse:
\t\t\t\t\tbreak

\t\t\tvar scene_to_use = candidate_scenes[_rng.randi_range(0, candidate_scenes.size() - 1)]
\t\t\tif female_model_scene and scene_to_use == female_model_scene:
\t\t\t\tchosen_model_type = 1
\t\t\tmember = scene_to_use.instantiate() as Node3D
\t\t\tmember.name = "CrowdMember_%d" % i
\t\t\tmember.set_meta("is_crowd_preview", true)
\t\t\tif not (member is CrowdMember):
\t\t\t\tvar crowd_member_script = preload("res://scripts/crowd_member.gd")
\t\t\t\tmember.set_script(crowd_member_script)
\t\t\tvar internal_mode = Node.INTERNAL_MODE_BACK if Engine.is_editor_hint() else Node.INTERNAL_MODE_DISABLED
\t\t\tadd_child(member, false, internal_mode)

\t\tplaced_positions.append(spawn_pos)
\t\tmember.global_position = spawn_pos
\t\tmember.rotation.y = _rng.randf_range(0.0, TAU)

\t\t# Collect RIDs from placed member to exclude from future spawn raycasts/shapes
\t\tif member is CollisionObject3D:
\t\t\tplaced_rids.append(member.get_rid())

\t\t# 1. Armed spacing check: crowd members with guns should not be near each other
\t\tvar can_have_gun = enable_water_gun_spawn
\t\tif can_have_gun:
\t\t\tfor armed_pos in armed_positions:
\t\t\t\tif spawn_pos.distance_to(armed_pos) < min_gun_spacing:
\t\t\t\t\tcan_have_gun = false
\t\t\t\t\tbreak

\t\tvar has_gun = can_have_gun and (_rng.randf() < gun_spawn_chance)
\t\tif has_gun:
\t\t\tarmed_positions.append(spawn_pos)""",
"""\t\tvar spawn_pos: Vector3 = spawn_info.position
\t\tvar member: Node3D = null
\t\tvar chosen_model_type: int = 0

\t\t# 1. Determine combat / balloon role before instantiating prefab
\t\tvar can_have_gun = enable_water_gun_spawn
\t\tif can_have_gun:
\t\t\tfor armed_pos in armed_positions:
\t\t\t\tif spawn_pos.distance_to(armed_pos) < min_gun_spacing:
\t\t\t\t\tcan_have_gun = false
\t\t\t\t\tbreak

\t\tvar has_gun: bool = can_have_gun and (_rng.randf() < gun_spawn_chance)
\t\tvar has_balloon: bool = false
\t\tif has_gun:
\t\t\tarmed_positions.append(spawn_pos)
\t\telif enable_balloon_spawn and enable_balloon_throwing:
\t\t\thas_balloon = (_rng.randf() < balloon_spawn_chance)

\t\tif i == 0 and existing_male:
\t\t\tmember = existing_male
\t\t\tmember.visible = true
\t\t\tchosen_model_type = 0
\t\telse:
\t\t\tvar scene_to_use: PackedScene = male_model_scene
\t\t\tif has_gun and male_model_gun_scene:
\t\t\t\tscene_to_use = male_model_gun_scene
\t\t\telif has_balloon and male_model_balloon_scene:
\t\t\t\tscene_to_use = male_model_balloon_scene
\t\t\telif enable_female_crowd and female_model_scene and not enable_male_crowd:
\t\t\t\tscene_to_use = female_model_scene
\t\t\t\tchosen_model_type = 1
\t\t\telif male_model_scene:
\t\t\t\tscene_to_use = male_model_scene

\t\t\tif not scene_to_use:
\t\t\t\tif male_model_scene:
\t\t\t\t\tscene_to_use = male_model_scene
\t\t\t\telse:
\t\t\t\t\tbreak

\t\t\tmember = scene_to_use.instantiate() as Node3D
\t\t\tmember.name = "CrowdMember_%d" % i
\t\t\tmember.set_meta("is_crowd_preview", true)
\t\t\tif not (member is CrowdMember):
\t\t\t\tvar crowd_member_script = preload("res://scripts/crowd_member.gd")
\t\t\t\tmember.set_script(crowd_member_script)
\t\t\tvar internal_mode = Node.INTERNAL_MODE_BACK if Engine.is_editor_hint() else Node.INTERNAL_MODE_DISABLED
\t\t\tadd_child(member, false, internal_mode)

\t\tplaced_positions.append(spawn_pos)
\t\tmember.global_position = spawn_pos
\t\tmember.rotation.y = _rng.randf_range(0.0, TAU)

\t\t# Collect RIDs from placed member to exclude from future spawn raycasts/shapes
\t\tif member is CollisionObject3D:
\t\t\t\tplaced_rids.append(member.get_rid())"""
    ),
    # 4. setup_member and saved_crowd_data in _setup_crowd()
    (
"""\t\tif member.has_method("setup_member"):
\t\t\tmember.setup_member(has_gun, mat, member_config)

\t\tactive_members.append(member)
\t\t_apply_culling_settings_to_member(member)

\t\tif Engine.is_editor_hint() or lock_editor_positions:
\t\t\tsaved_crowd_data.append({
\t\t\t\t"local_pos": to_local(spawn_pos),
\t\t\t\t"rot_y": member.rotation.y,
\t\t\t\t"row": row,
\t\t\t\t"has_gun": has_gun,
\t\t\t\t"color_idx": chosen_color_idx,
\t\t\t\t"model_type": chosen_model_type,
\t\t\t})""",
"""\t\tif member.has_method("setup_member"):
\t\t\tmember.setup_member(has_gun, mat, member_config, has_balloon)

\t\tactive_members.append(member)
\t\t_apply_culling_settings_to_member(member)

\t\tif Engine.is_editor_hint() or lock_editor_positions:
\t\t\tsaved_crowd_data.append({
\t\t\t\t"local_pos": to_local(spawn_pos),
\t\t\t\t"rot_y": member.rotation.y,
\t\t\t\t"row": row,
\t\t\t\t"has_gun": has_gun,
\t\t\t\t"has_balloon": has_balloon,
\t\t\t\t"color_idx": chosen_color_idx,
\t\t\t\t"model_type": chosen_model_type,
\t\t\t})"""
    ),
    # 5. _spawn_from_saved_layout()
    (
"""\t\tvar row: CrowdRow = data.get("row", CrowdRow.FRONT) as CrowdRow
\t\tvar has_gun: bool = bool(data.get("has_gun", false)) and enable_water_gun_spawn
\t\tvar color_idx: int = int(data.get("color_idx", 0))
\t\tvar model_type: int = int(data.get("model_type", 0))

\t\tvar member: Node3D = null
\t\tif i == 0 and existing_male:
\t\t\tmember = existing_male
\t\t\tmember.visible = true
\t\telse:
\t\t\tvar scene_to_use: PackedScene = male_model_scene
\t\t\tif model_type == 1 and female_model_scene and enable_female_crowd:
\t\t\t\tscene_to_use = female_model_scene
\t\t\telif not enable_male_crowd and female_model_scene:
\t\t\t\tscene_to_use = female_model_scene

\t\t\tif not scene_to_use:
\t\t\t\tif male_model_scene:
\t\t\t\t\tscene_to_use = male_model_scene
\t\t\t\telif female_model_scene:
\t\t\t\t\tscene_to_use = female_model_scene
\t\t\t\telse:
\t\t\t\t\tcontinue

\t\t\tmember = scene_to_use.instantiate() as Node3D
\t\t\tmember.name = "CrowdMember_%d" % i
\t\t\tmember.set_meta("is_crowd_preview", true)
\t\t\tif not (member is CrowdMember):
\t\t\t\tvar crowd_member_script = preload("res://scripts/crowd_member.gd")
\t\t\t\tmember.set_script(crowd_member_script)
\t\t\tvar internal_mode = Node.INTERNAL_MODE_BACK if Engine.is_editor_hint() else Node.INTERNAL_MODE_DISABLED
\t\t\tadd_child(member, false, internal_mode)""",
"""\t\tvar row: CrowdRow = data.get("row", CrowdRow.FRONT) as CrowdRow
\t\tvar has_gun: bool = bool(data.get("has_gun", false)) and enable_water_gun_spawn
\t\tvar has_balloon: bool = bool(data.get("has_balloon", false)) and enable_balloon_spawn
\t\tvar color_idx: int = int(data.get("color_idx", 0))
\t\tvar model_type: int = int(data.get("model_type", 0))

\t\tvar member: Node3D = null
\t\tif i == 0 and existing_male:
\t\t\tmember = existing_male
\t\t\tmember.visible = true
\t\telse:
\t\t\tvar scene_to_use: PackedScene = male_model_scene
\t\t\tif has_gun and male_model_gun_scene:
\t\t\t\tscene_to_use = male_model_gun_scene
\t\t\telif has_balloon and male_model_balloon_scene:
\t\t\t\tscene_to_use = male_model_balloon_scene
\t\t\telif model_type == 1 and female_model_scene and enable_female_crowd:
\t\t\t\tscene_to_use = female_model_scene
\t\t\telif not enable_male_crowd and female_model_scene:
\t\t\t\tscene_to_use = female_model_scene

\t\t\tif not scene_to_use:
\t\t\t\tif male_model_scene:
\t\t\t\t\tscene_to_use = male_model_scene
\t\t\t\telif female_model_scene:
\t\t\t\t\tscene_to_use = female_model_scene
\t\t\t\telse:
\t\t\t\t\tcontinue

\t\t\tmember = scene_to_use.instantiate() as Node3D
\t\t\tmember.name = "CrowdMember_%d" % i
\t\t\tmember.set_meta("is_crowd_preview", true)
\t\t\tif not (member is CrowdMember):
\t\t\t\tvar crowd_member_script = preload("res://scripts/crowd_member.gd")
\t\t\t\tmember.set_script(crowd_member_script)
\t\t\tvar internal_mode = Node.INTERNAL_MODE_BACK if Engine.is_editor_hint() else Node.INTERNAL_MODE_DISABLED
\t\t\tadd_child(member, false, internal_mode)"""
    ),
    # 6. setup_member in _spawn_from_saved_layout()
    (
"""\t\tif member.has_method("setup_member"):
\t\t\tmember.setup_member(has_gun, mat, member_config)

\t\tactive_members.append(member)""",
"""\t\tif member.has_method("setup_member"):
\t\t\tmember.setup_member(has_gun, mat, member_config, has_balloon)

\t\tactive_members.append(member)"""
    ),
    # 7. _trigger_random_balloon()
    (
"""func _trigger_random_balloon() -> void:
\t_candidate_shooters.clear()
\tfor m in active_members:
\t\tif m is CrowdMember and m.is_row_active and not m.is_armed and not m.is_performing_action:
\t\t\t_candidate_shooters.append(m)""",
"""func _trigger_random_balloon() -> void:
\t_candidate_shooters.clear()
\tfor m in active_members:
\t\tif m is CrowdMember and m.is_row_active and not m.is_performing_action:
\t\t\tif m.is_balloon_thrower or (is_instance_valid(m.attached_balloon) and not m.is_armed):
\t\t\t\t_candidate_shooters.append(m)"""
    )
]

crowd_member_gd_replacements = [
    # 1. Add is_balloon_thrower variable
    (
"""var attached_balloon: Node3D = null
var hit_reaction_modifier: EnemyHitReactionModifier = null""",
"""var attached_balloon: Node3D = null
var is_balloon_thrower: bool = false
var hit_reaction_modifier: EnemyHitReactionModifier = null"""
    ),
    # 2. Preview cleanup protection for balloon throwers
    (
"""\t\t\tif skeleton:
\t\t\t\tfor child in skeleton.get_children():
\t\t\t\t\tif child is BoneAttachment3D and child.name != "HitboxAttachRightHand":
\t\t\t\t\t\tchild.queue_free()
\t\t\tif not is_armed:
\t\t\t\t_remove_hand_attachment()
\t\treturn""",
"""\t\t\tif skeleton:
\t\t\t\tfor child in skeleton.get_children():
\t\t\t\t\tif child is BoneAttachment3D and child.name != "HitboxAttachRightHand":
\t\t\t\t\t\tchild.queue_free()
\t\t\tif not is_armed and not is_balloon_thrower and not is_instance_valid(attached_balloon):
\t\t\t\t_remove_hand_attachment()
\t\treturn"""
    ),
    # 3. Resolve nodes for existing HitboxAttachRightHand, gun, and balloon
    (
"""\tif not is_instance_valid(hitboxes):
\t\thitboxes = find_child("Hitboxes", true, false) as Node3D

\t# Cache meshes and collision RIDs once to avoid thousands of find_children() calls during gameplay""",
"""\tif not is_instance_valid(hitboxes):
\t\thitboxes = find_child("Hitboxes", true, false) as Node3D

\t# Resolve right hand attachment and accessories if present in the scene
\tvar hand = skeleton.get_node_or_null("HitboxAttachRightHand") if skeleton else null
\tif hand:
\t\tif not is_instance_valid(npc_gun):
\t\t\tnpc_gun = hand.get_node_or_null("NPCGun") as Node3D
\t\tif is_instance_valid(npc_gun) and not is_instance_valid(gun_spawn_point):
\t\t\tgun_spawn_point = npc_gun.find_child("GunSpawnPoint", true, false) as Node3D
\t\tif not is_instance_valid(attached_balloon):
\t\t\tattached_balloon = hand.get_node_or_null("WaterBalloon") as Node3D

\tif is_instance_valid(attached_balloon):
\t\tis_balloon_thrower = true
\t\tattached_balloon.visible = false
\t\tif "trail_particles" in attached_balloon:
\t\t\tattached_balloon.trail_particles = null
\t\tif "splash_particles" in attached_balloon:
\t\t\tattached_balloon.splash_particles = null
\t\tfor child in attached_balloon.find_children("*", "GPUParticles3D", true, false):
\t\t\tchild.queue_free()

\tif is_instance_valid(npc_gun):
\t\tis_armed = true

\t# Cache meshes and collision RIDs once to avoid thousands of find_children() calls during gameplay"""
    ),
    # 4. _unequip_gun() simply hides gun instead of freeing or removing hand attachment
    (
"""func _unequip_gun() -> void:
\tif is_instance_valid(npc_gun):
\t\tnpc_gun.queue_free()
\t\tnpc_gun = null
\t\tgun_spawn_point = null
\tif not is_instance_valid(attached_balloon):
\t\t_remove_hand_attachment()""",
"""func _unequip_gun() -> void:
\tif is_instance_valid(npc_gun):
\t\tnpc_gun.visible = false"""
    ),
    # 5. setup_member with balloon_thrower parameter
    (
"""func setup_member(armed: bool, material: Material, config: Dictionary = {}) -> void:
\t_is_setup_done = true
\tfor k in config:
\t\tif k in self:
\t\t\tset(k, config[k])

\t_resolve_nodes()
\tif not Engine.is_editor_hint():
\t\t_optimize_skeleton_bones()
\t\t_setup_hit_reactions()
\t\t_setup_hitboxes()

\tis_armed = armed and enable_water_gun
\tif is_armed:
\t\t_equip_gun()
\t\tif is_instance_valid(attached_balloon):
\t\t\tattached_balloon.queue_free()
\t\t\tattached_balloon = null
\telse:
\t\t_unequip_gun()

\tif material:
\t\tset_crowd_material(material)

\tstart_idle_loop()
\t_apply_audio_state()""",
"""func setup_member(armed: bool, material: Material, config: Dictionary = {}, balloon_thrower: bool = false) -> void:
\t_is_setup_done = true
\tfor k in config:
\t\tif k in self:
\t\t\tset(k, config[k])

\t_resolve_nodes()
\tif not Engine.is_editor_hint():
\t\t_optimize_skeleton_bones()
\t\t_setup_hit_reactions()
\t\t_setup_hitboxes()

\tis_armed = armed and enable_water_gun
\tif balloon_thrower or (is_instance_valid(attached_balloon) and not is_armed):
\t\tis_balloon_thrower = true

\tif is_armed:
\t\t_equip_gun()
\t\tif is_instance_valid(attached_balloon):
\t\t\tattached_balloon.visible = false
\telse:
\t\t_unequip_gun()

\tif is_balloon_thrower:
\t\tif is_instance_valid(attached_balloon):
\t\t\tattached_balloon.visible = false

\tif material:
\t\tset_crowd_material(material)

\tstart_idle_loop()
\t_apply_audio_state()"""
    ),
    # 6. throw_balloon_at only spawns if null, and does not remove hand attachment
    (
"""\t# Smoothly rotate toward target
\t_rotate_smoothly_toward(target_pos)

\t_spawn_hand_balloon()
\t_set_attached_balloon_visible(true)""",
"""\t# Smoothly rotate toward target
\t_rotate_smoothly_toward(target_pos)

\tif not is_instance_valid(attached_balloon):
\t\t_spawn_hand_balloon()
\t_set_attached_balloon_visible(true)"""
    ),
    # 7. throw_balloon_at completion callback
    (
"""\t\tget_tree().create_timer(anim_len).timeout.connect(func():
\t\t\tif is_instance_valid(self):
\t\t\t\tis_performing_action = false
\t\t\t\tif not is_armed:
\t\t\t\t\t_remove_hand_attachment()
\t\t\t\tresume_base_loop()
\t\t)
\telse:
\t\tvar spawn_pos = attached_balloon.global_position if attached_balloon else (global_position + Vector3(0, 1.4, 0))
\t\t_set_attached_balloon_visible(false)
\t\tif on_balloon_release.is_valid():
\t\t\ton_balloon_release.call(self, spawn_pos, target_pos)
\t\tis_performing_action = false
\t\tif not is_armed:
\t\t\t_remove_hand_attachment()
\t\tresume_base_loop()""",
"""\t\tget_tree().create_timer(anim_len).timeout.connect(func():
\t\t\tif is_instance_valid(self):
\t\t\t\tis_performing_action = false
\t\t\t\tresume_base_loop()
\t\t)
\telse:
\t\tvar spawn_pos = attached_balloon.global_position if attached_balloon else (global_position + Vector3(0, 1.4, 0))
\t\t_set_attached_balloon_visible(false)
\t\tif on_balloon_release.is_valid():
\t\t\ton_balloon_release.call(self, spawn_pos, target_pos)
\t\tis_performing_action = false
\t\tresume_base_loop()"""
    )
]

if __name__ == "__main__":
    ok1 = update_file("scripts/crowd.gd", crowd_gd_replacements)
    ok2 = update_file("scripts/crowd_member.gd", crowd_member_gd_replacements)
    if ok1 and ok2:
        print("ALL UPDATES APPLIED SUCCESSFULLY!")
    else:
        print("UPDATE FAILED!")
        exit(1)
