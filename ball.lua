-- Ball: energy ball that flies around, can bounce and activate stuff
-- rnd 2016
-- Copyright (C) 2022-2025 мтест
-- See README.md for license details

-- TO DO, move mode:
-- Ball just rolling around on ground without hopping
-- Also if inside slope it would "roll down", just increased velocity in slope direction

local F, S = basic_machines.F, basic_machines.S
local machines_TTL = basic_machines.properties.machines_TTL
local machines_minstep = basic_machines.properties.machines_minstep
local machines_timer = basic_machines.properties.machines_timer
local max_balls = math.max(0, basic_machines.settings.max_balls)
local max_range = basic_machines.properties.max_range
local max_damage = minetest.PLAYER_MAX_HP_DEFAULT / 4 -- player health 20
-- to be used with bounce setting 2 in ball spawner:
-- 1: bounce in x direction, 2: bounce in z direction, otherwise it bounces in y direction
local bounce_materials = {}
local bounce_materials_help, axis = {S(", and for the next blocks:")}, {"x", "z"}

local function add_bounce_material(name, direction)
	bounce_materials[name] = direction
	bounce_materials_help[#bounce_materials_help + 1] = ("%s: %s"):format(name, axis[direction])
end

if minetest.get_modpath("darkage") then
	add_bounce_material("darkage:iron_bars", 1)
end

if basic_machines.use_default then
	add_bounce_material("default:glass", 2)
	add_bounce_material("default:wood", 1)
end

if minetest.get_modpath("xpanes") then
	add_bounce_material("xpanes:bar_2", 1)
	add_bounce_material("xpanes:bar_10", 1)
end

if #bounce_materials_help > 1 then
	bounce_materials_help = table.concat(bounce_materials_help, "\n")
else
	bounce_materials_help = ""
end

local ball_default = {
	x0 = 0, y0 = 0, z0 = 0, speed = 5,
	energy = 1, bounce = 0, gravity = 1, punchable = 1,
	hp = 100, hurt = 0, lifetime = 20, solid = 0,
	texture = "basic_machines_ball.png",
	scale = 100, visual = "sprite"
}
local scale_factor = 100
local ballcount = {}
local abs = math.abs
local elasticity = 0.9 -- speed gets multiplied by this when bouncing
local use_boneworld = minetest.global_exists("boneworld")

minetest.register_entity("basic_machines:ball", {
	initial_properties = {
		hp_max = ball_default.hp,
		physical = ball_default.solid == 1,
		collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		visual = ball_default.visual,
		visual_size = {
			x = ball_default.scale / scale_factor,
			y = ball_default.scale / scale_factor
		},
		textures = {ball_default.texture},
		static_save = false
	},

	_in_air = false,
	_origin = {
		x = ball_default.x0,
		y = ball_default.y0,
		z = ball_default.z0
	},
	_owner = "",
	_timer = 0,

	_speed = ball_default.speed,			-- velocity when punched
	_energy = ball_default.energy,			-- if negative it will deactivate stuff, positive will activate, 0 wont do anything
	_bounce = ball_default.bounce,			-- 0: absorbs in block, 1: proper bounce = lag buggy, to do: line of sight bounce
	_punchable = ball_default.punchable,	-- can be punched by players in protection
	_hurt = ball_default.hurt,				-- how much damage it does to target entity, if 0 damage disabled
	_lifetime = ball_default.lifetime,		-- how long it exists before disappearing
	_solid = ball_default.solid,			-- wether physical or not

	on_deactivate = function(self)
		ballcount[self._owner] = (ballcount[self._owner] or 1) - 1
	end,

	on_step = function(self, dtime)
		self._timer = self._timer + dtime
		if self._timer > self._lifetime then
			self.object:remove(); return
		end

		local pos = self.object:get_pos()
		local origin = self._origin
		local dist = math.max(abs(pos.x - origin.x), abs(pos.y - origin.y), abs(pos.z - origin.z))

		if dist > 50 then -- maximal distance when balls disappear, remove if it goes too far
			self.object:remove(); return
		end

		local node_name, def, walkable
		local energy, bounce = self._energy, self._bounce

		if self._solid == 0 and (energy ~= 0 or bounce > 0) then
			node_name = minetest.get_node(pos).name
			if node_name == "air" then
				if bounce > 0 then self._in_air = true end
			elseif energy ~= 0 and node_name == "basic_machines:ball_spawner" and dist > 0.5 then
				-- ball can activate spawner, just not originating one
				def = minetest.registered_nodes[node_name]
				walkable = true
			elseif node_name == "ignore" then
				self.object:remove(); return
			else
				def = minetest.registered_nodes[node_name]
				if def then
					if bounce > 0 and self._in_air and ((def.groups or {}).liquid or 0) > 0 and self._speed < 7 then
						-- bounce on liquids surface
						walkable = true
					else
						walkable = def.walkable
					end
				end
			end
		end

		if walkable then -- we hit a node - only with physical = false (or solid = 0)
			if energy ~= 0 and def and (def.effector or def.mesecons and def.mesecons.effector) then -- activate target
				if minetest.is_protected(pos, self._owner) then
					return
				end

				self.object:remove()

				local effector = def.effector or def.mesecons.effector
				local param = def.effector and machines_TTL or minetest.get_node(pos)

				if energy > 0 and effector.action_on then
					effector.action_on(pos, param)
				elseif energy < 0 and effector.action_off then
					effector.action_off(pos, param)
				end
			elseif bounce > 0 then -- bounce (copyright rnd, 2016)
				local n = {x = 0, y = 0, z = 0} -- this will be bounce normal
				local v = self.object:get_velocity()
				local opos = vector.round(pos) -- obstacle

				if bounce == 1 then
					-- algorithm to determine bounce direction - problem:
					-- with lag it's impossible to determine reliably which node was hit and which face...

					-- possible bounce directions
					if v.x > 0 then n.x = -1 else n.x = 1 end
					if v.y > 0 then n.y = -1 else n.y = 1 end
					if v.z > 0 then n.z = -1 else n.z = 1 end

					-- obtain bounce direction
					local bpos = vector.subtract(pos, opos) -- boundary position on cube, approximate
					local dpos = vector.multiply(n, 0.5) -- calculate distance to bounding surface midpoints
					local d1 = (bpos.x - dpos.x)^2 + bpos.y^2 + bpos.z^2
					local d2 = bpos.x^2 + (bpos.y - dpos.y)^2 + bpos.z^2
					local d3 = bpos.x^2 + bpos.y^2 + (bpos.z - dpos.z)^2

					local d = math.min(d1, d2, d3) -- we obtain bounce direction from minimal distance
					if d1 == d then -- x
						n.y, n.z = 0, 0
					elseif d2 == d then -- y
						n.x, n.z = 0, 0
					elseif d3 == d then -- z
						n.x, n.y = 0, 0
					end
				else -- bounce == 2, uses special blocks for non buggy lag proof bouncing: by default it bounces in y direction
					local bounce_direction = bounce_materials[node_name] or 0
					if bounce_direction == 0 then
						if v.y > 0 then n.y = -1 else n.y = 1 end
					elseif bounce_direction == 1 then
						if v.x > 0 then n.x = -1 else n.x = 1 end
					elseif bounce_direction == 2 then
						if v.z > 0 then n.z = -1 else n.z = 1 end
					end
				end

				-- verify new ball position
				local new_pos = vector.add(pos, vector.multiply(n, 0.2))

				local new_pos_node_name = minetest.get_node(new_pos).name
				if new_pos_node_name == "air" then
					self._in_air = true
				else
					local new_pos_node_def = minetest.registered_nodes[new_pos_node_name]
					if new_pos_node_def then
						local new_pos_is_walkable = new_pos_node_def.walkable
						if new_pos_is_walkable then -- problem, nonempty node - incorrect position
							self.object:remove(); return -- just remove the ball
						elseif ((new_pos_node_def.groups or {}).liquid or 0) > 0 then
							if self._in_air and self._speed < 7 then
								self._speed = 7 -- sink the ball
							end
							self._in_air = false
						end
					end
				end

				-- elastify velocity
				if n.x ~= 0 then
					v.x = -elasticity * v.x
				elseif n.y ~= 0 then
					v.y = -elasticity * v.y
				elseif n.z ~= 0 then
					v.z = -elasticity * v.z
				end

				-- bounce
				self.object:set_pos(new_pos) -- ball placed a bit further away from box
				self.object:set_velocity(v)

				minetest.sound_play(basic_machines.sound_ball_bounce, {pos = pos, gain = 1, max_hear_distance = 8}, true)
			else
				self.object:remove(); return
			end

		elseif self._hurt ~= 0 then -- check for colliding nearby objects
			local objects = minetest.get_objects_inside_radius(pos, 2)
			if #objects > 1 then
				for _, obj in ipairs(objects) do
					if obj:is_player() then -- player
						if obj:get_player_name() ~= self._owner then -- don't hurt owner
							local hp = obj:get_hp()
							local newhp = hp - self._hurt
							if newhp <= 0 and use_boneworld and boneworld.killxp then
								local killxp = boneworld.killxp[self._owner]
								if killxp then
									boneworld.killxp[self._owner] = killxp + 0.01
								end
							end
							obj:set_hp(newhp)
							if newhp > 0 and newhp < hp then
								obj:add_velocity(vector.divide(self.object:get_velocity(), 3))
							end
							self.object:remove(); break
						end
					elseif obj ~= self.object then -- non player
						local lua_entity = obj:get_luaentity()
						if lua_entity then
							if lua_entity.itemstring == "robot" then
								self.object:remove(); break
							-- if protection (mobs_redo) is on level 2 then don't let ball harm mobs
							elseif lua_entity.protected ~= 2 and obj:get_armor_groups().fleshy then
								local hp = obj:get_hp()
								local newhp = math.min(obj:get_properties().hp_max, hp - self._hurt)
								if newhp > 0 then
									obj:set_hp(newhp)
									if newhp < hp then
										obj:add_velocity(vector.divide(self.object:get_velocity(), 4))
									end
								else
									obj:remove()
								end
								self.object:remove(); break
							end
						end
					end
				end
			end
		end
	end,

	on_punch = function(self, puncher, time_from_last_punch, _, dir)
		local punchable = self._punchable
		if punchable == 0 then -- no punch
			return
		elseif time_from_last_punch > 0.5 then
			if punchable == 1 then -- only those in protection
				local obj_pos = self.object:get_pos()
				if minetest.is_protected(obj_pos, "") or
					puncher and minetest.is_protected(obj_pos, puncher:get_player_name())
				then
					self.object:set_velocity(vector.multiply(dir, self._speed))
				else
					return
				end
			else -- everywhere
				self.object:set_velocity(vector.multiply(dir, self._speed))
			end
		end
	end
})

local function ball_spawner_update_form(meta)
	local field_lifetime
	if meta:get_int("admin") == 1 then
		field_lifetime = ("field[2.75,3;1,0.8;lifetime;%s;%i]"):format(F(S("Lifetime")), meta:get_int("lifetime"))
	else
		field_lifetime = ""
	end
	local function twodigits(f) return ("%.2f"):format(f) end
	meta:set_string("formspec", "formspec_version[4]size[5.25,6.6]" ..
		"field[0.25,0.5;1,0.8;x0;" .. F(S("Target")) .. ";" .. twodigits(meta:get_float("x0")) ..
		"]field[1.5,0.5;1,0.8;y0;;" .. twodigits(meta:get_float("y0")) ..
		"]field[2.75,0.5;1,0.8;z0;;" .. twodigits(meta:get_float("z0")) ..
		"]field[4,0.5;1,0.8;speed;" .. F(S("Speed")) .. ";" .. twodigits(meta:get_float("speed")) ..
		"]field[0.25,1.75;1,0.8;energy;" .. F(S("Energy")) .. ";" .. meta:get_int("energy") ..
		"]field[1.5,1.75;1,0.8;bounce;" .. F(S("Bounce")) .. ";" .. meta:get_int("bounce") ..
		"]field[2.75,1.75;1,0.8;gravity;" .. F(S("Gravity")) .. ";" .. twodigits(meta:get_float("gravity")) ..
		"]field[4,1.75;1,0.8;punchable;" .. F(S("Punch.")) .. ";" .. meta:get_int("punchable") ..
		"]tooltip[4,1.35;1,0.4;" .. F(S("Punchable")) ..
		"]field[0.25,3;1,0.8;hp;" .. F(S("HP")) .. ";" .. twodigits(meta:get_float("hp")) ..
		"]field[1.5,3;1,0.8;hurt;" .. F(S("Hurt")) .. ";" .. twodigits(meta:get_float("hurt")) .. "]" ..
		field_lifetime ..
		"field[4,3;1,0.8;solid;" .. F(S("Solid")) .. ";" .. meta:get_int("solid") ..
		"]field[0.25,4.25;4.75,0.8;texture;" .. F(S("Texture")) .. ";" .. F(meta:get_string("texture")) ..
		"]field[0.25,5.5;1,0.8;scale;" .. F(S("Scale")) .. ";" .. meta:get_int("scale") ..
		"]field[1.5,5.5;1,0.8;visual;" .. F(S("Visual")) .. ";" .. F(meta:get_string("visual")) ..
		"]button[2.75,5.5;1,0.8;help;" .. F(S("help")) .. "]button_exit[4,5.5;1,0.8;OK;" .. F(S("OK")) .. "]")
end

minetest.register_node("basic_machines:ball_spawner", {
	description = S("Ball Spawner"),
	groups = {cracky = 3, oddly_breakable_by_hand = 1},
	drawtype = "allfaces",
	tiles = {"basic_machines_ball.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	param1 = 1,
	walkable = false,
	sounds = basic_machines.sound_node_machine(),
	drop = "",

	after_place_node = function(pos, placer)
		if not placer then return end

		local meta, name = minetest.get_meta(pos), placer:get_player_name()
		meta:set_string("owner", name)

		local privs = minetest.get_player_privs(name)
		if privs.privs then meta:set_int("admin", 1) end
		if privs.machines then meta:set_int("machines", 1) end

		meta:set_float("x0", ball_default.x0)				-- target
		meta:set_float("y0", ball_default.y0)
		meta:set_float("z0", ball_default.z0)
		meta:set_float("speed", ball_default.speed)			-- if positive sets initial ball speed
		meta:set_int("energy", ball_default.energy)			-- if positive activates, negative deactivates, 0 does nothing
		meta:set_int("bounce", ball_default.bounce)			-- if nonzero bounces when hit obstacle, 0 gets absorbed
		meta:set_float("gravity", ball_default.gravity)
		-- if 0 not punchable, if 1 can be punched by players in protection, if 2 can be punched by anyone
		meta:set_int("punchable", ball_default.punchable)
		meta:set_float("hp", ball_default.hp)
		meta:set_float("hurt", ball_default.hurt)
		meta:set_int("lifetime", ball_default.lifetime)
		meta:set_int("solid", ball_default.solid)
		meta:set_string("texture", ball_default.texture)
		meta:set_int("scale", ball_default.scale)
		meta:set_string("visual", ball_default.visual)		-- cube or sprite
		meta:set_int("t", 0); meta:set_int("T", 0)

		ball_spawner_update_form(meta)
	end,

	after_dig_node = function(pos, _, oldmetadata, digger)
		local stack; local inv = digger:get_inventory()

		if (digger:get_player_control() or {}).sneak then
			stack = ItemStack("basic_machines:ball_spawner")
		else
			local meta = oldmetadata["fields"]
			meta["formspec"] = nil
			meta["x0"], meta["y0"], meta["z0"] = nil, nil, nil
			meta["solid"] = nil
			meta["scale"] = nil
			meta["visual"] = nil
			stack = ItemStack({name = "basic_machines:ball_spell",
				metadata = minetest.serialize(meta)})
		end

		if inv:room_for_item("main", stack) then
			inv:add_item("main", stack)
		else
			minetest.add_item(pos, stack)
		end
	end,

	on_receive_fields = function(pos, _, fields, sender)
		local name = sender:get_player_name()
		if fields.OK then
			if minetest.is_protected(pos, name) then return end
			local privs = minetest.check_player_privs(name, "privs")
			local meta = minetest.get_meta(pos)

			-- target
			local x0 = tonumber(fields.x0) or ball_default.x0
			local y0 = tonumber(fields.y0) or ball_default.y0
			local z0 = tonumber(fields.z0) or ball_default.z0
			if not privs and (abs(x0) > max_range or abs(y0) > max_range or abs(z0) > max_range) then return end
			meta:set_float("x0", ("%.2f"):format(x0))
			meta:set_float("y0", ("%.2f"):format(y0))
			meta:set_float("z0", ("%.2f"):format(z0))

			-- speed
			local speed = tonumber(fields.speed) or ball_default.speed
			if (speed < -10 or speed > 10) and not privs then return end
			meta:set_float("speed", ("%.2f"):format(speed))

			-- energy
			local energy = tonumber(fields.energy) or ball_default.energy
			if energy < -1 or energy > 1 then return end
			meta:set_int("energy", energy)

			-- bounce
			local bounce = tonumber(fields.bounce) or ball_default.bounce
			if bounce < 0 or bounce > 2 then return end
			meta:set_int("bounce", bounce)

			-- gravity
			local gravity = tonumber(fields.gravity) or ball_default.gravity
			if (gravity < 0 or gravity > 40) and not privs then return end
			meta:set_float("gravity", ("%.2f"):format(gravity))

			-- punchable
			local punchable = tonumber(fields.punchable) or ball_default.punchable
			if punchable < 0 or punchable > 2 then return end
			meta:set_int("punchable", punchable)

			-- hp
			local hp = tonumber(fields.hp) or ball_default.hp
			if hp < 0 then return end
			meta:set_float("hp", ("%.2f"):format(hp))

			-- hurt
			local hurt = tonumber(fields.hurt) or ball_default.hurt
			if hurt > max_damage and not privs then return end
			meta:set_float("hurt", ("%.2f"):format(hurt))

			if fields.lifetime then
				local lifetime = tonumber(fields.lifetime) or ball_default.lifetime
				if lifetime <= 0 then lifetime = ball_default.lifetime end
				meta:set_int("lifetime", lifetime)
			end

			-- solid
			local solid = tonumber(fields.solid) or ball_default.solid
			if solid < 0 or solid > 1 then return end
			meta:set_int("solid", solid)

			-- texture
			local texture = fields.texture or ""
			if texture:len() > 512 and not privs then return end
			meta:set_string ("texture", texture)

			-- scale
			local scale = tonumber(fields.scale) or ball_default.scale
			if scale < 1 or scale > 1000 and not privs then return end
			meta:set_int("scale", scale)

			-- visual
			local visual = fields.visual
			if visual ~= "cube" and visual ~= "sprite" then return end
			meta:set_string ("visual", fields.visual)

			ball_spawner_update_form(meta)

		elseif fields.help then
			local lifetime = minetest.get_meta(pos):get_int("admin") == 1 and S("\nLifetime:		[1,   +∞[") or ""
			minetest.show_formspec(name, "basic_machines:help_ball",
				"formspec_version[4]size[8,9.3]textarea[0,0.35;8,8.95;help;" .. F(S("Ball spawner help")) .. ";" ..
F(S([[Values:

Target*:		Direction of velocity
				x: [-@1, @2], y: [-@3, @4], z: [-@5, @6]
Speed:			[-10, 10]
Energy:			[-1,  1]
Bounce**:		[0,   2]
Gravity:		[0,  40]
Punchable***:	[0,   2]
Hp:				[0,   +∞[
Hurt:			]-∞,  @7]@8
Solid*:			[0,   1]
Texture:		Texture name with extension, up to 512 characters
Scale*:			[1,   1000]
Visual*:		"cube" or "sprite"

*: Not available as individual Ball Spawner

**: Set to 2, the ball bounces following y direction@9

***: 0: not punchable, 1: only in protected area, 2: everywhere

Note: Hold sneak while digging to get the Ball Spawner
]], max_range, max_range, max_range, max_range, max_range, max_range,
max_damage, lifetime, bounce_materials_help)) .. "]")
		end
	end,

	effector = {
		action_on = function(pos, _)
			local meta = minetest.get_meta(pos)

			local t0, t1 = meta:get_int("t"), minetest.get_gametime()
			local T = meta:get_int("T") -- temperature

			if t0 > t1 - 2 * machines_minstep then -- activated before natural time
				T = T + 1
			elseif T > 0 then
				if t1 - t0 > machines_timer then -- reset temperature if more than 5s (by default) elapsed since last activation
					T = 0; meta:set_string("infotext", "")
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

			local owner = meta:get_string("owner"); if owner == "" then return end

			if meta:get_int("machines") ~= 1 then -- no machines priv, limit ball count
				local count = ballcount[owner]
				if not count or count < 0 then count = 0 end

				if count >= max_balls then
					if max_balls > 0 and t1 - t0 > 10 then count = 0 else return end
				end

				ballcount[owner] = count + 1
			end

			local obj = minetest.add_entity(pos, "basic_machines:ball")
			if obj then
				local lua_entity = obj:get_luaentity(); lua_entity._origin, lua_entity._owner = pos, owner

				-- x, y , z
				local x0, y0, z0 = meta:get_float("x0"), meta:get_float("y0"), meta:get_float("z0") -- direction of velocity

				-- speed
				local speed = meta:get_float("speed")
				if speed ~= 0 and (x0 ~= 0 or y0 ~= 0 or z0 ~= 0) then -- set velocity direction
					local velocity = {x = x0, y = y0, z = z0}
					local v = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2); if v == 0 then v = 1 end
					v = v / speed
					obj:set_velocity(vector.divide(velocity, v))
				end
				lua_entity._speed = speed

				-- energy
				local energy = meta:get_int("energy") -- if positive activates, negative deactivates, 0 does nothing
				if energy ~= 0 then -- make the ball glow
					obj:set_properties({glow = 9})
				end
				local colorize = energy < 0 and "^[colorize:blue:120" or ""
				lua_entity._energy = energy

				-- bounce
				lua_entity._bounce = meta:get_int("bounce") -- if nonzero bounces when hit obstacle, 0 gets absorbed

				-- gravity
				obj:set_acceleration({x = 0, y = -meta:get_float("gravity"), z = 0})

				-- punchable
				-- if 0 not punchable, if 1 can be punched by players in protection, if 2 can be punched by anyone
				lua_entity._punchable = meta:get_int("punchable")

				-- hp
				obj:set_hp(meta:get_float("hp"))

				-- hurt
				lua_entity._hurt = meta:get_float("hurt")

				-- lifetime
				if meta:get_int("admin") == 1 then
					lua_entity._lifetime = meta:get_int("lifetime")
				end

				-- solid
				if meta:get_int("solid") == 1 then
					obj:set_properties({physical = true})
					lua_entity._solid = 1
				end

				local visual = meta:get_string("visual")
				-- texture
				local texture = meta:get_string("texture") .. colorize
				if visual == "cube" then
					obj:set_properties({textures = {texture, texture, texture, texture, texture, texture}})
				elseif visual == "sprite" then
					obj:set_properties({textures = {texture}})
				end

				-- scale
				local scale = meta:get_int("scale"); scale = scale / scale_factor
				obj:set_properties({visual_size = {x = scale, y = scale}})

				-- visual
				obj:set_properties({visual = visual})
			end
		end,

		action_off = function(pos, _)
			local meta = minetest.get_meta(pos)

			local t0, t1 = meta:get_int("t"), minetest.get_gametime()
			local T = meta:get_int("T") -- temperature

			if t0 > t1 - 2 * machines_minstep then -- activated before natural time
				T = T + 1
			elseif T > 0 then
				if t1 - t0 > machines_timer then -- reset temperature if more than 5s (by default) elapsed since last activation
					T = 0; meta:set_string("infotext", "")
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

			local owner = meta:get_string("owner"); if owner == "" then return end

			if meta:get_int("machines") ~= 1 then -- no machines priv, limit ball count
				local count = ballcount[owner]
				if not count or count < 0 then count = 0 end

				if count >= max_balls then
					if max_balls > 0 and t1 - t0 > 10 then count = 0 else return end
				end

				ballcount[owner] = count + 1
			end

			local obj = minetest.add_entity(pos, "basic_machines:ball")
			if obj then
				local lua_entity = obj:get_luaentity(); lua_entity._origin, lua_entity._owner = pos, owner

				-- x, y , z
				local x0, y0, z0 = meta:get_float("x0"), meta:get_float("y0"), meta:get_float("z0") -- direction of velocity

				-- speed
				local speed = meta:get_float("speed")
				if speed ~= 0 and (x0 ~= 0 or y0 ~= 0 or z0 ~= 0) then -- set velocity direction
					local velocity = {x = x0, y = y0, z = z0}
					local v = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2); if v == 0 then v = 1 end
					v = v / speed
					obj:set_velocity(vector.divide(velocity, v))
				end
				lua_entity._speed = speed

				-- energy
				obj:set_properties({glow = 9}) -- make the ball glow
				obj:get_luaentity()._energy = -1

				-- hp
				obj:set_hp(meta:get_float("hp"))

				-- lifetime
				if meta:get_int("admin") == 1 then
					lua_entity._lifetime = meta:get_int("lifetime")
				end

				local visual = meta:get_string("visual")
				-- texture
				local texture = meta:get_string("texture") .. "^[colorize:blue:120"
				if visual == "cube" then
					obj:set_properties({textures = {texture, texture, texture, texture, texture, texture}})
				elseif visual == "sprite" then
					obj:set_properties({textures = {texture}})
				end

				-- visual
				obj:set_properties({visual = visual})
			end
		end
	}
})

local spelltime = {}

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	ballcount[name] = nil
	spelltime[name] = nil
end)

-- ball as magic spell user can cast
minetest.register_tool("basic_machines:ball_spell", {
	description = S("Ball Spell"),
	groups = {not_in_creative_inventory = 1},
	inventory_image = "basic_machines_ball.png",
	light_source = 10,
	tool_capabilities = {
		full_punch_interval = 2,
		max_drop_level = 0
	},

	on_use = function(itemstack, user)
		if not user then return end
		local pos = user:get_pos(); pos.y = pos.y + 1
		local meta = minetest.deserialize(itemstack:get_meta():get_string("")) or {}
		local owner = user:get_player_name()
		local privs = minetest.check_player_privs(owner, "privs")

		-- if minetest.is_protected(pos, owner) then return end

		local t1 = minetest.get_gametime()
		if t1 - (spelltime[owner] or 0) < 2 then return end -- too soon
		spelltime[owner] = t1

		local obj = minetest.add_entity(pos, "basic_machines:ball")
		if obj then
			local lua_entity = obj:get_luaentity(); lua_entity._origin, lua_entity._owner = pos, owner

			-- speed
			local speed = tonumber(meta["speed"]) or ball_default.speed
			speed = privs and speed or math.min(math.max(speed, -10), 10)
			obj:set_velocity(vector.multiply(user:get_look_dir(), speed))
			lua_entity._speed = speed

			-- energy
			-- if positive activates, negative deactivates, 0 does nothing
			local energy = tonumber(meta["energy"]) or ball_default.energy
			if energy ~= 0 then -- make the ball glow
				obj:set_properties({glow = 9})
			end
			local colorize = energy < 0 and "^[colorize:blue:120" or ""
			lua_entity._energy = energy

			-- bounce
			-- if nonzero bounces when hit obstacle, 0 gets absorbed
			lua_entity._bounce = tonumber(meta["bounce"]) or ball_default.bounce

			-- gravity
			local gravity = tonumber(meta["gravity"]) or ball_default.gravity
			gravity = privs and gravity or math.min(math.max(gravity, 0.1), 40)
			obj:set_acceleration({x = 0, y = -gravity , z = 0})

			-- punchable
			-- if 0 not punchable, if 1 can be punched by players in protection, if 2 can be punched by anyone
			lua_entity._punchable = tonumber(meta["punchable"]) or ball_default.punchable

			-- hp
			obj:set_hp(tonumber(meta["hp"]) or ball_default.hp)

			-- hurt
			local hurt = tonumber(meta["hurt"]) or ball_default.hurt
			hurt = privs and hurt or math.min(hurt, max_damage)
			lua_entity._hurt = hurt

			-- lifetime
			if privs then
				lua_entity._lifetime = tonumber(meta["lifetime"]) or ball_default.lifetime
			end

			-- texture
			local texture = meta["texture"] or ball_default.texture
			if texture:len() > 512 and not privs then texture = texture:sub(1, 512) end
			obj:set_properties({textures = {texture .. colorize}})
		end
	end
})

if basic_machines.settings.register_crafts then
	minetest.register_craft({
		output = "basic_machines:ball_spawner",
		recipe = {
			{"basic_machines:power_cell"},
			{"basic_machines:keypad"}
		}
	})
end