-- rnd 2016
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local craft_recipes = {}
local recipes_order = {}
local recipes_order_translated = {}

local function constructor_update_form(constructor, meta)
	local description = craft_recipes[constructor][meta:get_string("craft")]
	local item

	if description then
		item = description.item
		local i = 0
		local inv = meta:get_inventory() -- set up craft list

		for _, v in ipairs(description.craft) do
			i = i + 1; inv:set_stack("recipe", i, ItemStack(v))
		end

		for j = i + 1, 6 do
			inv:set_stack("recipe", j, ItemStack(""))
		end

		description = description.description
	else
		description, item = "", ""
	end

	meta:set_string("formspec", "formspec_version[4]size[10.45,12.35]" ..
		"style_type[list;spacing=0.25,0.15]" ..
		"textlist[0.35,0.35;3.5,1.7;craft;" .. recipes_order_translated[constructor] .. ";" .. meta:get_int("selected") ..
		"]item_image[4.75,0.35;1,1;" .. item .. "]button[4.6,1.65;1.3,0.8;CRAFT;" .. F(S("CRAFT")) ..
		"]list[context;recipe;6.6,0.35;3,2]" ..
		"label[0.35,2.85;" .. F(description) ..
		"]list[context;main;0.35,3.25;8,3]" ..
		basic_machines.get_form_player_inventory(0.35, 7.3, 8, 4, 0.25) ..
		"listring[context;main]" ..
		"listring[current_player;main]")
end

local function constructor_process(pos, constructor, name)
	local meta = minetest.get_meta(pos)
	local craft = craft_recipes[constructor][meta:get_string("craft")]

	if craft then
		local item = craft.item
		local stack = ItemStack(item)
		local def = minetest.registered_items[stack:get_name()]

		if def then
			local inv = meta:get_inventory()

			if inv:room_for_item("main", stack) then
				if basic_machines.creative(name or "") then
					inv:add_item("main", stack)
				else
					local recipe = craft.craft

					for _, v in ipairs(recipe) do
						if not inv:contains_item("main", ItemStack(v)) then
							meta:set_string("infotext", S("CRAFTING: You need '@1' to craft '@2'", v, item)); return
						end
					end

					for _, v in ipairs(recipe) do
						inv:remove_item("main", ItemStack(v))
					end

					inv:add_item("main", stack)
				end
			end
		end

		if name or meta:get_string("infotext") == "" then
			meta:set_string("infotext", S("CRAFTING: '@1' (@2)",
				def and def.description or S("Unknown item"), item))
		end
	end
end

local function add_constructor(name, items, description, recipe)
	craft_recipes[name] = items.craft_recipes
	recipes_order[name] = items.recipes_order
	recipes_order_translated[name] = table.concat(items.recipes_order_translated, ",")

	minetest.register_node(name, {
		description = description,
		groups = {cracky = 3, constructor = 1},
		tiles = {name:gsub(":", "_") .. ".png"},
		sounds = basic_machines.sound_node_machine(),

		after_place_node = function(pos, placer)
			if not placer then return end

			local meta = minetest.get_meta(pos)
			meta:set_string("infotext",
				S("Constructor: to operate it insert materials, select item to make and click craft button"))
			meta:set_string("owner", placer:get_player_name())

			meta:set_string("craft", items.recipes_order[1])
			meta:set_int("selected", 1)

			local inv = meta:get_inventory()
			inv:set_size("main", 24)
			inv:set_size("recipe", 6)

			constructor_update_form(name, meta)
		end,

		can_dig = function(pos, player) -- main inv must be empty to be dug
			if player then
				local meta = minetest.get_meta(pos)
				return meta:get_inventory():is_empty("main") and meta:get_string("owner") == player:get_player_name()
			else
				return false
			end
		end,

		on_receive_fields = function(pos, _, fields, sender)
			if fields.quit then return end
			local player_name = sender:get_player_name()
			if minetest.is_protected(pos, player_name) then return end

			if fields.CRAFT then
				constructor_process(pos, name, player_name)
			elseif fields.craft then
				if fields.craft:sub(1, 3) == "CHG" then
					local sel = tonumber(fields.craft:sub(5)) or 1
					local meta = minetest.get_meta(pos)

					meta:set_string("infotext", "")
					for i, v in ipairs(recipes_order[name]) do
						if i == sel then meta:set_string("craft", v); break end
					end
					meta:set_int("selected", sel)

					constructor_update_form(name, meta)
				end
			end
		end,

		allow_metadata_inventory_move = function()
			return 0
		end,

		allow_metadata_inventory_put = function(pos, listname, _, stack, player)
			if listname == "recipe" or minetest.is_protected(pos, player:get_player_name()) then
				return 0
			end
			return stack:get_count()
		end,

		allow_metadata_inventory_take = function(pos, listname, _, stack, player)
			if listname == "recipe" or minetest.is_protected(pos, player:get_player_name()) then
				return 0
			end
			return stack:get_count()
		end,

		effector = {
			action_on = function(pos, _)
				constructor_process(pos, name, nil)
			end
		}
	})

	if recipe then
		minetest.register_craft({
			output = name,
			recipe = recipe
		})
	end
end


-- CONSTRUCTOR: used to make all other basic machines
local items = {
	craft_recipes = {
		["Autocrafter"] = {
			item = "basic_machines:autocrafter",
			description = S("Automate crafting"),
			craft = {"default:steel_ingot 5", "default:mese_crystal 2", "default:diamondblock 2"}
		},

		["Ball Spawner"] = {
			item = "basic_machines:ball_spawner",
			description = S("Spawn moving energy balls"),
			craft = {"basic_machines:power_cell", "basic_machines:keypad"}
		},

		["Battery"] = {
			item = "basic_machines:battery_0",
			description = S("Store energy, can power nearby machines"),
			craft = {"default:bronzeblock 2", "default:mese", "default:diamond"}
		},

		["Clock Generator"] = {
			item = "basic_machines:clockgen",
			description = S("For making circuits that run non stop"),
			craft = {"default:diamondblock", "basic_machines:keypad"}
		},

		["Coal Lump"] = {
			item = "default:coal_lump",
			description = S("Coal lump, contains 1 energy unit"),
			craft = {"basic_machines:power_cell 2"}
		},

		["Detector"] = {
			item = "basic_machines:detector",
			description = S("Detect block, player, object, light level..."),
			craft = {"default:mese_crystal 4", "basic_machines:keypad"}
		},

		["Distributor"] = {
			item = "basic_machines:distributor",
			description = S("Organize your circuits better"),
			craft = {"default:steel_ingot", "default:mese_crystal", "basic_machines:keypad"}
		},

		["Environment Changer"] = {
			item = "basic_machines:enviro",
			description = S("Change gravity and more"),
			craft = {"basic_machines:generator 8", "basic_machines:clockgen"}
		},

		["Generator"] = {
			item = "basic_machines:generator",
			description = S("Generate power crystals"),
			craft = {"default:diamondblock 5", "basic_machines:battery_0 5", "default:goldblock 5"}
		},

		["Grinder"] = {
			item = "basic_machines:grinder",
			description = S("Make dusts and grind materials"),
			craft = {"default:diamond 13", "default:mese 4"}
		},

		["Keypad"] = {
			item = "basic_machines:keypad",
			description = S("Activate machines by sending signal"),
			craft = {"default:wood", "default:stick"}
		},

		["Light"] = {
			item = "basic_machines:light_on",
			description = S("Light in darkness"),
			craft = {"default:torch 4"}
		},

		["Mover"] = {
			item = "basic_machines:mover",
			description = S("Universal digging, harvesting, teleporting, transporting machine"),
			craft = {"default:mese_crystal 6", "default:stone 2", "basic_machines:keypad"}
		},

		["Power Block"] = {
			item = "basic_machines:power_block 5",
			description = S("Energy block"),
			craft = {"basic_machines:power_rod"}
		},

		["Power Cell"] = {
			item = "basic_machines:power_cell 5",
			description = S("Energy cell"),
			craft = {"basic_machines:power_block"}
		},

		["Recycler"] = {
			item = "basic_machines:recycler",
			description = S("Recycle old tools"),
			craft = {"default:mese_crystal 8", "default:diamondblock"}
		}
	},
	recipes_order = { -- order in which nodes appear
		"Keypad",
		"Light",
		"Grinder",
		"Mover",
		"Battery",
		"Generator",
		"Detector",
		"Distributor",
		"Clock Generator",
		"Recycler",
		"Autocrafter",
		"Ball Spawner",
		"Environment Changer",
		"Power Block",
		"Power Cell",
		"Coal Lump"
	},
	recipes_order_translated = { -- for translation
		F(S("Keypad")), F(S("Light")), F(S("Grinder")), F(S("Mover")), F(S("Battery")),
		F(S("Generator")), F(S("Detector")), F(S("Distributor")), F(S("Clock Generator")),
		F(S("Recycler")), F(S("Autocrafter")), F(S("Ball Spawner")), F(S("Environment Changer")),
		F(S("Power Block")), F(S("Power Cell")), F(S("Coal Lump"))
	}
}

if minetest.global_exists("mesecon") then -- add mesecon adapter
	items.craft_recipes["Mesecon Adapter"] = {
		item = "basic_machines:mesecon_adapter",
		description = S("Interface between machines and mesecons"),
		craft = {"default:mese_crystal_fragment"}
	}
	items.recipes_order[#items.recipes_order + 1] = "Mesecon Adapter"
	items.recipes_order_translated[#items.recipes_order_translated + 1] = F(S("Mesecon Adapter"))
end

local recipe

if basic_machines.use_default then
	recipe = {
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
		{"default:steel_ingot", "default:copperblock", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"}
	}
end

add_constructor("basic_machines:constructor", items, S("Constructor"), recipe)