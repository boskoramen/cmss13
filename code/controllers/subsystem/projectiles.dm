SUBSYSTEM_DEF(projectiles)
	name = "Projectiles"
	wait = 1
	flags = SS_TICKER
	priority = SS_PRIORITY_PROJECTILES

	/// List of Tuples of projectile-target scheduled for passive hit checking (you walked into it you idiot)
	VAR_PRIVATE/list/list/atom/hit_queue
	/// Current run handled passive hit checking projectiles from hit_queue
	VAR_PRIVATE/list/list/atom/hit_current

	/// All projectiles being handled by the subsystem
	VAR_PRIVATE/list/obj/item/projectile/flying
	/// Projectiles to process with their current scheduled time remaining
	VAR_PRIVATE/list/obj/item/projectile/fly_queue
	/// Current sub-iteration of the fly_queue
	VAR_PRIVATE/list/obj/item/projectile/fly_current

	/// Projectiles to run visual updates for
	VAR_PRIVATE/list/obj/item/projectile/vis_queue

	/// Cached loop delay - don't touch this - see below in fire init. Unit is ds, not seconds.
	VAR_PRIVATE/delta_time

	/// Mathematically incorrect running "average" of hit updates
	VAR_PRIVATE/hit_updates = 0
	/// Hit updates ran during last firing
	VAR_PRIVATE/hit_updates_last = 0
	/// Mathematically incorrect running "average" of flight updates
	VAR_PRIVATE/fly_updates = 0
	/// Flight updates ran during last firing
	VAR_PRIVATE/fly_updates_last = 0
	/// Amount of projectiles dropped due to uncaught errors if any
	VAR_PRIVATE/total_errors = 0


/datum/controller/subsystem/projectiles/stat_entry(msg)
	msg = " | #Proj: [flying.len] | Fly: [round(fly_updates, 0.01)] | Scan: [round(hit_updates, 0.01)] | [total_errors] errors"
	return ..()

/datum/controller/subsystem/projectiles/Initialize(start_timeofday)
	hit_queue     = list()
	hit_current   = list()
	flying        = list()
	fly_queue     = list()
	fly_current   = list()
	return ..()

/datum/controller/subsystem/projectiles/fire(resumed = FALSE)
	if(!resumed)
		vis_queue = list()

		// Update stat counters (stolen from MC_AVERAGEs, not a real running average)
		hit_updates = 0.6 * hit_updates + 0.4 * hit_updates_last
		hit_updates_last = 0
		fly_updates = 0.6 * fly_updates + 0.4 * fly_updates_last
		fly_updates_last = 0

		// Switch hit queue to active but preserve the allocated list
		hit_current.Cut()
		var/list/permutation = hit_queue
		hit_queue = hit_current
		hit_current = reverselist(permutation) // We iterate in reverse order to avoid constant popleft shuffles

		// Cache elapsed time in case of wait or tick_lag modification mid-loop
		// Having it stored per iteration opens the possibility of eg. making it variable under load!
		delta_time = wait * world.tick_lag

		// Init projectile queue for the iteration
		fly_queue = reverselist(flying)
		for(var/obj/item/projectile/P as anything in fly_queue)
			fly_queue[P] = delta_time

	// Start by handling queued hits triggered by BYOND via Collide/Crossed and posted to register_passive_hit()
	while(hit_current.len)
		if(MC_TICK_CHECK)
			return
		var/list/atom/tuple = hit_current[hit_current.len]
		hit_current.len--
		if(length(tuple) == 2)
			var/obj/item/projectile/projectile = tuple[1]
			var/atom/affected = tuple[2]
			if(!QDELETED(projectile) || QDELETED(affected))
				continue // Already gone
			handle_projectile_hit(projectile, affected)
			hit_updates_last++

	// Process bullet flight updates, actually moving them
	while(fly_queue.len)
		if(MC_TICK_CHECK)
			return

		// We're basically iterating backwards discarding through fly_current as a copy of fly_queue,
		// giving each projectile a chance to move turn by turn so they all get more or less similiar
		// chances to hit. No more sudden teleporting bullets racing others.
		if(!length(fly_current))
			fly_current = fly_queue.Copy()

		var/obj/item/projectile/projectile = fly_current[fly_current.len]
		var/remaining = 0
		if(projectile)
			remaining = fly_queue[projectile] // We keep timings updated in fly_queue
		fly_current.len--
		if(QDELETED(projectile))
			continue // Huh. We handle their travel, and would know if we deleted it, something else must have...

		// State handling is too complex and unsafe for fire() so we defer queueing logic out of it. NO gameplay logic here.
		if(remaining <= 0 || !handle_projectile_flight(projectile, remaining))
			// Runtime error safety net
			total_errors++
			fly_queue.Remove(projectile)
			flying.Remove(projectile)
			qdel(projectile)

	while(vis_queue.len)
		if(MC_TICK_CHECK)
			return
		var/obj/item/projectile/projectile = vis_queue[vis_queue.len]
		vis_queue.len--
		if(!QDELETED(projectile))
			projectile.post_flight_visual_update()

/// Run internal projectile flight update for a single projectile within fire
/datum/controller/subsystem/projectiles/proc/handle_projectile_flight(obj/item/projectile/projectile, remaining)
	PRIVATE_PROC(TRUE) // Internal - This should NEVER return a truthy without updating fly_queue (see above in fire)
	SHOULD_NOT_SLEEP(TRUE)
	set waitfor = FALSE // Catching runtime sleeps that might evade static analysis (because it's imperfect by concept)
	. = FALSE

	fly_updates_last++
	var/update = projectile.process_projectile(remaining)

	if(update == PROC_CRIT_FAIL) // This shouldn't happen obviously but it did enough in the past to give me PTSD and warrant a minor warning.
		log_debug("SSprojectiles: PROJECTILE SLEPT IN HANDLING AND DISCARDED DESPITE GOING THROUGH TWO SHOULD_NOT_SLEEP STATIC CHECKS. SERIOUSLY WHAT THE FUCK. Name: [projectile] at [get_turf(projectile)]")
		CRASH("SSprojectiles: PROJECTILE SLEPT IN HANDLING AND DISCARDED DESPITE GOING THROUGH TWO SHOULD_NOT_SLEEP STATIC CHECKS. SERIOUSLY WHAT THE FUCK. Name: [projectile] at [get_turf(projectile)]")
	if(update && update >= remaining) // As the message say this shouldn't happen unless someone messes projectiles up big time
		CRASH("SSprojectiles: projectile stalled and discarded in controller due to messed up projectile travel logic")

	// Regular projectile stop
	if(QDELETED(projectile) || projectile?.speed <= 0)
		fly_queue.Remove(projectile)
		flying.Remove(projectile)
		. = TRUE
		qdel(projectile) // Probably already done, safety
		return

	// Projectile is still flying for this tick
	if(update > 0)
		fly_queue[projectile] = update
		return TRUE

	// Projectile still flies but we're done processing it for the tick
	fly_queue.Remove(projectile)
	return TRUE


/// Request to run hit checking and effect for a projectile on controller time when available
/datum/controller/subsystem/projectiles/proc/register_passive_hit(obj/item/projectile/projectile, atom/affected)
	// Because we're mixing up potentially zero-schedule BYOND events or move callbacks (via Crossed/Collided) and MC backed
	// ones through ALL OF GAME LOGIC, this requires some creative thinking... I'm sorry. Problem is, both hits and bullet flight
	// are intensive operations that warrant running under MC scheduling, but you can't just have
	// two separate controllers as they interwind (hit/effect delay, bullet cant fly if it already hit, ...)

	switch(state)
		// Assumption is, if you shut down the controller there is a good reason. Ignore entierly. Nothing hits.
		if(SS_IDLE)
			return

		// We're ALREADY RUNNING. This was caused by cascading effects, eg. something got hit
		// during flight, and something else got knocked into yet another projectile.
		// We need to take care of it NOW to ensure proper ordering. We're already on SS time, so it's fine.
		if(SS_RUNNING)
			handle_projectile_hit(projectile, affected)
			return

		// We're PAUSED (or worse) but something running inbetween wants to hit something.
		// We need to respect ordering vs flight still, but we can afford to defer it until we unpause to take advantage of MC scheduling.
		// Because this is SS_TICKER, this should be a rare fallback - and hopefully as it mostly defeats the point of the queue.
		if(SS_PAUSED)
			hit_current += list(projectile, affected)
			return

	// Just add it to next run, this is what should usually happen.
	hit_queue += list(projectile, affected)

/// Convenience to relay to projectile hit logic
/datum/controller/subsystem/projectiles/proc/handle_projectile_hit(obj/item/projectile/projectile, atom/affected)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	. = TRUE // Sleep safeguard, block the bullet rather than piercing multihit, people might be less confused
	if(!projectile?.speed)
		return FALSE
	if(isobj(affected))
		return projectile.handle_object(affected)
	if(isliving(affected))
		return projectile.handle_mob(affected)
	return FALSE

/// Queue a new projectile for processing
/datum/controller/subsystem/projectiles/proc/queue_projectile(obj/item/projectile/projectile)
	flying |= projectile // Very funny

/// Queue a new projectile for processing
/datum/controller/subsystem/projectiles/proc/queue_visual_update(obj/item/projectile/projectile)
	vis_queue |= projectile
