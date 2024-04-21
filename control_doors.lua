-- Make doors open/close with signal
-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

-- local S = basic_machines.S
local use_doors = minetest.global_exists("doors")
local use_xpanes = minetest.get_modpath("xpanes")

local function door_signal_overwrite(name)
	local def = minetest.registered_nodes[name]
	if not def or def.effector or def.mesecons then return end -- already exists, don't change

	local door_on_rightclick = def.on_rightclick
	if door_on_rightclick then -- safety if it doesn't exist
		minetest.override_item(name, {
			effector = {
				action_on = function(pos, _)
					-- create virtual player
					local clicker = {
						get_wielded_item = function() return ItemStack("") end,
						-- method needed for mods that check this: like denaid areas mod
						is_player = function() return true end,
						-- define method get_player_name() returning owner name so that we can call on_rightclick function in door
						get_player_name = function() return minetest.get_meta(pos):get_string("owner") end
					}
					door_on_rightclick(pos, nil, clicker, ItemStack(""), {})
					-- more direct approach ?, need to set param2 then too
					-- minetest.swap_node(pos, {name = "protector:trapdoor", param1 = node.param1, param2 = node.param2})
				end
			}
		})
	end
end

local function make_it_noclip(name)
	minetest.override_item(name, {walkable = false}) -- can't be walked on
end

-- doors
local doors = {}

-- cool_trees
if minetest.global_exists("birch") then
	table.insert(doors, "doors:door_birch_wood")
end

if minetest.get_modpath("chestnuttree") then
	table.insert(doors, "doors:door_chestnut_wood")
end

if minetest.get_modpath("clementinetree") then
	table.insert(doors, "doors:door_clementinetree_wood")
end

if minetest.get_modpath("larch") then
	table.insert(doors, "doors:door_larch_wood")
end

if minetest.get_modpath("maple") then
	table.insert(doors, "doors:door_maple_wood")
end

if minetest.get_modpath("oak") then
	table.insert(doors, "doors:door_oak_wood")
end

if minetest.get_modpath("palm") then
	table.insert(doors, "doors:door_palm")
end
--

if use_doors then
	table.insert(doors, "doors:door_glass")
	table.insert(doors, "doors:door_obsidian_glass")
	table.insert(doors, "doors:door_steel")
	table.insert(doors, "doors:door_wood")
end

if minetest.get_modpath("extra_doors") then
	table.insert(doors, "doors:door_barn1")
	table.insert(doors, "doors:door_barn2")
	table.insert(doors, "doors:door_castle1")
	table.insert(doors, "doors:door_castle2")
	table.insert(doors, "doors:door_cottage1")
	table.insert(doors, "doors:door_cottage2")
	table.insert(doors, "doors:door_dungeon1")
	table.insert(doors, "doors:door_dungeon2")
	table.insert(doors, "doors:door_french")
	table.insert(doors, "doors:door_japanese")
	table.insert(doors, "doors:door_mansion1")
	table.insert(doors, "doors:door_mansion2")
	table.insert(doors, "doors:door_steelglass1")
	table.insert(doors, "doors:door_steelglass2")
	table.insert(doors, "doors:door_steelpanel1")
	table.insert(doors, "doors:door_woodglass1")
	table.insert(doors, "doors:door_woodglass2")
	table.insert(doors, "doors:door_woodpanel1")
end

if minetest.global_exists("xdecor") then
	table.insert(doors, "doors:japanese_door")
	table.insert(doors, "doors:prison_door")
	table.insert(doors, "doors:rusty_prison_door")
	table.insert(doors, "doors:screen_door")
	table.insert(doors, "doors:slide_door")
	table.insert(doors, "doors:woodglass_door")
end

if use_xpanes then
	table.insert(doors, "xpanes:door_steel_bar")
end

for _, door in ipairs(doors) do
	door_signal_overwrite(door .. "_a")
	door_signal_overwrite(door .. "_b")
	door_signal_overwrite(door .. "_c")
	door_signal_overwrite(door .. "_d")
end

-- trapdoors
local trapdoors = {}

if use_doors then
	table.insert(trapdoors, "doors:trapdoor")
	table.insert(trapdoors, "doors:trapdoor_steel")
end

if use_xpanes then
	table.insert(trapdoors, "xpanes:trapdoor_steel_bar")
end

for _, trapdoor in ipairs(trapdoors) do
	door_signal_overwrite(trapdoor)
	door_signal_overwrite(trapdoor .. "_open")
	make_it_noclip(trapdoor .. "_open")
end
--[[
if use_doors then
	local function make_it_nondiggable_but_removable(name, dropname, door)
		minetest.override_item(name, {
			diggable = false,
			on_punch = function(pos, _, puncher) -- remove node if owner repeatedly punches it 3x
				local player_name = puncher:get_player_name()
				local meta = minetest.get_meta(pos)
				-- can be dug by owner or if unprotected
				if player_name == meta:get_string("owner") or not minetest.is_protected(pos, player_name) then
					local t0, t = meta:get_int("punchtime"), minetest.get_gametime()
					local count = meta:get_int("punchcount")

					if t - t0 < 2 then count = (count + 1) % 3 else count = 0 end
					meta:set_int("punchtime", t); meta:set_int("punchcount", count)

					if count == 1 then
						minetest.chat_send_player(player_name, S("@1: Punch me one more time to remove me", door))
					elseif count == 2 then -- remove steel door and drop it
						minetest.remove_node(pos)
						minetest.add_item(pos, ItemStack(dropname))
					end
				end
			end
		})
	end

	local impervious_steel = {
		{"doors:door_steel_a", "doors:door_steel", S("Steel Door")},
		{"doors:door_steel_b", "doors:door_steel", S("Steel Door")},
		{"doors:door_steel_c", "doors:door_steel", S("Steel Door")},
		{"doors:door_steel_d", "doors:door_steel", S("Steel Door")},
		{"doors:trapdoor_steel", "doors:trapdoor_steel", S("Steel Trapdoor")},
		{"doors:trapdoor_steel_open", "doors:trapdoor_steel", S("Steel Trapdoor")}
	}

	for _, door in ipairs(impervious_steel) do
		make_it_nondiggable_but_removable(door[1], door[2], door[3])
	end
end
--]]