-- Adds event handler for attempt to dig in protected area
-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2025 мтест
-- See README.md for license details

-- Tries to activate specially configured nearby distributor at points with coordinates of form 20 * i
-- Registers dig attempts in radius 10 around
-- Distributor must have first target filter set to 0 (disabled) to handle dig events

local machines_TTL = basic_machines.properties.machines_TTL
local old_is_protected = minetest.is_protected
local math_floor = math.floor
local r = 20
local function round(x) return math_floor(x / r + 0.5) * r end
local function distributor_vector_round(v) return {x = round(v.x), y = round(v.y) + 1, z = round(v.z)} end

basic_machines.get_event_distributor_near = function(pos) return distributor_vector_round(pos) end

function minetest.is_protected(pos, digger)
	local is_protected = old_is_protected(pos, digger)
	if is_protected then -- only if protected
		local p = distributor_vector_round(pos)
		-- attempt to activate distributor at special grid location: coordinates of the form 20 * i
		if minetest.get_node(p).name == "basic_machines:distributor" then
			local meta = minetest.get_meta(p)
			if meta:get_int("active1") == 0 then -- first output is disabled, indicating ready to be used as an event handler
				if meta:get_int("x1") ~= 0 then -- trigger protection event
					meta:set_string("infotext", digger) -- record digger name
					local def = minetest.registered_nodes["basic_machines:distributor"]
					local effector = def.effector
					effector.action_on(p, machines_TTL)
				end
			end
		end
	end
	return is_protected
end

local function distributor_event(name, message)
	local player = minetest.get_player_by_name(name); if not player then return end
	local pos = player:get_pos()
	local p = distributor_vector_round(pos)
	-- attempt to activate distributor at special grid location: coordinates of the form 20 * i
	if minetest.get_node(p).name == "basic_machines:distributor" then
		local meta = minetest.get_meta(p)
		if meta:get_int("active1") == 0 then -- first output is disabled, indicating ready to be used as an event handler
			local y1 = meta:get_int("y1")
			if y1 ~= 0 then -- chat event, positive relays message, negative drops it
				meta:set_string("infotext", message) -- record player message
				local def = minetest.registered_nodes["basic_machines:distributor"]
				local effector = def.effector
				effector.action_on(p, machines_TTL)
				if y1 < 0 then return true end
			end
		end
	end
end

if minetest.global_exists("beerchat") then
	beerchat.register_on_chat_message(distributor_event)
else
	minetest.register_on_chat_message(distributor_event)
end