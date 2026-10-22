## Flash Bombs evolution modules (StunPulse). Per-enemy marking that happens inside
## the pulse stays inline in StunPulse._flash(); hooked behaviors (on_flash, on_hurt)
## live here. Do not re-add on_attack handlers: that hook also fires on katana swings.
class_name StunPulseEvo
extends RefCounted

class SmokeVeil extends EvoModule:
	pass

class TrailingMines extends EvoModule:
	## Mine drop flow handled inline in StunPulse._mine_flow().
	pass

class Vanish extends EvoModule:
	## Each flash makes player untargetable 0.8s; next swing within 2s is x2.5 ambush.
	## Ambush multiplier applied inline in MeleeSwipe._swipe() via ambush_t.
	pass

class CascadeFlash extends EvoModule:
	## Stunned enemies that die emit a mini-flash (half radius, one generation only).
	## Handled in StunPulse.on_kill() so it can read the dead enemy's stun timer.
	pass

class KillingLight extends EvoModule:
	## First katana hit on stunned is x2 and ends stun; handled inline in
	## StunPulse._flash() (mark) and EnemyManager.damage() (mult + stun clear).
	pass

class PanicPowder extends EvoModule:
	## Fear on flash + delayed slow handled inline in StunPulse._flash().
	pass

class Kawarimi extends EvoModule:
	## When hit (12s cooldown): log takes it, blink ~120px, flash stuns area.
	var kawarimi_t := 0.0

	func update(_delta: float) -> void:
		self.kawarimi_t = maxf(0.0, self.kawarimi_t - _delta)

	func on_hurt(ctx: Dictionary) -> void:
		var amount := float(ctx.get("amount", 0.0))
		if amount <= 0.0:
			return
		var cd := float(p("cooldown", 12.0))
		if self.kawarimi_t > 0.0:
			return
		self.kawarimi_t = cd
		var blink := float(p("blink", 120.0))
		ab.player.blink_to(ab.player.global_position + ab.player.last_dir * blink, 0.4)
		var radius := float(p("radius_mult", 0.8)) * float(ab.p.get("radius", 95.0)) * ab.player.stat("area")
		var stun := float(p("stun", 1.0))
		for tgt in ab.world().enemies.query_circle(ab.player.global_position, radius):
			ab.world().enemies.stun(tgt, stun)
		ab.world().fx.ring(ab.player.global_position, 4.0, radius, 0.3, Color(1.0, 1.0, 0.8), 4.0)

class FivePointPalm extends EvoModule:
	## Flash-only: mark the toughest enemies on the field; each bursts after the delay.
	func on_flash(_ctx: Dictionary) -> void:
		var pool: Array[EnemyManager.E] = []
		for e in ab.world().enemies.query_circle(ab.player.global_position, 9999.0):
			if e.alive:
				pool.append(e)
		pool.sort_custom(func(a, b): return a.max_hp > b.max_hp)
		var delay := float(p("delay", 4.0))
		for i in mini(int(p("targets", 3)), pool.size()):
			var tgt: EnemyManager.E = pool[i]
			ab.world().enemies.mark(tgt, "five_point_palm", delay, "flash")
			ab.world().fx.ring(tgt.pos, 4.0, 26.0, 0.3, Color(1.0, 0.9, 0.6), 2.0)
			ab.after(delay, _burst.bind(tgt))

	func _burst(tgt: EnemyManager.E) -> void:
		if tgt == null or not tgt.alive:
			return
		var frac := float(p("pct", 0.20))
		if tgt.is_elite:
			frac = float(p("pct_elite", 0.08))
		elif float(tgt.def.boss_time) > 0.0:
			frac = float(p("pct_boss", 0.02))
		ab.world().enemies.damage(tgt, tgt.max_hp * frac, Vector2.ZERO, 0.0, Color(1.0, 0.85, 0.5), "five_point_palm")
		ab.world().fx.ring(tgt.pos, 6.0, 60.0, 0.3, Color(1.0, 0.85, 0.5), 4.0)
