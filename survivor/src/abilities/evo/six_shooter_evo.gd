## Six-Shooter evolution modules (Revolver). All behaviors are already wired
## inline in Revolver via has_evo()/evo_param(); modules here provide the
## hook-based pieces (cross-ability casts, etc.).
class_name RevolverEvo
extends RefCounted

class RunningReload extends EvoModule:
    ## Reload rate handled inline in Revolver.update().
    pass

class FanTheHammer extends EvoModule:
    ## Point-blank fan handled inline in Revolver.update()/_fan().
    pass

class Quickdraw extends EvoModule:
    ## First-shot x3 handled inline in Revolver._shoot().
    pass

class Showdown extends EvoModule:
    ## Re-mark cadence handled inline in Revolver.update()/_mark_showdown().
    pass

class RicochetRounds extends EvoModule:
    ## Ricochet opts passed in Revolver._shoot() fire() call.
    pass

class LongBarrel extends EvoModule:
    ## Range + distance damage handled inline in Revolver._shoot() opts.
    pass

class DeadEye extends EvoModule:
    ## Stillness meter + x3 slug handled inline in Revolver.update()/_shoot().
    pass

class DeadMansHand extends EvoModule:
    ## 6th-bullet explosive handled inline in Revolver._shoot()/update().
    pass
