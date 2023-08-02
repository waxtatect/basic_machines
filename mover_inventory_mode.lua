-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local mover_limit_inventory_table = basic_machines.get_mover("limit_inventory_table")
local get_palette_index = basic_machines.get_palette_index

local function inventory(_, meta, _, prefer, pos1, _, node1_name, _, pos2, mreverse, _, upgrade)
	local invName1, invName2

	if mreverse == 1 then -- reverse inventory names too
		invName1, invName2 = meta:get_string("inv2"), meta:get_string("inv1")
	else
		invName1, invName2 = meta:get_string("inv1"), meta:get_string("inv2")
	end

	-- checks
	local limit_inventory = mover_limit_inventory_table[node1_name]
	if limit_inventory then
		if limit_inventory == true or limit_inventory[invName1] then -- forbid to take from this inventory or list
			return
		end
	end

	prefer = prefer or meta:get_string("prefer")
	local stack, inv1, item_found

	-- inventory move
	if prefer ~= "" then -- pick preferred items to transfer
		if upgrade == -1 then -- free items for admin
			stack = ItemStack(prefer)

			local palette_index = get_palette_index(meta:get_inventory():get_stack("filter", 1))
			if palette_index then
				stack:get_meta():set_int("palette_index", palette_index)
			end
		else
			inv1 = minetest.get_meta(pos1):get_inventory()

			if inv1:is_empty(invName1) then -- nothing to move
				return
			end

			stack = ItemStack(prefer)

			if inv1:contains_item(invName1, stack) then
				item_found = true
			end
		end
	else -- just pick one item to transfer
		inv1 = minetest.get_meta(pos1):get_inventory()

		if inv1:is_empty(invName1) then -- nothing to move
			return
		end

		local i = 1
		while i <= inv1:get_size(invName1) do -- find items to move
			stack = inv1:get_stack(invName1, i)
			if stack:is_empty() then i = i + 1 else item_found = true; break end
		end
	end

	if item_found then -- can we move the item to target inventory ?
		local inv2 = minetest.get_meta(pos2):get_inventory()
		if inv2:room_for_item(invName2, stack) then
			inv2:add_item(invName2, inv1:remove_item(invName1, stack))
		else
			return
		end
	elseif upgrade == -1 and minetest.registered_items[stack:get_name()] then -- admin, just add stuff
		local inv2, stack_set = minetest.get_meta(pos2):get_inventory()
		for i = 1, inv2:get_size(invName2) do -- try to find an empty stack to add the new stack
			if inv2:get_stack(invName2, i):is_empty() then
				inv2:set_stack(invName2, i, stack); stack_set = true; break
			end
		end
		if not stack_set then
			return
		end
	else -- nothing to do
		return
	end

	-- play sound
	local activation_count = meta:get_int("activation_count")
	-- if activation_count < 16 then
		-- minetest.sound_play("basic_machines_inventory_move", {pos = pos2, gain = 1, max_hear_distance = 8}, true)
	-- end

	return activation_count
end

basic_machines.add_mover_mode("inventory",
	F(S("This will move items from inventory of any block at source position to any inventory of block at target position")),
	F(S("inventory")), inventory
)