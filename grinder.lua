-- There is a certain fuel cost to operate

local F, S = basic_machines.F, basic_machines.S
local grinder_dusts_legacy = basic_machines.settings.grinder_dusts_legacy
local machines_minstep = basic_machines.properties.machines_minstep
local twodigits_float = basic_machines.twodigits_float
local use_unified_inventory = minetest.global_exists("unified_inventory")
local use_i3 = minetest.global_exists("i3")
-- grinder recipes:
-- ["in"] = {fuel cost, "out", quantity of material produced, quantity of material required for processing}
local grinder_recipes = {}
local grinder_recipes_translated, grinder_recipes_help = {S("RECIPES\n")}, nil

if use_unified_inventory then
	unified_inventory.register_craft_type("basic_machines_grinding", {
		description = F(S("Grinding")),
		icon = "basic_machines_grinder.png",
		width = 1,
		height = 1
	})
elseif use_i3 then
	i3.register_craft_type("basic_machines_grinding", {
		description = F(S("Grinding")),
		icon = "basic_machines_grinder.png"
	})
end

local function register_recipe(name, def)
	local is_recipe = grinder_recipes[name] ~= nil
	grinder_recipes[name] = def

	if def then
		local i = #grinder_recipes_translated + 1
		if def[4] ~= 1 and def[3] ~= 1 then
			grinder_recipes_translated[i] = S("IN(@1): @2\nOUT(@3): @4\n", def[4], name, def[3], def[2])
		elseif def[3] ~= 1 then
			grinder_recipes_translated[i] = S("IN: @1\nOUT(@2): @3\n", name, def[3], def[2])
		elseif def[4] ~= 1 then
			grinder_recipes_translated[i] = S("IN(@1): @2\nOUT: @3\n", def[4], name, def[2])
		else
			grinder_recipes_translated[i] = S("IN: @1\nOUT: @2\n", name, def[2])
		end

		if grinder_recipes_help == nil then
			if use_unified_inventory then
				unified_inventory.register_craft({
					output = def[2] .. " " .. def[3],
					type = "basic_machines_grinding",
					items = {name .. " " .. def[4]},
					width = 0
				})
			elseif use_i3 then
				i3.register_craft({
					type = "basic_machines_grinding",
					result = def[2] .. " " .. def[3],
					items = {name .. " " .. def[4]}
				})
			end
		end
	end

	if grinder_recipes_help ~= nil then
		if is_recipe then
			for i = 2, #grinder_recipes_translated do
				if grinder_recipes_translated[i]:match("IN.-(" .. name .. ").-OUT") then
					table.remove(grinder_recipes_translated, i); break
				end
			end
		end
		grinder_recipes_help = F(table.concat(grinder_recipes_translated, "\n"))
	end
end

-- return either recipe of a given name or all recipes
basic_machines.get_grinder_recipes = function(name)
	local def
	if name and grinder_recipes[name] then
		def = grinder_recipes[name]
	else
		def = grinder_recipes
	end
	return table.copy(def)
end

-- add/replace grinder recipes, as table:
-- {["in"] = {fuel cost, "out", quantity of material produced, quantity of material required for processing}}
basic_machines.set_grinder_recipes = function(recipes)
	if not recipes then return end
	for k, v in pairs(recipes) do
		register_recipe(k, next(v) ~= nil and v or nil)
	end
end

-- default
register_recipe("default:cobble", {1, "default:gravel", 1, 1})
register_recipe("default:desert_stone", {2, "default:desert_sand", 4, 1})
register_recipe("default:dirt", {0.5, "default:clay_lump", 4, 1})
register_recipe("default:gravel", {0.5, "default:dirt", 1, 1})
register_recipe("default:ice", {1, "default:snow", 4, 1})
register_recipe("default:obsidian_shard", {199, "default:lava_source", 1, 1})
register_recipe("default:stone", {2, "default:sand", 1, 1})

if minetest.get_modpath("darkage") then
	register_recipe("darkage:silt_lump", {1, "darkage:chalk_powder", 1, 1})
end

if minetest.global_exists("es") then
	register_recipe("es:aikerum_crystal", {16, "es:aikerum_dust", 2, 1})
	register_recipe("es:emerald_crystal", {16, "es:emerald_dust", 2, 1})
	register_recipe("es:purpellium_lump", {16, "es:purpellium_dust", 2, 1})
	register_recipe("es:ruby_crystal", {16, "es:ruby_dust", 2, 1})
end

if minetest.get_modpath("gloopblocks") then
	register_recipe("gloopblocks:basalt", {1, "default:cobble", 1, 1})
end

if basic_machines.settings.grinder_register_dusts then
	local farming_table, farming_mod = {}, nil
	if minetest.global_exists("farming") and farming.mod == "redo" then
		farming_table[1] = "farming_redo"
	end
	if minetest.global_exists("x_farming") then
		farming_table[2] = "x_farming"
	end
	local grinder_extractors_type = basic_machines.settings.grinder_extractors_type
	if farming_table[grinder_extractors_type] then
		farming_mod = farming_table[grinder_extractors_type]
	else
		for i = 1, #farming_table do
			if farming_table[i] then farming_mod = farming_table[i]; break end
		end
	end
	local have_ff = farming_mod and minetest.global_exists("flowers")
	local have_ui_categories = use_unified_inventory and unified_inventory.registered_categories
	local purity_table = {"00", "33", "66"}; if grinder_dusts_legacy or not have_ff then table.remove(purity_table, 1) end

	-- REGISTER DUSTS
	-- dust_00 (mix)-> extractor (smelt) -> dust_33 (smelt) -> dust_66 (smelt) -> ingot
	-- or legacy mode: dust_33 (smelt) -> dust_66 (smelt) -> ingot
	local function register_dust(name, input_name, output_name, grind_cost, cooktime, quantity, hex, light_source)
		local dust = "basic_machines:" .. name .. "_dust_"
		local dust_output = dust .. purity_table[1]
		local dust_66 = dust .. "66"

		for i, purity in ipairs(purity_table) do
			minetest.register_craftitem(dust .. purity, {
				description = S(name:gsub("^%l", string.upper) .. " dust purity @1% " ..
					(purity == "00" and "(combine with chemicals to create " .. name .. " extractor)" or
					"(smelt to increase purity)"), purity),
				groups = {dust = 1},
				inventory_image = "basic_machines_dust.png^[colorize:#" .. hex .. ":180",
				light_source = light_source and light_source[i]
			})
			if have_ui_categories then
				unified_inventory.add_category_item("minerals", dust .. purity)
			end
		end

		register_recipe(input_name, {grind_cost, dust_output, quantity, 1}) -- register grinder recipe
		if output_name then
			register_recipe(output_name, {grind_cost, dust_output, quantity, 1}) -- grinding ingots gives dust too
		end

		minetest.register_craft({
			type = "cooking",
			output = dust_66,
			recipe = dust .. "33",
			cooktime = cooktime
		})

		minetest.register_craft({
			type = "cooking",
			output = output_name or input_name,
			recipe = dust_66,
			cooktime = cooktime
		})
	end

	local qt = math.max(0, basic_machines.settings.grinder_dusts_quantity)

	register_dust("iron", "default:iron_lump", "default:steel_ingot", 4, 8, qt, "999999")
	register_dust("copper", "default:copper_lump", "default:copper_ingot", 4, 8, qt, "C8800D")
	register_dust("tin", "default:tin_lump", "default:tin_ingot", 4, 8, qt, "9F9F9F")
	register_dust("gold", "default:gold_lump", "default:gold_ingot", 6, 25, qt, "FFFF00")
	register_dust("mese", "default:mese_crystal", nil, 8, 250, qt, "CCCC00")
	-- 0.3hr cooking time to make diamond!
	register_dust("diamond", "default:diamond", nil, 16, 500, qt, "00EEFF", {7, 11, 13})

	-- are moreores (tin, silver, mithril) present ?
	if minetest.registered_items["moreores:tin_lump"] then
		-- register_dust("tin", "moreores:tin_lump", "moreores:tin_ingot", 4, 8, qt, "FFFFFF")
		register_dust("silver", "moreores:silver_lump", "moreores:silver_ingot", 5, 15, qt, "BBBBBB", {9, 11, 14})
		register_dust("mithril", "moreores:mithril_lump", "moreores:mithril_ingot", 16, 750, qt, "0000FF", {8, 12, 14})
	end

	-- REGISTER EXTRACTORS, their recipes and smelting recipes
	if not grinder_dusts_legacy and have_ff then
		local function register_extractor(name, hex, recipe)
			local item = "basic_machines:" .. name .. "_extractor"

			minetest.register_craftitem(item, {
				description = S("Smelt to get " .. name),
				groups = {extractor = 1},
				inventory_image = "basic_machines_ore_extractor.png^[colorize:#" .. hex .. ":180"
			})

			minetest.register_craft({
				output = item,
				recipe = {recipe}
			})

			-- extractor smelts to dust_33
			minetest.register_craft({
				type = "cooking",
				output = "basic_machines:" .. name .. "_dust_33",
				recipe = item,
				cooktime = 10
			})
		end

		local recipe = {}

		if farming_mod == "farming_redo" then
			recipe.tin = {"farming:cocoa_beans", "farming:cocoa_beans", "basic_machines:tin_dust_00"}
			recipe.mese = {"farming:rhubarb", "farming:rhubarb", "basic_machines:mese_dust_00"}
		elseif farming_mod == "x_farming" then
			recipe.tin = {"x_farming:salt", "x_farming:salt", "basic_machines:tin_dust_00"}
			recipe.mese = {"x_farming:strawberry", "x_farming:strawberry", "basic_machines:mese_dust_00"}
		end

		register_extractor("iron", "999999", {"default:leaves", "default:leaves", "basic_machines:iron_dust_00"})
		register_extractor("copper", "C8800D", {"default:papyrus", "default:papyrus", "basic_machines:copper_dust_00"})
		register_extractor("tin", "C89F9F", recipe.tin)
		register_extractor("gold", "FFFF00",
			{"basic_machines:tin_extractor", "basic_machines:copper_extractor", "basic_machines:gold_dust_00"})
		register_extractor("mese", "CCCC00", recipe.mese)
		register_extractor("diamond", "00EEFF", {"farming:wheat", "farming:cotton", "basic_machines:diamond_dust_00"})

		if minetest.registered_items["moreores:tin_lump"] then
			register_extractor("silver", "BBBBBB", {"flowers:geranium", "flowers:tulip_black", "basic_machines:silver_dust_00"})
			register_extractor("mithril", "0000FF", {"flowers:geranium", "flowers:geranium", "basic_machines:mithril_dust_00"})
		end
	end
end

local function grinder_update_form(meta)
	meta:set_string("formspec", ([[
		size[8,8]
		label[0,-0.25;%s]list[context;src;0,0.25;1,1;]
		label[1,-0.25;%s]list[context;dst;1,0.25;3,3;]
		label[5,0;%s]list[context;upgrade;5,0.5;1,1;]
		button[6.5,0;1,1;OK;%s]
		button[6.5,1;1,1;help;%s]
		label[0,1.75;%s]list[context;fuel;0,2.25;1,1;]
		list[current_player;main;0,3.75;8,1;]
		list[current_player;main;0,5;8,3;8]
		listring[context;dst]
		listring[current_player;main]
		listring[context;src]
		listring[current_player;main]
		listring[context;upgrade]
		listring[current_player;main]
		listring[context;fuel]
		listring[current_player;main]
		%s
	]]):format(F(S("IN")), F(S("OUT")), F(S("UPGRADE")),
		F(S("OK")), F(S("help")), F(S("FUEL")), default.get_hotbar_bg(0, 3.75)
	))
end

local function grinder_process(pos)
	local meta = minetest.get_meta(pos)

	-- activation limiter: 1/s
	local t0, t1 = meta:get_int("t"), minetest.get_gametime()

	if t1 - t0 < machines_minstep then
		if t1 - t0 < 0 then meta:set_int("t", 0) end; return
	end
	meta:set_int("t", t1)

	local inv = meta:get_inventory()

	-- PROCESS: check out inserted items
	local stack = inv:get_stack("src", 1); if stack:is_empty() then return end -- nothing to do
	local src_item = stack:get_name()
	local def = grinder_recipes[src_item]

	if not def then
		meta:set_string("infotext", S("Please insert valid materials")); return -- unknown node
	end

	local steps = math.floor(stack:get_count() / def[4]) -- how many steps to process inserted stack

	if steps < 1 then
		local item_def = minetest.registered_items[src_item]
		local description = item_def and item_def.description or S("Unknown item")
		meta:set_string("infotext", S("Recipe requires at least @1 of '@2' (@3)", def[4], description, src_item))
		return
	end

	local upgrade = meta:get_int("upgrade") + 1; if steps > upgrade then steps = upgrade end

	-- FUEL CHECK
	local fuel, fuel_req = meta:get_float("fuel"), def[1] * steps
	local msg

	if fuel < fuel_req then -- we need new fuel
		local fuellist = inv:get_list("fuel"); if not fuellist then return end
		local fueladd, afterfuel = minetest.get_craft_result({method = "fuel", width = 1, items = fuellist})

		if fueladd.time == 0 then -- no fuel inserted, try look for outlet
			-- tweaked so 1 coal = 1 energy
			local supply = basic_machines.check_power({x = pos.x, y = pos.y - 1, z = pos.z}, fuel_req)
			if supply > 0 then
				fueladd.time = supply -- same as 10 coal
			else
				meta:set_string("infotext", S("Please insert fuel")); return
			end
		else
			inv:set_stack("fuel", 1, afterfuel.items[1])
			fueladd.time = fueladd.time * 0.1 / 4 -- thats 1 for coal
		end

		if fueladd.time > 0 then
			fuel = fuel + fueladd.time; meta:set_float("fuel", fuel)
		end

		if fuel < fuel_req then
			meta:set_string("infotext",
				S("Need at least @1 fuel to complete operation", twodigits_float(fuel_req - fuel))); return
		else
			msg = S("Added fuel furnace burn time @1, fuel status @2", fueladd.time, twodigits_float(fuel))
		end
	end

	-- process items
	local addstack = ItemStack({name = def[2], count = def[3]})
	if steps > 1 then -- multiply stack
		addstack:set_count(addstack:get_count() * steps)
	end
	if inv:room_for_item("dst", addstack) then
		inv:add_item("dst", addstack)
	else
		if msg then meta:set_string("infotext", msg) end; return
	end

	-- take 'steps' items from src inventory for each activation
	stack = stack:take_item(def[4] * steps); inv:remove_item("src", stack)

	minetest.sound_play("basic_machines_grinder", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)

	fuel = fuel - fuel_req; meta:set_float("fuel", fuel) -- burn fuel
	meta:set_string("infotext", S("Fuel status @1", twodigits_float(fuel)))
end

local function grinder_upgrade(meta)
	local stack = meta:get_inventory():get_stack("upgrade", 1)
	local upgrade = stack:get_name()
	meta:set_int("upgrade", upgrade == "basic_machines:grinder" and stack:get_count() or 0)
end

minetest.register_node("basic_machines:grinder", {
	description = S("Grinder"),
	groups = {cracky = 3},
	tiles = {"basic_machines_grinder.png"},
	sounds = default.node_sound_wood_defaults(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext",
			S("Grinder: to operate it insert fuel, then insert item to grind or activate with signal"))
		meta:set_string("owner", placer:get_player_name())

		meta:set_float("fuel", 0)
		meta:set_int("t", 0)

		local inv = meta:get_inventory()
		inv:set_size("src", 1)
		inv:set_size("dst", 9)
		inv:set_size("upgrade", 1)
		inv:set_size("fuel", 1)

		grinder_update_form(meta)
	end,

	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()

		return meta:get_string("owner") == player:get_player_name() and
			inv:is_empty("upgrade") and inv:is_empty("src") and -- all inv must be empty to be dug
			inv:is_empty("dst") and inv:is_empty("fuel")
	end,

	on_receive_fields = function(pos, formname, fields, sender)
		if fields.quit then return end

		if fields.OK then
			if minetest.is_protected(pos, sender:get_player_name()) then return end
			grinder_process(pos)

		elseif fields.help then
			if grinder_recipes_help == nil then
				grinder_recipes_help = F(table.concat(grinder_recipes_translated, "\n"))
			end
			minetest.show_formspec(sender:get_player_name(), "basic_machines:help_grinder",
				"size[6,7]textarea[0,0;6.5,8.5;help;" .. F(S("GRINDER HELP")) .. ";" ..
				F(S("To upgrade grinder, put grinders in upgrade slot." ..
				" Each upgrade adds ability to process additional materials.\n\n")) .. grinder_recipes_help .. "]")
		end
	end,

	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		return 0
	end,

	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end
		return stack:get_count()
	end,

	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end
		return stack:get_count()
	end,

	on_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname == "src" then
			grinder_process(pos)
		elseif listname == "upgrade" then
			local meta = minetest.get_meta(pos)
			grinder_upgrade(meta)
			grinder_update_form(meta)
		end
	end,

	on_metadata_inventory_take = function(pos, listname, index, stack, player)
		if listname == "upgrade" then
			local meta = minetest.get_meta(pos)
			grinder_upgrade(meta)
			grinder_update_form(meta)
		end
	end,

	effector = {
		action_on = function(pos, _)
			grinder_process(pos)
		end
	}
})

if basic_machines.settings.register_crafts then
	minetest.register_craft({
		output = "basic_machines:grinder",
		recipe = {
			{"default:diamond", "default:mese", "default:diamond"},
			{"default:mese", "default:diamondblock", "default:mese"},
			{"default:diamond", "default:mese", "default:diamond"}
		}
	})
end