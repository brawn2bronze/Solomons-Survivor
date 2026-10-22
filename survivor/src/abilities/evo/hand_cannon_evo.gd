## Hand cannon evolution modules (Cannon). All behaviors are already wired
## inline in Cannon via has_evo()/evo_param(); modules here provide the
## hook-based pieces (cross-ability casts, etc.).
class_name HandCannonEvo
extends RefCounted

class ChainShot extends EvoModule:
    ## Linked pair + chain sweep handled inline in Cannon._start_chain()/_update_tracers().
    pass

class Broadside extends EvoModule:
    ## Port/starboard balls while moving handled inline in Cannon._fire()/_fire_broadside().
    pass

class PhantomBroadside extends EvoModule:
    ## Ghost galleon lane handled inline in Cannon._update_phantom()/_phantom_fire().
    pass

class Bombard extends EvoModule:
    ## Mortar targeting handled inline in Cannon._fire_mortar()/_mortar_hit().
    pass

class Rebound extends EvoModule:
    ## Return leg handled by ProjectileManager rebound opts + Cannon._catch_ball().
    pass

class Kickback extends EvoModule:
    ## Backstep + muzzle cone handled inline in Cannon._recoil()/_muzzle_cone().
    pass

class BurningPitch extends EvoModule:
    ## Fire trail handled inline in Cannon._start_pitch()/_drop_pitch().
    pass

class PrimedPowder extends EvoModule:
    ## Charge fuse handled inline in Cannon._prime_enemy()/_update_primed().
    pass
