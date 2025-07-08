-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2025 мтест
-- See README.md for license details

local S = minetest.get_translator("basic_machines")

basic_machines = {
	F = minetest.formspec_escape,
	S = S,
	version = "07/08/2025 (fork)",
	properties = {
		no_clock			= false,	-- if true all continuously running activities (clock generators, keypads and balls) are disabled
		machines_TTL		= 16,		-- time to live for signals, how many hops before signal dissipates
		machines_minstep	= 1,		-- minimal allowed activation timestep, if faster machines overheat
		machines_operations	= 10,		-- 1 coal will provide 10 mover basic operations (moving dirt 1 block distance)
		machines_timer		= 5,		-- main timestep
		max_range			= 10,		-- machines normal range of operation
		mover_upgrade_max	= 10		-- upgrade mover to increase range and to reduce fuel consumption
	},
	settings = {							-- can be added to server configuration file, example: basic_machines_energy_multiplier = 1
		-- ball spawner
		max_balls				= 2,		-- balls count limit per player, minimum 0
		-- crystals
		energy_multiplier		= 1,		-- energy crystals multiplier
		power_stackmax			= 25,		-- power crystals stack max
		-- grinder
		grinder_register_dusts	= true,		-- dusts/extractors for lumps/ingots, needed for the other grinder settings
		grinder_dusts_quantity	= 2,		-- quantity of dusts produced by lump/ingot, minimum 0
		grinder_dusts_legacy	= false,	-- legacy dust mode: dust_33 (smelt) -> dust_66 (smelt) -> ingot
		grinder_extractors_type	= 1,		-- recipe priority if optional mod present, 1: farming_redo, 2: x_farming
		-- mover
		mover_add_removed_items	= false,	-- always add the removed items in normal mode with target chest
		mover_no_large_stacks	= false,	-- limit the stack count to its max in normal, drop and inventory mode
		mover_max_temp			= 176,		-- overheat above this temperature, minimum 1
		mover_modes_temp		= "",		-- modes maximum temperature override, minimum 0 for each
											-- "<normal>,<dig>,<drop>,<object>,<inventory>,<transport>" (default: "88,88,32,2,80,48")
		-- technic_power
		generator_upgrade		= 40,		-- generator maximum upgrade level
		-- space
		space_start_eff			= 1500,		-- space efficiency height
		space_start				= 1100,		-- space height, set to false to disable
		space_textures			= "",		-- skybox space textures replacement with up to 6 texture names separated by commas
		exclusion_height		= 6666,		-- above, without "include" priv, player is teleported to a random location
		space_effects			= false,	-- enable damage mechanism
		--
		machines_limit			= 2048,		-- number of machines allowed to run, above this limit, overheat, minimum 0
		register_crafts			= false		-- machines crafts recipes
	},
	-- returns inventory player form
	get_form_player_inventory = function(x, y, w, h, s)
		local player_inv = {
			("list[current_player;main;%g,%g;%i,1]"):format(x, y, w),
			("list[current_player;main;%g,%g;%i,%i;%i]"):format(x, y + 1.4, w, h - 1, w)
		}
		for i = 0 , w - 1 do
			player_inv[i + 3] = ("image[%g,%g;1,1;[combine:1x1^[noalpha^[colorize:black^[opacity:43]"):format(x + (s + 1) * i, y)
		end
		return table.concat(player_inv)
	end,
	-- returns the item description
	get_item_description = function(name)
		local def = minetest.registered_items[name]
		local description = def and def.description or S("Unknown Item")
		return description
	end,
	use_default = minetest.global_exists("default"), -- require minetest_game default mod
--[[ interfaces
	-- actions_dampener
	check_action = function() end,
	get_machines_cache_or_nil = function () end,
	set_machines_cache = function() end,
	-- autocrafter
	change_autocrafter_recipe = function() end,
	-- distributor
	get_distributor_form = function() end,
	-- enviro
	player_sneak = nil, -- table used by optional mod player_monoids
	-- grinder
	get_grinder_recipes = function() end,
	set_grinder_recipes = function() end,
	-- keypad
	use_keypad = function() end,
	-- mover
	add_mover_mode = function() end,
	calculate_elevator_range = function() end,
	calculate_elevator_requirement = function() end,
	check_mover_filter = function() end,
	check_mover_target = nil, -- function used with mover_no_large_stacks setting
	check_palette_index = function() end,
	clamp_item_count = nil, -- function used with mover_no_large_stacks setting
	find_and_connect_battery = function() end,
	get_distance = function() end,
	get_mover = function() end,
	get_mover_form = function() end,
	get_palette_index = function() end,
	is_protected = nil, -- function used with both optional protection mods: areas and protector
	itemstring_to_stack = function() end,
	node_to_stack = function() end,
	set_mover = function() end,
	-- protect
	get_event_distributor_near = function() end
	-- technic_power
	check_power = function() end
--]]
}

-- read settings from configuration file
for k, v in pairs(basic_machines.settings) do
	local setting = nil
	if type(v) == "boolean" then
		setting = minetest.settings:get_bool("basic_machines_" .. k)
	elseif type(v) == "number" then
		setting = tonumber(minetest.settings:get("basic_machines_" .. k))
	elseif type(v) == "string" then
		setting = minetest.settings:get("basic_machines_" .. k)
	end
	if setting ~= nil then
		basic_machines.settings[k] = setting
	end
end

-- machine registration fields
basic_machines.can_dig = function(pos, player, listnames)
	if player then
		local meta = minetest.get_meta(pos)
		local owner = meta:get_string("owner")
		if owner == player:get_player_name() or owner == "" then
			if listnames then
				local listnames_length = #listnames
				local inv = meta:get_inventory()
				for i = 1, listnames_length do
					if not inv:is_empty(listnames[i]) then
						return false
					end
				end
			end
			return true
		end
	end
	return false
end

-- returns a table of inventory items
local function get_inventory_items(pos, listnames)
	local items = {}
	local listnames_length = #listnames
	local inv = minetest.get_meta(pos):get_inventory()
	for i = 1, listnames_length do
		local listname = listnames[i]
		if not inv:is_empty(listname) then
			local inv_size = inv:get_size(listname)
			local k = #items
			for j = 1, inv_size do
				local stack = inv:get_stack(listname, j)
				if stack:get_count() > 0 then
					items[k + 1] = stack:to_table()
					k = k + 1
				end
			end
		end
	end
	return items
end

basic_machines.get_inventory_items = get_inventory_items

basic_machines.on_blast = function(pos, intensity, name, listnames, param2)
	if intensity < 2.5 then return end
	local drops
	if listnames then
		drops = get_inventory_items(pos, listnames)
	end
	if param2 and param2 > 0 then -- with paramtype2 == "color"
		name = ItemStack(name)
		name:get_meta():set_int("palette_index", param2)
		name = name:to_table()
	end
	if drops then
		drops[#drops + 1] = name
	else
		drops = {name}
	end
	if minetest.remove_node(pos) then
		return drops
	end
end
--

-- creative check
local creative_cache = minetest.settings:get_bool("creative_mode")
basic_machines.creative = function(name)
	return creative_cache or minetest.check_player_privs(name,
		{creative = true})
end

-- returns a float with two decimals precision or an integer
local math_floor = math.floor
basic_machines.truncate_to_two_decimals = function(x) return math_floor(x * 100) / 100 end

if basic_machines.use_default then
	basic_machines.sound_node_machine = default.node_sound_wood_defaults
	basic_machines.sound_overheat = "default_cool_lava"
	basic_machines.sound_ball_bounce = "default_dig_cracky"
else
	basic_machines.sound_node_machine = function(sound_table) return sound_table end
end

-- test: toggle machines running with clock generators, keypads and balls repeats, useful for debugging
-- i.e. seeing how machines running affect server performance
minetest.register_chatcommand("clockgen", {
	description = S("Toggle clock generators, keypads and balls repeats"),
	privs = {debug = true, privs = true},
	func = function(name, _)
		basic_machines.properties.no_clock = not basic_machines.properties.no_clock
		minetest.chat_send_player(name, S("No clock set to @1", tostring(basic_machines.properties.no_clock)))
	end
})

-- "machines" privilege
minetest.register_privilege("machines", {
	description = S("Player is expert basic_machines user: his machines work while not present on server," ..
		" can spawn more than @1 balls at once", basic_machines.settings.max_balls),
	give_to_singleplayer = false,
	give_to_admin = false
})

-- unified_inventory "machines" category
if (basic_machines.settings.register_crafts or creative_cache) and
	minetest.global_exists("unified_inventory") and
	unified_inventory.registered_categories and
	not unified_inventory.registered_categories["machines"]
then
	unified_inventory.register_category("machines", {
		symbol = "basic_machines:mover",
		label = S("Machines and Components"),
		items = {
			"basic_machines:autocrafter",
			"basic_machines:ball_spawner",
			"basic_machines:battery_0",
			"basic_machines:clockgen",
			"basic_machines:constructor",
			"basic_machines:detector",
			"basic_machines:distributor",
			"basic_machines:enviro",
			"basic_machines:generator",
			"basic_machines:grinder",
			"basic_machines:keypad",
			"basic_machines:light_on",
			"basic_machines:mesecon_adapter",
			"basic_machines:mover",
			"basic_machines:recycler"
		}
	})
end

-- for translations script (inventory list names)
--[[
	S("dst"); S("fuel"); S("main"); S("output");
	S("recipe"); S("src"); S("upgrade")
--]]

-- COMPATIBILITY
minetest.register_alias("basic_machines:battery", "basic_machines:battery_0")