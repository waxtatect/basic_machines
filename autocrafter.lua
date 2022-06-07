-- Modified and adapted from pipeworks mod by VanessaE
-- by rnd
-- Disabled timers and on/off button, now autocrafter is only activated by signal

local S = basic_machines.S
-- caches some recipe data to avoid to call the slow function minetest.get_craft_result() every second
local autocrafterCache = {}
local craft_time = 1

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

local function get_item_info(stack)
	local name = stack:get_name()
	local def = minetest.registered_items[name ~= "" and name or nil]
	local description = def and def.description or S("Unknown item")
	return description, name
end

local function get_craft(pos, inventory, hash)
	local hash_number = hash or minetest.hash_node_position(pos)
	local craft = autocrafterCache[hash_number]
	if not craft then
		local recipe = inventory:get_list("recipe")
		local output, decremented_input = minetest.get_craft_result({method = "normal", width = 3, items = recipe})
		craft = {recipe = recipe, consumption = count_index(recipe), output = output, decremented_input = decremented_input}
		autocrafterCache[hash_number] = craft
	end
	return craft
end

local function autocraft(inventory, craft)
	if not craft then return false end
	local output_item = craft.output.item

	-- check if we have enough room in dst
	if not inventory:room_for_item("dst", output_item) then	return false end
	local consumption = craft.consumption
	local inv_index = count_index(inventory:get_list("src"))
	-- check if we have enough material available
	for itemname, number in pairs(consumption) do
		if (not inv_index[itemname]) or inv_index[itemname] < number then return false end
	end
	-- consume material
	for itemname, number in pairs(consumption) do
		for _ = 1, number do -- we have to do that since remove_item does not work if count > stack_max
			inventory:remove_item("src", ItemStack(itemname))
		end
	end

	-- craft the result into the dst inventory and add any "replacements" as well
	inventory:add_item("dst", output_item)
	for i = 1, 9 do
		inventory:add_item("dst", craft.decremented_input.items[i])
	end
	return true
end

-- returns false to stop the timer, true to continue running
-- is started only from start_autocrafter(pos) after sanity checks and cached recipe
local function run_autocrafter(pos, elapsed)
	local meta = minetest.get_meta(pos)
	local inventory = meta:get_inventory()
	local craft = get_craft(pos, inventory, nil)
	local output_item = craft.output.item
	-- only use crafts that have an actual result
	if output_item:is_empty() then
		meta:set_string("infotext", S("Unconfigured autocrafter: unknown recipe"))
		return false
	end

	for _ = 1, math.floor(elapsed / craft_time) do
		if not autocraft(inventory, craft) then return false end -- continue ?
	end
	return true
end
--[[
local function start_crafter(pos) -- rnd we don't need timer anymore
	local meta = minetest.get_meta(pos)
	if meta:get_int("enabled") == 1 then
		local timer = minetest.get_node_timer(pos)
		if not timer:is_started() then
			timer:start(craft_time)
		end
	end
end

local function after_inventory_change(pos)
	start_crafter(pos)
end
--]]
-- note, that this function assumes already being updated to virtual items
-- and doesn't handle recipes with stacksizes > 1
local function after_recipe_change(pos, inventory)
	local meta = minetest.get_meta(pos)
	-- if we emptied the grid, there's no point in keeping it running or cached
	if inventory:is_empty("recipe") then
		-- minetest.get_node_timer(pos):stop()
		autocrafterCache[minetest.hash_node_position(pos)] = nil
		meta:set_string("infotext", S("Unconfigured autocrafter"))
		inventory:set_stack("output", 1, "")
		return
	end

	local recipe = inventory:get_list("recipe")
	local hash = minetest.hash_node_position(pos)
	local craft = autocrafterCache[hash]

	if craft then
		-- check if it changed
		local cached_recipe = craft.recipe
		for i = 1, 9 do
			if recipe[i]:get_name() ~= cached_recipe[i]:get_name() then
				autocrafterCache[hash] = nil -- invalidate recipe
				craft = nil
				break
			end
		end
	end

	craft = craft or get_craft(pos, inventory, hash)
	local output_item = craft.output.item
	local description, name = get_item_info(output_item)
	meta:set_string("infotext", S("Autocrafter: '@1' (@2)", description, name))
	inventory:set_stack("output", 1, output_item)

	-- after_inventory_change(pos)
end

-- clean out unknown items and groups
local function normalize(item_list)
	for i, item in pairs(item_list) do
		if not minetest.registered_items[item] then
			item_list[i] = ""
		end
	end
	return item_list
end

local function on_output_change(pos, inventory, stack)
	if not stack then
		inventory:set_stack("output", 1, ItemStack(""))
		-- inventory:set_list("output", {}) -- using saved map, it crashes the server... but why
		inventory:set_list("recipe", {})
	else
		local input = minetest.get_craft_recipe(stack:get_name())
		if not input.items or input.type ~= "normal" then return end
		local items, width = normalize(input.items), input.width
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
		-- we'll set the output slot in after_recipe_change to the actual result of the new recipe
	end
	after_recipe_change(pos, inventory)
end

-- returns false if we shouldn't bother attempting to start the timer again after this
local function autocrafter_update_form(meta) -- , enabled)
	-- local state = enabled and "on" or "off"
	-- meta:set_int("enabled", enabled and 1 or 0)
	meta:set_string("formspec",	"size[8,11.25]" ..
		"list[context;recipe;0,0;3,3;]" ..
		"image[3,1;1,1;gui_hb_bg.png^[colorize:#141318:255]" ..
		"list[context;output;3,1;1,1;]" ..
		-- rnd disable button
		-- "image_button[3,2;1,0.6;pipeworks_button_" .. state .. ".png;" .. state ..
		-- ";;;false;pipeworks_button_interm.png]" ..
		"list[context;src;0,3.5;8,3;]" ..
		"list[context;dst;4,0;4,3;]" ..
		"list[current_player;main;0,7;8,1;]" ..
		"list[current_player;main;0,8.25;8,3;8]" ..
		"listring[context;dst]" ..
		"listring[current_player;main]" ..
		"listring[context;src]" ..
		"listring[current_player;main]" ..
		"listring[context;recipe]" ..
		"listring[current_player;main]" ..
		default.get_hotbar_bg(0, 7))

	-- toggling the button doesn't quite call for running a recipe change check
	-- so instead we run a minimal version for infotext setting only
	-- this might be more written code, but actually executes less
	-- local output = meta:get_inventory():get_stack("output", 1)
	-- if output:is_empty() then -- doesn't matter if paused or not
		-- return false
	-- end
	--[[
	local description, name = get_item_info(output)
	local infotext = enabled and S("Autocrafter: '@1' (@2)", description, name)
		or ("paused '%s' Autocrafter"):format(description)

	meta:set_string("infotext", infotext)
	return enabled
	--]]
end
--[[
-- 1st version of the autocrafter had actual items in the crafting grid
-- the 2nd replaced these with virtual items, dropped the content on update and set "virtual_items" to string "1"
-- the third added an output inventory, changed the formspec and added a button for enabling/disabling
-- so we work out way backwards on this history and update each single case to the newest version
local function upgrade_autocrafter(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	if inv:get_size("output") == 0 then -- we are version 2 or 1
		inv:set_size("output", 1)
		-- migrate the old autocrafters into an "enabled" state
		autocrafter_update_form(meta, true)

		if meta:get_string("virtual_items") == "1" then -- we are version 2
			-- we already dropped stuff, so lets remove the metadata setting (we are not being called again for this node)
			meta:set_string("virtual_items", "")
		else -- we are version 1
			local recipe = inv:get_list("recipe")
			if not recipe then return end
			for idx, stack in ipairs(recipe) do
				if not stack:is_empty() then
					minetest.add_item(pos, stack)
					stack:set_count(1)
					stack:set_wear(0)
					inv:set_stack("recipe", idx, stack)
				end
			end
		end

		-- update the recipe, cache, and start the crafter
		autocrafterCache[minetest.hash_node_position(pos)] = nil
		after_recipe_change(pos, inv)
	end
end
--]]
minetest.register_node("basic_machines:autocrafter", {
	description = S("Autocrafter"),
	groups = {cracky = 3},
	drawtype = "normal",
	tiles = {"basic_machines_autocrafter.png"},

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
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()

		return meta:get_string("owner") == player:get_player_name() and
			inv:is_empty("src") and inv:is_empty("dst")
	end,
--[[
	after_place_node = pipeworks.scan_for_tube_objects,

	after_dig_node = function(pos)
		pipeworks.scan_for_tube_objects(pos)
	end,

	on_timer = run_autocrafter, -- rnd

	on_receive_fields = function(pos, formname, fields, sender)
		-- if not pipeworks.may_configure(pos, sender) then return end
		local meta = minetest.get_meta(pos)
		if fields.on then
			autocrafter_update_form(meta, false)
			-- minetest.get_node_timer(pos):stop()
		elseif fields.off then
			if autocrafter_update_form(meta, true) then
				start_crafter(pos)
			end
		end
	end,
--]]
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		-- if not pipeworks.may_configure(pos, player) then return 0 end
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end

		-- upgrade_autocrafter(pos)
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

		-- after_inventory_change(pos)
		return count
	end,

	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		-- if not pipeworks.may_configure(pos, player) then return 0 end
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end

		-- upgrade_autocrafter(pos)
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

		-- after_inventory_change(pos)
		return stack:get_count()
	end,

	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		--[[
		if not pipeworks.may_configure(pos, player) then
			minetest.log("action", ("%s attempted to take from autocrafter at %s"):format(player:get_player_name(),
				minetest.pos_to_string(pos)))
			return 0
		end
		--]]
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end

		-- upgrade_autocrafter(pos)
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

		-- after_inventory_change(pos)
		return stack:get_count()
	end,

	effector = { -- rnd: run machine when activated by signal
		action_on = function(pos, _)
			run_autocrafter(pos, craft_time)
		end
	}
})

if basic_machines.settings.register_crafts then
	minetest.register_craft({
		output = "basic_machines:autocrafter",
		recipe = {
			{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
			{"default:diamondblock", "default:steel_ingot", "default:diamondblock"},
			{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"}
		}
	})
end