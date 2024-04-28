-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2024 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local machines_TTL = basic_machines.properties.machines_TTL
local max_range = basic_machines.properties.max_range
local mover_upgrade_max = basic_machines.properties.mover_upgrade_max
local mover_no_large_stacks = basic_machines.settings.mover_no_large_stacks
local sounds, punchset, keypad_soundlist, sound_selected = {}, {}, nil, {}

minetest.register_on_mods_loaded(function()
	local sounds_array, i = {}, 1
	for _, mod_name in ipairs(minetest.get_modnames()) do
		local sounds_path = minetest.get_modpath(mod_name) .. "/sounds"
		for _, sound_file in ipairs(minetest.get_dir_list(sounds_path, false)) do
			local sound_name = sound_file:match("(.*)%.ogg$")
			if sound_name then
				local sounds_name = sound_name:gsub("%.[0-9]$", "")
				if sound_name == sounds_name then
					sounds[i] = {name = sound_name}; i = i + 1
				else
					local sound = sounds_array[sounds_name]
					local id, count = (sound or {}).id or i, (sound or {}).count
					count = count and count + 1 or 1
					sounds_array[sounds_name] = {id = id, count = count}
					sounds[id] = {name = sounds_name, count = count}
					if count == 1 then i = i + 1 end
				end
			end
		end
	end
end)

minetest.register_on_joinplayer(function(player)
	punchset[player:get_player_name()] = {state = 0, node = ""}
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	punchset[name] = nil
	sound_selected[name] = nil
end)

-- SETUP BY PUNCHING
local punchable_nodes = {
	["basic_machines:detector"] = "DETECTOR",
	["basic_machines:keypad"] = "KEYPAD",
	["basic_machines:mover"] = "MOVER"
}

local description_translated = {
	["DETECTOR"] = S("DETECTOR"),
	["DISTRIBUTOR"] = S("DISTRIBUTOR"),
	["KEYPAD"] = S("KEYPAD"),
	["MOVER"] = S("MOVER")
}

local function check_keypad(pos, name) -- called only when manually activated via punch
	local meta = minetest.get_meta(pos)

	if meta:get_string("pass") == "" then
		basic_machines.use_keypad(pos, machines_TTL, true); return -- time to live set when punched
	end

	if name == "" then return end

	if meta:get_string("text") == "@" then -- keypad works as a keyboard
		minetest.show_formspec(name, "basic_machines:check_keypad_" .. minetest.pos_to_string(pos),
			"formspec_version[4]size[4,2.5]field[0.25,0.5;3.5,0.8;pass;" .. F(S("Enter text:")) ..
			";]button_exit[0.25,1.45;1,0.8;OK;" .. F(S("OK")) .. "]")
	else
		minetest.show_formspec(name, "basic_machines:check_keypad_" .. minetest.pos_to_string(pos),
			"formspec_version[4]size[4,2.5]no_prepend[]bgcolor[#FF8888BB;false]" ..
			"pwdfield[0.25,0.5;3.5,0.8;pass;" .. F(S("Enter password:")) ..
			"]button_exit[0.25,1.45;1,0.8;OK;" .. F(S("OK")) .. "]")
	end
end

local abs = math.abs

minetest.register_on_punchnode(function(pos, node, puncher)
	local name = puncher:get_player_name()
	local punch_state = punchset[name].state
	local punchset_desc = punchable_nodes[node.name]
	if punch_state == 0 and punchset_desc == nil then return end
	local punch_node = punchset[name].node
	punchset_desc = punch_node == "basic_machines:distributor" and "DISTRIBUTOR" or
		(punchable_nodes[punch_node] or punchset_desc)

	if punchset_desc ~= "KEYPAD" and minetest.is_protected(pos, name) then
		if punch_state > 0 then
			minetest.chat_send_player(name, S("@1: Punched position is protected. Aborting.", description_translated[punchset_desc]))
			punchset[name] = {state = 0, node = ""}
		end
		return
	end

	if punch_state == 0 then
		if punchset_desc == "KEYPAD" then
			local meta = minetest.get_meta(pos)
			if meta:get_int("x0") ~= 0 or meta:get_int("y0") ~= 0 or meta:get_int("z0") ~= 0 or
				meta:get_string("text") ~= ""
			then -- already configured
				check_keypad(pos, name); return -- not setup, just standard operation
			elseif minetest.is_protected(pos, name) then
				minetest.chat_send_player(name, S("KEYPAD: You must be able to build to set up keypad.")); return
			end
		end
		punchset[name] = {
			pos = pos,
			node = node.name,
			state = 1
		}
		local msg
		if punchset_desc == "MOVER" then
			msg = S("MOVER: Now punch source1, source2, end position to set up mover.")
		elseif punchset_desc == "KEYPAD" then
			msg = S("KEYPAD: Now punch the target block.")
		elseif punchset_desc == "DETECTOR" then
			msg = S("DETECTOR: Now punch the source block.")
		end
		if msg then
			minetest.chat_send_player(name, msg)
		end
		return
	end

	local self_pos = punchset[name].pos

	if minetest.get_node(self_pos).name ~= punch_node or (puncher:get_player_control() or {}).sneak	then
		minetest.chat_send_player(name, S("@1: Aborting interactive setup.", description_translated[punchset_desc]))
		machines.remove_markers(name, {"1", "11", "2"}); punchset[name] = {state = 0, node = ""}; return
	end


	-- MOVER
	if punchset_desc == "MOVER" then
		local meta = minetest.get_meta(self_pos)
		local upgradetype = meta:get_int("upgradetype")
		local privs = minetest.check_player_privs(name, "privs")
		local range

		if upgradetype == 1 or upgradetype == 3 or
			meta:get_inventory():get_stack("upgrade", 1):get_name() == "default:mese" -- for compatibility
		then
			range = math.min(mover_upgrade_max + 1, meta:get_int("upgrade")) * max_range
		else
			range = max_range
		end

		if punch_state == 1 then
			if not privs and
				(abs(pos.x - self_pos.x) > range or abs(pos.y - self_pos.y) > range or abs(pos.z - self_pos.z) > range)
			then
				minetest.chat_send_player(name, S("MOVER: Punch closer to mover. Resetting."))
				punchset[name] = {state = 0, node = ""}; return
			end

			if vector.equals(pos, self_pos) then
				minetest.chat_send_player(name, S("MOVER: Punch something else. Aborting."))
				punchset[name] = {state = 0, node = ""}; return
			end

			punchset[name].pos1 = pos -- source1
			punchset[name].state = 2
			machines.mark_pos1(name, pos, true) -- mark pos1
			minetest.chat_send_player(name, S("MOVER: Source1 position for mover set. Punch again to set source2 position."))
		elseif punch_state == 2 then
			if not privs and
				(abs(pos.x - self_pos.x) > range or abs(pos.y - self_pos.y) > range or abs(pos.z - self_pos.z) > range)
			then
				minetest.chat_send_player(name, S("MOVER: Punch closer to mover. Resetting."))
				machines.remove_markers(name, {"1"}); punchset[name] = {state = 0, node = ""}; return
			end

			if vector.equals(pos, self_pos) then
				minetest.chat_send_player(name, S("MOVER: Punch something else. Aborting."))
				machines.remove_markers(name, {"1"}); punchset[name] = {state = 0, node = ""}; return
			end

			punchset[name].pos11 = pos -- source2
			punchset[name].state = 3
			machines.mark_pos11(name, pos, true) -- mark pos11
			minetest.chat_send_player(name, S("MOVER: Source2 position for mover set. Punch again to set target position."))
		elseif punch_state == 3 then
			local mode = meta:get_string("mode")
			local pos1 = punchset[name].pos1

			if mode == "object" then -- check if elevator mode, only if object mode
				if meta:get_int("elevator") == 1 then meta:set_int("elevator", 0) end

				if (pos1.x == self_pos.x and pos1.z == self_pos.z and pos.x == self_pos.x and pos.z == self_pos.z) or
					(pos1.x == self_pos.x and pos1.y == self_pos.y and pos.x == self_pos.x and pos.y == self_pos.y) or
					(pos1.y == self_pos.y and pos1.z == self_pos.z and pos.y == self_pos.y and pos.z == self_pos.z)
				then
					local ecost = abs(pos.x - self_pos.x) + abs(pos.y - self_pos.y) + abs(pos.z - self_pos.z)
					if ecost > 3 then -- trying to make an elevator ?
						-- count number of diamond blocks to determine if elevator can be set up with this height distance
						local upgrade = meta:get_int("upgrade")
						local requirement = math.floor(ecost / 100) + 1
						if (upgrade - 1) >= requirement and (meta:get_int("upgradetype") == 2 or
							meta:get_inventory():get_stack("upgrade", 1):get_name() == "default:diamondblock") or upgrade == -1 -- for compatibility
						then
							meta:set_int("elevator", 1)
							meta:set_string("infotext", S("ELEVATOR: Activate to use."))
							minetest.chat_send_player(name, S("MOVER: Elevator setup completed, upgrade level @1.", upgrade - 1))
						else
							minetest.chat_send_player(name, S("MOVER: Error while trying to make an elevator. Need at least @1 diamond block(s) in upgrade (1 for every 100 distance).", requirement))
							machines.remove_markers(name, {"1", "11"}); punchset[name] = {state = 0, node = ""}; return
						end
					end
				end
			elseif not privs and
				(abs(pos.x - self_pos.x) > range or abs(pos.y - self_pos.y) > range or abs(pos.z - self_pos.z) > range)
			then
				minetest.chat_send_player(name, S("MOVER: Punch closer to mover. Aborting."))
				machines.remove_markers(name, {"1", "11"}); punchset[name] = {state = 0, node = ""}; return
			end

			machines.mark_pos2(name, pos, true) -- mark pos2

			local x0 = pos1.x - self_pos.x					-- source1
			local y0 = pos1.y - self_pos.y
			local z0 = pos1.z - self_pos.z

			local x1 = punchset[name].pos11.x - self_pos.x	-- source2
			local y1 = punchset[name].pos11.y - self_pos.y
			local z1 = punchset[name].pos11.z - self_pos.z

			local x2 = pos.x - self_pos.x					-- target
			local y2 = pos.y - self_pos.y
			local z2 = pos.z - self_pos.z

			if mode == "object" then
				meta:set_int("dim", -1)
			else
				if x0 > x1 then x0, x1 = x1, x0 end -- this ensures that x0 <= x1
				if y0 > y1 then y0, y1 = y1, y0 end
				if z0 > z1 then z0, z1 = z1, z0 end
				meta:set_int("dim", (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1))
			end

			meta:set_int("x0", x0); meta:set_int("y0", y0); meta:set_int("z0", z0)
			meta:set_int("x1", x1); meta:set_int("y1", y1); meta:set_int("z1", z1)
			meta:set_int("x2", x2); meta:set_int("y2", y2); meta:set_int("z2", z2)
			meta:set_int("pc", 0)
			punchset[name] = {state = 0, node = ""}
			minetest.chat_send_player(name, S("MOVER: End position for mover set."))
		end


	-- DISTRIBUTOR
	elseif punchset_desc == "DISTRIBUTOR" then
		local x = pos.x - self_pos.x
		local y = pos.y - self_pos.y
		local z = pos.z - self_pos.z

		if abs(x) > 2 * max_range or abs(y) > 2 * max_range or abs(z) > 2 * max_range then
			minetest.chat_send_player(name, S("DISTRIBUTOR: Punch closer to distributor. Aborting."))
			punchset[name] = {state = 0, node = ""}; return
		end

		machines.mark_pos1(name, pos, true) -- mark pos1

		local meta = minetest.get_meta(self_pos)
		meta:set_int("x" .. punch_state, x); meta:set_int("y" .. punch_state, y); meta:set_int("z" .. punch_state, z)
		if x == 0 and y == 0 and z == 0 then meta:set_int("active" .. punch_state, 0) end

		punchset[name] = {state = 0, node = ""}
		minetest.chat_send_player(name, S("DISTRIBUTOR: Target set."))


	-- KEYPAD
	elseif punchset_desc == "KEYPAD" then -- keypad setup code
		if minetest.is_protected(pos, name) then
			minetest.chat_send_player(name, S("KEYPAD: Punched position is protected. Aborting."))
			punchset[name] = {state = 0, node = ""}; return
		end

		local x = pos.x - self_pos.x
		local y = pos.y - self_pos.y
		local z = pos.z - self_pos.z

		if abs(x) > max_range or abs(y) > max_range or abs(z) > max_range then
			minetest.chat_send_player(name, S("KEYPAD: Punch closer to keypad. Resetting."))
			punchset[name] = {state = 0, node = ""}; return
		end

		machines.mark_pos1(name, pos, true) -- mark pos1

		local meta = minetest.get_meta(self_pos)
		meta:set_int("x0", x); meta:set_int("y0", y); meta:set_int("z0", z)
		if meta:get_string("pass") == "" then
			meta:set_string("infotext", S("Punch keypad to use it."))
		else
			meta:set_string("infotext", S("Punch keypad to use it. Password protected."))
		end
		punchset[name] = {state = 0, node = ""}
		minetest.chat_send_player(name, S("KEYPAD: Target set with coordinates @1, @2, @3.", x, y, z))


	-- DETECTOR
	elseif punchset_desc == "DETECTOR" then
		if abs(pos.x - self_pos.x) > max_range or
			abs(pos.y - self_pos.y) > max_range or
			abs(pos.z - self_pos.z) > max_range
		then
			minetest.chat_send_player(name, S("DETECTOR: Punch closer to detector. Aborting."))
			punchset[name] = {state = 0, node = ""}; return
		end

		if punch_state == 1 then
			punchset[name].pos1 = pos
			punchset[name].state = 2
			machines.mark_pos1(name, pos, true) -- mark pos1
			minetest.chat_send_player(name, S("DETECTOR: Now punch the target machine."))
		elseif punch_state == 2 then
			if vector.equals(pos, self_pos) then
				minetest.chat_send_player(name, S("DETECTOR: Punch something else. Aborting."))
				machines.remove_markers(name, {"1"}); punchset[name] = {state = 0, node = ""}; return
			end

			machines.mark_pos2(name, pos) -- mark pos2

			local x = punchset[name].pos1.x - self_pos.x
			local y = punchset[name].pos1.y - self_pos.y
			local z = punchset[name].pos1.z - self_pos.z

			local meta = minetest.get_meta(self_pos)
			meta:set_int("x0", x); meta:set_int("y0", y); meta:set_int("z0", z)
			x = pos.x - self_pos.x; y = pos.y - self_pos.y; z = pos.z - self_pos.z
			meta:set_int("x2", x); meta:set_int("y2", y); meta:set_int("z2", z)
			punchset[name] = {state = 0, node = ""}
			minetest.chat_send_player(name, S("DETECTOR: Setup complete."))
		end
	end
end)

-- FORM PROCESSING for all machines: mover, distributor, keypad, detector
local fnames = {
	"basic_machines:mover_",
	"basic_machines:distributor_",
	"basic_machines:keypad_",
	"basic_machines:check_keypad_",
	"basic_machines:sounds_keypad_",
	"basic_machines:detector_"
}

local function check_fname(formname)
	for i = 1, #fnames do
		local fname = fnames[i]; local fname_len = fname:len()
		if formname:sub(1, fname_len) == fname then
			return fname:sub(("basic_machines:"):len() + 1, fname_len - 1), formname:sub(fname_len + 1)
		end
	end
end

local function strip_translator_sequence(msg, default)
	return msg and msg:match("%)([%w_-]+)") or default
end

-- list of machines that distributor can connect to, used for distributor scan feature
local connectables = {
	["basic_machines:ball_spawner"] = true,
	["basic_machines:battery_0"] = true,
	["basic_machines:battery_1"] = true,
	["basic_machines:battery_2"] = true,
	["basic_machines:clockgen"] = true,
	["basic_machines:detector"] = true,
	["basic_machines:distributor"] = true,
	["basic_machines:generator"] = true,
	["basic_machines:keypad"] = true,
	["basic_machines:light_off"] = true,
	["basic_machines:light_on"] = true,
	["basic_machines:mover"] = true
}

local use_unifieddyes = minetest.global_exists("unifieddyes")

minetest.register_on_player_receive_fields(function(player, formname, fields)
	local formname_sub, pos = check_fname(formname); if not formname_sub or pos == "" then return end
	local name = player:get_player_name(); if name == "" then return end
	pos = minetest.string_to_pos(pos)
	local meta = minetest.get_meta(pos)


	-- MOVER
	if formname_sub == "mover" then
		if fields.OK then
			if minetest.is_protected(pos, name) then return end

			if meta:get_int("seltab") == 2 then -- POSITIONS
				local x0, y0, z0 = tonumber(fields.x0) or 0, tonumber(fields.y0) or -1, tonumber(fields.z0) or 0
				local x1, y1, z1 = tonumber(fields.x1) or 0, tonumber(fields.y1) or -1, tonumber(fields.z1) or 0
				local x2, y2, z2 = tonumber(fields.x2) or 0, tonumber(fields.y2) or 1, tonumber(fields.z2) or 0

				if minetest.is_protected(vector.add(pos, {x = x0, y = y0, z = z0}), name) or
					minetest.is_protected(vector.add(pos, {x = x1, y = y1, z = z1}), name) or
					minetest.is_protected(vector.add(pos, {x = x2, y = y2, z = z2}), name)
				then
					minetest.chat_send_player(name, S("MOVER: Position is protected. Aborting.")); return
				end

				-- did the numbers change from last time ?
				if meta:get_int("x0") ~= x0 or meta:get_int("y0") ~= y0 or meta:get_int("z0") ~= z0 or
					meta:get_int("x1") ~= x1 or meta:get_int("y1") ~= y1 or meta:get_int("z1") ~= z1 or
					meta:get_int("x2") ~= x2 or meta:get_int("y2") ~= y2 or meta:get_int("z2") ~= z2
				then
					-- are new numbers inside bounds ?
					if not minetest.check_player_privs(name, "privs") and
						(abs(x0) > max_range or abs(y0) > max_range or abs(z0) > max_range or
						abs(x1) > max_range or abs(y1) > max_range or abs(z1) > max_range or
						abs(x2) > max_range or abs(y2) > max_range or abs(z2) > max_range)
					then
						minetest.chat_send_player(name, S("MOVER: All coordinates must be between @1 and @2. For increased range set up positions by punching.",
							-max_range, max_range)); return
					end
				end

				if meta:get_string("mode") == "object" then
					meta:set_int("dim", -1)
				else
					local x = x0; x0 = math.min(x, x1); x1 = math.max(x, x1)
					local y = y0; y0 = math.min(y, y1); y1 = math.max(y, y1)
					local z = z0; z0 = math.min(z, z1); z1 = math.max(z, z1)
					meta:set_int("dim", (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1))
				end

				meta:set_int("x0", x0); meta:set_int("y0", y0); meta:set_int("z0", z0)
				meta:set_int("x1", x1); meta:set_int("y1", y1); meta:set_int("z1", z1)
				meta:set_int("x2", x2); meta:set_int("y2", y2); meta:set_int("z2", z2)

				meta:set_string("inv1", strip_translator_sequence(fields.inv1, ""))
				meta:set_string("inv2", strip_translator_sequence(fields.inv2, ""))
				meta:set_int("reverse", tonumber(fields.reverse) or 0)

				-- notification
				meta:set_string("infotext", S("Mover block." ..
					" Set up with source coordinates @1, @2, @3 -> @4, @5, @6 and target coordinates @7, @8, @9." ..
					" Put charged battery next to it and start it with keypad.", x0, y0, z0, x1, y1, z1, x2, y2, z2))
			else -- MODE
				local mmode = meta:get_string("mode")
				local mode = strip_translator_sequence(fields.mode, mmode)
				local prefer = fields.prefer or ""

				-- mode
				if mode ~= mmode then
					if prefer:len() > 4896 then
						minetest.chat_send_player(name, S("MOVER: Filter too long."))
					elseif basic_machines.check_mover_filter(mode, pos, meta, prefer) then -- input validation
						if mover_no_large_stacks and basic_machines.check_mover_target(mode, pos, meta) then
							prefer = basic_machines.clamp_item_count(prefer)
						end
						meta:set_string("mode", mode)
					else
						minetest.chat_send_player(name, S("MOVER: Wrong filter - must be name of existing minetest block"))
					end
				end

				-- filter
				if prefer ~= meta:get_string("prefer") then
					if prefer:len() > 4896 then
						minetest.chat_send_player(name, S("MOVER: Filter too long."))
					elseif basic_machines.check_mover_filter(mode, pos, meta, prefer) then -- input validation
						if mover_no_large_stacks and basic_machines.check_mover_target(mode, pos, meta) then
							prefer = basic_machines.clamp_item_count(prefer)
						end
						meta:set_string("prefer", prefer)
						meta:get_inventory():set_list("filter", {})
					else
						minetest.chat_send_player(name, S("MOVER: Wrong filter - must be name of existing minetest block"))
					end
				end

				if meta:get_float("fuel") < 0 then meta:set_float("fuel", 0) end -- reset block

				local fpos = basic_machines.find_and_connect_battery(pos, meta)
				if fpos then
					minetest.chat_send_player(name, S("MOVER: Battery found - displaying mark 1"))
					machines.mark_pos1(name, fpos) -- display battery
				elseif meta:get_int("upgrade") ~= -1 then
					minetest.chat_send_player(name, S("MOVER: Please put battery nearby"))
				end
			end

		elseif fields.tabs then
			meta:set_int("seltab", tonumber(fields.tabs) or 1)

			minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
				basic_machines.get_mover_form(pos))

		elseif fields.now then -- mark current position
			local markerN = machines.mark_posN(meta:get_string("owner"), pos)
			if markerN then markerN:get_luaentity()._origin = pos end

		elseif fields.show then -- display mover area defined by sources
			local pos1 = {x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")}	-- source1
			local pos11 = {x = meta:get_int("x1"), y = meta:get_int("y1"), z = meta:get_int("z1")}	-- source2
			local markerS = machines.mark_posS(name, vector.add(pos, vector.divide(vector.add(pos1, pos11), 2)))
			if markerS then
				markerS:set_properties({visual_size = {x = abs(pos11.x - pos1.x) + 1.11,
					y = abs(pos11.y - pos1.y) + 1.11, z = abs(pos11.z - pos1.z) + 1.11}})
			end

		elseif fields.help then
			minetest.show_formspec(name, "basic_machines:help_mover", "formspec_version[4]size[8,9.3]textarea[0,0.35;8,8.95;help;" ..
				F(S("Mover help")) .. ";" .. F(S("version @1\nSetup: For interactive setup punch the mover and follow chat instructions (hold sneak and punch a block to abort setup)." ..
				" Put the mover directly next to a battery. For advanced setup right click mover." ..
				" Positions are defined by (x, y, z) coordinates. Mover itself is at coordinates (0, 0, 0).", basic_machines.version)) ..
				F(S("\n\nModes of operation: normal (just teleport block), dig (digs and gives you resulted node - good for harvesting farms);" ..
				" by setting 'filter' only selected node is moved, drop (drops node on ground), object (teleportation of players and objects)" ..
				" - distance between source1/2 defines teleport radius; by setting 'filter' you can specify move time - [0.2, 20] - for non players.\n" ..
				"After changing from/to object mode, you need to reconfigure sources position.\n" ..
				"Inventory mode can exchange items between node inventories." ..
				" You need to select inventory name for source/target from the dropdown list on the right." ..
				"\n\nAdvanced:\nYou can reverse start/end position by setting reverse nonzero." ..
				" This is useful for placing stuff at many locations-planting." ..
				" If you put reverse = 2/3 in transport mode it will disable parallel transport but will still do reverse effect with 3." ..
				" If you activate mover with OFF signal it will toggle reverse.")) ..
				F(S("\n\nFuel consumption depends on blocks to be moved, distance and temperature." ..
				" For example, stone or tree is harder to move than dirt, harvesting wheat is very cheap and and moving lava is very hard." ..
				" High temperature increases fuel consumption while low temperature reduces it." ..
				"\n\nUpgrade mover by moving mese blocks in upgrade inventory." ..
				" Each mese block increases mover range by @1, fuel consumption is divided by number of mese blocks in upgrade." ..
				" Max @2 blocks are used for upgrade." ..
				"\n\nActivate mover by keypad/detector signal or mese signal through mesecon adapter (if mesecons mod).",
				max_range, mover_upgrade_max)) .. "]")

		elseif fields.mode then
			if fields.quit or minetest.is_protected(pos, name) then return end

			local mmode = meta:get_string("mode")
			local mode = strip_translator_sequence(fields.mode, mmode)
			if mode == mmode then return end

			local prefer = fields.prefer or ""
			if prefer:len() > 4896 then
				minetest.chat_send_player(name, S("MOVER: Filter too long."))
			elseif basic_machines.check_mover_filter(mode, pos, meta, prefer) then -- input validation
				if mover_no_large_stacks and basic_machines.check_mover_target(mode, pos, meta) then
					prefer = basic_machines.clamp_item_count(prefer)
				end

				if prefer ~= meta:get_string("prefer") then
					meta:set_string("prefer", prefer)
					meta:get_inventory():set_list("filter", {})
				end

				meta:set_string("mode", mode)

				minetest.show_formspec(name, "basic_machines:mover_" .. minetest.pos_to_string(pos),
					basic_machines.get_mover_form(pos))
			else
				minetest.chat_send_player(name, S("MOVER: Wrong filter - must be name of existing minetest block"))
			end
		end


	-- DISTRIBUTOR
	elseif formname_sub == "distributor" then
		if fields.OK then
			if minetest.is_protected(pos, name) then return end

			local not_view = meta:get_int("view") == 0
			for i = 1, meta:get_int("n") do
				local xi, yi, zi = meta:get_int("x" .. i), meta:get_int("y" .. i), meta:get_int("z" .. i)
				local posfi = {
					x = tonumber(fields["x" .. i]) or xi,
					y = tonumber(fields["y" .. i]) or yi,
					z = tonumber(fields["z" .. i]) or zi
				}

				if minetest.is_protected(vector.add(pos, posfi), name) then
					minetest.chat_send_player(name, S("DISTRIBUTOR: Position @1 is protected. Aborting.",
						minetest.pos_to_string(posfi))); return
				end

				if not_view and (posfi.xi ~= xi or posfi.yi ~= yi or posfi.z ~= zi) then
					if not minetest.check_player_privs(name, "privs") and
						(abs(posfi.x) > 2 * max_range or abs(posfi.y) > 2 * max_range or abs(posfi.z) > 2 * max_range)
					then
						minetest.chat_send_player(name, S("DISTRIBUTOR: All coordinates must be between @1 and @2.",
							-2 * max_range, 2 * max_range)); return
					end

					meta:set_int("x" .. i, posfi.x); meta:set_int("y" .. i, posfi.y); meta:set_int("z" .. i, posfi.z)
				end

				local activefi = tonumber(fields["active" .. i]) or 0
				if meta:get_int("active" .. i) ~= activefi then
					if vector.equals(posfi, {x = 0, y = 0, z = 0}) then
						meta:set_int("active" .. i, 0) -- no point in activating itself
					else
						meta:set_int("active" .. i, activefi)
					end
				end
			end

			meta:set_float("delay", basic_machines.twodigits_float(tonumber(fields.delay) or 0))

		elseif fields.ADD then
			if minetest.is_protected(pos, name) then return end

			local n = meta:get_int("n")
			if n < 16 then meta:set_int("n", n + 1) end -- max 16 outputs

			minetest.show_formspec(name, "basic_machines:distributor_" .. minetest.pos_to_string(pos),
				basic_machines.get_distributor_form(pos))

		elseif fields.view then -- change view mode
			meta:set_int("view", 1 - meta:get_int("view"))

			minetest.show_formspec(name, "basic_machines:distributor_" .. minetest.pos_to_string(pos),
				basic_machines.get_distributor_form(pos))

		elseif fields.scan then -- scan for connectable nodes
			if minetest.is_protected(pos, name) then return end

			local x1, y1, z1 = meta:get_int("x1"), meta:get_int("y1"), meta:get_int("z1")
			local x2, y2, z2 = meta:get_int("x2"), meta:get_int("y2"), meta:get_int("z2")

			if x1 > x2 then x1, x2 = x2, x1 end
			if y1 > y2 then y1, y2 = y2, y1 end
			if z1 > z2 then z1, z2 = z2, z1 end

			local count = 0

			for x = x1, x2 do
				for y = y1, y2 do
					for z = z1, z2 do
						if count >= 16 then break end
						local poss = vector.add(pos, {x = x, y = y, z = z})
						if not minetest.is_protected(poss, name) and
							connectables[minetest.get_node(poss).name]
						then
							count = count + 1
							meta:set_int("x" .. count, x); meta:set_int("y" .. count, y); meta:set_int("z" .. count, z)
							meta:set_int("active" .. count, 1) -- turns the connection on
						end
					end
				end
			end

			meta:set_int("n", count)
			minetest.chat_send_player(name, S("DISTRIBUTOR: Connected @1 targets.", count))

		elseif fields.help then
			minetest.show_formspec(name, "basic_machines:help_distributor", "formspec_version[4]size[7.4,7.4]textarea[0,0.35;7.4,7.05;help;" ..
				F(S("Distributor help")) .. ";" .. F(S("Target: Coordinates (x, y, z) relative to the distributor." ..
				"\n\nMode: -2=only OFF, -1=NOT input, 0/1=input, 2=only ON, output signal of the target." ..
				"\n\nDelay: Adds delay to activations, in seconds. A negative delay activation is randomized with probability -delay/1000.")) ..
				F(S("\n\nSetup: To select a target for activation, click \"Set\" button then click the target (hold sneak and punch a block to abort setup).\n" ..
				"You can add more targets with \"Add\" button. To see where the target is click \"Show\" button next to it.\n" ..
				"4 numbers in each row represent (from left to right): first 3 numbers are target coordinates (x, y, z), last number (Mode) controls how signal is passed to target.\n" ..
				"For example, to only pass OFF signal use -2, to only pass ON signal use 2, -1 negates the signal, 1 passes original signal, 0 blocks signal.\n" ..
				"\"view\" button toggles view of target names, in names view there is \"scan\" button which automatically scans for valid targets in a box defined by first and second target."..
				"\n\nAdvanced:\nYou can use the distributor as an event handler - it listens to events like interact attempts and chat around the distributor.\n" ..
				"You need to place the distributor at a position (x, y, z), with coordinates of the form (20*i, 20*j+1, 20*k) for some integers i, j, k.\n" ..
				"Right click holding a distributor in the hand to show a suitable position.\n" ..
				"Then you need to configure first row of numbers in the distributor:\n" ..
				"By putting 0 as Mode it will start to listen." ..
				" First number x = 0/1 controls if node listens to failed interact attempts around it, second number y = -1/0/1 controls listening to chat (-1 additionally mutes chat)")) .. "]")

		else
			local n, j = meta:get_int("n"), -1

			-- SHOWING TARGET
			for i = 1, n do if fields["SHOW" .. i] then j = i; break end end
			-- show j - th point
			if j > 0 then
				machines.mark_pos1(name, vector.add(pos, {
					x = meta:get_int("x" .. j),
					y = meta:get_int("y" .. j),
					z = meta:get_int("z" .. j)
				}))
				return
			end

			if minetest.is_protected(pos, name) then return end

			-- SETUP TARGET
			for i = 1, n do if fields["SET" .. i] then j = i; break end end
			-- set up j - th point
			if j > 0 then
				punchset[name] = {
					pos = pos,
					node = "basic_machines:distributor",
					state = j
				}
				minetest.chat_send_player(name, S("DISTRIBUTOR: Punch the position to set target @1.", j)); return
			end

			-- REMOVE TARGET
			if n > 0 then
				for i = 1, n do if fields["X" .. i] then j = i; break end end
				-- remove j - th point
				if j > 0 then
					for i = j, n - 1 do
						meta:set_int("x" .. i, meta:get_int("x" .. (i + 1)))
						meta:set_int("y" .. i, meta:get_int("y" .. (i + 1)))
						meta:set_int("z" .. i, meta:get_int("z" .. (i + 1)))
						meta:set_int("active" .. i, meta:get_int("active" .. (i + 1)))
					end

					meta:set_int("n", n - 1)

					minetest.show_formspec(name, "basic_machines:distributor_" .. minetest.pos_to_string(pos),
						basic_machines.get_distributor_form(pos))
				end
			end
		end


	-- KEYPAD
	elseif formname_sub == "keypad" then
		if fields.OK then
			if minetest.is_protected(pos, name) then return end

			local x0, y0, z0 = tonumber(fields.x0) or 0, tonumber(fields.y0) or 1, tonumber(fields.z0) or 0

			if minetest.is_protected(vector.add(pos, {x = x0, y = y0, z = z0}), name) then
				minetest.chat_send_player(name, S("KEYPAD: Position is protected. Aborting.")); return
			end

			if not minetest.check_player_privs(name, "privs") and
				(abs(x0) > max_range or abs(y0) > max_range or abs(z0) > max_range)
			then
				minetest.chat_send_player(name, S("KEYPAD: All coordinates must be between @1 and @2.",
					-max_range, max_range)); return
			end

			meta:set_int("mode", tonumber(fields.mode) or 2)
			meta:set_int("iter", math.min(tonumber(fields.iter) or 1, 500)); meta:set_int("count", 0)

			local pass = fields.pass or ""

			if pass == "" then
				if meta:get_string("pass") ~= "" then
					meta:set_string("pass", "")
				end
			else
				local mpass = meta:get_string("pass")
				if pass ~= mpass then
					if pass:len() > 16 then -- don't replace password with hash which is longer - 27 chars
						pass = mpass
						minetest.chat_send_player(name, S("KEYPAD: Password too long."))
					else
						pass = minetest.get_password_hash(pos.x, pass .. pos.y); pass = minetest.get_password_hash(pos.y, pass .. pos.z)
						meta:set_string("pass", pass)
					end
				end
			end

			local text = fields.text or ""

			if text:len() > 4896 then
				text = meta:get_string("text")
				minetest.chat_send_player(name, S("KEYPAD: Text too long."))
			else
				meta:set_string("text", text)
			end
			meta:set_int("x0", x0); meta:set_int("y0", y0); meta:set_int("z0", z0)

			if pass == "" then
				if (text):byte() == 36 then -- text starts with $, play sound
					meta:set_string("infotext", S("Punch keypad to play sound."))
				else
					meta:set_string("infotext", S("Punch keypad to use it."))
				end
			elseif text == "@" then
				meta:set_string("infotext", S("Punch keyboard to use it."))
			else
				meta:set_string("infotext", S("Punch keypad to use it. Password protected."))
			end

		elseif fields.sounds then
			if keypad_soundlist == nil then
				keypad_soundlist = {}
				for i, v in ipairs(sounds) do
					local count, sound = v.count, v.name
					if count and count > 1 then
						sound = sound .. " " .. S("(@1 sounds)", count)
					end
					keypad_soundlist[i] = F(sound:gsub("_", " "))
				end
				keypad_soundlist = table.concat(keypad_soundlist, ",")
			end

			local idx, text = sound_selected[name], meta:get_string("text")
			if idx and text:byte() == 36 or text:byte() == 36 then -- text starts with $
				text = text:sub(2)
				if text ~= "" then
					local sound_text
					if idx then
						local sound_name = (sounds[idx] or {}).name
						sound_text = sound_name and "$" .. sound_name
					end
					text = text:split(" ")[1]
					if sound_text and sound_text ~= text or not sound_text then
						for i, v in ipairs(sounds) do
							if v.name == text then sound_selected[name] = i; break end
						end
					end
				end
			end

			minetest.show_formspec(name, "basic_machines:sounds_keypad_" .. minetest.pos_to_string(pos),
				"formspec_version[4]size[7.75,5.75]" ..
				"label[0.25,0.3;" .. F(S("Sounds (@1):", #sounds)) ..
				"]textlist[0.25,0.5;6,5;sound;" .. keypad_soundlist .. ";" .. (sound_selected[name] or 0) ..
				"]button_exit[6.5,0.6;1,0.8;OK;" .. F(S("OK")) .. "]")

		elseif fields.help then
			minetest.show_formspec(name, "basic_machines:help_keypad", "formspec_version[4]size[8,9.3]textarea[0,0.35;8,8.95;help;" ..
				F(S("Keypad help")) .. ";" .. F(S("Mode: 0=IDLE, 1=OFF, 2=ON, 3=TOGGLE, control the way how the target is activated." ..
				"\n\nRepeat: Number to control how many times activation is repeated after initial punch." ..
				"\n\nPassword: Enter password and press OK. Password will be encrypted." ..
				" Next time you use keypad you will need to enter correct password to gain access." ..
				"\n\nText: If set then text on target node will be changed." ..
				" In case target is detector/mover, filter settings will be changed. Can be used for special operations." ..
				"\n\nTarget: Coordinates (x, y, z) relative to the keypad." ..
				" (0, 0, 0) is keypad itself, (0, 1, 0) is one node above, (0, -1, 0) one node below." ..
				" X coordinate axes goes from east to west, Y from down to up, Z from south to north.")) ..
				F(S("\n\nSetup: Right click or punch (left click) the keypad, then follow chat instructions (hold sneak and punch a block to abort setup)." ..
				"\n\nTo set text on other nodes (text shows when you look at node) just target the node and set nonempty text." ..
				" Upon activation text will be set:\nWhen target node is keypad, its \"text\" field will be set.\n" ..
				"When target is detector/mover, its \"filter\" field will be set. To clear \"filter\" set text to \"@@\".\n" ..
				"When target is distributor, you can change i-th target of distributor mode with \"<i> <mode>\".\n" ..
				"When target is autocrafter, set i-th recipe with \"<itemname> [<i>]\". To clear the recipe set text to \"@@\".")) ..
				(use_unifieddyes and F(S("\nWhen target is light, you can change the index value (a multiple of 8) with \"i<index>\".")) or "") ..
				F(S("\n\nKeyboard: To use keypad as keyboard for text input write \"@@\" in \"text\" field and set any password." ..
				" Next time keypad is used it will work as text input device." ..
				"\n\nDisplaying messages to nearby players (up to 5 blocks around keypad's target): Set text to \"!text\"." ..
				" Upon activation player will see \"text\" in their chat." ..
				"\n\nPlaying sound to nearby players: set text to \"$sound_name\", optionally followed by a space and pitch value: 0.01 to 10. Can choose a sound with sounds menu.")) ..
				F(S("\n\nAdvanced:\nText replacement: Suppose keypad A is set with text \"@@some @@. text @@!\" and there are blocks on top of keypad A with infotext '1' and '2'." ..
				" Suppose we target B with A and activate A. Then text of keypad B will be set to \"some 1. text 2!\"." ..
				"\nWord extraction: Suppose similar setup but now keypad A is set with text \"%1\"." ..
				" Then upon activation text of keypad B will be set to 1.st word of infotext." ..
				"\n\nRotating List: A keypad's text prefixed with the \"^\" symbol will be interpreted as a rotating list, with items separated by spaces.\n" ..
				"On each signal, the keypad will transmit one word to the target.\n Example: Keypad configured to target mover filter with: \"^farming:wheat_8 farming:rice_8\"" ..
				"\nThe \"#\" symbol is used to escape spaces. For instance, a keypad targeting an autocrafter could be set as:\n\"^farming:flour#1 farming:flour#4\"")) .. "]")
		end

	elseif formname_sub == "check_keypad" then
		if fields.OK then
			local pass = fields.pass or ""

			if meta:get_string("text") == "@" then -- keyboard mode
				meta:set_string("input", pass)
				basic_machines.use_keypad(pos, machines_TTL)
			else
				pass = minetest.get_password_hash(pos.x, pass .. pos.y); pass = minetest.get_password_hash(pos.y, pass .. pos.z)
				if pass == meta:get_string("pass") then
					minetest.chat_send_player(name, S("ACCESS GRANTED"))

					local count = meta:get_int("count")
					if count == 0 or count == meta:get_int("iter") then -- only accept new operation requests if idle
						basic_machines.use_keypad(pos, machines_TTL)
					else
						basic_machines.use_keypad(pos, 1, true, S("Operation aborted by user. Punch to activate.")) -- reset
					end
				else
					minetest.chat_send_player(name, S("ACCESS DENIED. WRONG PASSWORD."))
				end
			end
		end

	elseif formname_sub == "sounds_keypad" then
		if minetest.is_protected(pos, name) then return end

		if fields.sound then
			sound_selected[name] = minetest.explode_textlist_event(fields.sound).index

		elseif fields.OK then
			local i = sound_selected[name]
			if i then
				local sound_name = (sounds[i] or {}).name
				if sound_name then
					local sound_text = "$" .. sound_name
					if sound_text ~= meta:get_string("text"):split(" ")[1] then
						meta:set_string("text", sound_text)
						meta:set_string("infotext", S("Punch keypad to play sound."))
					end
				end
			end

		else
			sound_selected[name] = nil
		end


	-- DETECTOR
	elseif formname_sub == "detector" then
		if fields.OK then
			if minetest.is_protected(pos, name) then return end

			local x0, y0, z0 = tonumber(fields.x0) or 0, tonumber(fields.y0) or 0, tonumber(fields.z0) or 0
			local x1, y1, z1 = tonumber(fields.x1) or 0, tonumber(fields.y1) or 0, tonumber(fields.z1) or 0
			local x2, y2, z2 = tonumber(fields.x2) or 0, tonumber(fields.y2) or 0, tonumber(fields.z2) or 0

			if minetest.is_protected(vector.add(pos, {x = x0, y = y0, z = z0}), name) or
				minetest.is_protected(vector.add(pos, {x = x1, y = y1, z = z1}), name) or
				minetest.is_protected(vector.add(pos, {x = x2, y = y2, z = z2}), name)
			then
				minetest.chat_send_player(name, S("DETECTOR: Position is protected. Aborting.")); return
			end

			if not minetest.check_player_privs(name, "privs") and
				(abs(x0) > max_range or abs(y0) > max_range or abs(z0) > max_range or
				abs(x1) > max_range or abs(y1) > max_range or abs(z1) > max_range or
				abs(x2) > max_range or abs(y2) > max_range or abs(z2) > max_range)
			then
				minetest.chat_send_player(name, S("DETECTOR: All coordinates must be between @1 and @2.",
					-max_range, max_range)); return
			end

			meta:set_int("x0", x0); meta:set_int("y0", y0); meta:set_int("z0", z0)
			meta:set_int("x1", x1); meta:set_int("y1", y1); meta:set_int("z1", z1)
			meta:set_int("x2", x2); meta:set_int("y2", y2); meta:set_int("z2", z2)

			meta:set_string("op", strip_translator_sequence(fields.op, ""))
			meta:set_int("r", math.min((tonumber(fields.r) or 1), max_range))
			local filter = fields.node or ""
			if filter:len() > 4896 then
				minetest.chat_send_player(name, S("DETECTOR: Detection filter too long."))
			else
				meta:set_string("node", filter)
			end
			meta:set_int("NOT", tonumber(fields.NOT) or 0)
			meta:set_string("mode", strip_translator_sequence(fields.mode, ""))
			meta:set_string("inv1", strip_translator_sequence(fields.inv1, ""))

		elseif fields.help then
			minetest.show_formspec(name, "basic_machines:help_detector", "formspec_version[4]size[7.4,7.4]textarea[0,0.35;7.4,7.05;help;" ..
				F(S("Detector help")) .. ";" .. F(S("Setup: Right click or punch and follow chat instructions (hold sneak and punch a block to abort setup)." ..
				" With a detector you can detect nodes, objects, players, items inside inventories, nodes information and light levels. " ..
				"If detector activates it will trigger machine (on or off) at target position." ..
				"\n\nThere are 6 modes of operation - node/player/object/inventory/infotext/light detection." ..
				" Inside detection filter write node/player/object name or infotext/light level." ..
				" If you detect node/player/object you can specify a range of detection." ..
				" If you want detector to activate target precisely when its not triggered set output signal to 1." ..
				"\n\nFor example, to detect empty space write air, to detect tree write default:tree, to detect ripe wheat write farming:wheat_8, for flowing water write default:water_flowing... " ..
				"If mode is inventory it will check for items in specified inventory of source node like a chest." ..
				"\n\nAdvanced:\nIn inventory (must set a filter)/node detection mode, you can specify a second source and select AND/OR from the right top dropdown list to do logical operations." ..
				"\nYou can also filter output signal in any modes:\n" ..
				"-2=only OFF, -1=NOT, 0/1=normal, 2=only ON, 3=only if changed, 4=if target is keypad set its text to detected object name.")) .. "]")
		end
	end
end)