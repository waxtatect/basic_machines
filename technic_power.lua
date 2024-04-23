-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local energy_multiplier = basic_machines.settings.energy_multiplier
local generator_upgrade_max = 50 + math.max(0, basic_machines.settings.generator_upgrade)
local machines_minstep = basic_machines.properties.machines_minstep
local machines_timer = basic_machines.properties.machines_timer
local power_stackmax = basic_machines.settings.power_stackmax
local space_start_eff = basic_machines.settings.space_start_eff

-- BATTERY
local energy_crystals = { -- [power crystal name] = energy provided
	["basic_machines:power_cell"] = 1 * energy_multiplier,
	["basic_machines:power_block"] = 11 * energy_multiplier,
	["basic_machines:power_rod"] = 100 * energy_multiplier
}

local function swap_battery(energy_new, energy, capacity, pos)
	if capacity > 0 then
		local full_coef_new = math.floor(energy_new / capacity * 3) -- 0, 1, 2
		local full_coef = math.floor(energy / capacity * 3)

		if full_coef_new > 2 then full_coef_new = 2 end
		if full_coef_new ~= full_coef then -- graphic energy level display
			minetest.swap_node(pos, {name = "basic_machines:battery_" .. full_coef_new})
		end
	end
end

local function battery_recharge(pos, energy, origin)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack("fuel", 1)
	local capacity
	energy = energy or meta:get_float("energy")

	local add_energy = energy_crystals[stack:get_name()]

	if add_energy and add_energy > 0 then
		if pos.y > space_start_eff then add_energy = 2 * add_energy end -- in space recharge is more efficient
		capacity = meta:get_float("capacity")
		if add_energy <= capacity then
			stack:take_item(1); inv:set_stack("fuel", 1, stack)
		else
			meta:set_string("infotext", S("Recharge problem: capacity @1, needed @2", capacity, energy + add_energy))
			return energy
		end
	else -- try do determine caloric value of fuel inside battery
		local fuellist = inv:get_list("fuel"); if not fuellist then return energy end
		local fueladd, afterfuel = minetest.get_craft_result({method = "fuel", width = 1, items = fuellist})
		if fueladd.time > 0 then
			add_energy = fueladd.time / 40
			local energy_new = energy + add_energy
			capacity = meta:get_float("capacity")
			if energy_new <= capacity then
				inv:set_stack("fuel", 1, afterfuel.items[1])
			else
				meta:set_string("infotext", S("Recharge problem: capacity @1, needed @2", capacity, energy_new))
				return energy
			end
		end
	end

	if add_energy and add_energy > 0 then
		local energy_new = energy + add_energy
		if energy_new < 0 then energy_new = 0 end
		if energy_new > capacity then energy_new = capacity end -- excess energy is wasted

		if origin ~= "check_power" then
			if origin == nil then
				meta:set_float("energy", energy_new)
			end

			swap_battery(energy_new, energy, capacity, pos)

			if origin == "recharge_furnace" and energy_new < 1 then
				meta:set_string("infotext", S("Furnace needs at least 1 energy"))
			else
				meta:set_string("infotext", S("(R) Energy: @1 / @2", math.ceil(energy_new * 10) / 10, capacity))
			end
		end

		energy = energy_new

		-- local count = meta:get_int("activation_count")
		-- if count < 16 then
			-- minetest.sound_play("basic_machines_electric_zap", {pos = pos, gain = 0.05, max_hear_distance = 8}, true)
		-- end

		-- local t0, t1 = meta:get_int("t"), minetest.get_gametime()
		-- if t0 > t1 - machines_minstep then
			-- meta:set_int("activation_count", count + 1)
		-- elseif count > 0 then
			-- meta:set_int("activation_count", 0)
		-- end
		-- meta:set_int("t", t1)
	elseif origin == "recharge_furnace" and energy < 1 then
		minetest.swap_node(pos, {name = "basic_machines:battery_0"})
		meta:set_string("infotext", S("Furnace needs at least 1 energy"))
	elseif origin ~= "check_power" then
		capacity = capacity or meta:get_float("capacity")
		meta:set_string("infotext", S("Energy: @1 / @2", math.ceil(energy * 10) / 10, capacity))
	end

	return energy -- new battery energy level
end

-- API for power distribution, mover checks power source - battery
basic_machines.check_power = function(pos, power_draw)
	if not (minetest.get_node(pos).name):find("basic_machines:battery") then -- check with hashtables probably faster ?
		return -1 -- battery not found!
	end

	local meta = minetest.get_meta(pos)
	local maxpower = meta:get_float("maxpower")

	if power_draw > maxpower then
		meta:set_string("infotext", S("Power draw required: @1, maximum power output @2. Please upgrade battery.",
			basic_machines.twodigits_float(power_draw), maxpower)); return 0
	end

	local energy = meta:get_float("energy")
	local energy_recharge, energy_new

	if power_draw > energy then
		energy_recharge = battery_recharge(pos, energy, "check_power") -- try recharge battery and continue operation immediately
		energy_new = energy_recharge - power_draw
	else
		energy_new = energy - power_draw
	end

	if energy_new < 0 then
		if energy_recharge and energy_recharge ~= energy then
			meta:set_float("energy", energy_recharge)
		end
		meta:set_string("infotext", S("Used fuel provides too little power for current power draw @1",
			basic_machines.twodigits_float(power_draw))); return 0
	end -- recharge wasn't enough, needs to be repeated manually, return 0 power available

	meta:set_float("energy", energy_new)
	local capacity = meta:get_float("capacity")
	swap_battery(energy_new, energy, capacity, pos)
	-- update energy display
	meta:set_string("infotext", S("Energy: @1 / @2", math.ceil(energy_new * 10) / 10, capacity))

	return power_draw
end

local function battery_update_form(meta)
	meta:set_string("formspec", "formspec_version[4]size[10.25,8.35]" ..
		"style_type[list;spacing=0.25,0.15]" ..
		"label[0.25,0.3;" .. F(S("Fuel")) .. "]list[context;fuel;0.25,0.5;1,1]" ..
		"box[2,0.5;2.35,1.1;#222222]" ..
		"label[2.15,0.8;" .. F(S("Power: @1", meta:get_float("maxpower"))) ..
		"]label[2.15,1.3;" .. F(S("Capacity: @1", meta:get_float("capacity"))) ..
		"]image_button[5.6,0.85;1.55,0.35;basic_machines_wool_black.png;help;" .. F(S("help")) ..
		"]label[7.75,0.3;" .. F(S("Upgrade")) .. "]list[context;upgrade;7.75,0.5;2,2]" ..
		basic_machines.get_form_player_inventory(0.25, 3.4, 8, 4, 0.25) ..
		"listring[context;upgrade]" ..
		"listring[current_player;main]" ..
		"listring[context;fuel]" ..
		"listring[current_player;main]")
end

local function battery_upgrade(meta, pos)
	local inv = meta:get_inventory()
	local count1, count2 = 0, 0

	for i = 1, 4 do
		local stack = inv:get_stack("upgrade", i)
		local item = stack:get_name()
		if item == "default:mese" then
			count1 = count1 + stack:get_count()
		elseif item == "default:diamondblock" then
			count2 = count2 + stack:get_count()
		end
	end

	if pos.y > space_start_eff then count1, count2 = 2 * count1, 2 * count2 end -- space increases efficiency

	local energy = 0
	local capacity = 3 + count1 * 3 -- mese for capacity
	capacity = math.ceil(capacity * 10) / 10 -- adjust capacity
	local maxpower = 1 + count2 * 2 -- old 99 upgrade -> 200 power

	if meta:get_float("energy") ~= energy then
		minetest.swap_node(pos, {name = "basic_machines:battery_0"}) -- battery level 0
		meta:set_float("energy", energy)
	end

	meta:set_int("upgrade", count2) -- diamond for power
	meta:set_float("capacity", capacity)
	meta:set_float("maxpower", maxpower)
	meta:set_string("infotext", S("Energy: @1 / @2", math.ceil(energy * 10) / 10, capacity))
end

-- this function will activate furnace
local machines_activate_furnace = (minetest.registered_nodes["default:furnace"] or {}).on_metadata_inventory_put

minetest.register_node("basic_machines:battery_0", {
	description = S("Battery"),
	groups = {cracky = 3},
	tiles = {"basic_machines_outlet.png", "basic_machines_battery.png", "basic_machines_battery_0.png"},
	sounds = basic_machines.sound_node_machine(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Battery - stores energy, generates energy from fuel, can power nearby machines," ..
			" or accelerate/run furnace above it"))
		meta:set_string("owner", placer:get_player_name())

		meta:set_float("capacity", 3)
		meta:set_float("maxpower", 1)
		meta:set_float("energy", 0)
		meta:set_int("upgrade", 0) -- upgrade level determines max energy output
		meta:set_int("t", 0); meta:set_int("activation_count", 0)

		local inv = meta:get_inventory()
		inv:set_size("fuel", 1) -- place to put crystals
		inv:set_size("upgrade", 2 * 2)

		battery_update_form(meta)
	end,

	can_dig = function(pos, player)
		if player then
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()

			return meta:get_string("owner") == player:get_player_name() and
				inv:is_empty("upgrade") and inv:is_empty("fuel") -- fuel AND upgrade inv must be empty to be dug
		else
			return false
		end
	end,

	on_receive_fields = function(_, _, fields, sender)
		if fields.help then
			minetest.show_formspec(sender:get_player_name(), "basic_machines:help_battery",
				"formspec_version[4]size[7.4,7.4]textarea[0,0.35;7.4,7.05;help;" .. F(S("Battery help")) .. ";" ..
				F(S("Battery provides power to machines or furnace. It can either use " ..
				"power crystals or convert ordinary furnace fuels into energy. 1 coal lump gives 1 energy." ..
				"\n\nUpgrade with diamond blocks for more available power output or with " ..
				"mese blocks for more power storage capacity.")) .. "]")
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
		if listname == "fuel" then
			battery_recharge(pos)
		elseif listname == "upgrade" then
			local meta = minetest.get_meta(pos)
			battery_upgrade(meta, pos)
			battery_update_form(meta)
		end
	end,

	on_metadata_inventory_take = function(pos, listname)
		if listname == "upgrade" then
			local meta = minetest.get_meta(pos)
			battery_upgrade(meta, pos)
			battery_update_form(meta)
		end
	end,

	effector = {
		action_on = function(pos, _)
			local meta = minetest.get_meta(pos)
			local energy = meta:get_float("energy")

			-- try to power furnace on top of it
			if energy >= 1 then -- need at least 1 energy
				local fpos = {x = pos.x, y = pos.y + 1, z = pos.z} -- furnace pos
				local node = minetest.get_node(fpos).name
				if node == "default:furnace_active" or node == "default:furnace" then
					local t0 = meta:get_int("ftime") -- furnace time
					local t1 = minetest.get_gametime()
					local fmeta = minetest.get_meta(fpos)

					if t1 - t0 < machines_minstep then -- to prevent too quick furnace acceleration, punishment is cooking reset
						if t1 - t0 < 0 then meta:set_int("ftime", 0) end
						fmeta:set_float("src_time", 0); return
					end
					meta:set_int("ftime", t1)

					local fuel_time = fmeta:get_float("fuel_time")
					local fuel_totaltime = fmeta:get_float("fuel_totaltime")
					local upgrade = meta:get_int("upgrade") * 0.1
					local energy_new = energy - 0.25 * upgrade -- use energy to accelerate burning

					-- to add burn time: must burn for at least 40 secs or furnace out of fuel
					if fuel_time > 40 or fuel_totaltime == 0 or node == "default:furnace" then
						fmeta:set_float("fuel_totaltime", 60); fmeta:set_float("fuel_time", 0) -- add 60 seconds burn time to furnace
						energy_new = energy_new - 0.5 -- use up energy to add fuel

						-- make furnace start if not already started
						if node ~= "default:furnace_active" and machines_activate_furnace then machines_activate_furnace(fpos) end
					end

					-- only accelerate if we had enough energy
					-- note: upgrade * 0.1 * 0.25 < power_rod is limit upgrade, so upgrade = 40 * 100 = 4000
					if energy_new < 0 then
						energy_new = 0
					else
						-- accelerated smelt: with 99 upgrade battery furnace works 11x faster
						fmeta:set_float("src_time", fmeta:get_float("src_time") + machines_timer * upgrade)
					end

					if energy_new > 0 then -- no need to recharge yet, will still work next time
						meta:set_float("energy", energy_new)
						local capacity = meta:get_float("capacity")
						swap_battery(energy_new, energy, capacity, pos)
						-- update energy display
						meta:set_string("infotext", S("Energy: @1 / @2", math.ceil(energy_new * 10) / 10, capacity))
					else
						local energy_recharge = battery_recharge(pos, energy_new, "recharge_furnace")
						if energy_recharge ~= energy_new then
							meta:set_float("energy", energy_recharge)
						end
					end

					return
				end
			end

			local capacity = meta:get_float("capacity")
			if energy < capacity then -- not full, try to recharge
				battery_recharge(pos, energy) -- try to recharge by converting inserted fuel/power crystals into energy
			else -- update energy display
				meta:set_string("infotext", S("Energy: @1 / @2", math.ceil(energy * 10) / 10, capacity))
			end
		end
	}
})

-- various battery levels: 0, 1, 2 (2 >= 66%, 1 >= 33%, 0>=0%)
local batdef = table.copy(minetest.registered_nodes["basic_machines:battery_0"])
batdef.groups.not_in_creative_inventory = 1

for i = 1, 2 do
	batdef.tiles[3] = "basic_machines_battery_" .. i .. ".png"
	minetest.register_node("basic_machines:battery_" .. i, batdef)
end


-- GENERATOR
local minenergy = 17500 -- amount of energy required to initialize a generator

local function generator_update_form(meta, not_init)
	if not_init then
		local upgrade = basic_machines.twodigits_float(meta:get_float("upgrade"))
		meta:set_string("formspec", "formspec_version[4]size[10.25,7.2]" ..
			"style_type[list;spacing=0.25,0.15]" ..
			"label[0.25,0.3;" .. F(S("Fuel")) .. "]list[context;fuel;0.25,0.5;1,1]" ..
			"box[2,0.5;3.15,1.1;#222222]" ..
			"label[2.15,0.8;" .. F(S("Power: @1", -1)) ..
			"]label[2.15,1.3;" .. F(S("Energy: @1 / @2", upgrade, minenergy)) ..
			"]image_button[5.6,0.85;1.55,0.35;basic_machines_wool_black.png;init;" .. F(S("initialize")) .. "]" ..
			basic_machines.get_form_player_inventory(0.25, 2.25, 8, 4, 0.25) ..
			"listring[context;fuel]" ..
			"listring[current_player;main]")
	else
		local upgrade = meta:get_int("upgrade")
		local level = upgrade >= 20 and S("high") or (upgrade >= 5 and S("medium") or S("low"))
		meta:set_string("formspec", "formspec_version[4]size[10.25,7.2]" ..
			"style_type[list;spacing=0.25,0.15]" ..
			"label[0.25,0.3;" .. F(S("Power Crystals")) .. "]list[context;fuel;0.25,0.5;1,1]" ..
			"box[2,0.5;2.85,0.9;#222222]" ..
			"label[2.15,0.8;" .. F(S("Power: @1 (@2)", upgrade, level)) ..
			"]image_button[5.6,0.85;1.55,0.35;basic_machines_wool_black.png;help;" .. F(S("help")) ..
			"]label[7.75,0.3;" .. F(S("Upgrade")) .. "]list[context;upgrade;7.75,0.5;2,1]" ..
			basic_machines.get_form_player_inventory(0.25, 2.25, 8, 4, 0.25) ..
			"listring[context;fuel]" ..
			"listring[current_player;main]" ..
			"listring[context;upgrade]" ..
			"listring[current_player;main]")
	end
end

minetest.register_abm({
	label = "[basic_machines] Generator",
	nodenames = {"basic_machines:generator"},
	neighbors = {},
	interval = 19,
	chance = 1,
	action = function(pos)
		local meta = minetest.get_meta(pos)

		if meta:get_string("owner") == "" then
			local inv = meta:get_inventory()
			if inv:get_size("fuel") == 0 then
				meta:set_string("infotext", S("Generator - not enough energy to operate"))
				meta:set_float("upgrade", 0)
				inv:set_size("fuel", 1)
				generator_update_form(meta, true)
			end
			return
		end

		local upgrade = meta:get_int("upgrade")

		if upgrade > generator_upgrade_max then
			meta:set_string("infotext", S("Error: max upgrade is @1", generator_upgrade_max)); return
		end

		local inv = meta:get_inventory()
		local stack = inv:get_stack("fuel", 1)
		local crystal, text

		if upgrade >= 20 then
			crystal = "basic_machines:power_rod " .. math.floor(1 + (upgrade - 20) * 9 / 178)
			text = S("High upgrade: power rod")
		elseif upgrade >= 5 then
			crystal = "basic_machines:power_block " .. math.floor(1 + (upgrade - 5) * 9 / 15)
			text = S("Medium upgrade: power block")
		else
			crystal = "basic_machines:power_cell " .. math.floor(1 + 2 * upgrade)
			text = S("Low upgrade: power cell")
		end

		stack:add_item(ItemStack(crystal))
		inv:set_stack("fuel", 1, stack)
		meta:set_string("infotext", text)
	end
})

local function generator_near_found(pos, name) -- check to prevent too many generators being placed at one place
	if minetest.find_node_near(pos, 15, {"basic_machines:generator"}) then
		minetest.remove_node(pos)
		minetest.add_item(pos, "basic_machines:generator")
		minetest.chat_send_player(name, S("Generator: Interference from nearby generator detected"))
		return true
	end
end

local function generator_upgrade(meta)
	local inv = meta:get_inventory()
	local count = 0
	for i = 1, 2 do
		local stack = inv:get_stack("upgrade", i)
		if stack:get_name() == "basic_machines:generator" then
			count = count + stack:get_count()
		end
	end
	meta:set_int("upgrade", count)
end

minetest.register_node("basic_machines:generator", {
	description = S("Generator"),
	groups = {cracky = 3},
	tiles = {"basic_machines_generator.png"},
	sounds = basic_machines.sound_node_machine(),

	after_place_node = function(pos, placer)
		if not placer then return end
		local name = placer:get_player_name()

		if generator_near_found(pos, name) then return end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Generator - generates power crystals that provide power," ..
			" upgrade with up to @1 generators", generator_upgrade_max))
		meta:set_string("owner", name)

		meta:set_int("upgrade", 0) -- upgrade level determines quality of produced crystals

		local inv = meta:get_inventory()
		inv:set_size("fuel", 1) -- here generated power crystals are placed
		inv:set_size("upgrade", 2)

		generator_update_form(meta)
	end,

	can_dig = function(pos, player) -- fuel inv is not so important as generator generates it
		if player then
			local meta = minetest.get_meta(pos)
			return meta:get_inventory():is_empty("upgrade") and meta:get_string("owner") == player:get_player_name()
		else
			return false
		end
	end,

	on_receive_fields = function(pos, _, fields, sender)
		if fields.help then
			minetest.show_formspec(sender:get_player_name(), "basic_machines:help_generator",
				"formspec_version[4]size[7.4,7.4]textarea[0,0.35;7.4,7.05;help;" .. F(S("Generator help")) .. ";" ..
				F(S("Generator slowly produces power crystals. Those can be used to recharge batteries and come in 3 flavours:\n\n" ..
				"Low (0-4), medium (5-19) and high level (20+)." ..
				" Upgrading the generator (upgrade with generators) will increase the rate at which the crystals are produced." ..
				"\n\nYou can automate the process of battery recharging by using mover in inventory mode, taking from inventory \"fuel\".")) .. "]")
		elseif fields.init then
			local name = sender:get_player_name()
			if minetest.is_protected(pos, name) or generator_near_found(pos, name) then return end

			local meta = minetest.get_meta(pos)
			if meta:get_float("upgrade") >= minenergy then
				meta:set_string("owner", name)

				meta:set_string("infotext", S("Generator - generates power crystals that provide power," ..
					" upgrade with up to @1 generators", generator_upgrade_max))

				meta:set_int("upgrade", 0) -- upgrade level determines quality of produced crystals
				meta:get_inventory():set_size("upgrade", 2)

				generator_update_form(meta)
			end
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
		if listname == "upgrade" then
			local meta = minetest.get_meta(pos)
			generator_upgrade(meta)
			generator_update_form(meta)
		elseif listname == "fuel" then
			local meta = minetest.get_meta(pos)
			if meta:get_string("owner") == "" then
				local inv = meta:get_inventory()
				local inv_stack = inv:get_stack("fuel", 1)
				local add_energy = energy_crystals[inv_stack:get_name()] or 0
				local energy = meta:get_float("upgrade")

				if add_energy > 0 then
					add_energy = add_energy * inv_stack:get_count()
					if add_energy <= minenergy then
						inv:set_stack("fuel", 1, ItemStack(""))
					else
						return
					end
				else -- try do determine caloric value of fuel inside battery
					local fueladd, _ = minetest.get_craft_result({method = "fuel", width = 1, items = {inv_stack}})
					if fueladd.time > 0 then
						add_energy = (fueladd.time / 40) * inv_stack:get_count()
						if energy + add_energy <= minenergy + 3 then
							inv:set_stack("fuel", 1, ItemStack(""))
						else
							return
						end
					end
				end

				if add_energy > 0 then
					energy = energy + add_energy
					if energy < 0 then energy = 0 end
					if energy > minenergy then energy = minenergy end -- excess energy is wasted
					meta:set_float("upgrade", energy)
					-- minetest.sound_play("basic_machines_electric_zap", {pos = pos, gain = 0.05, max_hear_distance = 8}, true)
					generator_update_form(meta, true)
				end
			end
		end
	end,

	on_metadata_inventory_take = function(pos, listname)
		if listname == "upgrade" then
			local meta = minetest.get_meta(pos)
			generator_upgrade(meta)
			generator_update_form(meta)
		end
	end
})

-- CRAFTS
minetest.register_craftitem("basic_machines:power_cell", {
	description = S("Power Cell"),
	groups = {energy = 1},
	inventory_image = "basic_machines_power_cell.png",
	stack_max = power_stackmax,
	light_source = 7
})

minetest.register_craftitem("basic_machines:power_block", {
	description = S("Power Block"),
	groups = {energy = 1},
	inventory_image = "basic_machines_power_block.png",
	stack_max = power_stackmax,
	light_source = 9
})

minetest.register_craftitem("basic_machines:power_rod", {
	description = S("Power Rod"),
	groups = {energy = 1},
	inventory_image = "basic_machines_power_rod.png",
	stack_max = power_stackmax,
	light_source = 12
})

if basic_machines.settings.register_crafts and basic_machines.use_default then
	minetest.register_craft({
		output = "basic_machines:battery_0",
		recipe = {
			{"default:bronzeblock 2", "default:mese", "default:diamond"}
		}
	})

	minetest.register_craft({
		output = "basic_machines:generator",
		recipe = {
			{"default:diamondblock 5", "basic_machines:battery_0 5", "default:goldblock 5"}
		}
	})
end