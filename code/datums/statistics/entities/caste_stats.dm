/datum/entity/player_stats/caste
	var/name = null
	var/total_hits = 0
	var/list/actions_used = list() // types of /datum/entity/statistic, "tail sweep" = 10, "screech" = 2

/datum/entity/player_stats/caste/Destroy(force)
	. = ..()
	QDEL_LIST_ASSOC_VAL(actions_used)

/datum/entity/player_stats/caste/proc/setup_action(action)
	if(!action)
		return
	var/action_key = strip_improper(action)
	if(actions_used["[action_key]"])
		return actions_used["[action_key]"]
	var/datum/entity/statistic/S = new()
	S.name = action_key
	S.value = 0
	actions_used["[action_key]"] = S
	return S

/datum/entity/player_stats/caste/proc/track_personal_actions_used(action, amount = 1)
	var/datum/entity/statistic/S = setup_action(action)
	S.value += amount
