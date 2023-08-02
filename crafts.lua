-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local use_default = basic_machines.use_default

if minetest.get_modpath("darkage") then
	minetest.register_craft({
		type = "cooking",
		output = "darkage:schist",
		recipe = "darkage:slate",
		cooktime = 20
	})

	-- dark age recipe: cook schist to get gneiss
	minetest.register_craft({
		type = "cooking",
		output = "darkage:marble",
		recipe = "darkage:gneiss",
		cooktime = 20
	})

	if use_default then
		minetest.register_craft({
			type = "cooking",
			output = "darkage:basalt",
			recipe = "default:stone",
			cooktime = 60
		})

		minetest.register_craft({
			output = "darkage:serpentine",
			recipe = {
				{"darkage:marble", "default:cactus"}
			}
		})

		minetest.register_craft({
			output = "darkage:mud",
			recipe = {
				{"default:dirt", "default:water_flowing"}
			}
		})
	end
end

if use_default then
	minetest.register_craft({
		type = "cooking",
		output = "default:water_flowing",
		recipe = "default:ice",
		cooktime = 4
	})
end

-- CHARCOAL
minetest.register_craftitem("basic_machines:charcoal", {
	description = basic_machines.S("Wood Charcoal"),
	inventory_image = "basic_machines_charcoal.png",
	groups = {coal = 1}
})

minetest.register_craft({
	type = "cooking",
	output = "basic_machines:charcoal",
	recipe = "group:tree",
	cooktime = 30
})

if use_default then
	minetest.register_craft({
		output = "default:coal_lump",
		recipe = {
			{"basic_machines:charcoal"},
			{"basic_machines:charcoal"}
		}
	})
end

minetest.register_craft({
	type = "fuel",
	recipe = "basic_machines:charcoal",
	-- note: to make it you need to use 1 tree block for fuel + 1 tree block, thats 2, caloric value 2 * 30 = 60
	burntime = 40 -- coal lump has 40, tree block 30, coal block 370 (9 * 40 = 360!)
})