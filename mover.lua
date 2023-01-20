------------------------------------------------------------------------------------------------------------------------
-- BASIC MACHINES MOD by rnd
-- Mod with basic simple automatization for minetest
-- No background processing, just two abms (clock generator, generator), no other lag causing background processing
------------------------------------------------------------------------------------------------------------------------

local F, S = basic_machines.F, basic_machines.S
local machines_minstep = basic_machines.properties.machines_minstep
local machines_operations = basic_machines.properties.machines_operations
local machines_timer = basic_machines.properties.machines_timer
local max_range = basic_machines.properties.max_range
local mover_max_temp = math.max(1, basic_machines.settings.mover_max_temp)
local twodigits_float = basic_machines.twodigits_float
local vector_add = vector.add
local temp_80P = mover_max_temp > 12 and math.ceil(mover_max_temp * 0.8)
local temp_15P = math.ceil(mover_max_temp * 0.15)
local abs = math.abs
local vplayer = {}
local have_bucket_liquids = minetest.global_exists("bucket") and bucket.liquids

minetest.register_on_leaveplayer(function(player)
	vplayer[player:get_player_name()] = nil
end)

-- *** MOVER SETTINGS *** --
local mover = {
	bonemeal_table = {
		["bonemeal:bonemeal"] = true,
		["bonemeal:fertiliser"] = true,
		["bonemeal:mulch"] = true,
		["x_farming:bonemeal"] = true
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
	dig_up_table = {
		["default:acacia_tree"] = {r = 2}, -- acacia trees grow wider than others
		["default:aspen_tree"] = true,
		["default:cactus"] = {r = 0},
		["default:jungletree"] = true,
		["default:papyrus"] = {r = 0},
		["default:pine_tree"] = true,
		["default:tree"] = true
	},

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
		["gloopblocks:pumice_cooled"] = 2,
		["itemframes:frame"] = 999999,
		["itemframes:pedestal"] = 999999,
		["painting:canvasnode"] = 999999,
		["painting:pic"] = 999999,
		["statue:pedestal"] = 999999,
		["x_farming:cocoa_1"] = 999999,
		["x_farming:cocoa_2"] = 999999,
		["x_farming:cocoa_3"] = 999999,

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
		["basic_machines:autocrafter"] = {["recipe"] = 1, ["output"] = 1},
		["basic_machines:battery_0"] = {["upgrade"] = 1},
		["basic_machines:battery_1"] = {["upgrade"] = 1},
		["basic_machines:battery_2"] = {["upgrade"] = 1},
		["basic_machines:constructor"] = {["recipe"] = 1},
		["basic_machines:generator"] = {["upgrade"] = 1},
		["basic_machines:grinder"] = {["upgrade"] = 1},
		["basic_machines:mover"] = true,
		["moreblocks:circular_saw"] = true,
		["smartshop:shop"] = true
	},

	-- list of objects that can't be teleported with mover
	no_teleport_table = {
		[""] = true,
		["3d_armor_stand:armor_entity"] = true,
		["__builtin:item"] = true,
		["machines:posA"] = true,
		["machines:posN"] = true,
		["painting:paintent"] = true,
		["painting:picent"] = true,
		["shield_frame:shield_entity"] = true,
		["signs_lib:text"] = true,
		["statue:statue"] = true,
		["xdecor:f_item"] = true
	},

	-- set up nodes for plant with reverse on and filter set (for example seeds -> plant): [nodename] = plant_name
	plants_table = {
		["farming:seed_cotton"] = "farming:cotton_1", ["farming:seed_wheat"] = "farming:wheat_1" -- minetest_game farming mod
	}
}

-- cool_trees
local cool_trees = {
	{"baldcypress", h = 17, r = 5}, "bamboo", {"birch", d = 1}, "cacaotree", "cherrytree",
	{"chestnuttree", r = 5}, "clementinetree", {"ebony", r = 4}, {"hollytree", r = 3},
	"jacaranda", {"larch", r = 2}, "lemontree", {"mahogany", r = 2}, {"maple", r = 3},
	{"oak", r = 4}, {"palm", r = 2}, {"plumtree", r = 3, d = 1}, "pomegranate",
	{"sequoia", h = 46, r = 7, d = 4}, {"willow", r = 4}
}

for _, cool_tree in ipairs(cool_trees) do
	local name = type(cool_tree) == "table" and cool_tree[1] or cool_tree
	if minetest.global_exists(name) or minetest.get_modpath(name) then
		mover.dig_up_table[name .. ":trunk"] = type(cool_tree) == "table" and
			{h = cool_tree.h, r = cool_tree.r, d = cool_tree.d} or true
	end
end
--

local use_x_farming = minetest.global_exists("x_farming")
if minetest.global_exists("farming") and (farming.mod == "redo" or use_x_farming) then
	for name, plant in pairs(farming.registered_plants or {}) do
		if farming.mod == "redo" then
			mover.plants_table[plant.seed] = plant.crop .. "_1"
		elseif use_x_farming then
			local seed = "x_farming:seed_" .. name
			if minetest.registered_nodes[seed] then
				mover.plants_table[seed] = "x_farming:" .. name .. "_1"
			end
		end
	end
end
-- *** END OF MOVER SETTINGS *** --

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

-- add/replace value(s) as table of an existing setting
basic_machines.set_mover = function(setting, def)
	if not setting or not mover[setting] then return end
	for k, v in pairs(def) do
		mover[setting][k] = v
	end
end

-- anal retentive change in minetest 5.0.0 to minetest 5.1.0 (#7011) changing unknown node warning into crash
-- forcing many checks with all possible combinations + adding many new crashes combinations
basic_machines.check_mover_filter = function(mode, filter, mreverse) -- mover input validation, is it correct node
	if filter == "" then return true end -- allow clearing filter
	if mode == "normal" or mode == "dig" or mode == "transport" then
		if mreverse == 1 and mover.plants_table[filter] then return true end -- allow farming
		if not minetest.registered_nodes[filter] then
			return false
		end
	end
	return true
end

basic_machines.check_target_chest = function(mode, pos, meta)
	if mode == "normal" and meta:get_int("reverse") == 0 then
		local pos2 = vector_add(pos, {x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")})
		if mover.chests[minetest.get_node(pos2).name] then
			return true
		end
	end
	return false
end

local function itemstring_to_stack(itemstring, palette_index)
	local stack = ItemStack(itemstring)
	if palette_index then
		stack:get_meta():set_int("palette_index", palette_index)
	end
	return stack
end

local function create_virtual_player(name)
	local virtual_player = {}
	function virtual_player:is_player() return true end
	function virtual_player:get_player_name() return name end
	function virtual_player:get_player_control() return {} end
	return virtual_player
end

local function item_to_stack(item, paramtype2)
	local stack = ItemStack(item.name)
	if paramtype2 == nil then
		local def = minetest.registered_items[stack:get_name()]
		paramtype2 = def and def.paramtype2
	end
	local palette_index = minetest.strip_param2_color(item.param2, paramtype2)
	if palette_index then
		stack:get_meta():set_int("palette_index", palette_index)
	end
	return stack
end


-- MOVER --
local mover_modes = {
	["normal"] = {id = 1, desc = F(S("This will move blocks as they are - without change"))},
	["dig"] = {id = 2, desc = F(S("This will transform blocks as if player dug them"))},
	["drop"] = {id = 3, desc = F(S("This will take block/item out of chest (you need to set filter) and will drop it"))},
	["object"] = {id = 4 , desc = F(S("Make TELEPORTER/ELEVATOR:\n This will move any object inside a sphere (with center source1 and radius defined by distance between source1/source2) to target position\n" ..
		" For ELEVATOR, teleport origin/destination need to be placed exactly in same coordinate line with mover, and you need to upgrade with 1 diamond block for every 100 height difference"))},
	["inventory"] = {id = 5, desc = F(S("This will move items from inventory of any block at source position to any inventory of block at target position"))},
	["transport"] = {id = 6, desc = F(S("This will move all blocks at source area to new area starting at target position\n" ..
		"This mode preserves all inventories and other metadata"))}
}
local mover_modelist_translated = -- translations of mover_modes keys
	table.concat({F(S("normal")), F(S("dig")), F(S("drop")), F(S("object")), F(S("inventory")), F(S("transport"))}, ",")

basic_machines.get_mover_form = function(pos, name)
	local meta = minetest.get_meta(pos)
	local seltab = meta:get_int("seltab")
	local mode_string = meta:get_string("mode")

	if seltab ~= 2 then -- MODE
		local mode = mover_modes[mode_string]
		local list_name = "nodemeta:" .. pos.x .. ',' .. pos.y .. ',' .. pos.z

		return ("formspec_version[4]size[10.25,10.8]style_type[list;spacing=0.25,0.15]tabheader[0,0;tabs;" ..
			F(S("Mode of operation")) .. "," .. F(S("Where to move")) .. ";" .. seltab .. ";true;true]" ..
			"label[0.25,0.3;" .. minetest.colorize("lawngreen", F(S("Mode selection"))) ..
			"]dropdown[0.25,0.5;3.5,0.8;mode;" .. mover_modelist_translated .. ";" .. (mode and mode.id or 1) ..
			"]button[4,0.5;1,0.8;help;" .. F(S("help")) .. "]button_exit[6.5,0.5;1,0.8;OK;" .. F(S("OK")) ..
			"]textarea[0.25,1.6;9.75,2;description;;" .. (mode and mode.desc or F(S("description"))) ..
			"]field[0.25,4.2;3.5,0.8;prefer;" .. F(S("Filter")) .. ";" .. F(meta:get_string("prefer")) ..
			"]image[4,4.1;1,1;[combine:1x1^[noalpha^[colorize:#141318]" ..
			"list[" .. list_name .. ";filter;4,4.1;1,1]" ..
			"]label[6.5,3.9;" .. F(S("Upgrade")) .. "]list[" .. list_name .. ";upgrade;6.5,4.1;1,1]" ..
			basic_machines.get_form_player_inventory(0.25, 5.85, 8, 4, 0.25) ..
			"listring[" .. list_name .. ";upgrade]" ..
			"listring[current_player;main]" ..
			"listring[" .. list_name .. ";filter]" ..
			"listring[current_player;main]")
	else -- POSITIONS
		local pos1 = {x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")}
		local pos11 = {x = meta:get_int("x1"), y = meta:get_int("y1"), z = meta:get_int("z1")}
		local pos2 = {x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")}
		local inventory_list1, inventory_list2, btns_ns

		if mode_string == "inventory" then
			local meta1 = minetest.get_meta(vector_add(pos, pos1)) -- source1 meta
			local meta2 = minetest.get_meta(vector_add(pos, pos2)) -- target meta

			local inv1m, inv2m = meta:get_string("inv1"), meta:get_string("inv2")
			local inv1, inv2 = 1, 1

			local list1, inv_list1 = meta1:get_inventory():get_lists(), ""
			-- stupid dropdown requires item index but returns string on receive so we have to find index.. grrr
			-- one other solution: invert the table: key <-> value
			local j = 1
			for k, _ in pairs(list1) do
				inv_list1 = inv_list1 .. F(S(k)) .. ","
				if k == inv1m then inv1 = j end; j = j + 1
			end

			local list2, inv_list2 = meta2:get_inventory():get_lists(), ""; j = 1
			for k, _ in pairs(list2) do
				inv_list2 = inv_list2 .. F(S(k)) .. ","
				if k == inv2m then inv2 = j; end; j = j + 1
			end

			inventory_list1 = "label[5.5,0.7;" .. F(S("Source inventory")) .. "]dropdown[5.5,0.9;2.25,0.8;inv1;" ..
				inv_list1:gsub(",$", "") .. ";" .. inv1 .. "]"
			inventory_list2 = "label[5.5,3.85;" .. F(S("Target inventory")) .. "]dropdown[5.5,4.05;2.25,0.8;inv2;" ..
				inv_list2:gsub(",$", "") .. ";" .. inv2 .. "]"
		else
			inventory_list1, inventory_list2 = "", ""
		end

		if mode_string == "object" then
			btns_ns = ""
		else
			btns_ns = "button_exit[0.25,6.8;1,0.8;now;" .. F(S("Now")) .. "]button_exit[1.5,6.8;1,0.8;show;" .. F(S("Show")) .. "]"
		end

		return ("formspec_version[4]size[8,7.8]tabheader[0,0;tabs;" ..
			F(S("Mode of operation")) .. "," .. F(S("Where to move")) .. ";" .. seltab .. ";true;true]" ..
			"label[0.25,0.3;" .. minetest.colorize("lawngreen", F(S("Input area - mover will dig here"))) ..
			"]field[0.25,0.9;1,0.8;x0;" .. F(S("Source1")) .. ";" .. pos1.x .. "]field[1.5,0.9;1,0.8;y0;;" .. pos1.y ..
			"]field[2.75,0.9;1,0.8;z0;;" .. pos1.z .. "]image[4,0.8;1,1;machines_pos1.png]" .. inventory_list1 ..
			"field[0.25,2.15;1,0.8;x1;" .. F(S("Source2")) .. ";" .. pos11.x .. "]field[1.5,2.15;1,0.8;y1;;" .. pos11.y ..
			"]field[2.75,2.15;1,0.8;z1;;" .. pos11.z .. "]image[4,2.05;1,1;machines_pos11.png]" ..
			"label[0.25,3.45;" .. minetest.colorize("red", F(S("Target position - mover will move to here"))) ..
			"]field[0.25,4.05;1,0.8;x2;" .. F(S("Target")) .. ";" .. pos2.x .. "]field[1.5,4.05;1,0.8;y2;;" .. pos2.y ..
			"]field[2.75,4.05;1,0.8;z2;;" .. pos2.z .. "]image[4,3.95;1,1;machines_pos2.png]" .. inventory_list2 ..
			"label[0.25,5.3;" .. F(S("Reverse source and target (0/1/2/3)")) ..
			"]field[0.25,5.55;1,0.8;reverse;;" .. meta:get_int("reverse") .. "]" .. btns_ns ..
			"button[5.5,6.8;1,0.8;help;" .. F(S("help")) .. "]button_exit[6.75,6.8;1,0.8;OK;" .. F(S("OK")) .. "]")
	end
end

basic_machines.find_and_connect_battery = function(pos)
	for i = 0, 2 do
		local positions = minetest.find_nodes_in_area( -- find battery
			vector.subtract(pos, 1), vector_add(pos, 1), "basic_machines:battery_" .. i)
		if #positions > 0 then
			local meta = minetest.get_meta(pos)
			local fpos = positions[1] -- pick first battery found
			meta:set_int("batx", fpos.x); meta:set_int("baty", fpos.y); meta:set_int("batz", fpos.z)
			return fpos
		end
	end
end

local check_for_falling = minetest.check_for_falling or nodeupdate -- 1st for mt 5.0.0+, 2nd for 0.4.17.1 and older

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
	["default:mese"] = {id = 1, max = basic_machines.properties.mover_upgrade_max},
	["default:diamondblock"] = {id = 2, max = 99}
}

minetest.register_node("basic_machines:mover", {
	description = S("Mover"),
	groups = {cracky = 3},
	tiles = {"basic_machines_mover.png"},
	sounds = default.node_sound_wood_defaults(),

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

		basic_machines.find_and_connect_battery(pos) -- try to find battery early
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

	can_dig = function(pos, player) -- don't dig if upgrades inside, cause they will be destroyed
		local meta = minetest.get_meta(pos)
		return meta:get_inventory():is_empty("upgrade") and meta:get_string("owner") == player:get_player_name()
	end,

	on_rightclick = function(pos, node, player, itemstack, pointed_thing)
		local name, meta = player:get_player_name(), minetest.get_meta(pos)

		machines.mark_pos1(name, vector_add(pos,
			{x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")})) -- mark pos1
		machines.mark_pos11(name, vector_add(pos,
			{x = meta:get_int("x1"), y = meta:get_int("y1"), z = meta:get_int("z1")})) -- mark pos11
		machines.mark_pos2(name, vector_add(pos,
			{x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")})) -- mark pos2

		minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
			basic_machines.get_mover_form(pos, name))
	end,

	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		return 0 -- no internal inventory moves!
	end,

	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		local name = player:get_player_name()
		if minetest.is_protected(pos, name) then return 0 end
		local meta = minetest.get_meta(pos)

		if listname == "filter" then
			local inv = meta:get_inventory()
			local inv_stack = inv:get_stack("filter", 1)
			local inv_palette_index = tonumber(inv_stack:get_meta():get("palette_index"))
			local item = stack:to_table()
			local palette_index = tonumber(stack:get_meta():get("palette_index"))

			if inv_stack:get_name() == item.name and inv_palette_index == palette_index then
				item.count = inv_stack:get_count() + item.count
			end

			local mode = meta:get_string("mode")
			local prefer = item.name .. (item.count > 1 and (" " .. math.min(item.count, 65535)) or "")

			-- input validation
			if basic_machines.check_mover_filter(mode, prefer, meta:get_int("reverse")) or
				basic_machines.check_target_chest(mode, pos, meta)
			then
				meta:set_string("prefer", prefer)
				local filter_stack = itemstring_to_stack(prefer, palette_index)
				inv:set_stack("filter", 1, filter_stack) -- inv:add_item("filter", filter_stack)
			else
				minetest.chat_send_player(name, S("MOVER: Wrong filter - must be name of existing minetest block")); return 0
			end
			minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
				basic_machines.get_mover_form(pos, name))
		elseif listname == "upgrade" then
			local stack_name = stack:get_name()
			local mover_upgrade = mover_upgrades[stack_name]
			if mover_upgrade then
				local inv_stack = meta:get_inventory():get_stack("upgrade", 1)
				local inv_stack_is_empty = inv_stack:is_empty()
				if inv_stack_is_empty or stack_name == inv_stack:get_name() then
					local upgrade = inv_stack:get_count()
					local mover_upgrade_max = mover_upgrade.max
					if upgrade < mover_upgrade_max then
						local stack_count = stack:get_count()
						local new_upgrade = upgrade + stack_count
						if new_upgrade > mover_upgrade_max then
							new_upgrade = mover_upgrade_max -- not more than max
							stack_count = math.min(stack_count, mover_upgrade_max - upgrade)
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

	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		local name = player:get_player_name()
		if minetest.is_protected(pos, name) then return 0 end
		local meta = minetest.get_meta(pos)

		if listname == "filter" then
			local inv = meta:get_inventory()
			local inv_stack = inv:get_stack("filter", 1)
			local item = stack:to_table()
			item.count = inv_stack:get_count() - item.count

			if item.count < 1 then
				meta:set_string("prefer", "")
				inv:set_stack("filter", 1, ItemStack(""))
				-- inv:set_list("filter", {}) -- using saved map, mover with prefer previously set, it crashes the game... but why
			else
				local prefer = item.name .. (item.count > 1 and (" " .. item.count) or "")
				meta:set_string("prefer", prefer)
				local filter_stack = itemstring_to_stack(prefer, tonumber(inv_stack:get_meta():get("palette_index")))
				inv:set_stack("filter", 1, filter_stack) -- inv:add_item("filter", filter_stack)
			end
			minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
				basic_machines.get_mover_form(pos, name))
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


			-- TEMPERATURE
			local t0, t1 = meta:get_int("t"), minetest.get_gametime()
			local tn, T = t1 - machines_minstep, meta:get_int("T") -- temperature

			if t0 <= tn and T < mover_max_temp then
				T = 0
			end

			if t0 > tn then -- activated before natural time
				T = T + 1
			elseif T > mover_max_temp then
				if t1 - t0 > machines_timer then -- reset temperature if more than 5s elapsed since last activation
					T = 0; meta:set_string("infotext", "")
				else
					T = T - 1
				end
			end
			meta:set_int("t", t1); meta:set_int("T", T)

			if T > mover_max_temp then
				minetest.sound_play("default_cool_lava", {pos = pos, max_hear_distance = 16, gain = 0.25}, true)
				meta:set_string("infotext", S("Overheat! Temperature: @1", T))
				return
			end

			local mode = meta:get_string("mode")
			local object = mode == "object"
			local mreverse = meta:get_int("reverse")
			local transport
			local owner = meta:get_string("owner")


			-- POSITIONS
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
				transport = mode == "transport"
				-- special mode that use its own source/target positions:
				if transport and mreverse < 2 then
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


			-- PROTECTION CHECK
			if minetest.is_protected(pos1, owner) or minetest.is_protected(pos2, owner) then
				meta:set_string("infotext", S("Mover block. Protection fail.")); return
			end

			local inventory = mode == "inventory"
			local prefer = meta:get_string("prefer")
			local node1, node1_name, source_chest, msg


			-- FUEL
			local upgrade = meta:get_int("upgrade")
			local fuel_cost
			local fuel = meta:get_float("fuel")

			if upgrade == -1 then
				if not object then
					node1 = minetest.get_node(pos1); node1_name = node1.name
					if node1_name == "air" or node1_name == "ignore" then return end -- nothing to move
					if not inventory then
						source_chest = mover.chests[node1_name] or false
					end
				end
				fuel_cost = 0 -- free operations for admin
			else
				-- FUEL COST: calculate
				if object and meta:get_int("elevator") == 1 then -- check if elevator mode
					local requirement = math.floor((abs(pos2.x - pos.x) + abs(pos2.y - pos.y) + abs(pos2.z - pos.z)) / 100) + 1
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
					node1 = minetest.get_node(pos1); node1_name = node1.name
					if node1_name == "air" or node1_name == "ignore" then return end -- nothing to move
					if inventory then -- taking items from chests/inventory move
						fuel_cost = mover.hardness[prefer] or 1
					else
						source_chest = mover.chests[node1_name] or false
						if source_chest and node1_name ~= "default:chest" then
							fuel_cost = mover.hardness[prefer] or 1
						else
							local hardness = mover.hardness[node1_name]
							if hardness == 0 and object then hardness = 1 end -- no free teleport from machine blocks
							fuel_cost = hardness or 1
						end
					end
				end

				if fuel_cost > 0 then
					local dist = abs(pos2.x - pos1.x) + abs(pos2.y - pos1.y) + abs(pos2.z - pos1.z)
					-- machines_operations = 10 by default, so 10 basic operations possible with 1 coal
					fuel_cost = fuel_cost * dist / machines_operations

					if inventory or object then
						fuel_cost = fuel_cost * 0.1
					end

					if temp_80P then
						if T > temp_80P then
							fuel_cost = fuel_cost + (0.2 / mover_max_temp) * T * fuel_cost
						elseif T < temp_15P then
							fuel_cost = fuel_cost * 0.97
						end
					end

					if meta:get_int("upgradetype") == 1 or
						meta:get_inventory():get_stack("upgrade", 1):get_name() == "default:mese" -- for compatibility
					then
						fuel_cost = fuel_cost / upgrade -- upgrade decreases fuel cost
					end
				end

				-- FUEL OPERATIONS
				if fuel < fuel_cost then -- needs fuel to operate, find nearby battery
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

					local found_fuel

					if supply > 0 then
						found_fuel = supply
					elseif supply < 0 then -- no battery at target location, try to find it!
						if not basic_machines.find_and_connect_battery(pos) then
							meta:set_string("infotext", S("Can not find nearby battery to connect to!"))
							minetest.sound_play("default_cool_lava", {pos = pos, gain = 1, max_hear_distance = 8}, true)
							return
						end
					end

					if found_fuel then
						fuel = fuel + found_fuel; meta:set_float("fuel", fuel)
					end

					if fuel < fuel_cost then
						meta:set_string("infotext", S("Mover block. Energy @1, needed energy @2. Put nonempty battery next to mover.",
							fuel, fuel_cost)); return
					else
						msg = S("Mover block refueled. Fuel status @1.", twodigits_float(fuel))
					end
				end
			end


			-- OBJECT MODE
			if object then -- teleport objects and return
				local x1, y1, z1
				if mreverse == 1 then
					x1, y1, z1 = meta:get_int("x0"), meta:get_int("y0"), meta:get_int("z0") -- source1
				else
					x1, y1, z1 = meta:get_int("x1"), meta:get_int("y1"), meta:get_int("z1") -- source2
				end
				local radius = math.min(vector.distance(pos1, vector_add(pos, {x = x1, y = y1, z = z1})), max_range) -- distance source1-source2
				local elevator = meta:get_int("elevator"); if elevator == 1 and radius == 0 then radius = 1 end -- for compatibility
				local teleport_any = false

				if mover.chests[minetest.get_node(pos2).name] and elevator == 0 then -- put objects in target chest
					local inv = minetest.get_meta(pos2):get_inventory()
					local mucca

					for _, obj in ipairs(minetest.get_objects_inside_radius(pos1, radius)) do
						if not obj:is_player() then
							local lua_entity = obj:get_luaentity()
							local detected_obj = lua_entity and (lua_entity.itemstring or lua_entity.name) or ""
							if not mover.no_teleport_table[detected_obj] and lua_entity then -- object on no teleport list
								if prefer == "" or prefer == detected_obj then
									if not lua_entity.protected then -- check if mob (mobs_redo) protected
										-- put item in chest
										local stack = ItemStack(lua_entity.itemstring)
										if not stack:is_empty() and inv:room_for_item("main", stack) then
											inv:add_item("main", stack); teleport_any = true
										end
										obj:remove()
									end
								elseif prefer == "bucket:bucket_empty" and lua_entity.name == "mobs_animal:cow" then
									if not lua_entity.child then
										if lua_entity.gotten then -- already milked
											mucca = (mucca or "") .. ", " ..
												((lua_entity.nametag and lua_entity.nametag ~= "") and lua_entity.nametag or "Cow")
											meta:set_string("infotext", S("@1 already milked!", mucca:gsub(", Cow", "") ~= "" and
												mucca:sub(3):gsub("Cow", S("Cow")) or S("Cows")))
										elseif inv:contains_item("main", "bucket:bucket_empty") then
											inv:remove_item("main", "bucket:bucket_empty")
											if inv:room_for_item("main", "mobs:bucket_milk") then
												inv:add_item("main", "mobs:bucket_milk")
											else
												minetest.add_item(obj:get_pos(), {name = "mobs:bucket_milk"})
											end
											lua_entity.gotten = true; teleport_any = true
										end
									end
								end
							end
						end
					end
				else
					local times, velocityv = tonumber(prefer) or 0, nil
					if times ~= 0 then
						if times == 99 then
							velocityv = {x = 0, y = 0, z = 0}
						else
							if times > 20 then times = 20 elseif times < 0.2 then times = 0.2 end
							velocityv = vector.subtract(pos2, pos1)
							local vv = math.sqrt(velocityv.x * velocityv.x + velocityv.y * velocityv.y + velocityv.z * velocityv.z)
							if vv ~= 0 then vv = vv / vv * times else vv = 0 end
							velocityv = vector.multiply(velocityv, vv)
						end
					end

					-- move objects to another location
					for _, obj in ipairs(minetest.get_objects_inside_radius(pos1, radius)) do
						if obj:is_player() then
							if not minetest.is_protected(obj:get_pos(), owner) and
								(prefer == "" or obj:get_player_name() == prefer)
							then -- move player only from owners land
								obj:move_to(pos2, false); teleport_any = true
							end
						else
							local lua_entity = obj:get_luaentity()
							local detected_obj = lua_entity and (lua_entity.itemstring or lua_entity.name) or ""
							if not mover.no_teleport_table[detected_obj] and lua_entity then -- object on no teleport list
								if times > 0 then -- interaction with objects like carts
									local name = lua_entity.name
									if times == 99 then
										obj:set_acceleration(velocityv)
										obj:set_velocity(velocityv)
										obj:set_properties({automatic_rotate = vector.distance(pos1, obj:get_pos()) / (radius + 5)})
									elseif name == "basic_machines:ball" then -- move balls for free
										obj:set_velocity(velocityv) -- move objects with set velocity in target direction
									elseif name == "carts:cart" then -- just accelerate cart
										obj:set_velocity(velocityv) -- move objects with set velocity in target direction
										fuel = fuel - fuel_cost; meta:set_float("fuel", fuel)
										meta:set_string("infotext", S("Mover block. Temperature: @1, Fuel: @2.", T, twodigits_float(fuel)))
										return
									else -- don't move objects like balls to destination after delay
										minetest.after(times, function()
											obj:move_to(pos2, false); teleport_any = true
										end)
									end
								else
									obj:move_to(pos2, false); teleport_any = true
								end
							end
						end
					end
				end

				if teleport_any then
					fuel = fuel - fuel_cost; meta:set_float("fuel", fuel)
					meta:set_string("infotext", S("Mover block. Temperature: @1, Fuel: @2.", T, twodigits_float(fuel)))
					minetest.sound_play("basic_machines_tng_transporter1", {pos = pos2, gain = 1, max_hear_distance = 8}, true)
				elseif msg then
					meta:set_string("infotext", msg)
				end


			-- INVENTORY MODE
			elseif inventory then
				local invName1, invName2

				if mreverse == 1 then -- reverse inventory names too
					invName1, invName2 = meta:get_string("inv2"), meta:get_string("inv1")
				else
					invName1, invName2 = meta:get_string("inv1"), meta:get_string("inv2")
				end

				-- forbidden nodes to take from in inventory mode - to prevent abuses:
				local limit_inventory = mover.limit_inventory_table[node1_name]
				if limit_inventory then
					if limit_inventory == true or limit_inventory[invName1] then -- forbidden to take from this inventory
						if msg then meta:set_string("infotext", msg) end; return
					end
				end

				local stack, inv1

				if prefer ~= "" then
					stack = ItemStack(prefer)
				else -- just pick one item from chest to transfer
					inv1 = minetest.get_meta(pos1):get_inventory()
					if inv1:is_empty(invName1) then -- nothing to move
						if msg then meta:set_string("infotext", msg) end; return
					end
					local i, found = 1, false
					while i <= inv1:get_size(invName1) do -- find item to move in inventory
						stack = inv1:get_stack(invName1, i)
						if stack:is_empty() then i = i + 1 else found = true; break end
					end
					if not found then if msg then meta:set_string("infotext", msg) end; return end
				end

				-- can we move the items to target inventory ?
				local inv2 = minetest.get_meta(pos2):get_inventory()
				if inv2:room_for_item(invName2, stack) then
					inv1 = inv1 or minetest.get_meta(pos1):get_inventory()
					-- add item to target inventory and remove item from source inventory
					if inv1:contains_item(invName1, stack) then
						inv2:add_item(invName2, stack)
						inv1:remove_item(invName1, stack)
					elseif upgrade == -1 and minetest.registered_items[stack:get_name()] then -- admin is owner.. just add stuff
						inv2:add_item(invName2, stack)
					else
						if msg then meta:set_string("infotext", msg) end; return -- item not found in chest
					end
				else
					if msg then meta:set_string("infotext", msg) end; return
				end

				local count = meta:get_int("activation_count")
				if count < 16 then
					minetest.sound_play("basic_machines_chest_inventory_move", {pos = pos2, gain = 1, max_hear_distance = 8}, true)
				end

				if t0 > tn then
					meta:set_int("activation_count", count + 1)
				elseif count > 0 then
					meta:set_int("activation_count", 0)
				end

				fuel = fuel - fuel_cost; meta:set_float("fuel", fuel)
				meta:set_string("infotext", S("Mover block. Temperature: @1, Fuel: @2.", T, twodigits_float(fuel)))


			-- NORMAL, DIG, DROP, TRANSPORT MODES
			else
				local bonemeal

				if prefer ~= "" then -- filter check
					if source_chest then
						bonemeal = mover.bonemeal_table[prefer]
					else
						if prefer ~= node1_name then -- only take preferred node
							if msg then meta:set_string("infotext", msg) end; return
						else
							local inv_stack = meta:get_inventory():get_stack("filter", 1)
							if inv_stack:get_count() > 0 then
								local inv_palette_index = tonumber(inv_stack:get_meta():get("palette_index"))
								if inv_palette_index then
									local def = inv_stack:get_definition()
									local palette_index = minetest.strip_param2_color(node1.param2, def and def.paramtype2)
									if inv_palette_index ~= palette_index then
										if msg then meta:set_string("infotext", msg) end; return
									end
								end
							end
						end
					end
				elseif source_chest then -- prefer == "", doesn't know what to take out of chest/inventory
					if msg then meta:set_string("infotext", msg) end; return
				end

				local node2_name = minetest.get_node(pos2).name
				local target_chest = mover.chests[node2_name] or false

				-- do nothing if target non-empty and not chest and not bonemeal or transport mode and target chest
				if not target_chest and node2_name ~= "air" and not bonemeal or transport and target_chest then
					if msg then meta:set_string("infotext", msg) end; return
				end

				local drop, dig = mode == "drop", mode == "dig"

				-- filtering
				if prefer ~= "" then -- preferred node set
					local plant, normal = mover.plants_table[prefer], mode == "normal"; local def

					if drop or mreverse == 1 and plant or
						normal and target_chest
					then
						node1.name, node1_name = prefer, prefer
					elseif normal or dig or transport then
						def = minetest.registered_nodes[prefer]
						if def then
							node1.name, node1_name = prefer, prefer
						else
							minetest.chat_send_player(owner, S("MOVER: Filter defined with unknown node (@1) at @2, @3, @4.",
								prefer, pos.x, pos.y, pos.z)); return
						end
					else
						minetest.chat_send_player(owner, S("MOVER: Wrong filter (@1) at @2, @3, @4.",
							prefer, pos.x, pos.y, pos.z)); return
					end

					if source_chest and not transport then -- take stuff from chest
						local inv_stack = meta:get_inventory():get_stack("filter", 1)
						local stack, match_meta = ItemStack(prefer), false
						local inv = minetest.get_meta(pos1):get_inventory()

						if inv_stack:get_count() > 0 then
							local palette_index = tonumber(inv_stack:get_meta():get("palette_index"))
							if palette_index then
								stack:get_meta():set_int("palette_index", palette_index)
								match_meta = true; node1.param1, node1.param2 = nil, palette_index
							end
						end

						if inv:contains_item("main", stack, match_meta) then
							if mreverse == 1 and not match_meta then
								if normal or dig then
									if plant then -- planting mode: check if transform seed -> plant is needed
										def = minetest.registered_nodes[plant]
										if def then
											node1 = {name = plant, param1 = nil,
												param2 = def.place_param2}
											node1_name = plant
										else
											if msg then meta:set_string("infotext", msg) end; return
										end
									elseif def and def.paramtype2 ~= "facedir" then
										node1.param2 = nil
									end
								elseif drop and bonemeal then -- bonemeal check
									local on_use = (minetest.registered_items[prefer] or {}).on_use
									if on_use then
										vplayer[owner] = vplayer[owner] or create_virtual_player(owner)
										local itemstack = on_use(ItemStack(prefer .. " 2"),
											vplayer[owner], {type = "node",	under = pos2,
											above = {x = pos2.x, y = pos2.y + 1, z = pos2.z}})
										bonemeal = itemstack and itemstack:get_count() == 1 or
											basic_machines.creative(owner)
									else
										if msg then meta:set_string("infotext", msg) end; return
									end
								end
							elseif not match_meta then
								node1.param1, node1.param2 = nil, nil
							end
							inv:remove_item("main", stack)
						else
							if msg then meta:set_string("infotext", msg) end; return
						end
					end
				end

				local not_special = true -- mode for special items: trees, liquids using bucket, mese crystals ore

				if target_chest and not transport then -- if target chest put in chest
					local inv = minetest.get_meta(pos2):get_inventory()
					if dig then
						if not source_chest then
							local dig_up = mover.dig_up_table[node1_name] -- digs up node as a tree
							if dig_up then
								local h, r, d = 16, 1, 0 -- height, radius, depth

								if type(dig_up) == "table" then
									h, r, d = dig_up.h or h, dig_up.r or r, dig_up.d or d
								end

								local positions = minetest.find_nodes_in_area(
									{x = pos1.x - r, y = pos1.y - d, z = pos1.z - r},
									{x = pos1.x + r, y = pos1.y + h, z = pos1.z + r},
									node1_name)

								for _, pos3 in ipairs(positions) do
									minetest.set_node(pos3, {name = "air"})
								end
								check_for_falling(pos1)

								local count, stack_max, stacks = #positions, ItemStack(node1_name):get_stack_max(), {}

								if count > stack_max then
									local stacks_n = count / stack_max
									for i = 1, stacks_n do stacks[i] = stack_max end
									stacks[#stacks + 1] = stacks_n % 1 * stack_max
								else
									stacks[1] = count
								end

								not_special = false

								local i = 1
								repeat
									local item = node1_name .. " " .. stacks[i]
									if inv:room_for_item("main", item) then
										inv:add_item("main", item) -- if tree or cactus was dug up
									else
										minetest.add_item(pos1, item)
									end
									i = i + 1
								until(i > #stacks)
							else
								local liquiddef = have_bucket_liquids and bucket.liquids[node1_name]
								local harvest_node1 = mover.harvest_table[node1_name]

								if liquiddef and node1_name == liquiddef.source and liquiddef.itemname then
									local itemname = liquiddef.itemname
									if inv:contains_item("main", "bucket:bucket_empty") then
										not_special = false; inv:remove_item("main", "bucket:bucket_empty")
										if inv:room_for_item("main", itemname) then
											inv:add_item("main", itemname)
											-- force_renew requires a source neighbour (borrowed from bucket mod)
											local source_neighbor = false
											if liquiddef.force_renew then
												source_neighbor = minetest.find_node_near(pos1, 1, liquiddef.source)
											end
											if not (source_neighbor and liquiddef.force_renew) then
												minetest.set_node(pos1, {name = "air"})
											end
										else
											minetest.add_item(pos1, itemname)
										end
									end
								elseif harvest_node1 then -- do we harvest the node ?
									local item = harvest_node1[2]
									if item and inv:room_for_item("main", item) then
										not_special = false
										inv:add_item("main", item)
										minetest.set_node(pos1, {name = harvest_node1[1]})
									else
										if msg then meta:set_string("infotext", msg) end; return
									end
								end
							end
						end

						if not_special then -- minetest drop code emulation, alternative: minetest.get_node_drops
							local def = minetest.registered_items[node1_name]
							if def then -- put in chest
								local drops = def.drop
								if drops then -- drop handling
									if drops.items then -- handle drops better, emulation of drop code
										local max_items = drops.max_items or 0 -- item lists to drop
										if max_items == 0 then -- just drop all the items (taking the rarity into consideration)
											max_items = #drops.items or 0
										end
										local itemlists_dropped = 0
										for _, item in ipairs(drops.items) do
											if itemlists_dropped >= max_items then break end
											if math.random(1, item.rarity or 1) == 1 then
												local inherit_color, palette_index = item.inherit_color, nil
												if inherit_color then
													palette_index = minetest.strip_param2_color(node1.param2, def.paramtype2)
												end
												for _, add_item in ipairs(item.items) do -- pick all items from list
													if inherit_color and palette_index then
														add_item = itemstring_to_stack(add_item, palette_index)
													end
													inv:add_item("main", add_item)
												end
												itemlists_dropped = itemlists_dropped + 1
											end
										end
									else
										inv:add_item("main", drops)
									end
								else
									inv:add_item("main", item_to_stack(node1, def.paramtype2))
								end
							end
						end
					else -- if not dig just put it in
						inv:add_item("main", item_to_stack(node1))
					end
				end

				local count = meta:get_int("activation_count")
				if count < 16 then
					minetest.sound_play("basic_machines_transporter", {pos = pos2, gain = 1, max_hear_distance = 8}, true)
				end

				if t0 > tn then
					meta:set_int("activation_count", count + 1)
				elseif count > 0 then
					meta:set_int("activation_count", 0)
				end

				if target_chest and source_chest then -- chest to chest transport has lower cost, * 0.1
					fuel_cost = fuel_cost * 0.1
				end

				fuel = fuel - fuel_cost; meta:set_float("fuel", fuel)
				meta:set_string("infotext", S("Mover block. Temperature: @1, Fuel: @2.", T, twodigits_float(fuel)))

				if transport then -- transport nodes parallel as defined by source1 and target, clone with complete metadata
					local meta1 = minetest.get_meta(pos1):to_table()
					minetest.set_node(pos2, node1); minetest.get_meta(pos2):from_table(meta1)
					minetest.set_node(pos1, {name = "air"}); minetest.get_meta(pos1):from_table(nil)
				else
					-- REMOVE NODE DUG
					if not target_chest and not bonemeal then
						if drop then -- drops node instead of placing it
							minetest.add_item(pos2, item_to_stack(node1)) -- drops it
						else
							minetest.set_node(pos2, node1)
						end
					end

					if not source_chest and not_special then
						minetest.set_node(pos1, {name = "air"})
						if dig then check_for_falling(pos1) end -- pre 5.0.0 nodeupdate(pos1)
					end
				end
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

if basic_machines.settings.register_crafts then
	minetest.register_craft({
		output = "basic_machines:mover",
		recipe = {
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
			{"default:stone", "basic_machines:keypad", "default:stone"}
		}
	})
end