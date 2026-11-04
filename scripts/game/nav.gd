extends RefCounted
## The bots' map of a level: every surface you can stand on, and the moves that get you from
## one to another — walking across, walking off an edge, dropping through a platform, or
## jumping (straight up through a platform, or across a gap).

const RUN := 300.0
const JUMP_V := 800.0
const GRAVITY := 2300.0
const MAX_RISE := 125.0


class Surface:
	var idx := 0
	var x0 := 0.0
	var x1 := 0.0
	var y := 0.0
	var oneway := false
	var links: Array = []

	func has_x(x: float, margin := 0.0) -> bool:
		return x >= x0 - margin and x <= x1 + margin


class Link:
	var from := 0
	var to := 0
	## "walk", "fall" (walk off the edge), "drop" (↓ + jump through a platform) or "jump".
	var kind := "walk"
	var take_x := 0.0
	var land_x := 0.0
	## For drops and straight-up jumps, any take-off point in [lo, hi] works (the move goes
	## straight down or up there); otherwise lo == hi == take_x.
	var lo := 0.0
	var hi := 0.0
	var cost := 0.0


var surfaces: Array = []


func build(w: RefCounted) -> void:
	surfaces = []
	for r: Rect2 in w.solids:
		if r.position.y > -100.0 and r.size.x >= 30.0:
			_add(r.position.x, r.end.x, r.position.y, false)
	for r: Rect2 in w.oneways:
		_add(r.position.x, r.end.x, r.position.y, true)
	for a: Surface in surfaces:
		for b: Surface in surfaces:
			if a != b:
				_link(a, b)


func _add(x0: float, x1: float, y: float, oneway: bool) -> void:
	var s := Surface.new()
	s.idx = surfaces.size()
	s.x0 = maxf(x0, 0.0)
	s.x1 = minf(x1, 1280.0)
	s.y = y
	s.oneway = oneway
	if s.x1 - s.x0 >= 20.0:
		surfaces.append(s)


## Horizontal distance a running jump covers while ending `rise` px higher (negative = lower).
static func jump_reach(rise: float) -> float:
	var disc := JUMP_V * JUMP_V - 2.0 * GRAVITY * rise
	if disc < 0.0:
		return 0.0
	return RUN * (JUMP_V + sqrt(disc)) / GRAVITY


## The first surface under (x, y), other than `skip`.
func first_below(x: float, y: float, skip: Surface = null) -> Surface:
	var best: Surface = null
	for s: Surface in surfaces:
		if s == skip or not s.has_x(x) or s.y < y - 1.0:
			continue
		if best == null or s.y < best.y:
			best = s
	return best


func _link(a: Surface, b: Surface) -> void:
	var dy := b.y - a.y  # positive: b is lower
	var right := b.x0 >= a.x1 - 2.0
	var left := b.x1 <= a.x0 + 2.0
	var ov0 := maxf(a.x0, b.x0) + 10.0
	var ov1 := minf(a.x1, b.x1) - 10.0
	# Side by side at the same height.
	if absf(dy) < 3.0 and (right or left):
		var gap := (b.x0 - a.x1) if right else (a.x0 - b.x1)
		if gap <= 3.0:
			var edge := a.x1 if right else a.x0
			var dir := 1.0 if right else -1.0
			_make(a, b, "walk", edge - dir * 4.0, edge + dir * 18.0)
			return
	if dy > 3.0:
		# b is lower: drop through, or walk off an edge.
		if a.oneway and ov1 - ov0 >= 10.0:
			var x := (ov0 + ov1) * 0.5
			if first_below(x, a.y + 2.0, a) == b:
				_make(a, b, "drop", x, x, ov0, ov1)
		var fall_reach := RUN * sqrt(2.0 * dy / GRAVITY) * 0.85 + 10.0
		for dir in [1.0, -1.0]:
			var edge := a.x1 if dir > 0.0 else a.x0
			var land := clampf(edge + dir * 30.0, b.x0 + 14.0, b.x1 - 14.0)
			if (land - edge) * dir < 8.0 or (land - edge) * dir > fall_reach:
				continue
			if first_below(land, a.y + 2.0, a) == b and first_below(edge + dir * 12.0, a.y + 2.0, a) in [b, null]:
				_make(a, b, "fall", edge - dir * 3.0, land)
	var rise := -dy
	if rise > MAX_RISE:
		return
	# b is higher (or level but across a gap): jump.
	if rise > 3.0 and b.oneway and ov1 - ov0 >= 24.0:
		var x := (ov0 + ov1) * 0.5
		_make(a, b, "jump", x, x, ov0, ov1)
		return
	var reach := jump_reach(maxf(rise, 0.0) + 12.0) * 0.78
	if rise > 3.0 and not b.oneway and b.x0 > a.x0 + 20.0 and b.x0 < a.x1 - 20.0:
		# A block standing on a: jump onto it from beside it.
		_make(a, b, "jump", b.x0 - 28.0, b.x0 + 16.0)
	if rise > 3.0 and not b.oneway and b.x1 < a.x1 - 20.0 and b.x1 > a.x0 + 20.0:
		_make(a, b, "jump", b.x1 + 28.0, b.x1 - 16.0)
	if right or left or (rise > 3.0 and ov1 - ov0 < 24.0):
		var dir := 1.0 if b.x0 + b.x1 > a.x0 + a.x1 else -1.0
		var edge := a.x1 if dir > 0.0 else a.x0
		var far := b.x0 if dir > 0.0 else b.x1
		var gap := (far - edge) * dir
		if gap > reach or (gap < -60.0):
			return
		if dy > 3.0 and gap < RUN * sqrt(2.0 * dy / GRAVITY) * 0.85 - 30.0:
			return  # walking off the edge already gets there
		_make(a, b, "jump", edge - dir * 10.0, far + dir * 20.0)


func _make(a: Surface, b: Surface, kind: String, take_x: float, land_x: float, lo := NAN, hi := NAN) -> void:
	var l := Link.new()
	l.from = a.idx
	l.to = b.idx
	l.kind = kind
	l.take_x = clampf(take_x, a.x0 + 2.0, a.x1 - 2.0)
	l.land_x = clampf(land_x, b.x0 + 6.0, b.x1 - 6.0)
	l.lo = l.take_x if is_nan(lo) else lo
	l.hi = l.take_x if is_nan(hi) else hi
	l.cost = absf(l.land_x - l.take_x) + absf(b.y - a.y) * (1.6 if b.y < a.y else 0.6) + (30.0 if kind == "jump" else 10.0)
	a.links.append(l)


## The surface a fighter standing at `pos` is on, or null in the air.
func surface_at(pos: Vector2) -> Surface:
	for s: Surface in surfaces:
		if absf(s.y - pos.y) < 3.0 and s.has_x(pos.x, 8.0):
			return s
	return null


## The surface under a point (a target's feet, a weapon lying around), or null over a pit.
func surface_under(pos: Vector2) -> Surface:
	return first_below(pos.x, pos.y - 4.0)


## Cheapest list of links from `start` (standing at `x`) to `goal`, or [] if there's no way.
## Links in `banned` are skipped.
func path(start: Surface, goal: Surface, x: float, banned := {}) -> Array:
	if start == null or goal == null or start == goal:
		return []
	var dist := {start.idx: 0.0}
	var at_x := {start.idx: x}
	var via := {}
	var open := [start.idx]
	var done := {}
	while not open.is_empty():
		var best := -1
		for i: int in open:
			if best < 0 or dist[i] < dist[best]:
				best = i
		open.erase(best)
		if best == goal.idx:
			break
		done[best] = true
		var s: Surface = surfaces[best]
		for l: Link in s.links:
			if done.has(l.to) or banned.has(l):
				continue
			var c: float = dist[best] + absf(float(at_x[best]) - l.take_x) + l.cost
			if not dist.has(l.to) or c < dist[l.to]:
				dist[l.to] = c
				at_x[l.to] = l.land_x
				via[l.to] = l
				if not open.has(l.to):
					open.append(l.to)
	if not via.has(goal.idx):
		return []
	var out := []
	var cur := goal.idx
	while cur != start.idx:
		var l: Link = via[cur]
		out.push_front(l)
		cur = l.from
	return out


## Path cost between two points (for choosing the nearest target), INF if unreachable.
func travel_cost(from: Vector2, to: Vector2) -> float:
	var a := surface_at(from)
	if a == null:
		a = surface_under(from)
	var b := surface_under(to)
	if a == null or b == null:
		return INF
	if a == b:
		return absf(from.x - to.x)
	var p := path(a, b, from.x)
	if p.is_empty():
		return INF
	var c := 0.0
	var x := from.x
	for l: Link in p:
		c += absf(x - l.take_x) + l.cost
		x = l.land_x
	return c + absf(x - to.x)
