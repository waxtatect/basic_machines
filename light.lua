-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local def = {groups = {cracky = 3}}
if minetest.global_exists("unifieddyes") then
	def.groups.ud_param2_colorable = 1
	def.palette = "unifieddyes_palette_colorwallmounted.png"
	def.paramtype2 = "color"
	def.light_on_actions = {
		action_on = function(pos, _)
			local meta = minetest.get_meta(pos)
			if meta:get_float("deactivate") == 99 then
				local node = minetest.get_node_or_nil(pos)
				if node and node.name == "basic_machines:light_on" then
					node.param2 = node.param2 + 8; if node.param2 > 248 then node.param2 = 0 end
					minetest.swap_node(pos, node)
				end
			else
				local count = tonumber(meta:get_string("infotext")) or 0
				meta:set_string("infotext", count + 1) -- increase activate count
			end
		end,
		action_off = function(pos, _)
			local node = minetest.get_node_or_nil(pos)
			if node and node.name == "basic_machines:light_on" then
				minetest.swap_node(pos, {name = "basic_machines:light_off", param2 = node.param2})
			end
		end
	}
	def.light_off_action = {action_on = function(pos, _)
		local node = minetest.get_node_or_nil(pos)
		if node and node.name == "basic_machines:light_off" then
			local deactivate = minetest.get_meta(pos):get_float("deactivate")
			if deactivate == 99 then
				node.param2 = node.param2 + 8; if node.param2 > 248 then node.param2 = 0 end
				minetest.swap_node(pos, node); return
			end
			minetest.swap_node(pos, {name = "basic_machines:light_on", param2 = node.param2})
			if deactivate > 0 then
				minetest.after(deactivate, function()
					minetest.swap_node(pos, node) -- turn off again
				end)
			end
		end
	end}
else
	def.light_on_actions = {
		action_on = function(pos, _)
			local meta = minetest.get_meta(pos)
			local count = tonumber(meta:get_string("infotext")) or 0
			meta:set_string("infotext", count + 1) -- increase activate count
		end,
		action_off = function(pos, _)
			minetest.swap_node(pos, {name = "basic_machines:light_off"})
		end
	}
	def.light_off_action = {action_on = function(pos, _)
		minetest.swap_node(pos, {name = "basic_machines:light_on"})
		local deactivate = minetest.get_meta(pos):get_float("deactivate")
		if deactivate > 0 then
			minetest.after(deactivate, function()
				minetest.swap_node(pos, {name = "basic_machines:light_off"}) -- turn off again
			end)
		end
	end}
end


-- LIGHT ON
minetest.register_node("basic_machines:light_on", {
	description = S("Light"),
	groups = def.groups,
	light_source = 14,
	tiles = {"basic_machines_light.png"},
	paramtype2 = def.paramtype2,
	palette = def.palette,
	sounds = basic_machines.sound_node_machine(),

	after_place_node = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", "formspec_version[4]size[2.5,2.4]" ..
			"field[0.25,0.4;2,0.8;deactivate;" .. F(S("Deactivate after:")) .. ";0" ..
			"]button_exit[0.25,1.35;1,0.8;OK;" .. F(S("OK")) .. "]")
		meta:set_float("deactivate", 0)
	end,

	on_receive_fields = function(pos, _, fields, sender)
		if fields.OK then
			if minetest.is_protected(pos, sender:get_player_name()) then return end
			local deactivate = tonumber(fields.deactivate) or 0
			if deactivate >= 0 and deactivate <= 600 then
				local meta = minetest.get_meta(pos)
				deactivate = basic_machines.twodigits_float(deactivate)
				meta:set_string("formspec", "formspec_version[4]size[2.5,2.5]" ..
					"field[0.25,0.5;2,0.8;deactivate;" .. F(S("Deactivate after:")) .. ";" .. deactivate ..
					"]button_exit[0.25,1.45;1,0.8;OK;" .. F(S("OK")) .. "]")
				meta:set_float("deactivate", deactivate)
			end
		end
	end,

	effector = def.light_on_actions
})


-- LIGHT OFF
def.groups = table.copy(def.groups)
def.groups.not_in_creative_inventory = 1

minetest.register_node("basic_machines:light_off", {
	description = S("Light off"),
	groups = def.groups,
	tiles = {"basic_machines_light_off.png"},
	paramtype2 = def.paramtype2,
	palette = def.palette,
	sounds = basic_machines.sound_node_machine(),

	effector = def.light_off_action
})

if basic_machines.settings.register_crafts and basic_machines.use_default then
	minetest.register_craft({
		output = "basic_machines:light_on",
		recipe = {
			{"default:torch", "default:torch"},
			{"default:torch", "default:torch"}
		}
	})
end