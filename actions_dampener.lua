-- (c) 2015-2016 rnd
-- Copyright (C) 2025 мтест
-- See README.md for license details

local machines_limit = math.max(0, basic_machines.settings.machines_limit) -- max 65535
local machines_minstep = basic_machines.properties.machines_minstep
local machines_timer = basic_machines.properties.machines_timer
local os_time, math_abs, math_min = os.time, math.abs, math.min
local size, machines_cache = 0, {} -- ["<x,y,z>"] = {<seconds>, <count>} or ["<x,y,z>"] = <seconds>

local timer, no_log = 0, true
minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if no_log and timer > 75 and size > machines_limit then -- limit reached
		minetest.log("warning", "[basic_machines] Machines limit(" .. machines_limit .. ") reached.")
		no_log = false; return
	elseif timer < 900 then
		return
	end
	timer = 0; no_log = true; size, machines_cache = 0, {}
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

basic_machines.get_machines_cache_or_nil = function(pos)
	local pos_str = pos.x .. "," .. pos.y .. "," .. pos.z
	return get_cache_or_nil(pos_str)
end

basic_machines.set_machines_cache = function(pos, new_t, count)
	local pos_str = pos.x .. "," .. pos.y .. "," .. pos.z
	local t = get_cache_or_nil(pos_str)
	if t == nil then -- only set existing cache
		return
	end
	if count and count > 0 then
		machines_cache[pos_str] = {new_t or t, math_min(count, 65535)}
	else
		machines_cache[pos_str] = new_t or t
	end
end

basic_machines.check_action = function(pos, cooldown, step, limit, reset)
	local pos_str = pos.x .. "," .. pos.y .. "," .. pos.z
	local t0, count = get_cache_or_nil(pos_str)

	if t0 == nil then
		if size > machines_limit then -- limit reached
			return 65535 -- all newly activated machines overheat
		end
		t0, count = 0, 0
		size = size + 1
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

-- machines_stats chat command
local S = basic_machines.S
local machines_stats, summary_displayed, machine_count

local function add_machine_count(data, machine_name, meta)
	if machine_name == "basic_machines:mover" then
		 -- 0: no upgrade, 1: mese blocks, 2: diamond blocks, 3: movers
		 -- see mover.lua, mover.upgrades table
		local upgrade_type = meta:get_int("upgradetype")

		data[machine_name] = data[machine_name] or {}
		local movers_stats = data[machine_name]
		data[machine_name][upgrade_type] = (movers_stats[upgrade_type] or 0) + 1
		data[machine_name]["count"] = (movers_stats["count"] or 0) + 1
	else
		data[machine_name] = (data[machine_name] or 0) + 1
	end
end

minetest.register_chatcommand("machines_stats", {
	params = "[<owner>]",
	description = S("Build and display the number of machines from the cache, grouped by owner"),
	privs = {debug = true, privs = true},
	func = function(name, param)
		local machines_summary

		if param == "" and summary_displayed then
			machines_stats, summary_displayed, machine_count = nil, nil, nil
		end

		if machines_stats == nil then
			machines_stats, machines_summary, machine_count = {}, {}, 0
			local string_to_pos = minetest.string_to_pos
			for pos_str, _ in pairs(machines_cache) do
				local pos = string_to_pos(pos_str)
				local machine_name = minetest.get_node(pos).name

				if (machine_name):sub(1, 15) == "basic_machines:" then
					local meta = minetest.get_meta(pos)
					local owner = meta:get_string("owner")

					machines_stats[owner] = machines_stats[owner] or {}

					add_machine_count(machines_stats[owner], machine_name, meta)
					add_machine_count(machines_summary, machine_name, meta)

					machines_stats[owner]["count"] = (machines_stats[owner]["count"] or 0) + 1
					machines_summary["owners"] = machines_summary["owners"] or {}
					machines_summary["owners"][owner] = true
					machine_count = machine_count + 1
				end
			end
		end

		if param == "" then
			minetest.chat_send_player(name, dump(machines_summary)); summary_displayed = true
		elseif machines_stats and machines_stats[param] then
			local owner_stats = machines_stats[param]
			minetest.chat_send_player(name, dump(owner_stats))
			local owner_machine_count = owner_stats["count"]
			minetest.chat_send_player(name, S("Owner: '@1', Machines number: @2" ..
				", Part of the total machines number: @3%", param, owner_machine_count, owner_machine_count / machine_count * 100))
		else
			minetest.chat_send_player(name, S("Owner '@1' not found", param))
		end
		minetest.chat_send_player(name, S("Cache size: @1, Total machines number: @2" ..
			"\nDifference (unloaded/removed machines / outdated stats): @3", size, machine_count, size - machine_count))
	end
})