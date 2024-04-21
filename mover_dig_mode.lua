-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local mover_chests = basic_machines.get_mover("chests")
local mover_dig_up_table = basic_machines.get_mover("dig_up_table")
local mover_hardness = basic_machines.get_mover("hardness")
local mover_harvest_table = basic_machines.get_mover("harvest_table")
local mover_plants_table = basic_machines.get_mover("plants_table")
local check_for_falling = minetest.check_for_falling or nodeupdate -- 1st for mt 5.0.0+, 2nd for 0.4.17.1 and older
local check_palette_index = basic_machines.check_palette_index
local get_distance = basic_machines.get_distance
local have_bucket_liquids = minetest.global_exists("bucket") and bucket.liquids
local itemstring_to_stack = basic_machines.itemstring_to_stack
local machines_operations = basic_machines.properties.machines_operations
local mover_upgrade_max = basic_machines.properties.mover_upgrade_max
local node_to_stack = basic_machines.node_to_stack
local use_farming = minetest.global_exists("farming")
local use_x_farming = minetest.global_exists("x_farming")
local math_min = math.min

-- minetest drop code emulation, other idea: minetest.get_node_drops
local function add_node_drops(node_name, pos, node, filter, node_def, param2)
	local def = node_def or minetest.registered_nodes[node_name]
	if def then
		local drops, inv = def.drop, minetest.get_meta(pos):get_inventory()
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
						local inherit_color, palette_index = item.inherit_color
						if inherit_color then
							if filter then
								palette_index = param2
							else
								palette_index = minetest.strip_param2_color(node.param2, def.paramtype2)
							end
						end
						for _, drop_item in ipairs(item.items) do -- pick all items from list
							if inherit_color and palette_index then
								drop_item = itemstring_to_stack(drop_item, palette_index)
							end
							inv:add_item("main", drop_item)
						end
						itemlists_dropped = itemlists_dropped + 1
					end
				end
			else
				inv:add_item("main", drops)
			end
		elseif filter then
			inv:add_item("main", node_to_stack(node, nil, param2))
		else -- without filter
			inv:add_item("main", node_to_stack(node, def.paramtype2))
		end
	end
	return true
end

local function dig(pos, meta, owner, prefer, pos1, node1, node1_name, source_chest, pos2, mreverse, upgradetype, upgrade, fuel_cost)
	prefer = prefer or meta:get_string("prefer")
	source_chest = source_chest or mover_chests[node1_name]
	local third_upgradetype = upgradetype == 3
	local seed_planting, node_def, node1_param2, sound_def, last_pos2, new_fuel_cost

	-- checks
	if prefer ~= "" then -- filter check
		if source_chest then
			if mreverse == 1 then
				seed_planting = mover_plants_table[prefer]
			end
			if seed_planting then -- allow farming
				local plant_def = minetest.registered_nodes[seed_planting]
				if plant_def then -- farming redo mod, check if transform seed -> plant is needed
					node1 = {name = seed_planting, param2 = plant_def.place_param2 or 1}
				elseif seed_planting == true then -- minetest_game farming mod and x_farming mod
					node1 = {name = prefer, param2 = 1}
				else
					return
				end
				sound_def = ((plant_def or minetest.registered_nodes[prefer] or {}).sounds or {}).place -- preparing for sound_play
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

	-- dig node
	if source_chest then -- take node from chest (filter needed)
		local air_found, node2_count

		if third_upgradetype then
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
		elseif minetest.get_node(pos2).name == "air" then
			air_found = true
		end

		if air_found then -- take node out of chest and place it
			local inv = minetest.get_meta(pos1):get_inventory()
			local stack = ItemStack(prefer)
			if third_upgradetype then stack:set_count(node2_count) end
			if inv:contains_item("main", stack) then
				if seed_planting then
					if use_farming and farming.mod == "redo" then -- check for beanpole and trellis
						if prefer == "farming:beans" then
							local item = "farming:beanpole"
							if third_upgradetype then item = item .. " " .. node2_count end
							if inv:contains_item("main", item) then
								inv:remove_item("main", item)
							else
								return
							end
						elseif prefer == "farming:grapes" then
							local item = "farming:trellis"
							if third_upgradetype then item = item .. " " .. node2_count end
							if inv:contains_item("main", item) then
								inv:remove_item("main", item)
							else
								return
							end
						end
					end
					inv:remove_item("main", stack)
				else
					local removed_items = inv:remove_item("main", stack)
					local palette_index = removed_items:get_meta():get_int("palette_index")
					if palette_index ~= 0 then
						node1.param2 = palette_index
					elseif mreverse ~= 1 or node_def.paramtype2 ~= "facedir" then
						node1.param2 = 0
					end
				end
			else
				return
			end

			if seed_planting then
				if third_upgradetype then
					local length_pos2 = #pos2

					if fuel_cost > 0 and node2_count < length_pos2 then
						new_fuel_cost = fuel_cost * (1 - node2_count / length_pos2)
					end

					minetest.bulk_set_node(pos2, node1)

					if use_x_farming and node1.name:sub(1, 9) == "x_farming" and x_farming.grow_plant then -- x_farming mod
						for i = 1, length_pos2 do
							local pos2i = pos2[i]
							if pos2i.x then
								x_farming.grow_plant(pos2i)
							end
						end
					elseif farming.handle_growth then -- farming redo mod
						for i = 1, length_pos2 do
							local pos2i = pos2[i]
							if pos2i.x then
								farming.handle_growth(pos2i, node1)
							end
						end
					elseif farming.grow_plant then -- minetest_game farming mod
						for i = 1, length_pos2 do
							local pos2i = pos2[i]
							if pos2i.x then
								farming.grow_plant(pos2i)
							end
						end
					end
				else
					minetest.set_node(pos2, node1)
					if use_x_farming and node1.name:sub(1, 9) == "x_farming" and x_farming.grow_plant then -- x_farming mod
						x_farming.grow_plant(pos2)
					elseif farming.handle_growth then -- farming redo mod
						farming.handle_growth(pos2, node1)
					elseif farming.grow_plant then -- minetest_game farming mod
						farming.grow_plant(pos2)
					end
				end
			elseif third_upgradetype then -- place nodes as in normal mode
				if fuel_cost > 0 then
					local length_pos2 = #pos2
					if node2_count < length_pos2 then
						new_fuel_cost = fuel_cost * (1 - node2_count / length_pos2)
					end
				end
				sound_def = (node_def.sounds or {}).place -- preparing for sound_play

				minetest.bulk_set_node(pos2, node1)
			else -- try to place node as the owner would
				sound_def = (node_def.sounds or {}).place -- preparing for sound_play

				local placer, is_placed = minetest.get_player_by_name(owner)
				if placer then -- only if owner online
					local on_place = node_def.on_place
					if on_place then
						local _, placed_pos = on_place(node_to_stack(node1, node_def.paramtype2),
							placer, {type = "node",	under = pos2,
							above = {x = pos2.x, y = pos2.y + 1, z = pos2.z}})
						if placed_pos then
							local placed_node = minetest.get_node_or_nil(placed_pos)
							if placed_node and prefer == placed_node.name then
								local param2 = node1.param2
								if param2 ~= placed_node.param2 then
									placed_node.param2 = param2
									minetest.swap_node(placed_pos, placed_node)
								end
							end
							is_placed = true
						end
					end
				end
				if not is_placed then -- place node as in normal mode
					minetest.set_node(pos2, node1)
				end
			end
		else -- nothing to do
			return
		end
	else
		local node2_name = minetest.get_node(pos2).name

		if mover_chests[node2_name] then -- target_chest, put node dug in chest
			if third_upgradetype then
				local length_pos1, node1_count = #pos1, 0
				local first_pos1; new_fuel_cost = 0

				for i = 1, length_pos1 do
					local node1i_name = node1_name[i]
					if node1i_name then
						if mover_chests[node1i_name] then
							pos1[i] = {}
						else
							local drops

							if prefer == "" then
								drops = add_node_drops(node1i_name, pos2, node1[i])
							elseif prefer == node1i_name then
								local node1i = node1[i]
								local valid, node1i_param2 = check_palette_index(meta, node1i, node_def)
								if valid then
									drops = add_node_drops(node1i_name, pos2, node1i, true, node_def, node1i_param2)
								else
									pos1[i] = {}
								end
							end

							if drops then
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
				for i = 1, length_pos1 do
					local pos1i = pos1[i]
					if pos1i.x then
						check_for_falling(pos1i)
					end
				end
			else
				local dig_up = mover_dig_up_table[node1_name] -- digs up node as a tree
				if dig_up then
					local h, r, d = dig_up.h or 16, dig_up.r or 1, dig_up.d or 0 -- height, radius, depth
					local positions = minetest.find_nodes_in_area(
						{x = pos1.x - r, y = pos1.y - d, z = pos1.z - r},
						{x = pos1.x + r, y = pos1.y + h, z = pos1.z + r},
						node1_name)
					local count = #positions

					if count > 1 then
						local is_protected = minetest.is_protected
						for i = 1, count do
							if is_protected(positions[i], owner) then
								return
							end
						end
					end

					minetest.bulk_set_node(positions, {name = "air"})

					for i = 1, count do
						check_for_falling(positions[i])
					end

					local stack_max, stacks = ItemStack(node1_name):get_stack_max(), {}

					if count > stack_max then
						local stacks_n = count / stack_max
						for i = 1, stacks_n do stacks[i] = stack_max end
						stacks[#stacks + 1] = stacks_n % 1 * stack_max
					else
						stacks[1] = count
					end

					local i, inv = 1, minetest.get_meta(pos2):get_inventory()
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
					local harvest_node1 = mover_harvest_table[node1_name]

					if liquiddef and node1_name == liquiddef.source and liquiddef.itemname then -- put bucket with liquid in chest
						local inv = minetest.get_meta(pos2):get_inventory()
						if inv:contains_item("main", "bucket:bucket_empty") then
							local itemname = liquiddef.itemname
							inv:remove_item("main", "bucket:bucket_empty")
							if inv:room_for_item("main", itemname) then
								inv:add_item("main", itemname)
							else
								minetest.add_item(pos1, itemname)
							end
							-- borrowed and adapted from bucket mod
							-- https://github.com/minetest/minetest_game/tree/master/mods/bucket
							-- GNU Lesser General Public License, version 2.1
							-- Copyright (C) 2011-2016 Kahrl <kahrl@gmx.net>
							-- Copyright (C) 2011-2016 celeron55, Perttu Ahola <celeron55@gmail.com>
							-- Copyright (C) 2011-2016 Various Minetest developers and contributors
							-- force_renew requires a source neighbour
							local source_neighbor = false
							if liquiddef.force_renew then
								source_neighbor = minetest.find_node_near(pos1, 1, liquiddef.source)
							end
							if not (source_neighbor and liquiddef.force_renew) then
								minetest.remove_node(pos1)
							end
							--
						end
					elseif harvest_node1 then -- do we harvest the node ? (if optional mese_crystals mod present)
						local item = harvest_node1[2]
						if item then
							minetest.swap_node(pos1, {name = harvest_node1[1]})
							local inv = minetest.get_meta(pos2):get_inventory()
							if inv:room_for_item("main", item) then
								inv:add_item("main", item)
							else
								minetest.add_item(pos1, item)
							end
						end
					else -- remove node and put drops in chest
						minetest.remove_node(pos1)
						check_for_falling(pos1) -- pre 5.0.0 nodeupdate(pos1)

						add_node_drops(node1_name, pos2, node1, prefer ~= "", node_def, node1_param2)
					end
				end
			end
		elseif node2_name == "air" and not third_upgradetype then -- move node from pos1 to pos2
			minetest.remove_node(pos1)
			check_for_falling(pos1) -- pre 5.0.0 nodeupdate(pos1)

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

basic_machines.add_mover_mode("dig",
	F(S("This will transform blocks as if player dug them\nUpgrade with movers to process additional blocks")),
	F(S("dig")), dig
)