require "string"
require "math"
require "table"
require "lib/lib_InterfaceOptions"
require "./lib/lib_LKSettings"
require "lib/lib_Slash";

local pairs = pairs
local math = math
local string = string

-- // SpeedWidget "class" \\ --

SpeedWidget = {}
SpeedWidget.__index = SpeedWidget
function SpeedWidget.create(name, description, speed_param, unit, default, only_when_gliding)
	local obj = {}
	setmetatable(obj, SpeedWidget)
	obj.name = name
	obj.frame = Component.GetFrame("SM_"..name)
	local group = Component.GetWidget("SM_"..name)
	obj.text = group:GetChild("Text")
	obj.value = group:GetChild("Value")
	obj.description = description
	obj.speed_param = speed_param
	obj.default = default
	obj.unit = unit
	obj.only_when_gliding = only_when_gliding
	return obj
end

function SpeedWidget:draw(speed_results)
	if self.enabled then
		self.value:SetText(formatSpeed(speed_results[self.speed_param], self.unit))
	end
end

-- \\ SpeedWidget "class" // --

PLUGIN_TAG = '[SpeedoMeter]'

local SPEED_WIDGETS = {}
SPEED_WIDGETS.XY = SpeedWidget.create("XY", "horizontal", "speed_xy", "m/s", true, false)
SPEED_WIDGETS.Z = SpeedWidget.create("Z", "vertical", "speed_z", "m/s", true, false)
SPEED_WIDGETS.XY_DIFF = SpeedWidget.create("XY_ACCEL", "horizontal accel", "accel_xy", "m/s²", false, false)
SPEED_WIDGETS.Z_DIFF = SpeedWidget.create("Z_ACCEL", "vertical accel", "accel_z", "m/s²", false, false)
SPEED_WIDGETS.EFFICIENCY = SpeedWidget.create("EFFICIENCY", "efficiency", "efficiency", "", false, true)

local UPDATE_RATE = 10 -- Hz
local HIDE_WHEN_NOT_INTERESTING = true
local SUMMARY = true

local g_cb_update_speed = nil
local g_gliding = false
local g_gui_visible = true
local g_position = { x=0, y=0, z=0 }
local g_speed_results = { speed_xy=0, speed_z=0 }
local g_time = nil
local g_vehicle_distance = 0
local g_vehicle_time = 0

-- register options

for _, speed_widget in pairs(SPEED_WIDGETS) do

	InterfaceOptions.AddMovableFrame({
		frame = speed_widget.frame,
		label = "SpeedoMeter - "..speed_widget.description,
		scalable = true,
	})

	option_name = "ENABLED_"..speed_widget.name
	InterfaceOptions.AddCheckBox({id=option_name, label="Enable "..speed_widget.description.." meter", default=speed_widget.default})
	LKSettings.AddOption(option_name,
		function(value)
			speed_widget.frame:Show(value)
			speed_widget.enabled = value
			DisplayOrHide()
		end
	)
end

InterfaceOptions.AddSlider({id="UPDATE_RATE", label="Updates Per Second", min=0, max=60, inc=1, format="%d", suffix="fps", default=UPDATE_RATE})
InterfaceOptions.AddCheckBox({id="HIDE_WHEN_NOT_INTERESTING", label="Hide when not gliding" --[[/driving]], default=HIDE_WHEN_NOT_INTERESTING})
InterfaceOptions.AddCheckBox({id="SUMMARY", label="Show summary after gliding" --[[/driving]], default=SUMMARY})

LKSettings.AddOption("UPDATE_RATE",
	function(value)
		UPDATE_RATE = value
		DisplayOrHide()
	end
)

LKSettings.AddOption("SUMMARY",
	function(value)
		SUMMARY = value
	end
)

LKSettings.AddOption("HIDE_WHEN_NOT_INTERESTING",
	function(value)
		HIDE_WHEN_NOT_INTERESTING = value
		DisplayOrHide()
	end
)

-- event handlers

function OnComponentLoad()
	InterfaceOptions.SetCallbackFunc(LKSettings.OnMessage, "SpeedoMeter")
	--UpdateSpeed() -- HIDE_WHEN_NOT_INTERESTING option calls that indirectly
end

function OnMessage(args)
	-- it seems that We don't need it
	local option, message = args.type, args.data
	--if not ( OnMessageOption[option] ) then log("["..option.."] Not Found") return nil end
	--OnMessageOption[option](message)
end

function OnPlayerGlide(args)
	if args.gliding == true then
		g_gliding = true
		g_vehicle_distance = 0
		g_vehicle_time = 0
		g_time = nil -- reset time, in case it wasn't updated due to timer being stopped
	else
		g_gliding = false
		displaySummary()
	end
	DisplayOrHide()
end

function OnShow(args)
	g_gui_visible = false
	if args.show then
		g_gui_visible = true
	end
	DisplayOrHide()
end

-- functions

function displaySummary()
	if SUMMARY then
		print_system_message(string.format("Traveled %.2fm (%.2fm/s)", g_vehicle_distance, g_vehicle_distance/g_vehicle_time))
	end
end

function formatSpeed(speed, unit)
	return string.format("%.2f ", speed)..unit
end

function ShouldShow()
	if not g_gui_visible then
		return false
	elseif HIDE_WHEN_NOT_INTERESTING and not g_gliding then
		return false
	elseif UPDATE_RATE == 0 then
		return false
	end
	for _, speed_widget in pairs(SPEED_WIDGETS) do
		if speed_widget.enabled then
			return true
		end
	end
	return false
end

function DisplayOrHide()
	set_to = ShouldShow()
	for _, speed_widget in pairs(SPEED_WIDGETS) do
		override = set_to
		if set_to and speed_widget.only_when_gliding then
			override = g_gliding
		end
		speed_widget.frame:ParamTo("alpha", tonumber(override), 0)
	end
	SafeUpdateSpeed()
end

function print_system_message(message)
	Component.GenerateEvent("MY_SYSTEM_MESSAGE", {text=PLUGIN_TAG.." "..message})
end

function SafeUpdateSpeed()
	if g_cb_update_speed then
		cancel_callback(g_cb_update_speed)
		g_cb_update_speed = nil
		g_time = nil
	end
	return UpdateSpeed()
end

function UpdateSpeed()
	-- if not interesting, quit
	if not ShouldShow() and not (SUMMARY and g_gliding) then
		g_time = nil
		return
	end
	-- if it's a first run, initialize
    if not g_time then
		g_time = System.GetClientTime()
		g_position = Player.GetPosition()
		g_cb_update_speed = callback(UpdateSpeed, nil, 1/UPDATE_RATE)
		return
	end
	
	-- compute differences
	local new_position = Player.GetPosition()
	local new_time = System.GetClientTime()
	local diff_time = System.GetElapsedTime(g_time)
	if diff_time==0 then
		-- reschedule
		g_cb_update_speed = callback(UpdateSpeed, nil, 1/UPDATE_RATE)
		return
	end
	local speed_results = {}
	-- compute diff
	speed_results.diff_time = diff_time
	speed_results.diff_x = unitsToMeters(new_position.x - g_position.x)
	speed_results.diff_y = unitsToMeters(new_position.y - g_position.y)
	speed_results.diff_z = unitsToMeters(new_position.z - g_position.z)
	speed_results.diff_xy = math.sqrt(math.pow(speed_results.diff_x, 2) + math.pow(speed_results.diff_y, 2))
	-- compute speed
	speed_results.speed_xy = speed_results.diff_xy / diff_time
	speed_results.speed_z = speed_results.diff_z / diff_time
	-- compute accel
	speed_results.accel_xy = (speed_results.speed_xy - g_speed_results.speed_xy) / diff_time
	speed_results.accel_z = (speed_results.speed_z - g_speed_results.speed_z) / diff_time
	if speed_results.speed_z == 0 then
		speed_results.efficiency = 0
	else
		speed_results.efficiency = speed_results.speed_xy/speed_results.speed_z*-1
	end
	UpdateUI(speed_results)

	-- update global variables for the next run
	g_vehicle_distance = g_vehicle_distance + speed_results.diff_xy
	g_vehicle_time = g_vehicle_time + speed_results.diff_time
	g_position = new_position
	g_time = new_time
	g_speed_results = speed_results
	
	-- schedule next run
	g_cb_update_speed = callback(UpdateSpeed, nil, 1/UPDATE_RATE)
end

function unitsToMeters(value)
	-- return value*5.27/7.71
	-- at first I thought it's linear, but either it's not, or the values of servo description are lying
	-- I have no idea how to compute that - so let's just leave it in units
	return value
end

function UpdateUI(diff_time, old_position, new_position)
	-- update all widgets
	for _, speed_widget in pairs(SPEED_WIDGETS) do
		speed_widget:draw(diff_time, g_position, new_position)
	end
end
