extends SceneTree
func _init():
    var anim1 = load('res://AnimationsExport/Zombies/Hit RightLeg act 1 Slipping.res') as Animation
    var anim2 = load('res://AnimationsExport/Zombies/Hit RightLeg act 2 (Slipping_Ilde).res') as Animation
    if not anim1 or not anim2:
        print('Failed to load animations')
        quit()
        return
    print('Anim 1 Tracks: ', anim1.get_track_count())
    print('Anim 2 Tracks: ', anim2.get_track_count())
    
    var t1 = []
    for i in range(anim1.get_track_count()):
        t1.append(anim1.track_get_path(i))
        
    var t2 = []
    for i in range(anim2.get_track_count()):
        t2.append(anim2.track_get_path(i))
        
    var missing = []
    for p in t1:
        if not p in t2:
            missing.append(str(p))
            
    print('Missing in Anim 2: ', missing.size())
    for m in missing:
        print('  ', m)
        
    quit()

