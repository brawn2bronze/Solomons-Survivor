## Pirate crew evolution modules (SummonAllies). All behaviors are already wired
## inline in SummonAllies via has_evo()/evo_param(); modules here provide the
## hook-based pieces (cross-ability casts, etc.).
class_name PirateCrewEvo
extends RefCounted

class GunCrew extends EvoModule:
    ## Per-ally cannons handled inline in SummonAllies._ally_gun().
    pass

class BoardingParty extends EvoModule:
    ## Ally leap + slam handled inline in SummonAllies._send_boarder()/_board_slam().
    pass

class JollyRoger extends EvoModule:
    ## Banner aura handled inline in SummonAllies._plant_banner()/_update_banner().
    pass

class XMarksTheSpot extends EvoModule:
    ## Dig spot + treasure draft handled inline in SummonAllies._plant_spot()/_update_spot().
    pass

class GrogRations extends EvoModule:
    ## Keg toss handled inline in SummonAllies._toss_keg()/_update_keg().
    pass

class HumanShield extends EvoModule:
    ## Projectile interception handled inline in SummonAllies._ally_shield().
    pass

class ManOverboard extends EvoModule:
    ## Pre-damage absorb handled inline in SummonAllies.absorb_hit().
    pass

class ReleaseTheKraken extends EvoModule:
    ## Departure slams handled inline in SummonAllies._kraken_volley().
    pass
