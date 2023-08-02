-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local math_abs = math.abs
local mover_chests = basic_machines.get_mover("chests")
local mover_modes
local mover_plants_table = basic_machines.get_mover("plants_table")
local vector_add = vector.add

basic_machines.get_distance = function(pos1, pos2)
	return (math_abs(pos2.x - pos1.x) + math_abs(pos2.y - pos1.y) + math_abs(pos2.z - pos1.z))
end

if basic_machines.settings.mover_no_large_stacks then
	basic_machines.check_mover_target = function(mode, pos, meta)
		if mode == "normal" then
			local pos2 = vector_add(pos, {x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")})
			if mover_chests[minetest.get_node(pos2).name] then return true end
		elseif mode == "drop" or mode == "inventory" then -- any target
			return true
		end
		return false
	end

	basic_machines.clamp_item_count = function(item)
		local itemstring = type(item) == "string"
		local stack = itemstring and ItemStack(item) or item
		local stack_max = stack:get_stack_max()
		if stack:get_count() > stack_max then stack:set_count(stack_max) end
		return itemstring and stack:to_string() or stack
	end
end

-- anal retentive change in minetest 5.0.0 to minetest 5.1.0 (#7011) changing unknown node warning into crash
-- forcing many checks with all possible combinations + adding many new crashes combinations
basic_machines.check_mover_filter = function(mode, pos, meta, filter) -- mover input validation, is it correct node
	filter = filter or meta:get_string("prefer")
	if filter == "" then return true end -- allow clearing filter
	if mode == "object" or mode == "inventory" or mode == "drop" then
		return true
	elseif mode == "dig" and meta:get_int("reverse") == 1 and mover_plants_table[filter] then -- allow farming
		return true
	elseif minetest.registered_nodes[filter] then -- normal, dig and transport mode
		return true
	elseif mode == "normal" then -- allow chest transfer
		local pos2 = vector_add(pos, {x = meta:get_int("x2"), y = meta:get_int("y2"), z = meta:get_int("z2")})
		if mover_chests[minetest.get_node(pos2).name] then return true end
	end
	return false
end

basic_machines.find_and_connect_battery = function(pos, meta)
	for i = 0, 2 do
		local positions = minetest.find_nodes_in_area( -- find battery
			vector.subtract(pos, 1), vector_add(pos, 1), "basic_machines:battery_" .. i)
		if #positions > 0 then
			local fpos = positions[1] -- pick first battery found
			meta:set_int("batx", fpos.x); meta:set_int("baty", fpos.y); meta:set_int("batz", fpos.z)
			return fpos
		end
	end
end

local mover_modelist_translated
basic_machines.get_mover_form = function(pos)
	local meta = minetest.get_meta(pos)
	local seltab = meta:get_int("seltab")

	if seltab ~= 2 then -- MODE
		if mover_modes == nil then
			mover_modes = basic_machines.get_mover("modes")
			mover_modelist_translated = table.concat(mover_modes._tr_table, ",")
		end
		local mode = mover_modes[meta:get_string("mode")]
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
		local mode_string = meta:get_string("mode")
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
			btns_ns = "button_exit[0.25,6.8;1,0.8;now;" .. F(S("Now")) ..
				"]button_exit[1.5,6.8;1,0.8;show;" .. F(S("Show")) .. "]"
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

local predefined_id = {["normal"] = 1, ["dig"] = 2, ["drop"] = 3, ["object"] = 4, ["inventory"] = 5, ["transport"] = 6}
basic_machines.add_mover_mode = function(name, description, tr_name, func) -- just add a mode
	local modes = basic_machines.get_mover("modes")
	if modes.name then return end

	local count = modes._count + 1
	local id = predefined_id[name] or count
	local tr_table = modes._tr_table; tr_table[id] = tr_name

	basic_machines.set_mover("modes", {
		_count = count,
		_tr_table = tr_table,
		[name] = {id = id, desc = description, task = func}
	})
end

basic_machines.get_palette_index = function(inventory)
	local palette_index
	if inventory:get_count() > 0 then
		palette_index = tonumber(inventory:get_meta():get("palette_index"))
	end
	return palette_index
end

local get_palette_index = basic_machines.get_palette_index
basic_machines.check_palette_index = function(meta, node, node_def)
	local inv_stack = meta:get_inventory():get_stack("filter", 1)
	local def = node_def or inv_stack:get_definition()
	local inv_palette_index = get_palette_index(inv_stack)
	local palette_index = minetest.strip_param2_color(node.param2, def and def.paramtype2)

	if inv_palette_index ~= palette_index then
		return false
	end

	return true, palette_index
end

basic_machines.itemstring_to_stack = function(itemstring, palette_index)
	local stack = ItemStack(itemstring)
	if palette_index then
		stack:get_meta():set_int("palette_index", palette_index)
	end
	return stack
end

basic_machines.node_to_stack = function(node, paramtype2, param2)
	local stack = ItemStack(node.name)
	if paramtype2 then
		param2 = minetest.strip_param2_color(node.param2, paramtype2)
	end
	if param2 then
		stack:get_meta():set_int("palette_index", param2)
	end
	return stack
end