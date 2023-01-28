unused_args = false

globals = {
	"basic_machines"
}

read_globals = {
	"ItemStack",
	"default",
	"farming",
	"machines",
	"minetest",
	"player_monoids",
	"unified_inventory",
	"vector",
	table = {fields = {"copy"}}
}

files["ball.lua"] = {globals = {"boneworld.killxp"}}
files["grinder.lua"] = {read_globals = {"i3"}}
files["keypad.lua"] = {read_globals = {"signs_lib"}}
files["machines_configuration.lua"] = {max_line_length = 190}
files["mark.lua"] = {globals = {"machines"}}
files["mesecon_adapter.lua"] = {read_globals = {"mesecon"}}
files["mover.lua"] = {max_line_length = 290, read_globals = {"bucket", "nodeupdate"}}
files["protect.lua"] = {globals = {"minetest.is_protected"}, read_globals = {"beerchat"}}
files["technic_power.lua"] = {max_line_length = 140}