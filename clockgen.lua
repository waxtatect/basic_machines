local S = basic_machines.S
local machines_TTL = basic_machines.properties.machines_TTL
local machines_timer = basic_machines.properties.machines_timer
local no_clock = basic_machines.properties.no_clock

minetest.register_abm({
	label = "[basic_machines] Clock Generator",
	nodenames = {"basic_machines:clockgen"},
	neighbors = {},
	interval = machines_timer,
	chance = 1,

	action = function(pos, node, active_object_count, active_object_count_wider)
		if no_clock then return end
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

minetest.register_node("basic_machines:clockgen", {
	description = S("Clock Generator - use sparingly, continually activates top block"),
	groups = {cracky = 3},
	tiles = {"basic_machines_clock_generator.png"},
	sounds = default.node_sound_wood_defaults(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local name = placer:get_player_name()
		if minetest.find_node_near(pos, 15, {"basic_machines:clockgen"}) then
			minetest.set_node(pos, {name = "air"})
			minetest.add_item(pos, "basic_machines:clockgen")
			minetest.chat_send_player(name, S("Clock Generator: Interference from nearby clock generator detected"))
			return
		end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Clock Generator (owned by @1): place machine to be activated on top", name))
		meta:set_string("owner", name)

		if minetest.check_player_privs(name, "machines") then meta:set_int("machines", 1) end
	end,

	can_dig = function(pos, player)
		local owner = minetest.get_meta(pos):get_string("owner")
		return owner == player:get_player_name() or owner == ""
	end
})

if basic_machines.settings.register_crafts then
	minetest.register_craft({
		output = "basic_machines:clockgen",
		recipe = {
			{"default:diamondblock"},
			{"basic_machines:keypad"}
		}
	})
end