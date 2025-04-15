-- (c) 2015-2016 rnd
-- Copyright (C) 2025 мтест
-- See README.md for license details

local machines_limit = math.max(0, basic_machines.settings.machines_limit) -- max 65535
local machines_minstep = basic_machines.properties.machines_minstep
local machines_timer = basic_machines.properties.machines_timer
local os_time, math_abs, math_min = os.time, math.abs, math.min
local machines_cache = {[1] = 0} -- [1] = size, ["pos"] = {t, count} or ["pos"] = t

local timer, no_log = 0, true
minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if no_log and timer > 75 and machines_cache[1] > machines_limit then -- limit reached
		minetest.log("warning", "[basic_machines] Machines limit(" .. machines_limit .. ") reached.")
		no_log = false; return
	elseif timer < 900 then
		return
	end
	timer = 0; no_log = true; machines_cache = {[1] = 0}
end)

local function get_cache_or_nil(pos_str)
	local cache_at_pos = machines_cache[pos_str]
	if cache_at_pos == nil then
		return
	elseif type(cache_at_pos) == "table" then
		return cache_at_pos[1], cache_at_pos[2]
	else
		return cache_at_pos, 0
	end
end

basic_machines.set_machines_cache = function(pos, new_t, count)
	local pos_str = ("%s,%s,%s"):format(pos.x, pos.y, pos.z)
	local t = get_cache_or_nil(pos_str)
	if t == nil then -- only set existing cache
		return
	end
	machines_cache[pos_str] = {new_t or t, count}
end

basic_machines.check_action = function(pos, cooldown, step, limit, reset)
	local pos_str = ("%s,%s,%s"):format(pos.x, pos.y, pos.z)
	local t0, count = get_cache_or_nil(pos_str)

	if t0 == nil then
		if machines_cache[1] > machines_limit then -- limit reached
			return 65535 -- all newly activated machines overheat
		end
		t0, count = 0, 0
		machines_cache[1] = machines_cache[1] + 1
	end

	local t1 = os_time()
	local tn = math_abs(t1 - t0)

	if cooldown then
		if (step or machines_minstep) > tn then -- activated before natural time
			count = count + 1
		elseif count > 0 then
			if tn > machines_timer then -- reset if more than 5s (by default) elapsed since last activation
				count = -1
			else
				count = count - 1
			end
		end
	elseif reset then
		if tn >= machines_minstep and count <= limit then
			count = 0
		end
		if machines_minstep > tn then -- activated before natural time
			count = count + 1
		elseif count > limit and tn > machines_timer then -- reset if more than 5s (by default) elapsed since last activation
			count = -1
		end
	elseif limit then
		if machines_minstep > tn then -- activated before natural time
			count = count + 1
			if count >= limit then
				return count
			end
		else
			count = 0
		end
	elseif machines_minstep > tn then -- activated before natural time
		return 1
	end

	if count > 0 then
		machines_cache[pos_str] = {t1, math_min(count, 65535)}
	else
		machines_cache[pos_str] = t1
	end

	return count
end