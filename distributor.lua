-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2025 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local vector_add, minetest_after = vector.add, minetest.after

local function pos_to_string(pos) return ("%s, %s, %s"):format(pos.x, pos.y, pos.z) end
local function round_to_half_integer(x) return math.floor(x * 2 + 0.5) / 2 end

basic_machines.get_distributor_form = function(pos)
	local meta = minetest.get_meta(pos)

	local n = meta:get_int("n")
	local form = {"formspec_version[4]size[9.35," .. (1.8 + n * 0.85) .. "]"}

	if meta:get_int("view") == 0 then
		form[2] = "label[0.25,0.3;" .. F(S("Target")) .. "]label[4,0.3;" .. F(S("Mode")) .. "]"
		for i = 1, n do
			local posi = {x = meta:get_int("x" .. i), y = meta:get_int("y" .. i), z = meta:get_int("z" .. i)}
			local yi = 0.5 + (i - 1) * 0.85
			form[i + 2] = "field[0.25," .. yi .. ";1,0.8;x" .. i .. ";;" .. posi.x ..
				"]field[1.5," .. yi .. ";1,0.8;y" .. i .. ";;" .. posi.y ..
				"]field[2.75," .. yi .. ";1,0.8;z" .. i .. ";;" .. posi.z ..
				"]field[4," .. yi .. ";1,0.8;active" .. i .. ";;" .. meta:get_int("active" .. i) ..
				"]button[5.25," .. yi .. ";1.6,0.8;SHOW" .. i .. ";" .. F(S("Show @1", i)) ..
				"]button_exit[6.8," .. yi .. ";1,0.8;SET" .. i .. ";" .. F(S("Set")) ..
				"]button[8.1," .. yi .. ";1,0.8;X" .. i .. ";" .. F(S("x")) .. "]"
		end
	else
		form[2] = "label[0.25,0.3;" .. F(S("Position Name")) .. "]label[4,0.3;" .. F(S("Mode")) .. "]"
		for i = 1, n do
			local posi = {x = meta:get_int("x" .. i), y = meta:get_int("y" .. i), z = meta:get_int("z" .. i)}
			local yi = 0.5 + (i - 1) * 0.85
			local tname = minetest.get_node(vector_add(pos, posi)).name
			tname = posi.x .. " " .. posi.y .. " " .. posi.z .. " " .. tname:sub((tname:find(":") or 0) + 1)
			form[i + 2] = "field[0.25," .. yi .. ";3.5,0.8;text;;" .. tname ..
				"]field[4," .. yi .. ";1,0.8;active" .. i .. ";;" .. meta:get_int("active" .. i) ..
				"]button[5.25," .. yi .. ";1.6,0.8;SHOW" .. i .. ";" .. F(S("Show @1", i)) ..
				"]button_exit[6.8," .. yi .. ";1,0.8;SET" .. i .. ";" .. F(S("Set")) ..
				"]button[8.1," .. yi .. ";1,0.8;X" .. i .. ";" .. F(S("x")) .. "]"
		end
		form[#form + 1] = "button_exit[2.75," .. (0.75 + n * 0.85) .. ";1,0.8;scan;" .. F(S("scan")) .. "]"
	end

	local y = 0.75 + n * 0.85
	form[#form + 1] = "label[0.5," .. (1.15 + n * 0.85) .. ";" .. F(S("Delay")) ..
		"]field[1.5," .. y .. ";1,0.8;delay;;" .. basic_machines.truncate_to_two_decimals(meta:get_float("delay")) ..
		"]button_exit[4," .. y .. ";1,0.8;OK;" .. F(S("OK")) .. "]button[5.55," .. y .. ";1,0.8;ADD;" .. F(S("Add")) ..
		"]button[6.8," .. y .. ";1,0.8;view;" .. F(S("view")) .. "]button[8.1," .. y .. ";1,0.8;help;" .. F(S("help")) .. "]"

	return table.concat(form)
end

local machine_name = "basic_machines:distributor"
minetest.register_node(machine_name, {
	description = S("Distributor"),
	groups = {cracky = 3},
	tiles = {"basic_machines_distributor.png"},
	is_ground_content = false,
	sounds = basic_machines.sound_node_machine(),

	on_secondary_use = function(_, user)
		if user then
			local user_pos, name = user:get_pos(), user:get_player_name()
			local pos = basic_machines.get_event_distributor_near(user_pos)

			if minetest.is_protected(pos, name) then return end

			local user_pos_y = math.floor(user_pos.y + 0.5)
			local up_or_down
			if user_pos_y > pos.y then
				up_or_down = "▼"
			elseif user_pos_y < pos.y and user_pos_y + 1 < pos.y then
				up_or_down = "▲"
			else
				up_or_down = "–"
			end

			minetest.chat_send_player(name,
				S("DISTRIBUTOR: Position found at @1 (distance: @2, vertical: @3) - displaying mark 1",
				pos_to_string(pos), round_to_half_integer(vector.distance(user_pos, pos)), up_or_down))
			machines.mark_pos1(name, pos)
		end
	end,

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Distributor. Right click to set it up."))
		meta:set_string("owner", placer:get_player_name())

		for i = 1, 10 do
			meta:set_int("x" .. i, 0); meta:set_int("y" .. i, 1); meta:set_int("z" .. i, 0)
			meta:set_int("active" .. i, 1) -- target i
		end
		meta:set_int("n", 2) -- how many targets initially
		meta:set_float("delay", 0) -- delay when transmitting signal
	end,

	can_dig = basic_machines.can_dig,

	on_rightclick = function(pos, _, player)
		minetest.show_formspec(player:get_player_name(),
			"basic_machines:distributor_" .. minetest.pos_to_string(pos),
			basic_machines.get_distributor_form(pos))
	end,

	on_blast = function(pos, intensity)
		return basic_machines.on_blast(pos, intensity, machine_name)
	end,

	effector = {
		action_on = function(pos, ttl)
			if ttl < 1 then return end -- machines_TTL prevents infinite recursion

			local meta = minetest.get_meta(pos)

			local T = basic_machines.check_action(pos, true)
			if T > 2 then -- overheat
				minetest.sound_play(basic_machines.sound_overheat, {pos = pos, gain = 0.25, max_hear_distance = 16}, true)
				meta:set_string("infotext", S("Overheat! Temperature: @1", T))
				return
			elseif T == -1 then -- reset
				meta:set_string("infotext", "")
			end

			local function activate()
				local n = meta:get_int("n")
				for i = 1, n do
					local activei = meta:get_int("active" .. i)
					if activei ~= 0 then
						local posi = vector_add(pos, {x = meta:get_int("x" .. i), y = meta:get_int("y" .. i), z = meta:get_int("z" .. i)})
						local node = minetest.get_node(posi)
						local def = minetest.registered_nodes[node.name]

						-- check if all elements exist, safe cause it checks from left to right
						if def and (def.effector or def.mesecons and def.mesecons.effector) then
							-- alternative way: overkill, exception handling to determine if structure exists
							-- ret = pcall(function() if not def.effector then end end)

							local effector = def.effector or def.mesecons.effector
							local param = def.effector and (ttl - 1) or node

							if (activei == 1 or activei == 2) and effector.action_on then -- normal OR only forward input ON
								effector.action_on(posi, param)
							elseif activei == -1 and effector.action_off then
								effector.action_off(posi, param)
							end
						end
					end
				end
			end

			local delay = meta:get_float("delay")

			if delay > 0 then
				minetest_after(delay, activate)
			elseif delay == 0 then
				activate()
			else -- delay < 0 - do random activation: delay = -500 means 500/1000 chance to activate
				if math.random(1000) <= -delay then
					activate()
				end
			end
		end,

		action_off = function(pos, ttl)
			if ttl < 1 then return end -- machines_TTL prevents infinite recursion

			local meta = minetest.get_meta(pos)

			local T = basic_machines.check_action(pos, true)
			if T > 2 then -- overheat
				minetest.sound_play(basic_machines.sound_overheat, {pos = pos, gain = 0.25, max_hear_distance = 16}, true)
				meta:set_string("infotext", S("Overheat! Temperature: @1", T))
				return
			elseif T == -1 then -- reset
				meta:set_string("infotext", "")
			end

			local function activate()
				local n = meta:get_int("n")
				for i = 1, n do
					local activei = meta:get_int("active" .. i)
					if activei ~= 0 then
						local posi = vector_add(pos, {x = meta:get_int("x" .. i), y = meta:get_int("y" .. i), z = meta:get_int("z" .. i)})
						local node = minetest.get_node(posi)
						local def = minetest.registered_nodes[node.name]

						if def and (def.effector or def.mesecons and def.mesecons.effector) then
							local effector = def.effector or def.mesecons.effector
							local param = def.effector and (ttl - 1) or node

							if (activei == 1 or activei == -2) and effector.action_off then -- normal OR only forward input OFF
								effector.action_off(posi, param)
							elseif activei == -1 and effector.action_on then
								effector.action_on(posi, param)
							end
						end
					end
				end
			end

			local delay = meta:get_float("delay")
			if delay > 0 then minetest_after(delay, activate) else activate() end
		end
	}
})

if basic_machines.settings.register_crafts and basic_machines.use_default then
	minetest.register_craft({
		output = "basic_machines:distributor",
		recipe = {
			{"default:steel_ingot"},
			{"default:mese_crystal"},
			{"basic_machines:keypad"}
		}
	})
end