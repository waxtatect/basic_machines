-- Modified and adapted from pipeworks mod by VanessaE
-- https://github.com/mt-mods/pipeworks
-- by rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

-- Disabled timers and on/off button, now autocrafter is only activated by signal

local S = basic_machines.S
-- caches some recipe data to avoid to call the slow function minetest.get_craft_result() every second
local autocrafterCache = {}

local function autocrafter_update_form(meta)
	meta:set_string("formspec",	table.concat({
		"formspec_version[4]size[10.45,13.35]",
		"style_type[list;spacing=0.25,0.15]",
		"list[context;recipe;0.35,0.35;3,3]",
		"image[4.1,1.5;1,1;[combine:1x1^[noalpha^[colorize:#141318]",
		"list[context;output;4.1,1.5;1,1]",
		"list[context;dst;5.35,0.35;4,3]",
		"list[context;src;0.35,4.25;8,3]",
		basic_machines.get_form_player_inventory(0.35, 8.3, 8, 4, 0.25),
		"listring[context;dst]",
		"listring[current_player;main]",
		"listring[context;src]",
		"listring[current_player;main]",
		"listring[context;recipe]",
		"listring[current_player;main]"}))
end

local function count_index(invlist)
	local index = {}
	for _, stack in pairs(invlist) do
		if not stack:is_empty() then
			local stack_name = stack:get_name()
			index[stack_name] = (index[stack_name] or 0) + stack:get_count()
		end
	end
	return index
end

local function get_craft(pos, inventory, hash)
	hash = hash or minetest.hash_node_position(pos)
	local craft = autocrafterCache[hash]
	if craft then return craft end
	local recipe = inventory:get_list("recipe")
	local output, decremented_input = minetest.get_craft_result({method = "normal", width = 3, items = recipe})
	craft = {recipe = recipe, consumption = count_index(recipe), output = output, decremented_input = decremented_input}
	autocrafterCache[hash] = craft
	return craft
end

local function get_item_info(stack)
	local name = stack:get_name()
	local def = minetest.registered_items[name ~= "" and name or nil]
	local description = def and def.description or S("Unknown item")
	return description, name
end

local function after_recipe_change(pos, inventory)
	-- if we emptied the grid, there's no point in keeping it running or cached
	if inventory:is_empty("recipe") then
		autocrafterCache[minetest.hash_node_position(pos)] = nil
		minetest.get_meta(pos):set_string("infotext", S("Unconfigured autocrafter"))
		inventory:set_stack("output", 1, ItemStack(""))
	else
		local hash = minetest.hash_node_position(pos)
		autocrafterCache[hash] = nil
		local output_item = get_craft(pos, inventory, hash).output.item
		local description, name = get_item_info(output_item)
		minetest.get_meta(pos):set_string("infotext", S("Autocrafter: '@1' (@2)", description, name))
		inventory:set_stack("output", 1, output_item)
	end
end

-- clean out unknown items and groups
local function normalize(items_list)
	for i, item in pairs(items_list) do
		if not minetest.registered_items[item] then -- ItemStack(item):get_name(), for items with count > 1
			items_list[i] = ItemStack("")
		end
	end
	return items_list
end

local function on_output_change(pos, inventory, stack, index)
	if stack then
		local recipe
		if index then
			recipe = minetest.get_all_craft_recipes(stack:get_name())
			recipe = (recipe or {})[index] or {}
		else
			recipe = minetest.get_craft_recipe(stack:get_name())
		end
		if not recipe.items or recipe.type ~= "normal" then return end
		local items, width = normalize(recipe.items), recipe.width
		if width == 0 then -- shapeless recipe
			inventory:set_list("recipe", items)
		else
			local item_idx, width_idx = 1, 1
			for i = 1, 9 do
				if width_idx <= width then
					inventory:set_stack("recipe", i, items[item_idx])
					item_idx = item_idx + 1
				else
					inventory:set_stack("recipe", i, ItemStack(""))
				end
				width_idx = (width_idx < 3) and (width_idx + 1) or 1
			end
		end
	else
		inventory:set_list("recipe", {})
	end
	after_recipe_change(pos, inventory)
end

basic_machines.change_autocrafter_recipe = on_output_change

local function autocraft(inventory, craft)
	if not craft then return end

	local consumption = craft.consumption

	-- check if we have enough material available
	local inv_items = count_index(inventory:get_list("src"))
	for itemname, number in pairs(consumption) do
		local itemcount = inv_items[itemname]
		if not itemcount or itemcount < number then return end
	end

	local output = craft.output.item
	local decremented_input_items = craft.decremented_input.items -- replacements

	-- check if output and all replacements fit in dst
	local out_items = count_index(decremented_input_items)
	local output_name = output:get_name()
	out_items[output_name] = (out_items[output_name] or 0) + output:get_count()
	local empty_count = 0

	for _, item in pairs(inventory:get_list("dst")) do
		if item:is_empty() then
			empty_count = empty_count + 1
		else
			local name = item:get_name()
			if out_items[name] then
				out_items[name] = out_items[name] - item:get_free_space()
			end
		end
	end

	for _, count in pairs(out_items) do
		if count > 0 then
			empty_count = empty_count - 1
		end
	end

	if empty_count < 0 then return end

	-- consume material
	for itemname, number in pairs(consumption) do
		for _ = 1, number do -- we have to do that since remove_item does not work if count > stack_max
			inventory:remove_item("src", ItemStack(itemname))
		end
	end

	-- craft the result into the dst inventory and add any "replacements" as well
	inventory:add_item("dst", output)
	for i = 1, 9 do
		inventory:add_item("dst", decremented_input_items[i])
	end
end

minetest.register_node("basic_machines:autocrafter", {
	description = S("Autocrafter"),
	groups = {cracky = 3},
	drawtype = "normal",
	tiles = {"basic_machines_autocrafter.png"},
	sounds = basic_machines.sound_node_machine(),

	on_destruct = function(pos)
		autocrafterCache[minetest.hash_node_position(pos)] = nil
	end,

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Unconfigured autocrafter: Place items for recipe top left." ..
			" To operate place required items in bottom space (src inventory) and activate with signal." ..
			" Obtain crafted item from top right (dst inventory)."))
		meta:set_string("owner", placer:get_player_name())

		local inv = meta:get_inventory()
		inv:set_size("src", 3 * 8)
		inv:set_size("recipe", 3 * 3)
		inv:set_size("dst", 4 * 3)
		inv:set_size("output", 1)

		autocrafter_update_form(meta)
	end,

	can_dig = function(pos, player)
		if player then
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()

			return meta:get_string("owner") == player:get_player_name() and
				inv:is_empty("src") and inv:is_empty("dst")
		else
			return false
		end
	end,

	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end

		if to_list == "recipe" or from_list == "recipe" then
			local inv = minetest.get_meta(pos):get_inventory()
			if to_list == "recipe" then
				local stack = inv:get_stack(from_list, from_index)
				stack:set_count(1)
				inv:set_stack(to_list, to_index, stack)
			elseif from_list == "recipe" then
				inv:set_stack(from_list, from_index, ItemStack(""))
			end
			after_recipe_change(pos, inv)
			return 0
		elseif to_list == "output" or from_list == "output" then
			local inv = minetest.get_meta(pos):get_inventory()
			if to_list == "output" then
				local stack = inv:get_stack(from_list, from_index)
				on_output_change(pos, inv, stack)
				return 0
			elseif from_list == "output" then
				on_output_change(pos, inv, nil)
				if to_list ~= "recipe" then return 0 end
			end
		end

		return count
	end,

	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end

		if listname == "recipe" or listname == "output" then
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()

			if listname == "recipe" then
				stack:set_count(1)
				inv:set_stack(listname, index, stack)
				after_recipe_change(pos, inv)
				autocrafter_update_form(meta)
			elseif listname == "output" then
				on_output_change(pos, inv, stack)
				autocrafter_update_form(meta)
			end

			return 0
		end

		return stack:get_count()
	end,

	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end

		if listname == "recipe" or listname == "output" then
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()

			if listname == "recipe" then
				inv:set_stack(listname, index, ItemStack(""))
				after_recipe_change(pos, inv)
				autocrafter_update_form(meta)
			elseif listname == "output" then
				on_output_change(pos, inv, nil)
				autocrafter_update_form(meta)
			end

			return 0
		end

		return stack:get_count()
	end,

	effector = { -- rnd: run machine when activated by signal
		action_on = function(pos, _)
			local meta = minetest.get_meta(pos)
			local inventory = meta:get_inventory()
			local craft = get_craft(pos, inventory, nil)
			local output_item = craft.output.item
			-- only use crafts that have an actual result
			if output_item:is_empty() then
				meta:set_string("infotext", S("Unconfigured autocrafter: Unknown recipe")); return
			end

			autocraft(inventory, craft)
		end
	}
})

if basic_machines.settings.register_crafts and basic_machines.use_default then
	minetest.register_craft({
		output = "basic_machines:autocrafter",
		recipe = {
			{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
			{"default:diamondblock", "default:steel_ingot", "default:diamondblock"},
			{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"}
		}
	})
end