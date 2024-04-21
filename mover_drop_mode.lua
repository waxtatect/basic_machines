-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local mover_bonemeal_table = basic_machines.get_mover("bonemeal_table")
local mover_chests = basic_machines.get_mover("chests")
local check_palette_index = basic_machines.check_palette_index
local node_to_stack = basic_machines.node_to_stack
local vplayer = {}

minetest.register_on_leaveplayer(function(player)
	vplayer[player:get_player_name()] = nil
end)

local function create_virtual_player(name)
	return {is_player = function() return true end,
		get_player_name = function() return name end,
		get_player_control = function() return {} end}
end

local function drop(_, meta, owner, prefer, pos1, node1, node1_name, source_chest, pos2, mreverse)
	prefer = prefer or meta:get_string("prefer")
	source_chest = source_chest or mover_chests[node1_name]
	local bonemeal, node1_param2

	-- checks
	if prefer ~= "" then -- filter check
		if source_chest then
			if mreverse == 1 then
				bonemeal = mover_bonemeal_table[prefer]
			end
		elseif prefer == node1_name then -- only take preferred node
			local valid
			valid, node1_param2 = check_palette_index(meta, node1) -- only take preferred node with palette_index
			if not valid then
				return
			end
		else
			return
		end
	elseif source_chest then -- prefer == "", doesn't know what to take out of chest
		return
	end

	-- drop items
	if source_chest then -- take items from chest (filter needed)
		if bonemeal then -- use bonemeal
			local stack = ItemStack(prefer)

			local inv = minetest.get_meta(pos1):get_inventory()
			if inv:contains_item("main", stack) then
				inv:remove_item("main", stack)
			else
				return
			end

			local on_use = (minetest.registered_items[prefer] or {}).on_use
			if on_use then
				vplayer[owner] = vplayer[owner] or create_virtual_player(owner)
				local itemstack = on_use(ItemStack(prefer .. " 2"),
					vplayer[owner], {type = "node",	under = pos2,
					above = {x = pos2.x, y = pos2.y + 1, z = pos2.z}})
				bonemeal = itemstack and itemstack:get_count() == 1 or
					basic_machines.creative(owner)
				if not bonemeal then -- bonemeal not used, drop it
					minetest.add_item(pos2, stack)
				end
			else
				return
			end
		elseif minetest.get_node(pos2).name == "air" then -- drop items
			local stack, removed_items = ItemStack(prefer)

			local inv = minetest.get_meta(pos1):get_inventory()
			if inv:contains_item("main", stack) then
				if (stack:to_table() or {}).metadata == "" then
					removed_items = inv:remove_item("main", stack)
				else
					inv:remove_item("main", stack)
				end
			elseif prefer == node1_name and inv:is_empty("main") then -- remove chest only if empty
				minetest.remove_node(pos1)
			else
				return
			end

			minetest.add_item(pos2, removed_items or stack)
		else -- nothing to do
			return
		end
	elseif minetest.get_node(pos2).name == "air" then -- drop node
		minetest.remove_node(pos1)

		if prefer ~= "" then
			minetest.add_item(pos2, node_to_stack(node1, nil, node1_param2))
		else -- without filter
			local paramtype2 = (minetest.registered_nodes[node1.name] or {}).paramtype2
			minetest.add_item(pos2, node_to_stack(node1, paramtype2))
		end
	else -- nothing to do
		return
	end

	-- play sound
	local activation_count = meta:get_int("activation_count")
	-- if activation_count < 16 then
		-- minetest.sound_play("basic_machines_transport", {pos = pos2, gain = 1, max_hear_distance = 8}, true)
	-- end

	return activation_count
end

basic_machines.add_mover_mode("drop",
	F(S("This will take block/item out of chest (you need to set filter) and will drop it")),
	F(S("drop")), drop
)