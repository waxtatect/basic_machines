-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

basic_machines = {
	F = minetest.formspec_escape,
	S = minetest.get_translator("basic_machines"),
	version = "02/27/2024 (fork)",
	properties = {
		no_clock			= false,	-- if true all continuously running activities (clockgen/keypad) are disabled
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
		-- technic_power
		generator_upgrade		= 0,		-- upgrade available in addition to the current limit (50)
		-- space
		space_start_eff			= 1500,		-- space efficiency height
		space_start				= 1100,		-- space height, set to false to disable
		space_textures			= "",		-- skybox space textures replacement with up to 6 texture names separated by commas
		exclusion_height		= 6666,		-- above, without "include" priv, player is teleported to a random location
		space_effects			= false,	-- enable damage mechanism
		--
		register_crafts			= false		-- machines crafts recipes
	},
	-- form
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
	use_default = minetest.global_exists("default"), -- require minetest_game default mod
--[[ interfaces
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
	check_mover_filter = function() end,
	check_mover_target = nil, -- function used with mover_no_large_stacks setting
	check_palette_index = function() end,
	clamp_item_count = nil, -- function used with mover_no_large_stacks setting
	find_and_connect_battery = function() end,
	get_distance = function() end,
	get_mover = function() end,
	get_mover_form = function() end,
	get_palette_index = function() end,
	itemstring_to_stack = function() end,
	node_to_stack = function() end,
	set_mover = function() end,
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

-- creative check
local creative_cache = minetest.settings:get_bool("creative_mode")
basic_machines.creative = function(name)
	return creative_cache or minetest.check_player_privs(name,
		{creative = true})
end

-- result: float with precision up to two digits or integer number
local modf = math.modf
basic_machines.twodigits_float = function(number)
	local r
	if number ~= 0 then
		local i, f = modf(number)
		if f ~= 0 then r = i + ("%.2f"):format(f) else r = number end
	else
		r = 0
	end
	return r
end

if basic_machines.use_default then
	basic_machines.sound_node_machine = default.node_sound_wood_defaults
	basic_machines.sound_overheat = "default_cool_lava"
	basic_machines.sound_ball_bounce = "default_dig_cracky"
else
	basic_machines.sound_node_machine = function(sound_table) return sound_table end
end

local S = basic_machines.S

-- test: toggle machine running with clockgen/keypad repeats, useful for debugging
-- i.e. seeing how machines running affect server performance
minetest.register_chatcommand("clockgen", {
	description = S("Toggle clock generator/keypad repeats"),
	privs = {privs = true},
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