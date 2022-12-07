-- BALL: energy ball that flies around, can bounce and activate stuff
-- rnd 2016:

-- TO DO, move mode:
-- Ball just rolling around on ground without hopping
-- Also if inside slope it would "roll down", just increased velocity in slope direction

local F, S = basic_machines.F, basic_machines.S
local machines_TTL = basic_machines.properties.machines_TTL
local machines_minstep = basic_machines.properties.machines_minstep
local machines_timer = basic_machines.properties.machines_timer
local max_balls = math.max(0, basic_machines.settings.max_balls)
local max_range = basic_machines.properties.max_range
local max_damage = minetest.PLAYER_MAX_HP_DEFAULT / 2 -- player health 20
-- to be used with bounce setting 2 in ball spawner:
-- 1: bounce in x direction, 2: bounce in z direction, otherwise it bounces in y direction
local bounce_materials = {
	["default:glass"] = 2, ["default:wood"] = 1
}

if minetest.get_modpath("darkage") then
	bounce_materials["darkage:iron_bars"] = 1
end

if minetest.get_modpath("xpanes") then
	bounce_materials["xpanes:bar_10"] = 1
	bounce_materials["xpanes:bar_2"] = 1
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
local use_boneworld = minetest.global_exists("boneworld")

local function round(x)
	if x < 0 then
		return -math.floor(-x + 0.5)
	else
		return math.floor(x + 0.5)
	end
end

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

	_origin = {
		x = ball_default.x0,
		y = ball_default.y0,
		z = ball_default.z0
	},
	_owner = "",
	_elasticity = 0.9,						-- speed gets multiplied by this after bounce
	_is_arrow = false,						-- advanced mob protection
	_timer = 0,

	_speed = ball_default.speed,			-- velocity when punched
	_energy = ball_default.energy,			-- if negative it will deactivate stuff, positive will activate, 0 wont do anything
	_bounce = ball_default.bounce,			-- 0: absorbs in block, 1: proper bounce=lag buggy, to do: line of sight bounce
	_gravity = ball_default.gravity,
	_punchable = ball_default.punchable,	-- can be punched by players in protection
	_hurt = ball_default.hurt,				-- how much damage it does to target entity, if 0 damage disabled
	_lifetime = ball_default.lifetime,		-- how long it exists before disappearing

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

		local nodename = minetest.get_node(pos).name
		local walkable = false
		if nodename ~= "air" then
			walkable = minetest.registered_nodes[nodename].walkable
			-- ball can activate spawner, just not originating one
			if nodename == "basic_machines:ball_spawner" and dist > 0.5 then walkable = true end
		end

		if not walkable then
			if self._hurt ~= 0 then -- check for colliding nearby objects
				local objects = minetest.get_objects_inside_radius(pos, 2)
				if #objects > 1 then
					for _, obj in ipairs(objects) do
						local p, d = obj:get_pos(), 0
						if p then
							d = math.sqrt((p.x - pos.x)^2 + (p.y - pos.y)^2 + (p.z - pos.z)^2)
						end
						if d > 0 then
							-- if minetest.is_protected(p, self._owner) then break end
							-- if abs(p.x) < 32 and abs(p.y) < 32 and abs(p.z) < 32 then break end -- no damage around spawn

							if obj:is_player() then -- player
								if obj:get_player_name() == self._owner then break end -- don't hurt owner

								local newhp = obj:get_hp() - self._hurt
								if newhp <= 0 and use_boneworld and boneworld.killxp then
									local killxp = boneworld.killxp[self._owner]
									if killxp then
										boneworld.killxp[self._owner] = killxp + 0.01
									end
								end
								obj:set_hp(newhp)
							else -- non player
								local lua_entity = obj:get_luaentity()
								if lua_entity then
									if lua_entity.itemstring == "robot" then
										self.object:remove(); break
									-- if protection (mobs_redo) is on level 2 then don't let arrows harm mobs
									elseif self._is_arrow and lua_entity.protected == 2 then
										break
									end
								end
								local newhp = obj:get_hp() - self._hurt
								minetest.chat_send_player(self._owner, S("#BALL: target hp @1", newhp))
								if newhp > 0 then obj:set_hp(newhp) else obj:remove() end
							end

							self.object:remove(); break
						end
					end
				end
			end

		elseif walkable then -- we hit a node
			-- minetest.chat_send_all("Hit node at " .. minetest.pos_to_string(pos))
			local node = minetest.get_node(pos)
			local def = minetest.registered_nodes[node.name]
			if def and (def.effector or def.mesecons and def.mesecons.effector) then -- activate target
				local energy = self._energy

				if energy ~= 0 and minetest.is_protected(pos, self._owner) then
					return
				end

				local effector = def.effector or def.mesecons.effector
				local param = def.effector and machines_TTL or node

				self.object:remove()

				if energy > 0 and effector.action_on then
					effector.action_on(pos, param)
				elseif energy < 0 and effector.action_off then
					effector.action_off(pos, param)
				end
			else -- bounce (copyright rnd, 2016)
				local bounce = self._bounce

				if bounce == 0 then
					self.object:remove(); return
				end

				local n = {x = 0, y = 0, z = 0} -- this will be bounce normal
				local v = self.object:get_velocity()

				if bounce == 2 then -- uses special blocks for non buggy lag proof bouncing: by default it bounces in y direction
					local bounce_direction = bounce_materials[node.name] or 0

					if bounce_direction == 0 then
						if v.y >= 0 then n.y = -1 else n.y = 1 end
					elseif bounce_direction == 1 then
						if v.x >= 0 then n.x = -1 else n.x = 1 end
					elseif bounce_direction == 2 then
						if v.z >= 0 then n.z = -1 else n.z = 1 end
					end
				else
					-- algorithm to determine bounce direction - problem:
					-- with lag it's impossible to determine reliable which node was hit and which face ..
					if v.x <= 0 then n.x = 1 else n.x = -1 end -- possible bounce directions
					if v.y <= 0 then n.y = 1 else n.y = -1 end
					if v.z <= 0 then n.z = 1 else n.z = -1 end

					local opos = {x = round(pos.x), y = round(pos.y), z = round(pos.z)} -- obstacle
					local bpos = vector.subtract(pos, opos) -- boundary position on cube, approximate
					local dpos = {x = 0.5 * n.x, y = 0.5 * n.y, z = 0.5 * n.z} -- calculate distance to bounding surface midpoints
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

					nodename = minetest.get_node(vector.add(opos, n)).name -- verify normal
					walkable = nodename ~= "air"
					if walkable then -- problem, nonempty node - incorrect normal, fix it
						if n.x ~= 0 then -- x direction is wrong, try something else
							n.x = 0
							if v.y >= 0 then n.y = -1 else n.y = 1 end -- try y
							nodename = minetest.get_node(vector.add(opos, n)).name -- verify normal
							walkable = nodename ~= "air"
							if walkable then -- still problem, only remaining is z
								n.y = 0
								if v.z >= 0 then n.z = -1 else n.z = 1 end
								nodename = minetest.get_node(vector.add(opos, n)).name -- verify normal
								walkable = nodename ~= "air"
								if walkable then -- messed up, just remove the ball
									self.object:remove(); return
								end
							end
						end
					end
				end

				local bpos = vector.add(pos, vector.multiply(n, 0.2)) -- point placed a bit further away from box
				local elasticity = self._elasticity

				-- bounce
				if n.x ~= 0 then
					v.x = -elasticity * v.x
				elseif n.y ~= 0 then
					v.y = -elasticity * v.y
				elseif n.z ~= 0 then
					v.z = -elasticity * v.z
				end

				self.object:set_pos(bpos) -- place object at last known outside point
				self.object:set_velocity(v)

				minetest.sound_play("default_dig_cracky", {pos = pos, gain = 1, max_hear_distance = 8}, true)
			end
		end
	end,

	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if self._punchable == 0 then return end
		if self._punchable == 1 then -- only those in protection
			local obj_pos = self.object:get_pos()
			if not minetest.is_protected(obj_pos) or
				not puncher or minetest.is_protected(obj_pos, puncher:get_player_name())
			then
				return
			end
		end
		if time_from_last_punch < 0.5 then return end
		self.object:set_velocity(vector.multiply(dir, (self._speed or ball_default.speed)))
	end
})

local function ball_spawner_update_form(meta)
	local field_lifetime = ""

	if meta:get_int("admin") == 1 then
		field_lifetime = ("field[2.25,2.5;1,1;lifetime;%s;%i]"):format(F(S("Lifetime")), meta:get_int("lifetime"))
	end

	meta:set_string("formspec", ([[
		size[4,5]
		field[0.25,0.5;1,1;x0;%s;%.2f]
		field[1.25,0.5;1,1;y0;;%.2f]
		field[2.25,0.5;1,1;z0;;%.2f]
		field[3.25,0.5;1,1;speed;%s;%.2f]
		field[0.25,1.5;1,1;energy;%s;%i]
		field[1.25,1.5;1,1;bounce;%s;%i]
		field[2.25,1.5;1,1;gravity;%s;%.2f]
		field[3.25,1.5;1,1;punchable;%s;%i]
		tooltip[2.95,0.97;0.8,0.34;%s]
		field[0.25,2.5;1,1;hp;%s;%.2f]
		field[1.25,2.5;1,1;hurt;%s;%.2f]
		%s
		field[3.25,2.5;1,1;solid;%s;%i]
		field[0.25,3.5;4,1;texture;%s;%s]
		field[0.25,4.5;1,1;scale;%s;%i]
		field[1.25,4.5;1,1;visual;%s;%s]
		button[2,4.2;1,1;help;%s]button_exit[3,4.2;1,1;OK;%s]
	]]):format(F(S("Target")), meta:get_float("x0"), meta:get_float("y0"), meta:get_float("z0"),
		F(S("Speed")), meta:get_float("speed"), F(S("Energy")), meta:get_int("energy"),
		F(S("Bounce")), meta:get_int("bounce"), F(S("Gravity")), meta:get_float("gravity"),
		F(S("Punch.")), meta:get_int("punchable"), F(S("Punchable")),
		F(S("HP")), meta:get_float("hp"), F(S("Hurt")), meta:get_float("hurt"),
		field_lifetime, F(S("Solid")), meta:get_int("solid"),
		F(S("Texture")), F(meta:get_string("texture")), F(S("Scale")), meta:get_int("scale"),
		F(S("Visual")), meta:get_string("visual"), F(S("help")), F(S("OK"))
	))
end

-- to be used with bounce setting 2 in ball spawner:
-- 1: bounce in x direction, 2: bounce in z direction, otherwise it bounces in y direction
local bounce_materialslist, dirs, i = {}, {"x", "z"}, 1
for material, v in pairs(bounce_materials) do
	bounce_materialslist[i] = ("%s: %s"):format(material, dirs[v]); i = i + 1
end
bounce_materialslist = table.concat(bounce_materialslist, "\n")

minetest.register_node("basic_machines:ball_spawner", {
	description = S("Ball Spawner"),
	groups = {cracky = 3, oddly_breakable_by_hand = 1},
	drawtype = "allfaces",
	tiles = {"basic_machines_ball.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	param1 = 1,
	walkable = false,
	sounds = default.node_sound_wood_defaults(),
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

	after_dig_node = function(pos, oldnode, oldmetadata, digger)
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

	on_receive_fields = function(pos, formname, fields, sender)
		local name = sender:get_player_name()
		if fields.OK then
			if minetest.is_protected(pos, name) then return end
			local privs = minetest.check_player_privs(name, "privs")
			local meta = minetest.get_meta(pos)

			-- minetest.chat_send_all("form at " .. dump(pos) .. " fields " .. dump(fields))

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
			if (gravity < 0.1 or gravity > 40) and not privs then return end
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
				"formspec_version[4]size[8,9.3]textarea[0,0.35;8,8.95;help;" .. F(S("BALL SPAWNER CAPABILITIES")) .. ";" ..
F(S([[
VALUES

Target*:		Direction of velocity
				x: [-@1, @2], y: [-@3, @4], z: [-@5, @6]
Speed:			[-10, 10]
Energy:			[-1,  1]
Bounce**:		[0,   2]
Gravity:		[0.1, 40]
Punchable***:	[0,   2]
Hp:				[0,   +∞[
Hurt:			]-∞,  @7]@8
Solid*:			[0,   1]
Texture:		Texture name with extension, up to 512 characters
Scale*:			[1,   1000]
Visual*:		"cube" or "sprite"

*: Not available as individual Ball Spawner

**: Set to 2, the ball bounce following y direction and for the next blocks:
@9

***: 0: not punchable, 1: only in protected area, 2: everywhere

Note: Hold sneak while digging to get the Ball Spawner
]], max_range, max_range, max_range, max_range, max_range, max_range,
max_damage, lifetime, bounce_materialslist)) .. "]")
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
				if t1 - t0 > machines_timer then -- reset temperature if more than 5s elapsed since last activation
					T = 0; meta:set_string("infotext", "")
				else
					T = T - 1
				end
			end
			meta:set_int("t", t1); meta:set_int("T", T)

			if T > 2 then -- overheat
				minetest.sound_play("default_cool_lava", {pos = pos, max_hear_distance = 16, gain = 0.25}, true)
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
				local luaent = obj:get_luaentity(); luaent._origin, luaent._owner = pos, owner

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
				luaent._speed = speed

				-- energy
				local energy = meta:get_int("energy") -- if positive activates, negative deactivates, 0 does nothing
				local colorize = energy < 0 and "^[colorize:blue:120" or ""
				luaent._energy = energy

				-- bounce
				luaent._bounce = meta:get_int("bounce") -- if nonzero bounces when hit obstacle, 0 gets absorbed

				-- gravity
				obj:set_acceleration({x = 0, y = -meta:get_float("gravity"), z = 0})

				-- punchable
				-- if 0 not punchable, if 1 can be punched by players in protection, if 2 can be punched by anyone
				luaent._punchable = meta:get_int("punchable")

				-- hp
				obj:set_hp(meta:get_float("hp"))

				-- hurt
				local hurt = meta:get_float("hurt")
				if hurt > 0 then luaent._is_arrow = true end -- tell advanced mob protection this is an arrow
				luaent._hurt = hurt

				-- lifetime
				if meta:get_int("admin") == 1 then
					luaent._lifetime = meta:get_int("lifetime")
				end

				-- solid
				if meta:get_int("solid") == 1 then
					obj:set_properties({physical = true})
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
				if t1 - t0 > machines_timer then -- reset temperature if more than 5s elapsed since last activation
					T = 0; meta:set_string("infotext", "")
				else
					T = T - 1
				end
			end
			meta:set_int("t", t1); meta:set_int("T", T)

			if T > 2 then -- overheat
				minetest.sound_play("default_cool_lava", {pos = pos, max_hear_distance = 16, gain = 0.25}, true)
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
				local luaent = obj:get_luaentity(); luaent._origin, luaent._owner = pos, owner

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
				luaent._speed = speed

				-- energy
				obj:get_luaentity()._energy = -1

				-- hp
				obj:set_hp(meta:get_float("hp"))

				-- lifetime
				if meta:get_int("admin") == 1 then
					luaent._lifetime = meta:get_int("lifetime")
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

	on_use = function(itemstack, user, pointed_thing)
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
			local luaent = obj:get_luaentity(); luaent._origin, luaent._owner = pos, owner

			-- speed
			local speed = tonumber(meta["speed"]) or ball_default.speed
			speed = privs and speed or math.min(math.max(speed, -10), 10)
			obj:set_velocity(vector.multiply(user:get_look_dir(), speed))
			luaent._speed = speed

			-- energy
			-- if positive activates, negative deactivates, 0 does nothing
			local energy = tonumber(meta["energy"]) or ball_default.energy
			local colorize = energy < 0 and "^[colorize:blue:120" or ""
			luaent._energy = energy

			-- bounce
			-- if nonzero bounces when hit obstacle, 0 gets absorbed
			luaent._bounce = tonumber(meta["bounce"]) or ball_default.bounce

			-- gravity
			local gravity = tonumber(meta["gravity"]) or ball_default.gravity
			gravity = privs and gravity or math.min(math.max(gravity, 0.1), 40)
			obj:set_acceleration({x = 0, y = -gravity , z = 0})

			-- punchable
			-- if 0 not punchable, if 1 can be punched by players in protection, if 2 can be punched by anyone
			luaent._punchable = tonumber(meta["punchable"]) or ball_default.punchable

			-- hp
			obj:set_hp(tonumber(meta["hp"]) or ball_default.hp)

			-- hurt
			local hurt = tonumber(meta["hurt"]) or ball_default.hurt
			hurt = privs and hurt or math.min(hurt, max_damage)
			if hurt > 0 then luaent._is_arrow = true end -- tell advanced mob protection this is an arrow
			luaent._hurt = hurt

			-- lifetime
			if privs then
				luaent._lifetime = tonumber(meta["lifetime"]) or ball_default.lifetime
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