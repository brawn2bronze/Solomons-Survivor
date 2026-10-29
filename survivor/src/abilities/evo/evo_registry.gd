class_name EvoRegistry
extends RefCounted
## Ids whose behavior code is live. A tier is only offered when BOTH its options
## are listed here, so each slice ships on its own.
const READY := {
	# six_shooter (Revolver)
	"running_reload": true, "fan_the_hammer": true, "quickdraw": true, "showdown": true,
	"ricochet_rounds": true, "long_barrel": true, "dead_eye": true, "dead_mans_hand": true,
	# katana (MeleeSwipe)
	"wayfinder": true, "momentum_edge": true, "moonfall_whirl": true, "afterimage": true,
	"weaving_blades": true, "unbroken_combo": true, "thousand_cuts": true, "reprisal": true,
	# flailing_whip (Whip)
	"twirling_lasso": true, "dragging_chain": true, "roundup": true, "barbed_fence": true,
	"sweet_spot": true, "snap_parry": true, "fast_hands": true, "wanted_poster": true,
	# flash_bombs (StunPulse)
	"smoke_veil": true, "trailing_mines": true, "vanish": true, "cascade_flash": true,
	"killing_light": true, "panic_powder": true, "kawarimi": true, "five_point_palm": true,
	# hand_cannon (Cannon)
	"chain_shot": true, "broadside": true, "phantom_broadside": true, "bombard": true,
	"rebound": true, "kickback": true, "burning_pitch": true, "primed_powder": true,
	# pirate_crew (SummonAllies)
	"gun_crew": true, "boarding_party": true, "jolly_roger": true, "x_marks_the_spot": true,
	"grog_rations": true, "human_shield": true, "man_overboard": true, "release_the_kraken": true,
	# greatsword (MeleeSwipe)
	"crusaders_march": true, "mirror_wave": true, "dawnbreaker": true, "pilgrims_road": true,
	"fervor": true, "retribution": true, "holy_leap": true, "bulwark_stance": true,
	# prayer (Whip)
	"consecration": true, "seraph_ring": true, "sanctuary": true, "lay_on_hands": true,
	"tolling_bell": true, "verdict_mark": true, "final_judgement": true, "twin_suns": true,
	# merlins_book (ChainLightning)
	"static_charge": true, "lightning_lance": true, "blink_strike": true, "capacitor": true,
	"orbit_guard": true, "rolling_thunder": true, "singularity": true, "faraday_cage": true,
	# astral_projection (AstralClone)
	"astral_anchor": true, "mirror_image": true, "astral_swap": true, "ethereal_walk": true,
	"spell_echo": true, "flow_state": true, "time_stop": true, "wild_magic": true,
	# horns (MeleeSwipe)
	"fling": true, "hook_swing": true, "labrys_whirl": true, "labyrinth_walls": true,
	"steered_rush": true, "skewer": true, "ramming_speed": true, "breaking_charge": true,
	# beasts_roar (Roar)
	"spiked_hide": true, "warcry_shockwave": true, "armored_charge": true, "outnumbered": true,
	"thundering_hooves": true, "bulldozer": true, "last_stand": true, "armor_burst": true,
}

static func is_ready(id: String) -> bool:
	return READY.has(id)

static func make(id: String) -> EvoModule:
	match id:
		# six_shooter
		"running_reload": return RevolverEvo.RunningReload.new()
		"fan_the_hammer": return RevolverEvo.FanTheHammer.new()
		"quickdraw": return RevolverEvo.Quickdraw.new()
		"showdown": return RevolverEvo.Showdown.new()
		"ricochet_rounds": return RevolverEvo.RicochetRounds.new()
		"long_barrel": return RevolverEvo.LongBarrel.new()
		"dead_eye": return RevolverEvo.DeadEye.new()
		"dead_mans_hand": return RevolverEvo.DeadMansHand.new()
		# katana
		"wayfinder": return KatanaEvo.Wayfinder.new()
		"momentum_edge": return KatanaEvo.MomentumEdge.new()
		"moonfall_whirl": return KatanaEvo.MoonfallWhirl.new()
		"afterimage": return KatanaEvo.Afterimage.new()
		"weaving_blades": return KatanaEvo.WeavingBlades.new()
		"unbroken_combo": return KatanaEvo.UnbrokenCombo.new()
		"thousand_cuts": return KatanaEvo.ThousandCuts.new()
		"reprisal": return KatanaEvo.Reprisal.new()
		# flailing_whip
		"twirling_lasso": return WhipEvo.TwirlingLasso.new()
		"dragging_chain": return WhipEvo.DraggingChain.new()
		"roundup": return WhipEvo.Roundup.new()
		"barbed_fence": return WhipEvo.BarbedFence.new()
		"sweet_spot": return WhipEvo.SweetSpot.new()
		"snap_parry": return WhipEvo.SnapParry.new()
		"fast_hands": return WhipEvo.FastHands.new()
		"wanted_poster": return WhipEvo.WantedPoster.new()
		# flash_bombs
		"smoke_veil": return StunPulseEvo.SmokeVeil.new()
		"trailing_mines": return StunPulseEvo.TrailingMines.new()
		"vanish": return StunPulseEvo.Vanish.new()
		"cascade_flash": return StunPulseEvo.CascadeFlash.new()
		"killing_light": return StunPulseEvo.KillingLight.new()
		"panic_powder": return StunPulseEvo.PanicPowder.new()
		"kawarimi": return StunPulseEvo.Kawarimi.new()
		"five_point_palm": return StunPulseEvo.FivePointPalm.new()
		# hand_cannon
		"chain_shot": return HandCannonEvo.ChainShot.new()
		"broadside": return HandCannonEvo.Broadside.new()
		"phantom_broadside": return HandCannonEvo.PhantomBroadside.new()
		"bombard": return HandCannonEvo.Bombard.new()
		"rebound": return HandCannonEvo.Rebound.new()
		"kickback": return HandCannonEvo.Kickback.new()
		"burning_pitch": return HandCannonEvo.BurningPitch.new()
		"primed_powder": return HandCannonEvo.PrimedPowder.new()
		# pirate_crew
		"gun_crew": return PirateCrewEvo.GunCrew.new()
		"boarding_party": return PirateCrewEvo.BoardingParty.new()
		"jolly_roger": return PirateCrewEvo.JollyRoger.new()
		"x_marks_the_spot": return PirateCrewEvo.XMarksTheSpot.new()
		"grog_rations": return PirateCrewEvo.GrogRations.new()
		"human_shield": return PirateCrewEvo.HumanShield.new()
		"man_overboard": return PirateCrewEvo.ManOverboard.new()
		"release_the_kraken": return PirateCrewEvo.ReleaseTheKraken.new()
		# greatsword
		"crusaders_march": return PaladinEvo.CrusadersMarch.new()
		"mirror_wave": return PaladinEvo.MirrorWave.new()
		"dawnbreaker": return PaladinEvo.Dawnbreaker.new()
		"pilgrims_road": return PaladinEvo.PilgrimsRoad.new()
		"fervor": return PaladinEvo.Fervor.new()
		"retribution": return PaladinEvo.Retribution.new()
		"holy_leap": return PaladinEvo.HolyLeap.new()
		"bulwark_stance": return PaladinEvo.BulwarkStance.new()
		# prayer
		"consecration": return PaladinEvo.Consecration.new()
		"seraph_ring": return PaladinEvo.SeraphRing.new()
		"sanctuary": return PaladinEvo.Sanctuary.new()
		"lay_on_hands": return PaladinEvo.LayOnHands.new()
		"tolling_bell": return PaladinEvo.TollingBell.new()
		"verdict_mark": return PaladinEvo.VerdictMark.new()
		"final_judgement": return PaladinEvo.FinalJudgement.new()
		"twin_suns": return PaladinEvo.TwinSuns.new()
	return null
