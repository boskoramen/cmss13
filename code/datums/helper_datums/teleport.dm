//wrapper
/proc/do_teleport(ateleatom, adestination, aprecision=0, afteleport=1, aeffectin=null, aeffectout=null, asoundin=null, asoundout=null)
	new /datum/teleport/instant/science(arglist(args))
	return

/datum/teleport
	var/atom/movable/teleatom //atom to teleport
	var/atom/destination //destination to teleport to
	var/precision = 0 //teleport precision
	var/datum/effect_system/effectin //effect to show right before teleportation
	var/datum/effect_system/effectout //effect to show right after teleportation
	var/soundin //soundfile to play before teleportation
	var/soundout //soundfile to play after teleportation
	var/force_teleport = 1 //if false, teleport will use Move() proc (dense objects will prevent teleportation)


/datum/teleport/New(ateleatom, adestination, aprecision=0, afteleport=1, aeffectin=null, aeffectout=null, asoundin=null, asoundout=null)
	..()
	if(!Init(arglist(args)))
		return 0
	return 1

/datum/teleport/proc/Init(ateleatom,adestination,aprecision,afteleport,aeffectin,aeffectout,asoundin,asoundout)
	if(!setTeleatom(ateleatom))
		return 0
	if(!setDestination(adestination))
		return 0
	if(!setPrecision(aprecision))
		return 0
	setEffects(aeffectin,aeffectout)
	setForceTeleport(afteleport)
	setSounds(asoundin,asoundout)
	return 1

	//must succeed
/datum/teleport/proc/setPrecision(aprecision)
	if(isnum(aprecision))
		precision = aprecision
		return 1
	return 0

	//must succeed
/datum/teleport/proc/setDestination(atom/adestination)
	if(istype(adestination))
		destination = adestination
		return 1
	return 0

	//must succeed in most cases
/datum/teleport/proc/setTeleatom(atom/movable/ateleatom)
	if(istype(ateleatom, /obj/effect))
		qdel(ateleatom)
		return 0
	if(istype(ateleatom))
		teleatom = ateleatom
		return 1
	return 0

	//custom effects must be properly set up first for instant-type teleports
	//optional
/datum/teleport/proc/setEffects(datum/effect_system/aeffectin=null,datum/effect_system/aeffectout=null)
	effectin = istype(aeffectin) ? aeffectin : null
	effectout = istype(aeffectout) ? aeffectout : null
	return 1

	//optional
/datum/teleport/proc/setForceTeleport(afteleport)
	force_teleport = afteleport
	return 1

	//optional
/datum/teleport/proc/setSounds(asoundin=null,asoundout=null)
	soundin = isfile(asoundin) ? asoundin : null
	soundout = isfile(asoundout) ? asoundout : null
	return 1

	//placeholder
/datum/teleport/proc/teleportChecks()
	return 1

/datum/teleport/proc/playSpecials(atom/location,datum/effect_system/effect,sound)
	if(location)
		if(effect)
			spawn(-1)
				src = null
				effect.attach(location)
				effect.start()
		if(sound)
			spawn(-1)
				src = null
				playsound(location, sound, 50, 1)
	return

//do the monkey dance
/datum/teleport/proc/doTeleport()

	var/turf/destturf
	var/turf/curturf = get_turf(teleatom)
	if(precision)
		var/list/posturfs = circlerangeturfs(destination,precision)
		destturf = SAFEPICK(posturfs)
	else
		destturf = get_turf(destination)

	if(!destturf || !curturf)
		return 0

	playSpecials(curturf,effectin,soundin)

	var/obj/structure/bed/chair/C = null
	if(isliving(teleatom))
		var/mob/living/L = teleatom
		if(L.buckled)
			C = L.buckled
	if(force_teleport)
		teleatom.forceMove(destturf)
		playSpecials(destturf,effectout,soundout)
	else
		if(teleatom.Move(destturf))
			playSpecials(destturf,effectout,soundout)
	if(C)
		C.forceMove(destturf)

	return 1

/datum/teleport/proc/teleport()
	if(teleportChecks())
		return doTeleport()
	return 0

/datum/teleport/instant //teleports when datum is created

/datum/teleport/instant/New(ateleatom, adestination, aprecision=0, afteleport=1, aeffectin=null, aeffectout=null, asoundin=null, asoundout=null)
	if(..())
		teleport()
	return


/datum/teleport/instant/science

/datum/teleport/instant/science/setEffects(datum/effect_system/aeffectin,datum/effect_system/aeffectout)
	if(!aeffectin || !aeffectout)
		var/datum/effect_system/spark_spread/aeffect = new
		aeffect.set_up(5, 1, teleatom)
		effectin = effectin || aeffect
		effectout = effectout || aeffect
		return 1
	else
		return ..()

/datum/teleport/instant/science/setPrecision(aprecision)
	..()
	if(istype(teleatom, /obj/item/storage/backpack/holding))
		precision = rand(1,100)

	var/list/bagholding = teleatom.search_contents_for(/obj/item/storage/backpack/holding)
	if(length(bagholding))
		precision = max(rand(1,100)*length(bagholding),100)
		if(istype(teleatom, /mob/living))
			var/mob/living/MM = teleatom
			to_chat(MM, SPAN_WARNING("The Bluespace interface on your Bag of Holding interferes with the teleport!"))
	return 1

/datum/teleport/instant/science/teleportChecks()
	if(istype(teleatom, /obj/item/disk/nuclear)) // Don't let nuke disks get teleported --NeoFite
		teleatom.visible_message(SPAN_DANGER("<B>[teleatom] bounces off of the portal!</B>"))
		return 0

	if(length(teleatom.search_contents_for(/obj/item/disk/nuclear)))
		if(istype(teleatom, /mob/living))
			var/mob/living/MM = teleatom
			MM.visible_message(SPAN_DANGER("<B>[MM] bounces off of the portal!</B>"),SPAN_DANGER("Something you are carrying seems to be unable to pass through the portal. Better drop it if you want to go through."))
		else
			teleatom.visible_message(SPAN_DANGER("<B>[teleatom] bounces off of the portal!</B>"))
		return 0

	if(should_block_game_interaction(destination))
		if(length(teleatom.search_contents_for(/obj/item/storage/backpack/holding)))
			teleatom.visible_message(SPAN_DANGER("<B>The Bag of Holding bounces off of the portal!</B>"))
			return 0

	return 1
