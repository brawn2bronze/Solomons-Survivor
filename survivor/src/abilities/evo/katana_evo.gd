## Katana evolution modules (MeleeSwipe). Most behaviors are already wired inline
## in MeleeSwipe via has_evo()/evo_param(); modules here add hook-based logic.
class_name KatanaEvo
extends RefCounted

class Wayfinder extends EvoModule:
    ## Aim handled inline in MeleeSwipe.update() via player.last_dir / nearest.
    pass

class MomentumEdge extends EvoModule:
    ## Radius stacks handled inline in MeleeSwipe.update() via meter("katana_mom").
    pass

class MoonfallWhirl extends EvoModule:
    ## Every-Nth whirl handled inline in MeleeSwipe.update() via nth("katana_whirl").
    pass

class Afterimage extends EvoModule:
    ## Delayed repeat handled inline in MeleeSwipe._swipe() via after().
    pass

class WeavingBlades extends EvoModule:
    ## Free slash on pass handled inline in MeleeSwipe._weaving().
    pass

class UnbrokenCombo extends EvoModule:
    ## Combo counter + finisher handled inline in MeleeSwipe._swipe()/update().
    pass

class ThousandCuts extends EvoModule:
    ## Flurry lock handled inline in MeleeSwipe._start_cuts()/_cut_tick().
    pass

class Reprisal extends EvoModule:
    ## Getting hit triggers an instant cross-slash (6s cooldown); handled inline
    ## in MeleeSwipe.on_player_hurt()/_reprisal(). Not hooked here (no double fire).
    pass
