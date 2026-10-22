## Flailing Whip evolution modules (Whip). Most behaviors are already wired
## inline in Whip via has_evo()/evo_param(); modules here add hook-based logic.
class_name WhipEvo
extends RefCounted

class TwirlingLasso extends EvoModule:
    ## Orbit ring tick rate handled inline in Whip.update().
    pass

class DraggingChain extends EvoModule:
    ## Ground trail handled inline in Whip.update().
    pass

class Roundup extends EvoModule:
    ## Pull + stun cadence handled inline in Whip.update()/_roundup().
    pass

class BarbedFence extends EvoModule:
    ## Post + link beam handled inline in Whip.update()/_fence_tick().
    pass

class SweetSpot extends EvoModule:
    ## Narrow line + tip crit handled inline in Whip._lash().
    pass

class SnapParry extends EvoModule:
    ## Projectile intercept handled inline in Whip._lash() via EvoPrims.intercept_segment().
    pass

class FastHands extends EvoModule:
    ## Lash-hit reloads six-shooter, handled inline in Whip._lash() via reload_now().
    pass

class WantedPoster extends EvoModule:
    ## Mark elites/bosses handled inline in Whip._wanted(); damage mult in EnemyManager.damage().
    pass
