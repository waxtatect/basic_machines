-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local mover_chests = basic_machines.get_mover("chests")
local mover_hardness = basic_machines.get_mover("hardness")
local mover_plants_table = basic_machines.get_mover("plants_table")
local machines_operations = basic_machines.properties.machines_operations
local mover_upgrade_max = basic_machines.properties.mover_upgrade_max
local check_palette_index = basic_machines.check_palette_index
local get_distance = basic_machines.get_distance
local mover_add_removed_items = basic_machines.settings.mover_add_removed_items
local node_to_stack = basic_machines.node_to_stack
local math_min = math.min

local function normal(pos, meta, owner, prefer, pos1, node1, node1_name, source_chest, pos2, mreverse, upgradetype, upgrade, fuel_cost)
	prefer = prefer or meta:get_string("prefer")
	source_chest = source_chest or mover_chests[node1_name]
	local third_upgradetype = upgradetype == 3
	local node2_name, target_chest, node_def, node1_param2, new_fuel_cost, last_pos2, sound_def

	-- checks
	if prefer ~= "" then -- filter check
		if source_chest then -- set preferred node
			if not third_upgradetype then
				node2_name = minetest.get_node(pos2).name
				target_chest = mover_chests[node2_name]
			end
			if target_chest then -- allow chest transfer
				node1.name = prefer
			else -- set preferred node
				node_def = minetest.registered_nodes[prefer]
				if node_def then
					node1.name = prefer
				else -- (see basic_machines.check_mover_filter)
					minetest.chat_send_player(owner, S("MOVER: Filter defined with unknown node (@1) at @2, @3, @4.",
						prefer, pos.x, pos.y, pos.z)); return
				end
			end
		elseif prefer == node1_name or third_upgradetype then -- only take preferred node
			node_def = minetest.registered_nodes[prefer]
			if node_def then
				if not third_upgradetype then
					local valid
					valid, node1_param2 = check_palette_index(meta, node1, node_def) -- only take preferred node with palette_index
					if not valid then
						return
					end
				end
			else -- (see basic_machines.check_mover_filter)
				minetest.chat_send_player(owner, S("MOVER: Filter defined with unknown node (@1) at @2, @3, @4.",
					prefer, pos.x, pos.y, pos.z)); return
			end
		else
			return
		end
	elseif source_chest then -- prefer == "", doesn't know what to take out of chest
		return
	end

	-- normal move
	if source_chest then -- take items from chest (filter needed)
		if target_chest then -- put items in chest
			local stack = ItemStack(prefer); local removed_items

			local inv1 = minetest.get_meta(pos1):get_inventory()
			if inv1:contains_item("main", stack) then
				removed_items = inv1:remove_item("main", stack)
				local palette_index = removed_items:get_meta():get_int("palette_index")
				if palette_index == 0 and not mover_add_removed_items then
					removed_items = nil
				end
			else
				return
			end

			local inv2 = minetest.get_meta(pos2):get_inventory()
			inv2:add_item("main", removed_items or stack)

			new_fuel_cost = fuel_cost * 0.1 -- chest to chest transport has lower cost, * 0.1
		else
			local air_found, node2_count

			if node2_name == "air" then
				air_found = true
			else
				node2_count = 0
				for i = #pos2, 1, -1 do
					if minetest.get_node(pos2[i]).name == "air" then
						if not last_pos2 then last_pos2 = pos2[i] end
						node2_count = node2_count + 1
					else
						pos2[i] = {}
					end
				end
				if node2_count > 0 then
					air_found = true
				end
			end

			if air_found then -- take node out of chest and place it
				local inv = minetest.get_meta(pos1):get_inventory()
				local stack = ItemStack(prefer)
				if third_upgradetype then stack:set_count(node2_count) end
				if inv:contains_item("main", stack) then
					local removed_items = inv:remove_item("main", stack)
					local palette_index = removed_items:get_meta():get_int("palette_index")
					if palette_index ~= 0 then
						node1.param2 = palette_index
					elseif mover_plants_table[prefer] then
						node1.param2 = 1
					elseif mreverse ~= 1 or node_def.paramtype2 ~= "facedir" then
						node1.param2 = 0
					end
				else
					return
				end

				sound_def = (node_def.sounds or {}).place -- preparing for sound_play

				if third_upgradetype then
					if fuel_cost > 0 then
						local length_pos2 = #pos2
						if node2_count < length_pos2 then
							new_fuel_cost = fuel_cost * (1 - node2_count / length_pos2)
						end
					end

					minetest.bulk_set_node(pos2, node1)
				else
					minetest.set_node(pos2, node1)
				end
			else -- nothing to do
				return
			end
		end
	else
		node2_name = minetest.get_node(pos2).name

		if mover_chests[node2_name] then -- target_chest, put items in chest
			if third_upgradetype then
				local length_pos1, node1_count = #pos1, 0
				local first_pos1; new_fuel_cost = 0

				local inv = minetest.get_meta(pos2):get_inventory()
				for i = 1, length_pos1 do
					local node1i_name = node1_name[i]
					if node1i_name then
						if mover_chests[node1i_name] then
							pos1[i] = {}
						else
							local items

							if prefer == "" then
								local node1i = node1[i]
								local paramtype2 = (minetest.registered_nodes[node1i.name] or {}).paramtype2
								items = inv:add_item("main", node_to_stack(node1i, paramtype2))
							elseif prefer == node1i_name then
								local node1i = node1[i]
								local valid, node1i_param2 = check_palette_index(meta, node1i, node_def)
								if valid then
									items = inv:add_item("main", node_to_stack(node1i, nil, node1i_param2))
								else
									pos1[i] = {}
								end
							end

							if items then
								if fuel_cost > 0 then
									if not first_pos1 then first_pos1 = pos1[i] end
									new_fuel_cost = new_fuel_cost + (mover_hardness[node1i_name] or 1)
								end
								node1_count = node1_count + 1
							else
								pos1[i] = {}
							end
						end
					end
				end

				if node1_count == 0 then
					return
				elseif new_fuel_cost > 0 then
					if node1_count < length_pos1 then
						new_fuel_cost = new_fuel_cost * get_distance(first_pos1, pos2) / machines_operations
						new_fuel_cost = new_fuel_cost / math_min(mover_upgrade_max + 1, upgrade) -- upgrade decreases fuel cost
					else
						new_fuel_cost = nil
					end
				end

				minetest.bulk_set_node(pos1, {name = "air"})
			else
				minetest.remove_node(pos1)

				local inv = minetest.get_meta(pos2):get_inventory()
				if prefer ~= "" then
					inv:add_item("main", node_to_stack(node1, nil, node1_param2))
				else -- without filter
					local paramtype2 = (minetest.registered_nodes[node1.name] or {}).paramtype2
					inv:add_item("main", node_to_stack(node1, paramtype2))
				end
			end
		elseif node2_name == "air" and not third_upgradetype then -- move node from pos1 to pos2
			sound_def = ((node_def or minetest.registered_nodes[node1_name] or {}).sounds or {}).place -- preparing for sound_play
			minetest.remove_node(pos1)
			minetest.set_node(pos2, node1)
		else -- nothing to do
			return
		end
	end

	local activation_count = meta:get_int("activation_count")

	if sound_def and activation_count < 16 then -- play sound
		minetest.sound_play(sound_def, {pitch = 0.9, pos = last_pos2 or pos2, max_hear_distance = 12}, true)
	end

	return activation_count, new_fuel_cost
end

basic_machines.add_mover_mode("normal",
	F(S("This will move blocks as they are - without change\nUpgrade with movers to process additional blocks")),
	F(S("normal")), normal
)