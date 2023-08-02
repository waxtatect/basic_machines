-- Make other light blocks work with signals - can toggle on/off
-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local function enable_toggle_light(name)
	local def = minetest.registered_nodes[name]
	if not def or def.effector or def.mesecons then return end -- we don't want to overwrite existing stuff!

	local offname = "basic_machines:" .. name:gsub(":", "_") .. "_OFF"

	-- redefine item
	minetest.override_item(name, {
		effector = { -- action to toggle light off
			action_off = function(pos, _)
				minetest.swap_node(pos, {name = offname})
			end
		}
	})

	local def_off = table.copy(def)

	def_off.groups.not_in_creative_inventory = 1
	def_off.light_source = 0 -- off block has light off
	def_off.effector = {
		action_on = function(pos, _)
			minetest.swap_node(pos, {name = name})
		end
	}

	-- REGISTER OFF BLOCK
	minetest.register_node(":" .. offname, def_off)
end

-- lights
local lights = {}

if minetest.get_modpath("darkage") then
	table.insert(lights, "darkage:lamp")
end

if basic_machines.use_default then
	table.insert(lights, "default:mese_post_light")
	table.insert(lights, "default:mese_post_light_acacia_wood")
	table.insert(lights, "default:mese_post_light_aspen_wood")
	table.insert(lights, "default:mese_post_light_junglewood")
	table.insert(lights, "default:mese_post_light_pine_wood")
	table.insert(lights, "default:meselamp")
end

if minetest.global_exists("moreblocks") then
	table.insert(lights, "moreblocks:slab_meselamp_1")
	table.insert(lights, "moreblocks:slab_super_glow_glass")
end

if minetest.global_exists("xdecor") then
	table.insert(lights, "xdecor:iron_lightbox")
	table.insert(lights, "xdecor:wooden2_lightbox")
	table.insert(lights, "xdecor:wooden_lightbox")
end

for _, light in ipairs(lights) do
	enable_toggle_light(light)
end