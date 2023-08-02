-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local mover_chests = basic_machines.get_mover("chests")
local check_palette_index = basic_machines.check_palette_index

local function transport(pos, meta, owner, prefer, pos1, node1, node1_name, source_chest, pos2)
	prefer = prefer or meta:get_string("prefer")

	-- checks
	if prefer ~= "" then -- filter check
		if prefer == node1_name then -- only take preferred node
			local node_def = minetest.registered_nodes[prefer]
			if node_def then
				if not check_palette_index(meta, node1, node_def) then -- only take preferred node with palette_index
					return
				end
			else -- (see basic_machines.check_mover_filter)
				minetest.chat_send_player(owner, S("MOVER: Filter defined with unknown node (@1) at @2, @3, @4.",
					prefer, pos.x, pos.y, pos.z)); return
			end
		else
			return
		end
	end

	source_chest = source_chest or mover_chests[node1_name]
	local node2_name = minetest.get_node(pos2).name

	-- transport items
	if source_chest and mover_chests[node2_name] then -- transport all chest items from source to target
		if prefer == node2_name then -- transport only with same chest type
			local inv2 = minetest.get_meta(pos2):get_inventory()
			if inv2:is_empty("main") then
				local inv1 = minetest.get_meta(pos1):get_inventory()
				if inv1:is_empty("main") then return end
				inv2:set_list("main", inv1:get_list("main"))
				inv1:set_list("main", {})
			else
				return
			end
		else
			return
		end
	elseif node2_name == "air" then -- transport nodes parallel as defined by source1 and target, clone with complete metadata
		local meta1 = minetest.get_meta(pos1):to_table()
		minetest.set_node(pos2, node1)
		if meta1 then minetest.get_meta(pos2):from_table(meta1) end
		minetest.set_node(pos1, {name = "air"})
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

basic_machines.add_mover_mode("transport",
	F(S("This will move all blocks at source area to new area starting at target position\nThis mode preserves all inventories and other metadata\n" ..
		"Make chest items transport: define the filter with the needed type of chest")),
	F(S("transport")), transport
)