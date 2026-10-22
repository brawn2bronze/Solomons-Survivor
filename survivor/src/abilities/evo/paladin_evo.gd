## Paladin evolution modules (Greatsword / Prayer). Most behaviors are inline
## in MeleeSwipe and Whip via has_evo()/evo_param(); modules here own hook logic.
class_name PaladinEvo
extends RefCounted

class CrusadersMarch extends EvoModule:
    ## Advance stacks handled inline in MeleeSwipe.update() via meter("greatsword_advance").
    pass

class MirrorWave extends EvoModule:
    ## Wave reflection handled inline in MeleeSwipe.update() via tracked wave paths.
    pass

class Dawnbreaker extends EvoModule:
    ## Rotating beams handled inline in MeleeSwipe.update() via nth("greatsword_dawn").
    pass

class PilgrimsRoad extends EvoModule:
    ## Ground tiles handled inline in MeleeSwipe.update().
    pass

class Fervor extends EvoModule:
    ## Stack build/decay handled inline in MeleeSwipe._fervor_gain()/update().
    pass

class Retribution extends EvoModule:
    ## Hurt charge and nova handled inline in MeleeSwipe.on_player_hurt()/_swipe().
    pass

class HolyLeap extends EvoModule:
    ## Leap cooldown handled inline in MeleeSwipe.update().
    pass

class BulwarkStance extends EvoModule:
    ## Guard arc handled inline in MeleeSwipe.update().
    pass


class Consecration extends EvoModule:
    ## Ground zones and healing handled inline in Whip._prayer_evos().
    pass

class SeraphRing extends EvoModule:
    ## Orbiting orbs handled inline in Whip._prayer_evos() and draw_overlay().
    pass

class Sanctuary extends EvoModule:
    ## Zone push and damage reduction handled inline in Whip.
    pass

class LayOnHands extends EvoModule:
    ## Emergency heal handled inline in Whip._prayer_evos().
    pass

class TollingBell extends EvoModule:
    ## Expanding pulse ring handled inline in Whip._prayer_pulse().
    pass

class VerdictMark extends EvoModule:
    ## Marked follow-up strike handled inline in Whip._prayer_pulse().
    pass

class FinalJudgement extends EvoModule:
    ## Delayed screen-wide pulse handled inline in Whip._prayer_pulse().
    pass

class TwinSuns extends EvoModule:
    ## Dual pulse origins handled inline in Whip._prayer_origins().
    pass
