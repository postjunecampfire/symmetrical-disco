class_name PartyMember
extends RefCounted
## Synthesizes the runtime CharacterData for a RUN MEMBER (ADR-0021 pt2 +
## ADR-0024). Member ids are STABLE handles (&"hero_1", &"hero_2") — no longer
## class ids: a member is race (base template, ADR-0021 pt1) + an optional
## CLASS OVERLAY chosen at the end of Act 3 (&"" = classless "normal person").
##
## Legacy compatibility: when a member id resolves directly in the character
## registry AND its recorded class equals itself (the pre-0024 "party of class
## ids" model used by tests/fixtures), the authored CharacterData is returned
## unchanged — every old call path behaves exactly as before.
##
## The synthesized sheet carries the class id (and race id) in `tags`, which is
## how card ownership (CardPlay tag gate) and sprite resolution find them.


## The class id of `cid` in `run` (&"" = classless). Legacy members default to
## themselves when they resolve as characters.
static func class_of(run: RunState, cid: StringName) -> StringName:
	return StringName(String(run.member_classes.get(cid, "")))


## Pre-class innate scaling rule (ADR-0021, decided 2026-06-10): a classless
## member attacks with their HIGHEST stat — the build chooses the weapon.
static func character_for(db: ContentDatabase, run: RunState, cid: StringName) -> CharacterData:
	var direct: CharacterData = db.get_character(cid)
	var cls_id: StringName = class_of(run, cid)
	if direct != null and (cls_id == cid or cls_id == &""):
		return direct  # legacy class-keyed member

	var cfg: BattleConfig = db.get_battle_config()
	var race_id: StringName = StringName(String(run.party_races.get(cid, "")))
	var race: RaceData = db.get_race(race_id)
	var cls: CharacterData = db.get_character(cls_id)

	var ch := CharacterData.new()
	ch.id = cid
	var race_name: String = race.display_name if race != null else "Wanderer"
	if cls != null:
		ch.display_name = "%s %s" % [race_name, cls.display_name]
		ch.strength = cls.strength
		ch.dexterity = cls.dexterity
		ch.constitution = cls.constitution
		ch.intelligence = cls.intelligence
		ch.attack_stat = cls.attack_stat
		ch.speed = cls.speed
		ch.tags = [cls_id, race_id] as Array[StringName]
	else:
		ch.display_name = race_name
		ch.attack_stat = &"highest"  # ADR-0021: pre-class Strike scales off the peak stat
		ch.tags = [race_id] as Array[StringName]
	# Ascension (ADR-0022): "Ascended <Capstone>" carries the flat mult step.
	var asc_v: Variant = run.ascended.get(cid)
	if asc_v is float or asc_v is int:
		ch.ascension_mult = float(asc_v)
		var caps: Array = run.member_progression.get(cid, [])
		if not caps.is_empty():
			ch.display_name = "Ascended %s" % ch.display_name
	var per_con: int = cfg.hp_per_con if cfg != null else 2
	var base: int = cfg.base_hp if cfg != null else 4
	ch.max_hp = base + ch.constitution * per_con
	ch.starting_deck = [] as Array[StringName]  # kits flow through skill collections
	return ch


## The synthesized party for the assembler, in party order.
static func party_data(db: ContentDatabase, run: RunState) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for cid in run.party:
		out.append(character_for(db, run, cid))
	return out
