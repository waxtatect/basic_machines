-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2025 мтест
-- See README.md for license details

local S = basic_machines.S
local machines_TTL = basic_machines.properties.machines_TTL

minetest.register_abm({
	label = "[basic_machines] Clock Generator",
	nodenames = {"basic_machines:clockgen"},
	neighbors = {},
	interval = basic_machines.properties.machines_timer,
	chance = 1,

	action = function(pos)
		if basic_machines.properties.no_clock then return end
		local meta = minetest.get_meta(pos)
		-- owner online or machines privilege
		if minetest.get_player_by_name(meta:get_string("owner")) or meta:get_int("machines") == 1 then
			pos.y = pos.y + 1; local node_above = minetest.get_node_or_nil(pos)
			if not node_above or node_above.name == "air" then return end
			local def = minetest.registered_nodes[node_above.name]
			-- check if all elements exist, safe cause it checks from left to right
			if def and (def.effector or def.mesecons and def.mesecons.effector) then
				local effector = def.effector or def.mesecons.effector
				if effector.action_on then
					effector.action_on(pos, def.effector and machines_TTL or node_above)
				end
			end
		end
	end
})

local machine_name = "basic_machines:clockgen"
minetest.register_node(machine_name, {
	description = S("Clock Generator"),
	groups = {cracky = 3},
	tiles = {"basic_machines_clock_generator.png"},
	is_ground_content = false,
	sounds = basic_machines.sound_node_machine(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local name = placer:get_player_name()
		if minetest.find_node_near(pos, 15, {"basic_machines:clockgen"}) then
			minetest.remove_node(pos)
			minetest.add_item(pos, "basic_machines:clockgen")
			minetest.chat_send_player(name, S("Clock Generator: Interference from nearby clock generator detected"))
			return
		end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Clock Generator (owned by @1): place machine to be activated on top", name))
		meta:set_string("owner", name)

		if minetest.check_player_privs(name, "machines") then meta:set_int("machines", 1) end
	end,

	can_dig = basic_machines.can_dig,

	on_blast = function(pos, intensity)
		return basic_machines.on_blast(pos, intensity, machine_name)
	end
})

if basic_machines.settings.register_crafts and basic_machines.use_default then
	minetest.register_craft({
		output = "basic_machines:clockgen",
		recipe = {
			{"default:diamondblock"},
			{"basic_machines:keypad"}
		}
	})
end