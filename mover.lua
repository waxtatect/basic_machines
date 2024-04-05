------------------------------------------------------------------------------------------------------------------------
-- BASIC MACHINES MOD by rnd
-- Mod with basic simple automatization for minetest
-- No background processing, just two abms (clock generator, generator), no other lag causing background processing
------------------------------------------------------------------------------------------------------------------------
-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local mover_upgrade_max = basic_machines.properties.mover_upgrade_max
local machines_minstep = basic_machines.properties.machines_minstep
local machines_operations = basic_machines.properties.machines_operations
local machines_timer = basic_machines.properties.machines_timer
local mover_max_temp = math.max(1, basic_machines.settings.mover_max_temp)
local mover_no_large_stacks = basic_machines.settings.mover_no_large_stacks
local twodigits_float = basic_machines.twodigits_float
local temp_80P = mover_max_temp > 12 and math.ceil(mover_max_temp * 0.8)
local temp_15P = math.ceil(mover_max_temp * 0.15)
local vector_add = vector.add
local math_min = math.min

-- *** MOVER SETTINGS *** --
local mover = {
	bonemeal_table = {
		["bonemeal:bonemeal"] = true,
		["bonemeal:fertiliser"] = true,
		["bonemeal:mulch"] = true
	},

	-- list of chests with inventory named "main"
	chests = {
		["chests_2:chest_locked_x2"] = true,
		["chests_2:chest_x2"] = true,
		["default:chest"] = true,
		["default:chest_locked"] = true,
		["digilines:chest"] = true,
		["protector:chest"] = true
	},

	-- define which nodes are dug up completely, like a tree
	dig_up_table = {},

	-- how hard it is to move blocks, default factor 1,
	-- note: fuel cost is this multiplied by distance and divided by machine_operations..
	hardness = {
		["bedrock2:bedrock"] = 999999,
		["bedrock:bedrock"] = 999999,
		["default:acacia_tree"] = 2,
		["default:bush_leaves"] = 0.1,
		["default:cloud"] = 999999,
		["default:jungleleaves"] = 0.1,
		["default:jungletree"] = 2,
		["default:leaves"] = 0.1,
		["default:obsidian"] = 20,
		["default:pine_tree"] = 2,
		["default:stone"] = 4,
		["default:tree"] = 2,
		["gloopblocks:basalt_cooled"] = 3,
		["gloopblocks:obsidian_cooled"] = 20,
		["gloopblocks:pumice_cooled"] = 2,
		["itemframes:frame"] = 999999,
		["itemframes:pedestal"] = 999999,
		["painting:canvasnode"] = 999999,
		["painting:pic"] = 999999,
		["statue:pedestal"] = 999999,
		["x_farming:cocoa_1"] = 999999,
		["x_farming:cocoa_2"] = 999999,
		["x_farming:cocoa_3"] = 999999,
		["x_farming:seed_rice"] = 999999,

		-- move machines for free (mostly)
		["basic_machines:ball_spawner"] = 0,
		["basic_machines:battery_0"] = 0,
		["basic_machines:battery_1"] = 0,
		["basic_machines:battery_2"] = 0,
		["basic_machines:clockgen"] = 999999, -- can only place clockgen by hand
		["basic_machines:detector"] = 0,
		["basic_machines:distributor"] = 0,
		["basic_machines:generator"] = 999999, -- can only place generator by hand
		["basic_machines:keypad"] = 0,
		["basic_machines:light_off"] = 0,
		["basic_machines:light_on"] = 0,
		["basic_machines:mover"] = 0,

		-- grief potential items need highest possible upgrades
		["boneworld:acid_source_active"] = 5950,
		["darkage:mud"] = 5950,
		["default:lava_source"] = 5950, ["default:river_water_source"] = 5950, ["default:water_source"] = 5950,
		["es:toxic_water_source"] = 5950, ["es:toxic_water_flowing"] = 5950,
		["integral:sap"] = 5950, ["integral:weightless_water"] = 5950,
		["underworlds:water_death_source"] = 5950, ["underworlds:water_poison_source"] = 5950,

		-- farming operations are much cheaper
		["farming:cotton_8"] = 1, ["farming:wheat_8"] = 1,
		["farming:seed_cotton"] = 0.5, ["farming:seed_wheat"] = 0.5,

		-- digging mese crystals more expensive
		["mese_crystals:mese_crystal_ore1"] = 10,
		["mese_crystals:mese_crystal_ore2"] = 10,
		["mese_crystals:mese_crystal_ore3"] = 10,
		["mese_crystals:mese_crystal_ore4"] = 10
	},

	-- set up nodes for harvest when digging: [nodename] = {what remains after harvest, harvest result}
	harvest_table = {
		["mese_crystals:mese_crystal_ore1"] = {"mese_crystals:mese_crystal_ore1", nil}, -- harvesting mese crystals
		["mese_crystals:mese_crystal_ore2"] = {"mese_crystals:mese_crystal_ore1", "default:mese_crystal 1"},
		["mese_crystals:mese_crystal_ore3"] = {"mese_crystals:mese_crystal_ore1", "default:mese_crystal 2"},
		["mese_crystals:mese_crystal_ore4"] = {"mese_crystals:mese_crystal_ore1", "default:mese_crystal 3"}
	},

	-- list of nodes mover can't take from in inventory mode
	-- node name = {list of bad inventories to take from} OR node name = true to ban all inventories
	limit_inventory_table = {
		["basic_machines:autocrafter"] = {["output"] = 1, ["recipe"] = 1},
		["basic_machines:battery_0"] = {["upgrade"] = 1},
		["basic_machines:battery_1"] = {["upgrade"] = 1},
		["basic_machines:battery_2"] = {["upgrade"] = 1},
		["basic_machines:constructor"] = {["recipe"] = 1},
		["basic_machines:generator"] = {["upgrade"] = 1},
		["basic_machines:grinder"] = {["upgrade"] = 1},
		["basic_machines:mover"] = true,
		["moreblocks:circular_saw"] = true,
		["smartshop:shop"] = true,
		["xdecor:workbench"] = {["forms"] = 1, ["input"] = 1}
	},

	-- list of mover modes
	modes = {
		_count = 0,
		_tr_table = {}
	},

	-- list of objects that can't be teleported with mover
	no_teleport_table = {
		[""] = true,
		["3d_armor_stand:armor_entity"] = true,
		["__builtin:item"] = true,
		["itemframes:item"] = true,
		["machines:posA"] = true,
		["machines:posN"] = true,
		["painting:paintent"] = true,
		["painting:picent"] = true,
		["shield_frame:shield_entity"] = true,
		["signs_lib:text"] = true,
		["statue:statue"] = true,
		["x_farming:stove_food"] = true,
		["xdecor:f_item"] = true
	},

	-- set up nodes for plant with reverse on and filter set
	-- for example seed -> plant, [nodename] = plant_name OR [nodename] = true
	plants_table = {}
}

if basic_machines.use_default then
	mover.dig_up_table = {
		["default:acacia_tree"] = {h = 6, r = 2}, -- acacia trees grow wider than others
		["default:aspen_tree"] = {h = 10, r = 0},
		["default:cactus"] = {h = 5, r = 2},
		["default:jungletree"] = {h = 11}, -- not emergent jungle tree
		["default:papyrus"] = {h = 3, r = 0},
		["default:pine_tree"] = {h = 13, r = 0},
		["default:tree"] = {h = 4, r = 1}
	}
end

-- cool_trees
local cool_trees = { -- all but pineapple
	{"baldcypress", h = 17, r = 5}, -- why the trunk isn't centered at the sapling position
	{"bamboo", h = 10, r = 0},
	{"birch", h = 4, r = 0, d = 1},
	{"cacaotree", h = 3, r = 0},
	{"cherrytree", h = 5},
	{"chestnuttree", h = 10, r = 5},
	{"clementinetree", h = 3, r = 0},
	{"ebony", h = 14, r = 4},
	{"hollytree", h = 10, r = 3},
	{"jacaranda", h = 6, r = 0},
	{"larch", h = 13, r = 2},
	{"lemontree", h = 3},
	{"mahogany", h = 15, r = 2},
	{"maple", h = 7, r = 3},
	{"oak", h = 14, r = 4},
	{"palm", h = 4, r = 2},
	{"plumtree", h = 8, r = 3, d = 1},
	{"pomegranate", h = 2, r = 0},
	{"sequoia", h = 46, r = 7, d = 4},
	{"willow", h = 11, r = 3}
}

for _, cool_tree in ipairs(cool_trees) do
	local name = cool_tree[1]
	if minetest.global_exists(name) or minetest.get_modpath(name) then
		mover.dig_up_table[name .. ":trunk"] = {h = cool_tree.h, r = cool_tree.r, d = cool_tree.d}
	end
end
--

if minetest.global_exists("farming") then
	for name, plant in pairs(farming.registered_plants or {}) do
		if farming.mod == "redo" then
			mover.plants_table[plant.seed] = plant.crop .. "_1"
		else
			local seed = "farming:seed_" .. name
			if minetest.registered_nodes[seed] then
				mover.plants_table[seed] = true
			end
		end
	end
end

if minetest.global_exists("x_farming") then
	for name, _ in pairs(x_farming.registered_plants or {}) do
		local seed = "x_farming:seed_" .. name
		if minetest.registered_nodes[seed] then
			mover.plants_table[seed] = true
		end
	end
	mover.plants_table["x_farming:seed_rice"] = nil
	if minetest.registered_nodes["x_farming:seed_salt"] then
		mover.plants_table["x_farming:seed_salt"] = true
	end
end

-- return either content of a given setting or all settings
basic_machines.get_mover = function(setting)
	local def
	if setting and mover[setting] then
		def = mover[setting]
	else
		def = mover
	end
	return table.copy(def)
end

-- add/replace values as table of an existing setting
basic_machines.set_mover = function(setting, def)
	if not setting or not mover[setting] then return end
	for k, v in pairs(def) do
		mover[setting][k] = v
	end
end
-- *** END OF MOVER SETTINGS *** --

-- load files
local MP = minetest.get_modpath("basic_machines") .. "/"

dofile(MP .. "mover_common.lua")
dofile(MP .. "mover_normal_mode.lua")
dofile(MP .. "mover_dig_mode.lua")
dofile(MP .. "mover_drop_mode.lua")
dofile(MP .. "mover_object_mode.lua")
dofile(MP .. "mover_inventory_mode.lua")
dofile(MP .. "mover_transport_mode.lua")


-- MOVER --
minetest.register_chatcommand("mover_intro", {
	description = S("Toggle mover introduction"),
	privs = {interact = true},
	func = function(name, _)
		local player = minetest.get_player_by_name(name); if not player then return end
		local player_meta = player:get_meta()
		if player_meta:get_int("basic_machines:mover_intro") == 1 then
			player_meta:set_int("basic_machines:mover_intro", 3)
			minetest.chat_send_player(name, S("Mover introduction disabled"))
		else
			player_meta:set_int("basic_machines:mover_intro", 1)
			minetest.chat_send_player(name, S("Mover introduction enabled"))
		end
	end
})

local mover_upgrades = {
	["default:mese"] = {id = 1, max = mover_upgrade_max},
	["default:diamondblock"] = {id = 2, max = 99},
	["basic_machines:mover"] = {id = 3, max = 74}
}
local mover_modes = mover.modes
local get_distance = basic_machines.get_distance

local function pos1_checks(pos, owner)
	if minetest.is_protected(pos, owner) then -- protection check
		return true
	end
	local node = minetest.get_node(pos)
	return false, node, node.name
end

local function pos1list_checks(pos, length_pos, owner, upgrade, meta)
	local is_protected = minetest.is_protected
	local node, node_name, count = {}, {}, 0
	local mover_hardness, hardness = mover.hardness, 0
	local maxpower -- battery maximum power output
	for i = 1, length_pos do
		local posi = pos[i]
		if is_protected(posi, owner) then -- protection check
			return true
		else
			local nodei = minetest.get_node(posi)
			local nodei_name = nodei.name
			if nodei_name == "air" or nodei_name == "ignore" then
				pos[i] = {}; count = count + 1
			elseif upgrade == -1 then -- admin, just add nodes
				node[i], node_name[i] = nodei, nodei_name
			else
				local nodei_hardness = mover_hardness[nodei_name] or 1
				if nodei_hardness < 596 then -- (3 * 99 diamond blocks + 1)
					node[i], node_name[i] = nodei, nodei_name
					hardness = hardness + nodei_hardness
				else
					maxpower = maxpower or minetest.get_meta( -- battery must be already connected
						{x = meta:get_int("batx"), y = meta:get_int("baty"), z = meta:get_int("batz")}):get_float("maxpower")
					if nodei_hardness > maxpower then -- ignore nodes too hard to move for the battery current upgrade
						pos[i] = {}; count = count + 1
					else
						node[i], node_name[i] = nodei, nodei_name
						hardness = hardness + nodei_hardness
					end
				end
			end
		end
	end
	if count == length_pos then -- only air/ignore/hard nodes, nothing to move
		node_name = "air"
	end
	return false, pos, node, node_name, hardness
end

local function is_pos2_protected(pos, owner, mode_third_upgradetype)
	if mode_third_upgradetype then
		local length_pos = #pos
		if length_pos > 0 then
			local is_protected = minetest.is_protected
			for i = 1, length_pos do
				if is_protected(pos[i], owner) then
					return true
				end
			end
			return false, length_pos
		end
	end
	return minetest.is_protected(pos, owner) -- protection check
end

minetest.register_node("basic_machines:mover", {
	description = S("Mover"),
	groups = {cracky = 2},
	tiles = {"basic_machines_mover.png"},
	sounds = basic_machines.sound_node_machine(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta, name = minetest.get_meta(pos), placer:get_player_name()
		meta:set_string("infotext", S("Mover block. Set it up by punching or right click. Activated by signal."))
		meta:set_string("owner", name)

		meta:set_int("x0", 0); meta:set_int("y0", -1); meta:set_int("z0", 0)	-- source1
		meta:set_int("x1", 0); meta:set_int("y1", -1); meta:set_int("z1", 0)	-- source2
		meta:set_int("x2", 0); meta:set_int("y2", 1); meta:set_int("z2", 0)		-- target
		meta:set_int("pc", 0); meta:set_int("dim", 1) -- current cube position and dimensions
		meta:set_float("fuel", 0)
		meta:set_string("prefer", "")
		meta:set_string("mode", "normal")
		meta:set_int("upgradetype", 0); meta:set_int("upgrade", 1)
		meta:set_int("seltab", 1) -- 0: undefined, 1: mode tab, 2: positions tab
		meta:set_int("t", 0); meta:set_int("T", 0); meta:set_int("activation_count", 0)

		basic_machines.find_and_connect_battery(pos, meta) -- try to find battery early
		if minetest.check_player_privs(name, "privs") then
			meta:set_int("upgrade", -1) -- means operations will be for free
		end

		local inv = meta:get_inventory()
		inv:set_size("filter", 1)
		inv:set_size("upgrade", 1)

		local player_meta = placer:get_meta()
		local mover_intro = player_meta:get_int("basic_machines:mover_intro")
		if mover_intro < 2 then
			if mover_intro == 0 then
				player_meta:set_int("basic_machines:mover_intro", 2)
			end

			minetest.show_formspec(name, "basic_machines:intro_mover", "formspec_version[4]size[7.4,7.4]textarea[0,0.35;7.4,7.05;intro_mover;" ..
				F(S("Mover introduction")) .. ";" .. F(S("This machine can move anything. General idea is the following:\n\n" ..
				"First you need to define rectangle box work area (larger area, where it takes from, defined by source1/source2 which appear as two number 1 boxes) and target position (where it puts, marked by one number 2 box) by punching mover then following chat instructions exactly." ..
				"\n\nCheck why it doesn't work: 1. did you click OK in mover after changing setting 2. does it have battery, 3. does battery have enough fuel 4. did you set filter for taking out of chest ?" ..
				"\n\nImportant: Please read the help button inside machine before first use.")) .. "]")
		end
	end,

	on_rightclick = function(pos, _, player)
		local name, meta = player:get_player_name(), minetest.get_meta(pos)

		machines.mark_pos1(name, vector_add(pos,
			{x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")})) -- mark pos1
		machines.mark_pos11(name, vector_add(pos,
			{x = meta:get_int("x1"), y = meta:get_int("y1"), z = meta:get_int("z1")})) -- mark pos11
		machines.mark_pos2(name, vector_add(pos,
			{x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")})) -- mark pos2

		minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
			basic_machines.get_mover_form(pos))
	end,

	on_dig = function(pos, node, digger)
		if digger and digger:is_player() then
			local meta = minetest.get_meta(pos)
			if meta:get_string("owner") == digger:get_player_name() then -- owner can always remove his mover
				local inv = meta:get_inventory()
				local inv_stack
				if not inv:is_empty("upgrade") then
					inv_stack = inv:get_stack("upgrade", 1)
				end
				local node_removed = minetest.remove_node(pos)
				if node_removed then
					if inv_stack then
						minetest.add_item(pos, inv_stack)
					end
					minetest.handle_node_drops(pos, {node.name}, digger)
				end
				return node_removed
			end
		end
		return false
	end,

	allow_metadata_inventory_move = function()
		return 0 -- no internal inventory moves!
	end,

	allow_metadata_inventory_put = function(pos, listname, _, stack, player)
		local name = player:get_player_name()
		if minetest.is_protected(pos, name) then return 0 end
		local meta = minetest.get_meta(pos)

		if listname == "filter" then
			local item = stack:to_table(); if not item then return 0 end
			local inv = meta:get_inventory()
			local palette_index = tonumber(stack:get_meta():get("palette_index"))

			local inv_stack = inv:get_stack("filter", 1)
			if inv_stack:get_name() == item.name then
				local inv_palette_index = tonumber(inv_stack:get_meta():get("palette_index"))
				if inv_palette_index == palette_index then
					item.count = inv_stack:get_count() + item.count
				end
			end

			local mode = meta:get_string("mode")
			local prefer
			if mode == "dig" then
				prefer = item.name -- skaapdev in dig mode allow filter to derive name from a stack. ( seems less broken to new users)
			else
				prefer = item.name .. (item.count > 1 and (" " .. math_min(item.count, 65535)) or "")
			end

			if basic_machines.check_mover_filter(mode, pos, meta, prefer) then -- input validation
				if mover_no_large_stacks and basic_machines.check_mover_target(mode, pos, meta) then
					prefer = basic_machines.clamp_item_count(prefer)
				end
				meta:set_string("prefer", prefer)
				local filter_stack = basic_machines.itemstring_to_stack(prefer, palette_index)
				inv:set_stack("filter", 1, filter_stack)
			else
				minetest.chat_send_player(name, S("MOVER: Wrong filter - must be name of existing minetest block")); return 0
			end
			minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
				basic_machines.get_mover_form(pos))
		elseif listname == "upgrade" then
			local stack_name = stack:get_name()
			local mover_upgrade = mover_upgrades[stack_name]
			if mover_upgrade then
				local inv_stack = meta:get_inventory():get_stack("upgrade", 1)
				local inv_stack_is_empty = inv_stack:is_empty()
				if inv_stack_is_empty or stack_name == inv_stack:get_name() then
					local upgrade = inv_stack:get_count()
					local upgrade_max = mover_upgrade.max
					if upgrade < upgrade_max then
						local stack_count = stack:get_count()
						local new_upgrade = upgrade + stack_count
						if new_upgrade > upgrade_max then
							new_upgrade = upgrade_max -- not more than max
							stack_count = math_min(stack_count, upgrade_max - upgrade)
						end
						if inv_stack_is_empty then meta:set_int("upgradetype", mover_upgrade.id) end
						meta:set_int("upgrade", new_upgrade + 1)
						return stack_count
					end
				end
			end
		end

		return 0
	end,

	allow_metadata_inventory_take = function(pos, listname, _, stack, player)
		local name = player:get_player_name()
		if minetest.is_protected(pos, name) then return 0 end
		local meta = minetest.get_meta(pos)

		if listname == "filter" then
			local inv = meta:get_inventory()
			local inv_stack = inv:get_stack("filter", 1)
			local count = inv_stack:get_count() - stack:get_count()

			if count < 1 then
				meta:set_string("prefer", "")
				inv:set_stack("filter", 1, ItemStack(""))
				-- inv:set_list("filter", {}) -- using saved map, mover with prefer previously set, it crashes the game... but why
			else
				local prefer = stack:get_name() .. (count > 1 and (" " .. count) or "")
				meta:set_string("prefer", prefer)
				local filter_stack = basic_machines.itemstring_to_stack(prefer, tonumber(inv_stack:get_meta():get("palette_index")))
				inv:set_stack("filter", 1, filter_stack)
			end
			minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
				basic_machines.get_mover_form(pos))
			return 0
		elseif listname == "upgrade" then
			if minetest.check_player_privs(name, "privs") then
				meta:set_int("upgrade", -1) -- means operations will be for free
			else
				local stack_name = stack:get_name()
				local mover_upgrade = mover_upgrades[stack_name]
				if mover_upgrade then
					local inv_stack = meta:get_inventory():get_stack("upgrade", 1)
					if stack_name == inv_stack:get_name() then
						local upgrade = inv_stack:get_count()
						upgrade = upgrade - stack:get_count()
						if upgrade < 0 or upgrade > mover_upgrade.max then upgrade = 0 end -- not less than 0 and not more than max
						if upgrade == 0 then meta:set_int("upgradetype", 0) end
						meta:set_int("upgrade", upgrade + 1)
					end
				end
			end
		end

		return stack:get_count()
	end,

	effector = {
		action_on = function(pos, _)
			local meta = minetest.get_meta(pos)
			local upgradetype = meta:get_int("upgradetype")
			local third_upgradetype = upgradetype == 3
			local msg

			-- temperature
			local t0, t1 = meta:get_int("t"), minetest.get_gametime()
			local tn, T = t1 - machines_minstep, meta:get_int("T") -- temperature

			if t0 <= tn and T < mover_max_temp then
				T = 0
			end

			if t0 > tn then -- activated before natural time
				T = T + 1
			elseif T > mover_max_temp or third_upgradetype and T > 0 then
				if t1 - t0 > machines_timer then -- reset temperature if more than 5s (by default) elapsed since last activation
					T = 0; msg = ""
				else
					T = T - 1
				end
			end
			meta:set_int("t", t1); meta:set_int("T", T)

			if T > mover_max_temp or third_upgradetype and T > 2 then
				minetest.sound_play(basic_machines.sound_overheat, {pos = pos, max_hear_distance = 16, gain = 0.25}, true)
				meta:set_string("infotext", S("Overheat! Temperature: @1", T))
				return
			end

			-- variables
			local mode = meta:get_string("mode")
			local object = mode == "object"
			local mreverse = meta:get_int("reverse")
			local mode_third_upgradetype = third_upgradetype and (mode == "normal" or mode == "dig")
			local owner = meta:get_string("owner")
			local upgrade, prefer, source_chest

			-- positions
			local pos1 -- where to take from
			local pos2 -- where to put

			if object then
				if meta:get_int("dim") ~= -1 then
					meta:set_string("infotext", S("MOVER: Must reconfigure sources position.")); return
				end
				if mreverse == 1 then -- reverse pos1, pos2
					pos1 = vector_add(pos, {x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")})
					pos2 = vector_add(pos, {x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")})
				else
					pos1 = vector_add(pos, {x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")}) -- source1
					pos2 = vector_add(pos, {x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")}) -- target
				end
			else
				if meta:get_int("dim") < 1 then
					meta:set_string("infotext", S("MOVER: Must reconfigure sources position.")); return
				end
				if mode_third_upgradetype then
					pos1 = {}

					local x0, y0, z0 = meta:get_int("x0"), meta:get_int("y0"), meta:get_int("z0") -- source1
					local x1, y1 = meta:get_int("x1") - x0 + 1, meta:get_int("y1") - y0 + 1 -- get dimensions
					local pc, dim = meta:get_int("pc"), meta:get_int("dim")

					upgrade = meta:get_int("upgrade")
					for i = 1, (upgrade == -1 and 1000 or upgrade) do -- up to 1000 blocks for admin
						pc = (pc + 1) % dim
						local yc = y0 + (pc % y1); local xpc = (pc - (pc % y1)) / y1
						local xc = x0 + (xpc % x1)
						local zc = z0 + (xpc - (xpc % x1)) / x1
						pos1[i] = vector_add(pos, {x = xc, y = yc, z = zc})
						if i >= dim then break end
					end
					meta:set_int("pc", pc) -- cycle position

					local markerN = machines.markerN[owner]
					if markerN then
						local lua_entity = markerN:get_luaentity()
						if lua_entity and vector.equals(pos, lua_entity._origin or {}) then
							markerN:set_pos(pos1[#pos1]) -- mark current position
						end
					end

					pos2 = vector_add(pos, {x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")}) -- target

					if mreverse == 1 then -- reverse pos1, pos2
						local xt, yt, zt = pos2.x, pos2.y, pos2.z
						pos2 = table.copy(pos1)
						pos1 = {x = xt, y = yt, z = zt}
					end
				else
					local x0, y0, z0 = meta:get_int("x0"), meta:get_int("y0"), meta:get_int("z0") -- source1
					local x1, y1 = meta:get_int("x1") - x0 + 1, meta:get_int("y1") - y0 + 1 -- get dimensions
					local pc = meta:get_int("pc"); pc = (pc + 1) % meta:get_int("dim"); meta:set_int("pc", pc) -- cycle position
					-- pc = z * a * b + x * b + y, from x, y, z to pc
					-- set current input position
					local yc = y0 + (pc % y1); pc = (pc - (pc % y1)) / y1
					local xc = x0 + (pc % x1); pc = (pc - (pc % x1)) / x1
					local zc = z0 + pc
					pos1 = vector_add(pos, {x = xc, y = yc, z = zc})

					local markerN = machines.markerN[owner]
					if markerN and T < temp_15P then
						local lua_entity = markerN:get_luaentity()
						if lua_entity and vector.equals(pos, lua_entity._origin or {}) then
							markerN:set_pos(pos1) -- mark current position
						end
					end

					local x2, y2, z2 = meta:get_int("x2"), meta:get_int("y2"), meta:get_int("z2") -- target
					-- special mode that use its own source/target positions:
					if mode == "transport" and mreverse < 2 then
						pos2 = vector_add(pos1, {x = x2 - x0, y = y2 - y0, z = z2 - z0}) -- translation from pos1
					else
						pos2 = vector_add(pos, {x = x2, y = y2, z = z2})
					end

					if mreverse ~= 0 and mreverse ~= 2 then -- reverse pos1, pos2
						local xt, yt, zt = pos1.x, pos1.y, pos1.z
						pos1 = {x = pos2.x, y = pos2.y, z = pos2.z}
						pos2 = {x = xt, y = yt, z = zt}
					end
				end
			end

			-- check pos1
			upgrade = upgrade or meta:get_int("upgrade")
			local first_pos1, pos_protected, node1, node1_name, nodes1_hardness
			if mode_third_upgradetype then
				local length_pos1 = #pos1
				if length_pos1 > 0 then
					first_pos1 = pos1[1]
					pos_protected, pos1, node1, node1_name, nodes1_hardness = pos1list_checks(pos1, length_pos1, owner, upgrade, meta)
				else
					pos_protected, node1, node1_name = pos1_checks(pos1, owner)
				end
			else
				pos_protected, node1, node1_name = pos1_checks(pos1, owner)
			end

			if pos_protected then -- protection check
				meta:set_int("T", T + math.ceil(mover_max_temp * 0.2))
				meta:set_string("infotext", S("Mover block. Protection fail.")); return
			elseif not object and node1_name == "air" or node1_name == "ignore" then -- node check
				return -- nothing to move
			end

			-- check pos2
			local length_pos2
			pos_protected, length_pos2 = is_pos2_protected(pos2, owner, mode_third_upgradetype)
			if pos_protected then -- protection check
				meta:set_int("T", T + math.ceil(mover_max_temp * 0.2))
				meta:set_string("infotext", S("Mover block. Protection fail.")); return
			end

			-- fuel
			local fuel_cost
			local fuel = meta:get_float("fuel")

			if upgrade == -1 then
				fuel_cost = 0 -- free operations for admin
			else -- calculate fuel cost
				if object then
					if meta:get_int("elevator") == 1 then -- check if elevator mode
						local requirement = math.floor(get_distance(pos, pos2) / 100) + 1
						if (upgrade - 1) >= requirement and (meta:get_int("upgradetype") == 2 or
							meta:get_inventory():get_stack("upgrade", 1):get_name() == "default:diamondblock") -- for compatibility
						then
							fuel_cost = 0
						else
							meta:set_string("infotext",
								S("MOVER: Elevator error. Need at least @1 diamond block(s) in upgrade (1 for every 100 distance).",
								requirement)); return
						end
					else
						local hardness = mover.hardness[node1_name]
						if hardness == 0 then hardness = 1 end -- no free teleport from machine blocks
						fuel_cost = hardness or 1
					end
				elseif mode == "inventory" then -- taking items from chests/inventory move
					prefer = meta:get_string("prefer")
					fuel_cost = mover.hardness[prefer] or 1
				else
					source_chest = mover.chests[node1_name]
					if source_chest then
						prefer = meta:get_string("prefer")
						fuel_cost = mover.hardness[prefer] or 1
						if node1_name == "default:chest" and fuel_cost > 1 then
							fuel_cost = fuel_cost * 0.65
						end
						if mode_third_upgradetype then
							fuel_cost = fuel_cost * length_pos2
						end
					else
						fuel_cost = nodes1_hardness or mover.hardness[node1_name] or 1 -- add maxpower battery check too ?
					end
				end

				if fuel_cost > 0 then
					local dist
					if mode_third_upgradetype then
						if length_pos2 then
							dist = get_distance(pos1, pos2[length_pos2])
						else
							dist = get_distance(first_pos1, pos2)
						end
					else
						dist = get_distance(pos1, pos2)
					end
					-- machines_operations = 10 by default, so 10 basic operations possible with 1 coal
					fuel_cost = fuel_cost * dist / machines_operations

					if mode == "inventory" or object then
						fuel_cost = fuel_cost * 0.1
					elseif mode == "dig" and not third_upgradetype then
						fuel_cost = fuel_cost * 1.1
					end

					if temp_80P and not third_upgradetype then
						if T > temp_80P then
							fuel_cost = fuel_cost + (0.2 / mover_max_temp) * T * fuel_cost
						elseif T < temp_15P then
							fuel_cost = fuel_cost * 0.97
						end
					end

					if upgradetype == 1 or third_upgradetype or
						meta:get_inventory():get_stack("upgrade", 1):get_name() == "default:mese" -- for compatibility
					then
						fuel_cost = fuel_cost / math_min(mover_upgrade_max + 1, upgrade) -- upgrade decreases fuel cost
					end
				end

				if fuel < fuel_cost then -- fuel operations: needs fuel to operate, find nearby battery
					local power_draw = fuel_cost; local supply
					if power_draw < 1 then power_draw = 1 end -- at least 10 one block operations with 1 refuel
					if power_draw == 1 then
						local bpos = {x = meta:get_int("batx"), y = meta:get_int("baty"), z = meta:get_int("batz")} -- battery pos
						supply = basic_machines.check_power(bpos, power_draw * 3) -- try to store energy to reduce refuel
						if supply <= 0 then
							supply = basic_machines.check_power(bpos, power_draw)
						end
					else
						supply = basic_machines.check_power(
							{x = meta:get_int("batx"), y = meta:get_int("baty"), z = meta:get_int("batz")}, power_draw)
					end

					if supply > 0 then -- fuel found
						fuel = fuel + supply
					elseif supply < 0 then -- no battery at target location, try to find it!
						if not basic_machines.find_and_connect_battery(pos, meta) then
							meta:set_string("infotext", S("Can not find nearby battery to connect to!"))
							minetest.sound_play(basic_machines.sound_overheat, {pos = pos, gain = 1, max_hear_distance = 8}, true)
							return
						end
					end

					if fuel < fuel_cost then
						meta:set_float("fuel", fuel)
						meta:set_string("infotext", S("Mover block. Energy @1, needed energy @2. Put nonempty battery next to mover.",
							twodigits_float(fuel), twodigits_float(fuel_cost))); return
					else
						msg = S("Mover block refueled. Fuel status @1.", twodigits_float(fuel))
					end
				end
			end

			-- do the thing
			local activation_count, new_fuel_cost = (mover_modes[mode] or {}).task(pos, meta, owner, prefer, pos1, node1, node1_name, source_chest, pos2, mreverse, upgradetype, upgrade, fuel_cost)

			if activation_count then -- something happened
				if t0 > tn then
					meta:set_int("activation_count", activation_count + 1)
				elseif activation_count > 0 then
					meta:set_int("activation_count", 0)
				end
				fuel_cost = new_fuel_cost or fuel_cost
				if fuel_cost ~= 0 then
					fuel = fuel - fuel_cost; meta:set_float("fuel", fuel) -- fuel remaining
				end
				meta:set_string("infotext", S("Mover block. Temperature: @1, Fuel: @2.", T, twodigits_float(fuel)))
			elseif fuel_cost > 1.5 then
				fuel = fuel - fuel_cost * 0.03; meta:set_float("fuel", fuel) -- 3% fuel cost if no task done
				meta:set_string("infotext", S("Mover block. Temperature: @1, Fuel: @2.", T, twodigits_float(fuel)))
			elseif msg then -- mover refueled
				meta:set_float("fuel", fuel)
				meta:set_string("infotext", msg)
			end
		end,

		action_off = function(pos, _) -- this toggles reverse option of mover
			local meta = minetest.get_meta(pos)
			local mreverse = meta:get_int("reverse")
			if mreverse == 1 then mreverse = 0 elseif mreverse == 0 then mreverse = 1 end
			meta:set_int("reverse", mreverse)
		end
	}
})

if basic_machines.settings.register_crafts and basic_machines.use_default then
	minetest.register_craft({
		output = "basic_machines:mover",
		recipe = {
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
			{"default:stone", "basic_machines:keypad", "default:stone"}
		}
	})
end