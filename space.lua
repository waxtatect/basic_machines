-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2025 мтест
-- See README.md for license details

local S = basic_machines.S
local exclusion_height = basic_machines.settings.exclusion_height
local space_effects = basic_machines.settings.space_effects
local space_start = basic_machines.settings.space_start
local space_start_eff = basic_machines.settings.space_start_eff
local use_player_monoids = minetest.global_exists("player_monoids")
local use_basic_protect = minetest.global_exists("basic_protect")

minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities)
	if player:get_pos().y > space_start and hitter and hitter:is_player() then
		if time_from_last_punch > 0.8 and vector.length(player:get_velocity()) > 0.2 then
			local dir = vector.subtract(player:get_pos(), hitter:get_pos())
			local unit_vector = vector.divide(dir, vector.length(dir))
			local punch_vector = {x = 5, y = 0.9, z = 5}
			player:add_velocity(vector.multiply(unit_vector, punch_vector)) -- push player a little
		end
		if tool_capabilities and ((tool_capabilities.damage_groups or {}).fleshy or 0) == 1 then
			return true
		end
	end
end)

minetest.register_privilege("include", {
	description = S("Allow player to move in exclusion zone")
})

local space_textures = basic_machines.settings.space_textures
space_textures = space_textures ~= "" and space_textures:split() or {
	"basic_machines_stars.png", "basic_machines_stars.png", "basic_machines_stars.png",
	"basic_machines_stars.png", "basic_machines_stars.png", "basic_machines_stars.png"
}
local skyboxes = {
	["surface"] = {type = "regular", tex = {}},
	["space"] = {type = "skybox", tex = space_textures}
}

local function toggle_visibility(player, b)
	player:set_sun({visible = b, sunrise_visible = b})
	player:set_moon({visible = b})
	player:set_stars({visible = b})
end

local function adjust_enviro(inspace, player) -- adjust players physics/skybox
	if inspace == 1 then -- is player in space or not ?
		local physics = {speed = 1, jump = 0.5, gravity = 0.1} -- value set for extreme test space spawn
		if use_player_monoids then
			player_monoids.speed:add_change(player, physics.speed,
				"basic_machines:physics")
			player_monoids.jump:add_change(player, physics.jump,
				"basic_machines:physics")
			player_monoids.gravity:add_change(player, physics.gravity,
				"basic_machines:physics")
		else
			player:set_physics_override(physics)
		end

		local sky = skyboxes["space"]
		player:set_sky({base_color = 0x000000, type = sky["type"], textures = sky["tex"], clouds = false})
		toggle_visibility(player, false)
	else
		local physics = {speed = 1, jump = 1, gravity = 1}
		if use_player_monoids then
			player_monoids.speed:add_change(player, physics.speed,
				"basic_machines:physics")
			player_monoids.jump:add_change(player, physics.jump,
				"basic_machines:physics")
			player_monoids.gravity:add_change(player, physics.gravity,
				"basic_machines:physics")
		else
			player:set_physics_override(physics)
		end

		local sky = skyboxes["surface"]
		player:set_sky({type = sky["type"], textures = sky["tex"], clouds = true})
		toggle_visibility(player, true)
	end

	return inspace
end

local space = {}

minetest.register_on_leaveplayer(function(player)
	space[player:get_player_name()] = nil
end)

local stimer = 0
local function pos_to_string(pos) return ("%s, %s, %s"):format(pos.x, pos.y, pos.z) end
local function protector_position() return {x = 0, y = 0, z = 0} end

if use_basic_protect then
	local math_floor = math.floor
	local function round(x, r) return math_floor(x / r + 0.5) * r end
	local r = 20; local ry = 2 * r
	local function protector_vector_round(v) return {x = round(v.x, r), y = round(v.y, ry), z = round(v.z, r)} end
	protector_position = function(pos) return protector_vector_round(pos) end
end

minetest.register_globalstep(function(dtime)
	stimer = stimer + dtime; if stimer < 5 then return end; stimer = 0

	for _, player in ipairs(minetest.get_connected_players()) do
		local pos = player:get_pos()
		local name = player:get_player_name()
		local inspace

		if pos.y > space_start then
			inspace = 1
			if pos.y > exclusion_height and not minetest.check_player_privs(name, "include") then
				local spawn_pos = {x = math.random(-100, 100), y = math.random(10), z = math.random(-100, 100)}
				local spos = pos_to_string(vector.round(pos))
				minetest.chat_send_player(name, S("Exclusion zone alert, current position: @1. Teleporting to @2.",
					spos, pos_to_string(spawn_pos)))
				minetest.log("action", "[basic_machines] Exclusion zone alert: " .. name .. " at " .. spos)
				if player.add_pos then -- for Minetest 5.9.0+
					player:add_pos(vector.subtract(spawn_pos, pos))
				else
					player:set_pos(spawn_pos)
				end
			end
		else
			inspace = 0
		end

		-- only adjust player environment ONLY if change occurred (earth->space or space->earth!)
		if inspace ~= space[name] then
			space[name] = adjust_enviro(inspace, player)
		end

		if space_effects and inspace == 1 then -- special space code
			local hp = player:get_hp()
			if hp > 0 and not minetest.check_player_privs(name, "kick") then
				if pos.y < space_start_eff and pos.y > space_start_eff - 380 then
					minetest.chat_send_player(name, S("WARNING: you entered DEADLY RADIATION ZONE")); player:set_hp(hp - 15)
				elseif use_basic_protect then
					local ppos = protector_position(pos)
					local populated = minetest.get_node(ppos).name == "basic_protect:protector"
					if populated and minetest.get_meta(ppos):get_int("space") == 1 then
						populated = false
					end
					if not populated then -- do damage if player found not close to protectors
						player:set_hp(hp - 10) -- dead in 20/10 = 2 events
						minetest.chat_send_player(name, S("WARNING: in space you must stay close to protected areas"))
					end
				elseif not minetest.is_protected(pos, "") then
					player:set_hp(hp - 10) -- dead in 20/10 = 2 events
					minetest.chat_send_player(name, S("WARNING: in space you must stay close to protected areas"))
				end
			end
		end
	end
end)
--[[
-- AIR EXPERIMENT
if basic_machines.use_default then
	minetest.register_node("basic_machines:air", {
		description = S("Enable breathing in space"),
		groups = {not_in_creative_inventory = 1},
		drawtype = "glasslike", -- drawtype = "liquid",
		tiles = {"default_water_source_animated.png"},
		use_texture_alpha = "blend",
		paramtype = "light",
		sunlight_propagates = true, -- Sunlight shines through
		walkable	= false, -- Would make the player collide with the air node
		pointable	= false, -- You can't select the node
		diggable	= false, -- You can't dig the node
		buildable_to = true,
		drop = "",

		after_place_node = function(pos)
			local r = 3
			for i = -r, r do
				for j = -r, r do
					for k = -r, r do
						local p = {x = pos.x + i, y = pos.y + j, z = pos.z + k}
						if minetest.get_node(p).name == "air" then
							minetest.set_node(p, {name = "basic_machines:air"})
						end
					end
				end
			end
		end
	})

	minetest.register_abm({
		label = "[basic_machines] Air experiment",
		nodenames = {"basic_machines:air"},
		neighbors = {"air"},
		interval = 10,
		chance = 1,
		action = function(pos)
			minetest.remove_node(pos)
		end
	})
end
--]]