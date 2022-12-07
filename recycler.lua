-- rnd 2015:

-- This node works as a reverse of crafting process with a 25% loss of items (aka recycling)
-- You can select which recipe to use when recycling
-- There is a fuel cost to recycle

local F, S = basic_machines.F, basic_machines.S
local machines_minstep = basic_machines.properties.machines_minstep
local twodigits_float = basic_machines.twodigits_float
local no_recycle_list = { -- prevent unrealistic recycling
	["default:bronze_ingot"] = 1, ["default:gold_ingot"] = 1,
	["default:copper_ingot"] = 1, ["default:steel_ingot"] = 1,
	["dye:black"] = 1, ["dye:blue"] = 1, ["dye:brown"] = 1, ["dye:cyan"] = 1,
	["dye:dark_green"] = 1, ["dye:dark_grey"] = 1, ["dye:green"] = 1,
	["dye:grey"] = 1, ["dye:magenta"] = 1, ["dye:orange"] = 1,
	["dye:pink"] = 1, ["dye:red"] = 1, ["dye:violet"] = 1,
	["dye:white"] = 1, ["dye:yellow"] = 1
}

local function recycler_update_form(meta)
	meta:set_string("formspec", "size[8,8]" .. -- width, height
		"label[0,-0.25;" .. F(S("IN")) .. "]list[context;src;0,0.25;1,1;]" ..
		"label[1,-0.25;" .. F(S("OUT")) .. "]list[context;dst;1,0.25;3,3;]" ..
		"field[4.5,0.65;2,1;recipe;" .. F(S("Select recipe:")) .. ";" .. meta:get_int("recipe") ..
		"]button[6.5,0;1,1;OK;" .. F(S("OK")) ..
		"]label[0,1.75;" .. F(S("FUEL")) .. "]list[context;fuel;0,2.25;1,1;]" ..
		"list[current_player;main;0,3.75;8,1;]" ..
		"list[current_player;main;0,5;8,3;8]" ..
		"listring[context;dst]" ..
		"listring[current_player;main]" ..
		"listring[context;src]" ..
		"listring[current_player;main]" ..
		"listring[context;fuel]" ..
		"listring[current_player;main]" ..
		default.get_hotbar_bg(0, 3.75))
end

local function recycler_process(pos)
	local meta = minetest.get_meta(pos)

	local inv = meta:get_inventory(); local msg

	-- FUEL CHECK
	local fuel_req; local fuel = meta:get_float("fuel")

	if meta:get_int("admin") == 1 then
		fuel_req = 0
	else
		fuel_req = 1

		if fuel < fuel_req then -- we need new fuel
			local fuellist = inv:get_list("fuel"); if not fuellist then return end
			local fueladd, afterfuel = minetest.get_craft_result({method = "fuel", width = 1, items = fuellist})

			if fueladd.time == 0 then -- no fuel inserted, try look for outlet
				local supply = basic_machines.check_power({x = pos.x, y = pos.y - 1, z = pos.z}, fuel_req)
				if supply > 0 then
					fueladd.time = 40 * supply -- same as 10 coal
				else
					meta:set_string("infotext", S("Please insert fuel")); return
				end
			else
				inv:set_stack("fuel", 1, afterfuel.items[1])
				fueladd.time = fueladd.time * 0.1 -- thats 4 for coal
			end

			if fueladd.time > 0 then
				fuel = fuel + fueladd.time; meta:set_float("fuel", fuel)
				msg = S("Added fuel furnace burn time @1, fuel status @2", fueladd.time, twodigits_float(fuel))
			end

			if fuel < fuel_req then return end
		end
	end

	-- RECYCLING: check out inserted items
	local stack = inv:get_stack("src", 1)
	if stack:is_empty() then if msg then meta:set_string("infotext", msg) end; return end -- nothing to do
	local src_item = stack:get_name()
	-- take first word to determine what item was
	local itemlist; local reqcount = 1; local description -- needed count of materials for recycle to work

	if src_item == meta:get_string("node") then -- did we already handle this ? if yes read from cache
		itemlist = minetest.deserialize(meta:get_string("itemlist")) or {} -- read cached itemlist
		reqcount = meta:get_int("reqcount")
		description = meta:get_string("description")
	else
		if no_recycle_list[src_item] then meta:set_string("node", ""); return end -- don't allow recycling of forbidden items

		local recipe = minetest.get_all_craft_recipes(src_item)
		if not recipe then return end

		local recipe_id = meta:get_int("recipe")
		itemlist = recipe[recipe_id]
		if not itemlist then meta:set_string("node", ""); return end
		itemlist = itemlist.items
		-- clean out unknown items and groups
		for i, item in pairs(itemlist) do
			if not minetest.registered_items[item] then
				itemlist[i] = nil
			end
		end
		if #itemlist == 0 then return end

		local output = recipe[recipe_id].output or ""
		if output:find(" ") then
			local par = output:find(" ")
			-- if (tonumber(output:sub(par)) or 0) > 1 then itemlist = {} end
			if par then
				reqcount = tonumber(output:sub(par)) or 1
			end
		end

		local def = minetest.registered_items[src_item]
		description = def and def.description or S("Unknown item")

		meta:set_string("node", src_item)
		meta:set_string("itemlist", minetest.serialize(itemlist))
		meta:set_int("reqcount", reqcount)
		meta:set_string("description", description)
	end

	if stack:get_count() < reqcount then
		meta:set_string("infotext", S("At least @1 of '@2' (@3) required", reqcount, description, src_item)); return
	end
	--[[
	-- empty dst inventory before proceeding
	for i = 1, inv:get_size("dst") do
		inv:set_stack("dst", i, ItemStack(""))
	end
	--]]
	for _, item in pairs(itemlist) do
		if math.random(1, 4) <= 3 then -- probability 3/4 = 75%
			local addstack = ItemStack(item)
			if inv:room_for_item("dst", addstack) then -- can item be put in
				inv:add_item("dst", addstack)
			else
				if msg then meta:set_string("infotext", msg) end; return
			end
		end
	end

	-- take 1 item from src inventory for each activation
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

	fuel = fuel - fuel_req; meta:set_float("fuel", fuel) -- burn fuel on successful operation
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
	sounds = default.node_sound_wood_defaults(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta, name = minetest.get_meta(pos), placer:get_player_name()
		meta:set_string("infotext",
			S("Recycler: Put one item in 'IN' (src) and obtain 75% of raw materials in 'OUT' (dst)." ..
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
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()

		return meta:get_string("owner") == player:get_player_name() and
			inv:is_empty("src") and inv:is_empty("dst") and inv:is_empty("fuel") -- all inv must be empty to be dug
	end,

	on_receive_fields = function(pos, formname, fields, sender)
		if fields.OK then
			if minetest.is_protected(pos, sender:get_player_name()) then return end

			local meta = minetest.get_meta(pos)

			if fields.recipe ~= meta:get_string("recipe") then
				meta:set_string("node", "") -- this will force to reread recipe on next use
			end
			meta:set_int("recipe", tonumber(fields.recipe) or 1)

			recycler_process(pos)
			recycler_update_form(meta)
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
		if listname == "src" then recycler_process(pos) end
	end,

	on_metadata_inventory_take = function(pos, listname, index, stack, player)
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

if basic_machines.settings.register_crafts then
	minetest.register_craft({
		output = "basic_machines:recycler",
		recipe = {
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
			{"default:mese_crystal", "default:diamondblock", "default:mese_crystal"},
			{"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"}
		}
	})
end