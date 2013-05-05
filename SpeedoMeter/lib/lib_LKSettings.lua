--
-- lib_LKSettings
--	by: Lemon King
--
--	A Very Simple Library for TweakUI based addons
--
-- Usage:
-- LKSettings.SetDisplayUpdate(func)			-- Called after options are processed to allow the user to control what settings are shown.
-- LKSettings.AddOption(option, func)			-- Adds an option by name to the Setting table, will not overwrite a pre-existing option unless force is true.
-- LKSettings.OnMessage(args)					-- Controller for all options when called, bind directly to the function name used by <OnMessage bind="OnMessage"/>.

-- VERSION : 1

-- "LICENSE": Lemon King: "I have no restrictions on other Authors using my libs in their Addons"

LKSettings = {}

local OPTIONS_TABLE = {}
local DisplayUpdate = nil

LKSettings.SetDisplayUpdate =
	function (func)
		DisplayUpdate = func
	end

LKSettings.AddOption = 
	function (option, func, force)
		if OPTIONS_TABLE[option] then log("Error ["..option.."] already exists!") return nil end
		OPTIONS_TABLE[option] = func
	end
	
LKSettings.OnMessage =
	function(option, value)
		if not ( OPTIONS_TABLE[option] ) then log("["..option.."] Not Found!") return nil end
		log("["..option.."]="..string.gsub(tostring(value), "\n", ""))	-- Converts JSON Multi Line Table to Single Line
		OPTIONS_TABLE[option](value)

		if DisplayUpdate then DisplayUpdate() end
	end