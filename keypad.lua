-- (c) 2015-2016 rnd
-- Copyright (C) 2022-2023 мтест
-- See README.md for license details

local F, S = basic_machines.F, basic_machines.S
local machines_TTL = basic_machines.properties.machines_TTL
local machines_minstep = basic_machines.properties.machines_minstep
local machines_timer = basic_machines.properties.machines_timer
local mover_no_large_stacks = basic_machines.settings.mover_no_large_stacks
local string_byte = string.byte
local signs -- when activated with keypad their text will be updated
local use_signs_lib = minetest.global_exists("signs_lib")
local use_default = basic_machines.use_default
local use_unifieddyes = minetest.global_exists("unifieddyes")

if use_signs_lib then
	signs = {}
	for _, sign_name in ipairs(signs_lib.lbm_restore_nodes or {}) do
		signs[sign_name] = true
	end
elseif use_default then
	signs = {
		["default:sign_wall_steel"] = true,
		["default:sign_wall_wood"] = true
	}
else
	signs = {}
end

local keypad_rot_list_idx_cache = {} -- Skaapdev add keypad support rotating word extraction from own list.
local function keypad_rot_list(text, pos)
	text = text:sub(2) -- Remove leading `^` from text.
	local i
	local pos_str = minetest.pos_to_string(pos)
	if keypad_rot_list_idx_cache[pos_str] ~= nil then
		i = keypad_rot_list_idx_cache[pos_str]
	else
		keypad_rot_list_idx_cache[pos_str] = 1
		i = 1
	end
	-- Extract words(seperated by space) from text. Replace '#' symbol with spaces in word.
	local words = {}; for word in text:gmatch("%S+") do word = word:gsub("#", " "); table.insert(words, word) end;
	if i <= #words then
		text = words[i]
		i = i + 1
	else
		text = words[1]
		i = 2
	end
	keypad_rot_list_idx_cache[pos_str] = i
    return text
end -- skaapdev end

-- position, time to live (how many times can signal travel before vanishing to prevent infinite recursion),
-- do we want to stop repeating
basic_machines.use_keypad = function(pos, ttl, reset, reset_msg)
	if ttl < 1 then return end

	local meta = minetest.get_meta(pos)
	local msg

	-- temperature
	local t0, t1 = meta:get_int("t"), minetest.get_gametime()
	local T = meta:get_int("T") -- temperature

	if t0 > t1 - machines_minstep then -- activated before natural time
		T = T + 1
	elseif T > 0 then
		if t1 - t0 > machines_timer then -- reset temperature if more than 5s (by default) elapsed since last activation
			T = 0; msg = ""
		else
			T = T - 1
		end
	end
	meta:set_int("t", t1); meta:set_int("T", T)

	if T > 2 then -- overheat
		minetest.sound_play(basic_machines.sound_overheat, {pos = pos, max_hear_distance = 16, gain = 0.25}, true)
		meta:set_string("infotext", S("Overheat! Temperature: @1", T))
		return
	end

	-- protection check
	if minetest.is_protected(pos, meta:get_string("owner")) then
		meta:set_int("count", 0)
		meta:set_int("T", T + 2)
		meta:set_string("infotext", S("Protection fail. Reset."))
		return
	end

	-- repeating activation
	local iter = meta:get_int("iter")
	if iter == 0 then if msg then meta:set_string("infotext", msg) end; return end
	local count = 0 -- counts repeats

	if iter > 1 then
		if basic_machines.properties.no_clock then return end
		count = meta:get_int("count")

		if reset and count > 0 or count == iter then
			meta:set_int("count", 0)
			meta:set_int("T", 4)
			meta:set_string("infotext", reset_msg or
				S("KEYPAD: Resetting. Punch again after @1s to activate.", machines_timer))
			return
		end

		if count < iter - 1 then
			minetest.after(machines_timer, function()
				basic_machines.use_keypad(pos, machines_TTL)
			end)
		end

		if count < iter then -- this is keypad repeating activation
			count = count + 1; meta:set_int("count", count)
			count = iter - count
		end
	end

	-- set text on target
	local text = meta:get_string("text")
	if text ~= "" then
		if text == "@" and meta:get_string("pass") ~= "" then -- keyboard mode, set text from input
			text = meta:get_string("input")
			meta:set_string("input", "") -- clear input
		end

		local bit = string_byte(text)

		if bit == 36 then -- text starts with $, play sound
			local text_sub = text:sub(2)
			if text_sub ~= "" then
				if iter > 1 then meta:set_int("count", iter) end -- play sound only once
				local i = text_sub:find(" ")
				if i then
					local sound_name = text_sub:sub(1, i - 1)
					local pitch = tonumber(text_sub:sub(i + 1)) or 1
					if pitch < 0.01 or pitch > 10 then pitch = 1 end
					meta:set_string("infotext", S("Playing sound: '@1', pitch: @2", (sound_name:gsub("_", " ")), pitch))
					minetest.sound_play(sound_name, {pos = pos, gain = 1, max_hear_distance = 16, pitch = pitch}, true)
				else
					meta:set_string("infotext", S("Playing sound: '@1'", (text_sub:gsub("_", " "))))
					minetest.sound_play(text_sub, {pos = pos, gain = 1, max_hear_distance = 16}, true)
				end
				return
			end

		elseif bit == 33 then -- if text starts with !, then we send chat text to all nearby players, radius 5
			local text_sub = text:sub(2)
			if text_sub ~= "" then
				if iter > 1 then meta:set_int("count", iter); count = 0 end -- send text only once
				meta:set_string("infotext", S("Keypad operation: @1 cycle left", count))
				local math_sqrt = math.sqrt
				local tpos = vector.add(pos, {x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")})
				for _, player in ipairs(minetest.get_connected_players()) do
					local pos1 = player:get_pos()
					if math_sqrt((pos1.x - tpos.x)^2 + (pos1.y - tpos.y)^2 + (pos1.z - tpos.z)^2) <= 5 then
						minetest.chat_send_player(player:get_player_name(), text_sub)
					end
				end
				return
			end
		end

		local tpos = vector.add(pos, {x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")})
		local node = minetest.get_node_or_nil(tpos); if not node then return end -- error
		local name = node.name

		if name ~= "basic_machines:keypad" or not vector.equals(tpos, pos) then
			if count < 2 then
				meta:set_string("infotext", S("Keypad operation: @1 cycle left", count))
			else
				meta:set_string("infotext", S("Keypad operation: @1 cycles left", count))
			end
		end

		if signs[name] then -- update text on signs
			if use_signs_lib then -- with signs_lib
				if signs_lib.update_sign then
					signs_lib.update_sign(tpos, {text = text})
				end
			elseif use_default then -- minetest_game default mod
				local infotext

				if text:len() > 512 then
					infotext = S("KEYPAD: Text too long.")
					text = infotext
				else
					infotext = S('"@1"', text)
				end

				local tmeta = minetest.get_meta(tpos)
				tmeta:set_string("infotext", infotext)
				tmeta:set_string("text", text)
			end

		-- target is keypad, special functions: @, % that output to target keypad's text
		elseif name == "basic_machines:keypad" then -- special modify of target keypad's text and change its target
			local tmeta = minetest.get_meta(tpos)
			if bit == 94 then -- target keypad's text starts with '^' (ascii code 94) -> rotating word extraction from own text. skaapdev start
				text = keypad_rot_list(text, pos)
				-- set target keypad's text
				tmeta:set_string("text", text) --skaapdev end
			elseif bit == 64 then -- target keypad's text starts with '@' (ascii code 64) -> character replacement
				text = text:sub(2)
				if text == "" then -- clear target keypad's text
					tmeta:set_string("text", ""); return
				end

				-- read words [j] from blocks above keypad:
				local j = 0
				text = text:gsub("@", function() -- replace every '@' in text with string on blocks above
					j = j + 1; return minetest.get_meta({x = pos.x, y = pos.y + j, z = pos.z}):get_string("infotext")
				end, 16) -- up to 16 replacements

				if text:len() > 4896 then
					tmeta:set_string("text", S("KEYPAD: Text too long."))
				else -- set target keypad's text
					tmeta:set_string("text", text)
				end
			elseif bit == 37 then -- target keypad's text starts with '%' (ascii code 37) -> word extraction
				local ttext = minetest.get_meta({x = pos.x, y = pos.y + 1, z = pos.z}):get_string("infotext")
				local i = tonumber(text:sub(2, 2)) or 1 -- read the number following the '%'
				-- extract i-th word from text
				local j = 0
				for word in ttext:gmatch("%S+") do
					j = j + 1; if j == i then text = word; break end
				end

				-- set target keypad's text
				tmeta:set_string("text", text)
			else
				-- just set text...
				tmeta:set_string("infotext", text)
			end

		elseif name == "basic_machines:detector" then -- change filter on detector
			if bit == 64 then -- if text starts with '@' -> clear the filter
				minetest.get_meta(tpos):set_string("node", "")
			else
				minetest.get_meta(tpos):set_string("node", text)
			end

		elseif name == "basic_machines:mover" then -- change filter on mover
			local tmeta = minetest.get_meta(tpos)
		    if bit == 64 then -- if text starts with '@' -> clear the filter
				tmeta:set_string("prefer", "")
				tmeta:get_inventory():set_list("filter", {})
			else
				local mode = tmeta:get_string("mode")
				-- mover input validation
				if bit == 94 then -- text starts with '^' (ascii code 94) -> rotating word extraction from own text. skaapdev start
					text = keypad_rot_list(text, pos)
				end -- skaapdev end
				if basic_machines.check_mover_filter(mode, tpos, tmeta, text) then
					if mover_no_large_stacks and basic_machines.check_mover_target(mode, tpos, tmeta) then
						text = basic_machines.clamp_item_count(text)
					end
					tmeta:set_string("prefer", text)
					tmeta:get_inventory():set_list("filter", {})
				end
			end

		elseif name == "basic_machines:distributor" then
			local i = text:find(" ")
			if i then
				local ti = tonumber(text:sub(1, i - 1)) or 1
				local tm = tonumber(text:sub(i + 1)) or 1
				if ti >= 1 and ti <= 16 and tm >= -2 and tm <= 2 then
					minetest.get_meta(tpos):set_int("active" .. ti, tm)
				end
			end

		elseif name == "basic_machines:autocrafter" then
			local tmeta = minetest.get_meta(tpos)
			if bit == 64 then -- if text starts with '@' -> clear the recipe
				basic_machines.change_autocrafter_recipe(tpos, tmeta:get_inventory(), nil)
			else
				if bit == 94 then -- text starts with '^' (ascii code 94) -> rotating word extraction from own text. skaapdev start
					text = keypad_rot_list(text, pos)
				end -- skaapdev end
				local i = text:find(" ")
				local stack_name, idx
				if i then
					stack_name = text:sub(1, i - 1)
					idx = tonumber(text:sub(i + 1)) or 1
					if idx < 1 or idx > 1000 then idx = 1 end
				else
					stack_name = text
				end
				if minetest.registered_items[stack_name ~= "" and stack_name or nil] then
					basic_machines.change_autocrafter_recipe(tpos, tmeta:get_inventory(), ItemStack(stack_name), idx)
				else
					tmeta:set_string("infotext", text:gsub("^ +$", ""))
				end
			end

		elseif use_unifieddyes and name:find("basic_machines:light") then
			if bit == 105 then -- text starts with 'i' -> set param2
				local idx = tonumber(text:sub(2)) or 0
				if idx ~= node.param2 and idx % 8 == 0 then -- colorwallmounted palette
					node.param2 = idx; minetest.swap_node(tpos, node)
				end
			else
				minetest.get_meta(tpos):set_string("infotext", text:gsub("^ +$", ""))
			end

		else
			if bit == 94 then -- text starts with '^' (ascii code 94) -> rotating word extraction from own text. skaapdev start
				text = keypad_rot_list(text, pos)
			end -- skaapdev end
			minetest.get_meta(tpos):set_string("infotext", text:gsub("^ +$", "")) -- just set text
		end

	-- target activation
	else
		if count < 2 then
			meta:set_string("infotext", S("Keypad operation: @1 cycle left", count))
		else
			meta:set_string("infotext", S("Keypad operation: @1 cycles left", count))
		end

		local mode = meta:get_int("mode"); if mode == 0 then return end -- do nothing
		local tpos = vector.add(pos, {x = meta:get_int("x0"), y = meta:get_int("y0"), z = meta:get_int("z0")})
		local node = minetest.get_node_or_nil(tpos); if not node then return end -- error
		local def = minetest.registered_nodes[node.name]
		if def and (def.effector or def.mesecons and def.mesecons.effector) then -- activate target
			if mode == 3 then -- keypad in toggle mode
				local state = meta:get_int("state"); state = 1 - state; meta:set_int("state", state)
				if state == 0 then mode = 2 else mode = 1 end
			end

			local effector = def.effector or def.mesecons.effector
			local param = def.effector and ttl or node

			-- pass the signal on to target, depending on mode
			if mode == 2 and effector.action_on then -- on
				effector.action_on(tpos, param) -- run
			elseif mode == 1 and effector.action_off then -- off
				effector.action_off(tpos, param) -- run
			end
		end
	end
end

minetest.register_node("basic_machines:keypad", {
	description = S("Keypad"),
	groups = {cracky = 2},
	tiles = {"basic_machines_keypad.png"},
	sounds = basic_machines.sound_node_machine(),

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", S("Keypad. Right click to set it up or punch it." ..
			" Set any password and text \"@@\" to work as keyboard."))
		meta:set_string("owner", placer:get_player_name())

		meta:set_int("mode", 2); meta:set_string("pass", "") -- mode, password
		meta:set_int("iter", 1); meta:set_int("count", 0) -- repeat, current repeat count
		meta:set_string("text", "")
		meta:set_int("x0", 0); meta:set_int("y0", 0); meta:set_int("z0", 0) -- target
		meta:set_int("input", 0); meta:set_int("state", 0)
		meta:set_int("t", 0); meta:set_int("T", 0)
	end,

	on_rightclick = function(pos, _, player)
		local meta, name = minetest.get_meta(pos), player:get_player_name()
		local x0, y0, z0 = meta:get_int("x0"), meta:get_int("y0"), meta:get_int("z0")

		machines.mark_pos1(name, vector.add(pos, {x = x0, y = y0, z = z0})) -- mark pos1
		minetest.show_formspec(name, "basic_machines:keypad_" .. minetest.pos_to_string(pos),
			"formspec_version[4]size[6,5.3]no_prepend[]bgcolor[#888888BB;false]set_focus[text]" ..
			"field[0.25,0.5;1,0.8;mode;" .. F(S("Mode")) .. ";" .. meta:get_int("mode") ..
			"]field[1.5,0.5;1,0.8;iter;" .. F(S("Repeat")) .. ";" .. meta:get_int("iter") ..
			"]field[2.75,0.5;3,0.8;pass;" .. F(S("Password")) .. ";" .. meta:get_string("pass") ..
			"]field[0.25,3;3.85,0.8;text;" .. F(S("Text")) .. ";" .. F(meta:get_string("text")) ..
			"]button[4.1,3;0.5,0.8;sounds;♫]button_exit[4.75,3;1,0.8;OK;" .. F(S("OK")) ..
			"]field[0.25,4.25;1,0.8;x0;" .. F(S("Target")) .. ";" .. x0 ..
			"]field[1.5,4.25;1,0.8;y0;;" .. y0 .. "]field[2.75,4.25;1,0.8;z0;;" .. z0 ..
			"]button[4.75,4.25;1,0.8;help;" .. F(S("help")) .. "]")
	end,

	on_dig = function(pos, node, digger)
		if digger and digger:is_player() then
			if minetest.get_meta(pos):get_string("owner") == digger:get_player_name() then -- owner can always remove his keypad
				local node_removed = minetest.remove_node(pos)
				if node_removed then
					minetest.handle_node_drops(pos, {node.name}, digger)
				end
				return node_removed
			end
		end
		return minetest.node_dig(pos, node, digger)
	end,

	effector = {
		action_on = function(pos, _)
			if minetest.get_meta(pos):get_string("pass") == "" then
				basic_machines.use_keypad(pos, 1)
			end
		end,

		action_off = function(pos, _)
			if minetest.get_meta(pos):get_string("pass") == "" then
				basic_machines.use_keypad(pos, 1, true) -- can stop repeats
			end
		end
	}
})

if basic_machines.settings.register_crafts and use_default then
	minetest.register_craft({
		output = "basic_machines:keypad",
		recipe = {
			{"default:stick"},
			{"default:wood"}
		}
	})
end