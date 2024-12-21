-- This node works as a reverse of crafting process with a 25% loss of items (aka recycling)
-- You can select which recipe to use when recycling
-- There is a fuel cost to recycle
-- rnd 2015
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local machines_minstep = basic_machines.properties.machines_minstep
local twodigits_float = basic_machines.twodigits_float
local no_recycle_list = { -- prevent unrealistic recycling
	["default:bronze_ingot"] = 1, ["default:coal_lump"] = 1,
	["default:copper_ingot"] = 1, ["default:diamond"] = 1,
	["default:gold_ingot"] = 1, ["default:mese_crystal"] = 1,
	["default:mese_crystal_fragment"] = 1, ["default:steel_ingot"] = 1,
	["default:tin_ingot"] = 1,
	["dye:black"] = 1, ["dye:blue"] = 1, ["dye:brown"] = 1,
	["dye:cyan"] = 1, ["dye:dark_green"] = 1, ["dye:dark_grey"] = 1,
	["dye:green"] = 1, ["dye:grey"] = 1, ["dye:magenta"] = 1,
	["dye:orange"] = 1, ["dye:pink"] = 1, ["dye:red"] = 1,
	["dye:violet"] = 1, ["dye:white"] = 1, ["dye:yellow"] = 1,
	["moreores:mithril_ingot"] = 1, ["moreores:silver_ingot"] = 1
}

local function set_fuel_and_infotext(meta, fuel, msg)
	if msg then
		meta:set_float("fuel", fuel)
		meta:set_string("infotext", msg)
	end
end

local function recycler_update_form(meta)
	meta:set_string("formspec", "formspec_version[4]size[10.25,9.5]" ..
		"style_type[list;spacing=0.25,0.15]" ..
		"label[0.25,0.3;" .. F(S("In")) .. "]list[context;src;0.25,0.5;1,1]" ..
		"label[1.5,0.3;" .. F(S("Out")) .. "]list[context;dst;1.5,0.5;3,3]" ..
		"field[5.75,0.9;2,0.8;recipe;" .. F(S("Select recipe:")) .. ";" .. meta:get_int("recipe") ..
		"]button[8.38,0.5;1,0.8;OK;" .. F(S("OK")) ..
		"]label[0.25,2.6;" .. F(S("Fuel")) .. "]list[context;fuel;0.25,2.8;1,1]" ..
		basic_machines.get_form_player_inventory(0.25, 4.55, 8, 4, 0.25) ..
		"listring[context;dst]" ..
		"listring[current_player;main]" ..
		"listring[context;src]" ..
		"listring[current_player;main]" ..
		"listring[context;fuel]" ..
		"listring[current_player;main]")
end

local function recycler_process(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	-- PROCESS: check out inserted items
	local stack = inv:get_stack("src", 1); if stack:is_empty() then return end -- nothing to do
	local src_item = stack:get_name()

	if no_recycle_list[src_item] then -- don't allow recycling of forbidden items
		meta:set_string("node", ""); return
	end

	local admin = meta:get_int("admin")

	-- FUEL CHECK
	local fuel = meta:get_float("fuel")
	local fuel_req, msg

	if admin == 1 then
		fuel_req = 0
	else
		fuel_req = (stack:to_string():len() + 5) * 0.16

		if fuel < fuel_req then -- we need new fuel
			local fuellist = inv:get_list("fuel"); if not fuellist then return end
			local fueladd, afterfuel = minetest.get_craft_result({method = "fuel", width = 1, items = fuellist})
			local add_fuel = fueladd.time

			if add_fuel == 0 then -- no fuel inserted, try look for outlet
				local supply = basic_machines.check_power({x = pos.x, y = pos.y - 1, z = pos.z}, fuel_req)
				if supply > 0 then
					add_fuel = supply * 2 -- * 40, same as 10 coal
				else
					meta:set_string("infotext", S("Please insert fuel")); return
				end
			else
				inv:set_stack("fuel", 1, afterfuel.items[1])
				add_fuel = add_fuel * 0.1 -- that's 4 for coal
			end

			if add_fuel > 0 then
				fuel = fuel + add_fuel
			end

			if fuel < fuel_req then
				meta:set_float("fuel", fuel)
				meta:set_string("infotext",
					S("Need at least @1 fuel to complete operation", twodigits_float(fuel_req - fuel))); return
			else
				msg = S("Added fuel furnace burn time @1, fuel status @2",
					twodigits_float(add_fuel), twodigits_float(fuel))
			end
		end
	end

	-- RECYCLING
	local itemlist, reqcount, description

	if src_item == meta:get_string("node") then -- did we already handle this ? if yes read from cache
		itemlist = minetest.deserialize(meta:get_string("itemlist")) -- read cached itemlist
		if itemlist == nil then
			meta:set_string("node", ""); set_fuel_and_infotext(meta, fuel, msg); return
		end
		reqcount = meta:get_int("reqcount")
		description = meta:get_string("description")
	else
		local recipe = minetest.get_all_craft_recipes(src_item)
		if recipe then
			local recipe_id = meta:get_int("recipe")
			itemlist = recipe[recipe_id]
			if not itemlist then
				meta:set_string("node", ""); set_fuel_and_infotext(meta, fuel, msg); return
			end
			itemlist = itemlist.items
			-- clean out unknown items and groups
			for i, item in pairs(itemlist) do
				if not minetest.registered_items[item] then
					itemlist[i] = nil
				end
			end
			if #itemlist == 0 then set_fuel_and_infotext(meta, fuel, msg); return end

			local output = recipe[recipe_id].output or ""
			local par = output:find(" ")
			if par then
				reqcount = tonumber(output:sub(par + 1))
			end
			reqcount = reqcount or 1

			local def = minetest.registered_items[src_item]
			description = def and def.description or S("Unknown item")

			meta:set_string("node", src_item)
			meta:set_string("itemlist", minetest.serialize(itemlist))
			meta:set_int("reqcount", reqcount)
			meta:set_string("description", description)
		else
			set_fuel_and_infotext(meta, fuel, msg); return
		end
	end

	if stack:get_count() < reqcount then
		if msg then meta:set_float("fuel", fuel) end
		meta:set_string("infotext", S("At least @1 of '@2' (@3) required", reqcount, description, src_item)); return
	end

	local consume_src = false
	for _, item in pairs(itemlist) do
		if math.random(1, 4) <= 3 then -- probability 3/4 = 75%
			local addstack = ItemStack(item)
			if inv:room_for_item("dst", addstack) then -- can item be put in ?
				if minetest.registered_items[item] then
					inv:add_item("dst", addstack)
					consume_src = true -- We have to consume src before return or this is duplication exploit.
				end
			else
				set_fuel_and_infotext(meta, fuel, msg)
			end
		end
	end
	if consume_src == false then return end -- Fine return without consuming.

	-- take required items from src inventory for each activation
	stack = stack:take_item(reqcount); inv:remove_item("src", stack)

	local count = meta:get_int("activation_count")
	if count < 16 then
		minetest.sound_play("basic_machines_recycler", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
	end

	local t0, t1 = meta:get_int("t"), minetest.get_gametime()
	if t0 > t1 - machines_minstep then
		meta:set_int("activation_count", count + 1)
	elseif count > 0 then
		meta:set_int("activation_count", 0)
	end
	meta:set_int("t", t1)

	if admin ~= 1 then
		fuel = fuel - fuel_req; meta:set_float("fuel", fuel) -- burn fuel on successful operation
	end
	if inv:is_empty("src") then
		meta:set_string("infotext", S("Fuel status @1", twodigits_float(fuel)))
	else
		meta:set_string("infotext", S("Fuel status @1, recycling '@2' (@3)", twodigits_float(fuel), description, src_item))
	end
end

minetest.register_node("basic_machines:recycler", {
	description = S("Recycler"),
	groups = {cracky = 3},
	tiles = {"basic_machines_recycler.png"},
	sounds = basic_machines.sound_node_machine(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta, name = minetest.get_meta(pos), placer:get_player_name()
		meta:set_string("infotext",
			S("Recycler: Put one item in 'In' (src) and obtain 75% of raw materials in 'Out' (dst)." ..
			" To operate it insert fuel, then insert item to recycle or activate with signal."))
		meta:set_string("owner", name)

		if minetest.check_player_privs(name, "privs") then meta:set_int("admin", 1) end

		meta:set_int("recipe", 1)
		meta:set_float("fuel", 0)
		meta:set_int("t", 0); meta:set_int("activation_count", 0)

		local inv = meta:get_inventory()
		inv:set_size("src", 1)
		inv:set_size("dst", 9)
		inv:set_size("fuel", 1)

		recycler_update_form(meta)
	end,

	can_dig = function(pos, player)
		if player then
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()

			return meta:get_string("owner") == player:get_player_name() and
				inv:is_empty("src") and inv:is_empty("dst") and inv:is_empty("fuel") -- all inv must be empty to be dug
		else
			return false
		end
	end,

	on_receive_fields = function(pos, _, fields, sender)
		if fields.OK then
			if minetest.is_protected(pos, sender:get_player_name()) then return end

			local meta = minetest.get_meta(pos)
			if fields.recipe ~= meta:get_string("recipe") then
				meta:set_string("node", "") -- this will force to reread recipe on next use
				meta:set_int("recipe", tonumber(fields.recipe) or 1)
				recycler_update_form(meta)
			end

			recycler_process(pos)
		end
	end,

	allow_metadata_inventory_move = function()
		return 0
	end,

	allow_metadata_inventory_put = function(pos, _, _, stack, player)
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end
		return stack:get_count()
	end,

	allow_metadata_inventory_take = function(pos, _, _, stack, player)
		if minetest.is_protected(pos, player:get_player_name()) then return 0 end
		return stack:get_count()
	end,

	on_metadata_inventory_put = function(pos, listname)
		if listname == "src" then recycler_process(pos) end
	end,

	on_metadata_inventory_take = function(pos, listname)
		if listname == "src" then
			local meta = minetest.get_meta(pos)
			if meta:get_inventory():is_empty("src") then
				meta:set_string("infotext", S("Fuel status @1", twodigits_float(meta:get_float("fuel"))))
			end
		end
	end,

	effector = {
		action_on = function(pos, _)
			recycler_process(pos)
		end
	}
})

if basic_machines.settings.register_crafts and basic_machines.use_default then
	minetest.register_craft({
		output = "basic_machines:recycler",
		recipe = {
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
			{"default:mese_crystal", "default:diamondblock", "default:mese_crystal"},
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"}
		}
	})
end
