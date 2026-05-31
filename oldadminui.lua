--// CFrame Zero Runtime - Commands Only
--// Uses the scaled command UI shape from NewFixedUI in a commands-only runtime.

local Services = {
	Players = game:GetService("Players"),
	TweenService = game:GetService("TweenService"),
	UserInputService = game:GetService("UserInputService"),
	RunService = game:GetService("RunService"),
	Lighting = game:GetService("Lighting"),
	GuiService = game:GetService("GuiService"),
	HttpService = game:GetService("HttpService"),
}

local LocalPlayer = Services.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Content = Content or { fromUri = function(uri) return uri end }

local TweenService = Services.TweenService
local UserInputService = Services.UserInputService
local RunService = Services.RunService
local Lighting = Services.Lighting
local GuiService = Services.GuiService
local HttpService = Services.HttpService

local Env = _G
if typeof(getgenv) == "function" then
	local ok, genv = pcall(getgenv)
	if ok and type(genv) == "table" then
		Env = genv
	end
end

local Runtime = {
	Alive = true,
	Connections = {},
	Tweens = {},
	Threads = {},
	Refs = {},
	Commands = {},
	CommandRows = {},
	CategoryRows = {},
	OriginalLighting = nil,
	FullbrightObjectStates = {},
	FullbrightEnabled = false,
	HoveringMain = false,
	InputFocused = false,
	HintVisible = false,
	HintTarget = nil,
	HintRow = nil,
	HintHoverStamp = 0,
	HintHoverRow = nil,
	SanitizingInput = false,
	CloseStamp = 0,
	Settings = nil,
	SettingsOpen = false,
	CapturingBind = false,
	DraggingSlider = false,
	FullbrightInputUpdating = false,
	FullbrightDropdownOpen = false,
	OnBoardingBlur = nil,
	DefaultClockTime = nil,
	DefaultShadowSoftness = nil,
}

--// Hint cursor tuning:
--// AnchorPoint controls which point of the hint follows the mouse.
--// Offset moves that attached point in pixels.
--// X: positive = right, negative = left.
--// Y: positive = down, negative = up.
--// Increase the Y anchor toward 1 to place more of the hint above the mouse; lower it to move the hint down.
--// Hint size is inside buildHint: Size = UDim2.fromOffset(185, 92).
local HintFollow = {
	AnchorPoint = Vector2.new(1, 0.78),
	Offset = Vector2.new(0, 0),
}

Runtime.DefaultClockTime = Lighting.ClockTime
Runtime.DefaultShadowSoftness = Lighting.ShadowSoftness

local CommandData = {
	{
		Category = "WORLD",
		Display = "fullbright / fb",
		Aliases = { "fullbright", "fb" },
		Description = "Brightens your client view by lifting ambient light, reducing fog, and disabling heavy shadows so darker maps and indoor areas stay much easier to see while the effect is active.",
		Undo = "unfullbright / unfb",
		Editable = true,
		SettingsPage = "fullbright",
	},
	{
		Category = "WORLD",
		Display = "disableshadows",
		Aliases = { "disableshadows" },
		Description = "Disables global world shadows on your client for a cleaner and brighter view. If another command changes shadows after this, the newest command wins.",
		Undo = "enableshadows",
	},
	{
		Category = "WORLD",
		Display = "time <number>",
		Aliases = { "time" },
		Description = "Changes the client-side world time. Use a number from 0 to 24, for example: time 12.",
		Undo = "resettime",
	},
	{
		Category = "PLAYER",
		Display = "sit",
		Aliases = { "sit" },
		Description = "Makes your character sit once. This command has no active toggle state and no undo command.",
	},
}

local SETTINGS_FILE = "CFrameZeroSettings.json"
local DEFAULT_SETTINGS = {
	Fullbright = {
		Enabled = false,
		BindKey = "",
		Brightness = 5,
		ForceDay = false,
		OverrideOptions = {
			Ambient = true,
			OutdoorAmbient = true,
			Brightness = true,
			ExposureCompensation = true,
			Fog = true,
			Shadows = true,
			ColorShifts = true,
			Environment = true,
			PostEffects = true,
			Atmosphere = true,
		},
	},
}

local SettingsSizing = {
	ToggleAspect = 10,
	BindAspect = 10,
	SliderAspect = 5.5,
	SliderBarAspect = 80,
	DropdownOptionAspect = 10,
	ButtonHoverScale = 1.1,
	ButtonPressScale = 0.9,
}

local FULLBRIGHT_OVERRIDE_OPTIONS = {
	{
		Key = "Ambient",
		Text = "Ambient",
	},
	{
		Key = "OutdoorAmbient",
		Text = "OutdoorAmbient",
	},
	{
		Key = "Brightness",
		Text = "Brightness",
	},
	{
		Key = "ExposureCompensation",
		Text = "ExposureCompensation",
	},
	{
		Key = "Fog",
		Text = "Fog",
	},
	{
		Key = "Shadows",
		Text = "Shadows",
	},
	{
		Key = "ColorShifts",
		Text = "Color shifts",
	},
	{
		Key = "Environment",
		Text = "Environment scales",
	},
	{
		Key = "PostEffects",
		Text = "Post-processing effects",
	},
	{
		Key = "Atmosphere",
		Text = "Atmosphere",
	},
}

local HINT_HOVER_DELAY = 0.4

local applyFullbrightState
local refreshFullbrightSettingsUi

local function cloneDefaults(value)
	if type(value) ~= "table" then
		return value
	end

	local clone = {}
	for key, child in pairs(value) do
		clone[key] = cloneDefaults(child)
	end
	return clone
end

local function clampNumber(value, minValue, maxValue)
	local number = tonumber(value) or minValue
	number = math.floor(number + 0.5)
	return math.clamp(number, minValue, maxValue)
end

local function getFullbrightSettings()
	Runtime.Settings = Runtime.Settings or cloneDefaults(DEFAULT_SETTINGS)
	Runtime.Settings.Fullbright = Runtime.Settings.Fullbright or cloneDefaults(DEFAULT_SETTINGS.Fullbright)
	return Runtime.Settings.Fullbright
end

local function getFullbrightOverrideOptions()
	local settings = getFullbrightSettings()
	settings.OverrideOptions = type(settings.OverrideOptions) == "table" and settings.OverrideOptions or cloneDefaults(DEFAULT_SETTINGS.Fullbright.OverrideOptions)

	for key, defaultValue in pairs(DEFAULT_SETTINGS.Fullbright.OverrideOptions) do
		if type(settings.OverrideOptions[key]) ~= "boolean" then
			settings.OverrideOptions[key] = defaultValue
		end
	end

	return settings.OverrideOptions
end

local function keyFromName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end

	local ok, keyCode = pcall(function()
		return Enum.KeyCode[name]
	end)

	if ok and typeof(keyCode) == "EnumItem" then
		return keyCode
	end

	return nil
end

local function sanitizeSettings(settings)
	settings.Fullbright = type(settings.Fullbright) == "table" and settings.Fullbright or cloneDefaults(DEFAULT_SETTINGS.Fullbright)

	local fullbright = settings.Fullbright
	fullbright.Enabled = fullbright.Enabled == true
	fullbright.ForceDay = fullbright.ForceDay == true
	fullbright.Brightness = clampNumber(fullbright.Brightness, 0, 100)
	fullbright.OverrideOptions = type(fullbright.OverrideOptions) == "table" and fullbright.OverrideOptions or cloneDefaults(DEFAULT_SETTINGS.Fullbright.OverrideOptions)

	for key, defaultValue in pairs(DEFAULT_SETTINGS.Fullbright.OverrideOptions) do
		if type(fullbright.OverrideOptions[key]) ~= "boolean" then
			fullbright.OverrideOptions[key] = defaultValue
		end
	end

	if keyFromName(fullbright.BindKey) == nil then
		fullbright.BindKey = ""
	end
end

local function readSettingsFile()
	if type(readfile) ~= "function" then
		return nil
	end

	if type(isfile) == "function" then
		local ok, exists = pcall(isfile, SETTINGS_FILE)
		if not ok or not exists then
			return nil
		end
	end

	local ok, raw = pcall(readfile, SETTINGS_FILE)
	if ok and type(raw) == "string" and raw ~= "" then
		return raw
	end

	return nil
end

local function saveSettings()
	if type(writefile) ~= "function" or not Runtime.Settings then
		return
	end

	sanitizeSettings(Runtime.Settings)
	getFullbrightOverrideOptions()

	local settingsToSave = cloneDefaults(Runtime.Settings)
	if settingsToSave.Fullbright then
		settingsToSave.Fullbright.Enabled = false
	end

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(settingsToSave)
	end)

	if ok and type(encoded) == "string" then
		pcall(writefile, SETTINGS_FILE, encoded)
	end
end

local function loadSettings()
	local settings = cloneDefaults(DEFAULT_SETTINGS)
	local raw = readSettingsFile()

	if raw then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)

		if ok and type(decoded) == "table" then
			for sectionName, sectionValue in pairs(decoded) do
				if type(sectionValue) == "table" and type(settings[sectionName]) == "table" then
					for key, value in pairs(sectionValue) do
						settings[sectionName][key] = value
					end
				end
			end
		end
	end

	sanitizeSettings(settings)
	settings.Fullbright.Enabled = false
	Runtime.Settings = settings
	getFullbrightOverrideOptions()
end

local function commitSettings(applyNow)
	sanitizeSettings(Runtime.Settings)
	saveSettings()

	if applyNow ~= false and applyFullbrightState then
		applyFullbrightState()
	end

	if refreshFullbrightSettingsUi then
		refreshFullbrightSettingsUi(false)
	end
end


local function getGuiParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and typeof(hui) == "Instance" then
			return hui
		end
	end

	return PlayerGui
end

local function isCFrameZeroGui(gui)
	if not gui or not gui:IsA("ScreenGui") then
		return false
	end

	if gui.Name == "CFrameZeroUI" then
		return true
	end

	return gui.Name == "MainUI"
		and gui:FindFirstChild("OnBoarding") ~= nil
		and gui:FindFirstChild("Main") ~= nil
end

local function destroyOldGui()
	local parents = { PlayerGui, getGuiParent() }
	local used = {}

	for _, parent in ipairs(parents) do
		if typeof(parent) == "Instance" and not used[parent] then
			used[parent] = true

			for _, child in ipairs(parent:GetChildren()) do
				if isCFrameZeroGui(child) then
					child:Destroy()
				end
			end
		end
	end
end

local function path(root, ...)
	local current = root
	for _, name in ipairs({ ... }) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function new(className, props, parent)
	local inst = Instance.new(className)

	for key, value in pairs(props or {}) do
		inst[key] = value
	end

	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	local c = new("UICorner", {}, parent)
	c.CornerRadius = radius or UDim.new(0, 5)
	return c
end

local function stroke(parent, thickness, transparency)
	return new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.fromRGB(255, 255, 255),
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.9,
	}, parent)
end

local function aspect(parent, ratio)
	local a = new("UIAspectRatioConstraint", {}, parent)
	if ratio then
		a.AspectRatio = ratio
	end
	return a
end

local function aspectFromWidth(parent, ratio)
	local a = aspect(parent, ratio)
	pcall(function()
		a.AspectType = Enum.AspectType.ScaleWithParentSize
	end)
	pcall(function()
		a.DominantAxis = Enum.DominantAxis.Width
	end)
	return a
end

local function aspectFromHeight(parent, ratio)
	local a = aspect(parent, ratio)
	pcall(function()
		a.AspectType = Enum.AspectType.ScaleWithParentSize
	end)
	pcall(function()
		a.DominantAxis = Enum.DominantAxis.Height
	end)
	return a
end

local function mainGradient(parent)
	return new("UIGradient", {
		Rotation = 15,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 33, 39)),
			ColorSequenceKeypoint.new(0.6453, Color3.fromRGB(30, 33, 39)),
			ColorSequenceKeypoint.new(0.6522, Color3.fromRGB(36, 40, 47)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 40, 47)),
		}),
	}, parent)
end

local function safeScrollImages(scroll)
	if not scroll then
		return
	end

	local image = "rbxasset://textures/ui/Scroll/scroll-middle.png"

	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageTransparency = 0
	scroll.ScrollBarImageColor3 = Color3.fromRGB(193, 54, 54)
	scroll.TopImage = image
	scroll.MidImage = image
	scroll.BottomImage = image

	pcall(function()
		scroll.TopImageContent = Content.fromUri(image)
	end)
	pcall(function()
		scroll.MiddleImageContent = Content.fromUri(image)
	end)
	pcall(function()
		scroll.MidImageContent = Content.fromUri(image)
	end)
	pcall(function()
		scroll.BottomImageContent = Content.fromUri(image)
	end)
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	Runtime.Connections[#Runtime.Connections + 1] = connection
	return connection
end


local function getPaddingPixels(padding)
	if not padding then
		return 0
	end

	local total = 0
	pcall(function()
		total += padding.PaddingTop.Offset
		total += padding.PaddingBottom.Offset
	end)

	return total
end

local function updateScrollableCanvas(scroll)
	if not scroll then
		return
	end

	local layout = scroll:FindFirstChildOfClass("UIListLayout")
	local padding = scroll:FindFirstChildOfClass("UIPadding")
	local contentHeight = getPaddingPixels(padding)

	if layout then
		contentHeight += layout.AbsoluteContentSize.Y
	end

	local visibleHeight = scroll.AbsoluteSize.Y
	if visibleHeight <= 0 then
		task.defer(function()
			updateScrollableCanvas(scroll)
		end)
		return
	end

	local canvasHeight = math.max(math.ceil(contentHeight), math.ceil(visibleHeight))
	scroll.CanvasSize = UDim2.fromOffset(0, canvasHeight)

	local maxCanvasY = math.max(canvasHeight - visibleHeight, 0)
	if scroll.CanvasPosition.Y > maxCanvasY then
		scroll.CanvasPosition = Vector2.new(scroll.CanvasPosition.X, maxCanvasY)
	end
end

local function configureTightScrollingFrame(scroll)
	if not scroll then
		return
	end

	Runtime.TightScrollFrames = Runtime.TightScrollFrames or {}
	if Runtime.TightScrollFrames[scroll] then
		updateScrollableCanvas(scroll)
		return
	end
	Runtime.TightScrollFrames[scroll] = true

	safeScrollImages(scroll)

	pcall(function()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	end)
	pcall(function()
		scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	end)

	local function queueUpdate()
		task.defer(function()
			updateScrollableCanvas(scroll)
		end)
	end

	queueUpdate()

	local layout = scroll:FindFirstChildOfClass("UIListLayout")
	if layout then
		connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), queueUpdate)
	end

	connect(scroll:GetPropertyChangedSignal("AbsoluteSize"), queueUpdate)
	connect(scroll:GetPropertyChangedSignal("CanvasPosition"), function()
		updateScrollableCanvas(scroll)
	end)
	connect(scroll.ChildAdded, queueUpdate)
	connect(scroll.ChildRemoved, queueUpdate)
end

local function addThread(thread)
	Runtime.Threads[#Runtime.Threads + 1] = thread
	return thread
end

local function playTween(instance, info, props)
	if not instance then
		return nil
	end

	local tween = TweenService:Create(instance, info, props)
	Runtime.Tweens[#Runtime.Tweens + 1] = tween
	tween:Play()
	return tween
end

local function waitTween(tween)
	if tween then
		tween.Completed:Wait()
	end
end

local function cancelTweens()
	for _, tween in ipairs(Runtime.Tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	Runtime.Tweens = {}
end

local function disconnectAll()
	for _, connection in ipairs(Runtime.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	Runtime.Connections = {}
end

local function setInstanceProperty(instance, propertyName, value)
	pcall(function()
		instance[propertyName] = value
	end)
end

local function restoreFullbrightObjectStates()
	for object, state in pairs(Runtime.FullbrightObjectStates or {}) do
		if typeof(object) == "Instance" and object.Parent and type(state) == "table" then
			for propertyName, value in pairs(state) do
				setInstanceProperty(object, propertyName, value)
			end
		end
	end

	Runtime.FullbrightObjectStates = {}
end

local function restoreLighting()
	local data = Runtime.OriginalLighting
	Runtime.FullbrightEnabled = false

	if data then
		for propertyName, value in pairs(data) do
			setInstanceProperty(Lighting, propertyName, value)
		end
	end

	restoreFullbrightObjectStates()
	Runtime.OriginalLighting = nil
end

local function enableOnBoardingBlur()
	local blur = Runtime.OnBoardingBlur

	if not blur or blur.Parent ~= Lighting then
		blur = Instance.new("BlurEffect")
		blur.Name = "CFrameZeroOnBoardingBlur"
		blur.Size = 0
		blur.Parent = Lighting
		Runtime.OnBoardingBlur = blur
	end

	playTween(blur, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = 12,
	})
end

local function disableOnBoardingBlur()
	local blur = Runtime.OnBoardingBlur
	Runtime.OnBoardingBlur = nil

	if not blur then
		return
	end

	local tween = playTween(blur, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = 0,
	})

	task.spawn(function()
		waitTween(tween)
		if blur then
			blur:Destroy()
		end
	end)
end

local function cleanup()
	Runtime.Alive = false
	cancelTweens()
	disconnectAll()
	disableOnBoardingBlur()
	restoreLighting()

	if Runtime.Refs.Gui then
		Runtime.Refs.Gui:Destroy()
	end
end

if type(Env.CFrameZeroRuntime) == "table" and type(Env.CFrameZeroRuntime.Cleanup) == "function" then
	pcall(Env.CFrameZeroRuntime.Cleanup)
end

destroyOldGui()
Env.CFrameZeroRuntime = Runtime
Runtime.Cleanup = cleanup
loadSettings()

-- Commands should never auto-enable from saved settings on execution.
-- Persistent settings like binds, brightness, force-day, and override choices still save normally.
Runtime.FullbrightEnabled = false
Runtime.OriginalLighting = nil
Runtime.FullbrightObjectStates = {}
if Runtime.Settings and Runtime.Settings.Fullbright then
	Runtime.Settings.Fullbright.Enabled = false
end
restoreLighting()

local mainUi = new("ScreenGui", {
	Name = "CFrameZeroUI",
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
}, nil)

Runtime.Refs.Gui = mainUi

local function buildBoardMainFrame(container)
	local mainFrame = new("Frame", {
		Name = "MainFrame",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.9993, 0.9974),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, container)

	corner(mainFrame, UDim.new(0, 5))

	local divider = new("Frame", {
		Name = "Divider",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.5677, 0.0096),
		Position = UDim2.fromScale(0.0566, 0.2903),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, mainFrame)

	corner(divider, UDim.new(1, 0))
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.6176, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.6384, Color3.fromRGB(193, 54, 54)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(193, 54, 54)),
		}),
	}, divider)

	mainGradient(mainFrame)
	return mainFrame
end

local function buildBoardLoading(container)
	local loading = new("Frame", {
		Name = "Loading",
		BorderSizePixel = 0,
		BackgroundTransparency = 0.97,
		Size = UDim2.fromScale(0.9993, 0.1203),
		Position = UDim2.fromScale(0, 0.8791),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, container)

	local barBack = new("Frame", {
		Name = "LoadingBarBackground",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.9071, 0.217),
		Position = UDim2.fromScale(0.0765, 0.5969),
		BackgroundColor3 = Color3.fromRGB(26, 29, 34),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, loading)

	corner(barBack, UDim.new(1, 0))

	local bar = new("Frame", {
		Name = "LoadingBar",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(193, 54, 54),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, barBack)

	corner(bar, UDim.new(1, 0))
	return loading
end

local function buildBoardText(container)
	new("TextLabel", {
		Text = 'Developed by <font color="rgb(203,57,57)">uni</font>',
		Name = "Creator",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		RichText = true,
		Position = UDim2.fromScale(0.3457, 0.3238),
		Size = UDim2.fromScale(0.2785, 0.0575),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(217, 217, 217),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, container)

	new("TextLabel", {
		Text = "Preparing client runtime",
		Name = "LoadingStatus",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		Size = UDim2.fromScale(0.61, 0.042),
		Position = UDim2.fromScale(0.0768, 0.892),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, container)

	new("TextLabel", {
		Text = 'CFrame <font color="rgb(203, 57, 57)">Zero</font>',
		Name = "Title",
		TextSize = 14,
		BackgroundTransparency = 1,
		ZIndex = 2,
		BorderSizePixel = 0,
		TextScaled = true,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.fromScale(0.6197, 0.1813),
		Position = UDim2.fromScale(0.0579, 0.0838),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(255, 255, 255),
	}, container)

	new("TextLabel", {
		Text = "VERSION: 1.0.0",
		Name = "Version",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		Size = UDim2.fromScale(0.3084, 0.0566),
		Position = UDim2.fromScale(0.0587, 0.3266),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, container)
end

local function buildBoardImages(container)
	local avatar = new("ImageLabel", {
		Image = "rbxassetid://129947899712384",
		Name = "Avatar",
		BackgroundTransparency = 1,
		ZIndex = 6,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.3062, 0.7941),
		Position = UDim2.fromScale(0.6946, 0.0501),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	}, container)
	aspect(avatar, 0.6)

	local circle = new("ImageLabel", {
		Image = "rbxassetid://95521811822581",
		Name = "LoadingCircle",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
		Size = UDim2.fromScale(0.0438, 0.0739),
		Position = UDim2.fromScale(0.0165, 0.8985),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ImageColor3 = Color3.fromRGB(193, 54, 54),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, container)
	aspect(circle)
end

local function buildBackgroundDim(parent)
	local dim = new("Frame", {
		Name = "BackgroundDim",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		ZIndex = 0,
		Visible = false,
	}, parent)

	return dim
end

local function buildOnBoarding(parent)
	local board = new("ImageLabel", {
		Image = "rbxassetid://95827797495948",
		Name = "OnBoarding",
		ImageTransparency = 0.8899,
		ZIndex = 1,
		BackgroundTransparency = 1,
		Visible = false,
		AnchorPoint = Vector2.one * 0.5,
		Size = UDim2.fromScale(0.259, 0.2292),
		Position = UDim2.fromScale(0.4999, 0.5),
		SliceCenter = Rect.new(85, 85, 427, 427),
		ScaleType = Enum.ScaleType.Slice,
		BorderColor3 = Color3.fromRGB(27, 42, 53),
	}, parent)

	local container = new("Frame", {
		Name = "Container",
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.9694, 0.9513),
		Position = UDim2.fromScale(0.0153, 0.0226),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, board)

	buildBoardMainFrame(container)
	buildBoardLoading(container)
	buildBoardImages(container)
	buildBoardText(container)
	aspect(container, 1.75)
	corner(container, UDim.new(0, 5))
	stroke(container, 1.5, 0.9)
	aspect(board, 1.7)

	return board
end

local function buildCategoryTitle(parent, categoryName, order)
	local row = new("Frame", {
		Name = "CategoryTitle",
		LayoutOrder = order or 1,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.9194, 0.0496),
		Position = UDim2.fromScale(0.0402, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ClipsDescendants = true,
	}, parent)

	new("UISizeConstraint", {
		MinSize = Vector2.new(0, 28),
		MaxSize = Vector2.new(10000, 28),
	}, row)

	local title = new("TextLabel", {
		Text = string.upper(tostring(categoryName or "Commands")),
		Name = "CategoryTitle",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		TextSize = 13,
		TextWrapped = false,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(1, 0.72),
		Position = UDim2.fromScale(0.004, 0.14),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, row)

	Runtime.CategoryRows[#Runtime.CategoryRows + 1] = {
		Frame = row,
		Title = title,
		Category = categoryName or "Commands",
		MatchCount = 0,
	}

	return row
end

local function buildCommandRow(parent, data, order)
	local row = new("Frame", {
		Name = "CommandFrame",
		LayoutOrder = order or 1,
		BorderSizePixel = 0,
		BackgroundTransparency = 0.97,
		Size = UDim2.fromScale(0.9194, 0.0367),
		Position = UDim2.fromScale(0.0402, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		Active = true,
		ClipsDescendants = true,
	}, parent)

	stroke(row, 0.51, 0.9)
	corner(row, UDim.new(0, 2))

	new("UISizeConstraint", {
		MinSize = Vector2.new(0, 22),
		MaxSize = Vector2.new(10000, 22),
	}, row)

	local title = new("TextLabel", {
		Text = data.Display,
		Name = "CommandTitle",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		TextSize = 13,
		TextWrapped = false,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = data.Editable and UDim2.fromScale(0.82, 0.72) or UDim2.fromScale(0.93, 0.72),
		Position = UDim2.fromScale(0.033, 0.14),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, row)

	local editButton = nil
	if data.Editable then
		editButton = new("ImageButton", {
			Image = "rbxassetid://118932265176548",
			Name = "EditCommand",
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.94, 0.48),
			Size = UDim2.fromScale(0.052, 0.62),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderColor3 = Color3.fromRGB(0, 0, 0),
			ZIndex = 6,
		}, row)
		aspect(editButton)
	end

	Runtime.CommandRows[#Runtime.CommandRows + 1] = {
		Frame = row,
		Title = title,
		EditButton = editButton,
		Data = data,
		Category = data.Category or "Commands",
		Search = table.concat(data.Aliases, " ") .. " " .. data.Display .. " " .. (data.Undo or "") .. " " .. (data.Description or ""),
	}

	return row
end

local function buildCommandScroll(mainFrame)
	local scroll = new("ScrollingFrame", {
		Name = "ScrollingFrame",
		BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		ScrollBarThickness = 3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarImageTransparency = 0.25,
		Active = true,
		Size = UDim2.fromScale(0.9809, 0.7733),
		Position = UDim2.fromScale(0, 0.0899),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, mainFrame)

	safeScrollImages(scroll)

	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, scroll)

	new("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
	}, scroll)

	configureTightScrollingFrame(scroll)

	table.clear(Runtime.CommandRows)
	table.clear(Runtime.CategoryRows)

	local categories = {}
	local categoryOrder = {}

	for _, data in ipairs(CommandData) do
		local categoryName = data.Category or "Commands"
		if not categories[categoryName] then
			categories[categoryName] = {}
			categoryOrder[#categoryOrder + 1] = categoryName
		end
		categories[categoryName][#categories[categoryName] + 1] = data
	end

	local order = 1
	for _, categoryName in ipairs(categoryOrder) do
		local list = categories[categoryName]
		if list and #list > 0 then
			buildCategoryTitle(scroll, categoryName, order)
			order += 1

			for _, data in ipairs(list) do
				buildCommandRow(scroll, data, order)
				order += 1
			end
		end
	end

	return scroll
end

local function buildInput(mainContainer)
	local frame = new("Frame", {
		Name = "CommandInputFrame",
		BorderSizePixel = 0,
		BackgroundTransparency = 0.97,
		Size = UDim2.fromScale(0.9337, 0.082),
		Position = UDim2.fromScale(0.0303, 0.8899),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, mainContainer)

	stroke(frame, 1.5, 0.9)
	corner(frame, UDim.new(0, 2))

	new("TextBox", {
		PlaceholderText = "Enter a command...",
		Name = "CommandInput",
		Text = "",
		ClearTextOnFocus = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		Size = UDim2.fromScale(0.9582, -0.558),
		Position = UDim2.fromScale(0.0419, 0.75),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		TextColor3 = Color3.fromRGB(235, 235, 235),
		PlaceholderColor3 = Color3.fromRGB(157, 157, 157),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, frame)

	return frame
end

local function buildHint(parent)
	local hint = new("Frame", {
		Name = "HintFrame",
		BorderSizePixel = 0,
		Visible = false,
		AnchorPoint = HintFollow.AnchorPoint,
		Size = UDim2.fromOffset(185, 92),
		Position = UDim2.fromOffset(0, 0),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(28, 30, 36),
		ZIndex = 200,
		ClipsDescendants = false,
		Active = false,
		Selectable = false,
	}, parent)

	stroke(hint, 1, 0.9)
	corner(hint, UDim.new(0, 2))

	new("UISizeConstraint", {
		MinSize = Vector2.new(170, 84),
		MaxSize = Vector2.new(205, 104),
	}, hint)

	new("Frame", {
		Name = "Top",
		BorderSizePixel = 0,
		BackgroundTransparency = 0.97,
		Size = UDim2.fromScale(1, 0.225),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 201,
	}, hint)

	new("TextLabel", {
		Text = "fullbright / fb",
		Name = "Title",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 202,
		TextSize = 13,
		TextWrapped = false,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0.90, 0.145),
		Position = UDim2.fromScale(0.04, 0.065),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, hint)

	new("TextLabel", {
		Text = "Command description goes here",
		Name = "Description",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 202,
		TextSize = 12,
		TextWrapped = true,
		TextScaled = false,
		Position = UDim2.fromScale(0.04, 0.285),
		Size = UDim2.fromScale(0.91, 0.405),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(217, 217, 217),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, hint)

	new("Frame", {
		Name = "Bottom",
		BorderSizePixel = 0,
		BackgroundTransparency = 0.97,
		Size = UDim2.fromScale(1, 0.225),
		Position = UDim2.fromScale(0, 0.775),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = 201,
	}, hint)

	new("TextLabel", {
		Text = "unfullbright / unfb",
		Name = "Title2",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 202,
		TextSize = 13,
		TextWrapped = false,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0.90, 0.145),
		Position = UDim2.fromScale(0.04, 0.825),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, hint)

	return hint
end


local function buildSettingsLabel(parent, text, width, isSlider)
	local sizeY = isSlider and -0.2856 or -0.5694
	local posX = isSlider and 0.0338 or 0.0367
	local posY = isSlider and 0.3953 or 0.7473

	return new("TextLabel", {
		Text = text,
		Name = "Title",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10001,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(width or 0.6608, sizeY),
		Position = UDim2.fromScale(posX, posY),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, parent)
end

local function buildToggleModule(parent, titleText, order, refName)
	local module = new("Frame", {
		Name = "ModuleExample1",
		LayoutOrder = order,
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.919, 0.045),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, parent)

	stroke(module, 0.51, 0.9)
	aspectFromWidth(module, SettingsSizing.ToggleAspect)
	buildSettingsLabel(module, titleText, 0.6608, false)

	local button = new("TextButton", {
		Text = "",
		Name = "ToggleButton",
		TextSize = 14,
		BackgroundTransparency = 0.97,
		ZIndex = 10002,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.8349, 0.164),
		Size = UDim2.fromScale(0.2389, 0.702),
		FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ClipsDescendants = true,
	}, module)

	stroke(button, 0.51, 0.9)
	aspectFromHeight(button, 2)

	local moving = new("Frame", {
		Name = "Moving",
		ZIndex = 10003,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(170, 57, 57),
	}, button)

	stroke(moving, 0.51, 0.9)
	aspectFromHeight(moving, 1)

	Runtime.Refs[refName .. "Module"] = module
	Runtime.Refs[refName .. "ToggleButton"] = button
	Runtime.Refs[refName .. "Moving"] = moving

	return module
end

local function buildBindModule(parent)
	local module = new("Frame", {
		Name = "ModuleExample5",
		LayoutOrder = 2,
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.919, 0.045),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, parent)

	stroke(module, 0.51, 0.9)
	aspectFromWidth(module, SettingsSizing.BindAspect)
	buildSettingsLabel(module, "Keybind", 0.6608, false)

	local button = new("TextButton", {
		Text = "",
		Name = "BindButton",
		TextSize = 14,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.8389, 0.18),
		Size = UDim2.fromScale(0.1437, 0.6522),
		FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(28, 37, 45),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = 10002,
	}, module)

	stroke(button, 0.51, 0.9)
	aspectFromHeight(button, 2.2)

	local keyLabel = new("TextLabel", {
		Text = "Bind...",
		Name = "BindedKey",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10003,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		Size = UDim2.fromScale(0.7762, -0.6183),
		Position = UDim2.fromScale(0.1, 0.7839),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, button)

	Runtime.Refs.FullbrightBindButton = button
	Runtime.Refs.FullbrightBindedKey = keyLabel
	return module
end

local function buildSliderModule(parent)
	local module = new("Frame", {
		Name = "ModuleExample3",
		LayoutOrder = 3,
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.919, 0.0846),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, parent)

	stroke(module, 0.51, 0.9)
	aspectFromWidth(module, SettingsSizing.SliderAspect)
	buildSettingsLabel(module, "Brightness", 0.6605, true)

	local slider = new("Frame", {
		Name = "SliderBackground",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.9298, 0.0626),
		Position = UDim2.fromScale(0.041, 0.7219),
		BackgroundColor3 = Color3.fromRGB(28, 37, 45),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		Active = true,
	}, module)

	stroke(slider, 0.51, 0.9)
	corner(slider, UDim.new(1, 0))
	aspectFromWidth(slider, SettingsSizing.SliderBarAspect)

	local moving = new("TextButton", {
		Text = "",
		Name = "Moving",
		TextSize = 14,
		ZIndex = 10003,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.0679, 4.9096),
		FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(170, 57, 57),
	}, slider)

	stroke(moving, 0.51, 0.9)
	corner(moving, UDim.new(1, 0))
	aspect(moving)

	local inputBack = new("Frame", {
		Name = "InputBackground",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.1439, 0.6814),
		Position = UDim2.fromScale(0.8389, 0.0799),
		BackgroundColor3 = Color3.fromRGB(28, 37, 45),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
	}, module)

	stroke(inputBack, 0.51, 0.9)
	aspect(inputBack, 2.0999)

	local input = new("TextBox", {
		PlaceholderText = "100",
		Name = "InputTextBox",
		Text = "",
		ClearTextOnFocus = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10003,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		Size = UDim2.fromScale(0.9582, -0.558),
		Position = UDim2.fromScale(0.1, 0.75),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		PlaceholderColor3 = Color3.fromRGB(157, 157, 157),
		TextColor3 = Color3.fromRGB(235, 235, 235),
	}, inputBack)

	Runtime.Refs.FullbrightSliderBackground = slider
	Runtime.Refs.FullbrightSliderMoving = moving
	Runtime.Refs.FullbrightInputTextBox = input
	return module
end


local function buildDropdownModule(parent, order)
	local module = new("Frame", {
		Name = "ModuleExample2",
		LayoutOrder = order,
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.919, 0.085),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = 10020,
	}, parent)

	stroke(module, 0.51, 0.9)
	aspectFromWidth(module, 5.1999)
	buildSettingsLabel(module, "Override Features", 0.6605, true)

	local button = new("TextButton", {
		Text = "",
		Name = "DropdownButton",
		TextSize = 14,
		BackgroundTransparency = 0.97,
		ZIndex = 10022,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.0169, 0.5465),
		Size = UDim2.fromScale(0.9612, 0.3716),
		FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	}, module)

	stroke(button, 0.51, 0.9)
	aspectFromWidth(button, 13.5)

	local state = new("ImageLabel", {
		Image = "rbxassetid://138153991601855",
		Name = "State",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Rotation = 0,
		Size = UDim2.fromScale(0.0571, 0.8692),
		Position = UDim2.fromScale(0.9239, 0.109),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = 10024,
	}, button)
	aspect(state)

	local label = new("TextLabel", {
		Text = "Pick override options.",
		Name = "ChoosenOption",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10023,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0.9033, -0.6183),
		Position = UDim2.fromScale(0.0206, 0.784),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, button)

	Runtime.Refs.FullbrightOverrideDropdownModule = module
	Runtime.Refs.FullbrightOverrideDropdownButton = button
	Runtime.Refs.FullbrightOverrideDropdownState = state
	Runtime.Refs.FullbrightOverrideDropdownLabel = label
	Runtime.Refs.FullbrightOverrideRows = {}

	return module
end

local function buildDropdownOptionRow(parent, option, order)
	local row = new("Frame", {
		Name = "ModuleExample1",
		LayoutOrder = order,
		Visible = false,
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = 10030,
		Active = true,
	}, parent)

	stroke(row, 0.51, 0.9)
	aspectFromWidth(row, SettingsSizing.DropdownOptionAspect or SettingsSizing.ToggleAspect)
	corner(row, UDim.new(0, 2))

	local title = new("TextLabel", {
		Text = option.Text,
		Name = "Title",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10031,
		TextSize = 14,
		TextWrapped = true,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0.91, -0.5694),
		Position = UDim2.fromScale(0.0367, 0.7473),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, row)

	local click = new("TextButton", {
		Text = "",
		Name = "ClickButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 10032,
	}, row)

	Runtime.Refs.FullbrightOverrideRows[option.Key] = {
		Frame = row,
		Title = title,
		Button = click,
		Option = option,
	}

	return row
end

local function buildFullbrightOverrideDropdown(parent, order)
	buildDropdownModule(parent, order)

	for index, option in ipairs(FULLBRIGHT_OVERRIDE_OPTIONS) do
		buildDropdownOptionRow(parent, option, order + index)
	end
end


local function buildSettingsBuilder(parent)
	local builder = new("Frame", {
		Name = "SettingsBuilder",
		BorderSizePixel = 0,
		ZIndex = 10000,
		Visible = false,
		Size = UDim2.fromScale(0.9993, 0.9974),
		Position = UDim2.fromScale(0, 1),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ClipsDescendants = true,
	}, parent)

	corner(builder, UDim.new(0, 5))
	mainGradient(builder)

	local scroll = new("ScrollingFrame", {
		Name = "ScrollingFrame",
		BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		ScrollBarThickness = 4,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarImageTransparency = 0,
		Active = true,
		Size = UDim2.fromScale(0.981, 0.91),
		Position = UDim2.fromScale(0, 0.09),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ScrollBarImageColor3 = Color3.fromRGB(193, 54, 54),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 10001,
	}, builder)

	safeScrollImages(scroll)

	new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, scroll)

	new("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
	}, scroll)

	buildToggleModule(scroll, "Enabled", 1, "FullbrightEnabled")
	buildBindModule(scroll)
	buildSliderModule(scroll)
	buildToggleModule(scroll, "Force Day Time", 4, "FullbrightDay")
	buildFullbrightOverrideDropdown(scroll, 5)
	configureTightScrollingFrame(scroll)

	local backButton = new("ImageButton", {
		Image = "rbxassetid://91613428185416",
		Name = "BackButton",
		ZIndex = 10002,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.0645, 0.0589),
		Position = UDim2.fromScale(0.94725, 0.04345),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	}, builder)
	aspect(backButton)

	local title = new("TextLabel", {
		Text = 'Fullbright <font color="rgb(203, 57, 57)">Settings</font>',
		Name = "Title",
		TextSize = 14,
		BackgroundTransparency = 1,
		ZIndex = 10002,
		BorderSizePixel = 0,
		TextScaled = false,
		TextWrapped = false,
		RichText = true,
		Size = UDim2.fromScale(0.64, 0.058),
		Position = UDim2.fromScale(0.04, 0.014),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextYAlignment = Enum.TextYAlignment.Center,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(255, 255, 255),
	}, builder)

	Runtime.Refs.SettingsBuilder = builder
	Runtime.Refs.SettingsScroll = scroll
	Runtime.Refs.SettingsBackButton = backButton
	Runtime.Refs.SettingsTitle = title
	return builder
end

local function buildMain(parent)
	local main = new("ImageLabel", {
		Name = "Main",
		Image = "rbxassetid://95827797495948",
		ZIndex = 0,
		BackgroundTransparency = 1,
		ImageTransparency = 0.9,
		AnchorPoint = Vector2.one * 0.5,
		Position = UDim2.fromScale(0.912, 0.8759),
		Size = UDim2.fromScale(0.1504, 0.2474),
		SliceCenter = Rect.new(85, 85, 427, 427),
		ScaleType = Enum.ScaleType.Slice,
		BorderColor3 = Color3.fromRGB(27, 42, 53),
		ClipsDescendants = false,
	}, parent)

	new("UISizeConstraint", {
		MinSize = Vector2.new(255, 285),
		MaxSize = Vector2.new(300, 335),
	}, main)

	local container = new("Frame", {
		Name = "MainContainer",
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.9274, 0.9684),
		Position = UDim2.fromScale(0.0349, 0.0325),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ClipsDescendants = false,
	}, main)

	local frame = new("Frame", {
		Name = "MainFrame",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.9955, 0.9974),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		ClipsDescendants = false,
	}, container)

	corner(frame, UDim.new(0, 5))
	mainGradient(frame)
	buildCommandScroll(frame)
	buildInput(container)

	new("TextLabel", {
		Text = "VERSION: 1.0.0",
		Name = "Version",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		TextSize = 13,
		TextWrapped = false,
		TextScaled = false,
		Size = UDim2.fromScale(0.3174, 0.045),
		Position = UDim2.fromScale(0.507, 0.027),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(217, 217, 217),
	}, container)

	new("TextLabel", {
		Text = 'CFrame <font color="rgb(203, 57, 57)">Zero</font>',
		Name = "Title",
		TextSize = 14,
		BackgroundTransparency = 1,
		ZIndex = 2,
		BorderSizePixel = 0,
		TextScaled = false,
		TextWrapped = false,
		RichText = true,
		Size = UDim2.fromScale(0.464, 0.0542),
		Position = UDim2.fromScale(0.0429, 0.0179),
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold),
		TextYAlignment = Enum.TextYAlignment.Center,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderColor3 = Color3.fromRGB(0, 0, 0),
		TextColor3 = Color3.fromRGB(255, 255, 255),
	}, container)

	buildSettingsBuilder(container)
	buildHint(parent)
	corner(container, UDim.new(0, 5))
	stroke(container, 1.5, 0.9)
	aspect(container, 0.97)
	aspect(main, 0.97)

	return main
end

local backgroundDim = buildBackgroundDim(mainUi)
buildOnBoarding(backgroundDim)
buildMain(mainUi)
mainUi.Parent = getGuiParent()

local function firstGradient(instance)
	if not instance then
		return nil
	end

	return instance:FindFirstChildWhichIsA("UIGradient")
end

local function setTextVisible(label, visible)
	if label and label:IsA("TextLabel") then
		label.Visible = true
		label.TextTransparency = visible and 0 or 1
	end
end

local function setImageVisible(image, visible)
	if image and image:IsA("ImageLabel") then
		image.Visible = true
		image.ImageTransparency = visible and 0 or 1
	end
end

local function fadeText(label, duration, target)
	if not label then
		return
	end

	label.Visible = true
	playTween(label, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = target,
	})
end

local function fadeImage(image, duration, target)
	if not image then
		return
	end

	image.Visible = true
	playTween(image, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = target,
	})
end

local function fadeFrame(frame, duration, target)
	if not frame then
		return
	end

	frame.Visible = true
	playTween(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = target,
	})
end

local function cacheRefs()
	local refs = Runtime.Refs

	refs.BackgroundDim = mainUi:FindFirstChild("BackgroundDim")
	refs.OnBoarding = refs.BackgroundDim and refs.BackgroundDim:FindFirstChild("OnBoarding") or mainUi:FindFirstChild("OnBoarding")
	refs.Main = mainUi:FindFirstChild("Main")
	refs.BoardContainer = path(refs.OnBoarding, "Container")
	refs.BoardMainFrame = path(refs.OnBoarding, "Container", "MainFrame")
	refs.BoardGradient = firstGradient(refs.BoardMainFrame)
	refs.BoardDivider = path(refs.OnBoarding, "Container", "MainFrame", "Divider")
	refs.BoardLoading = path(refs.OnBoarding, "Container", "Loading")
	refs.LoadingBar = path(refs.OnBoarding, "Container", "Loading", "LoadingBarBackground", "LoadingBar")
	refs.Avatar = path(refs.OnBoarding, "Container", "Avatar")
	refs.LoadingCircle = path(refs.OnBoarding, "Container", "LoadingCircle")
	refs.Creator = path(refs.OnBoarding, "Container", "Creator")
	refs.LoadingStatus = path(refs.OnBoarding, "Container", "LoadingStatus")
	refs.BoardTitle = path(refs.OnBoarding, "Container", "Title")
	refs.BoardVersion = path(refs.OnBoarding, "Container", "Version")
	refs.MainContainer = path(refs.Main, "MainContainer")
	refs.MainFrame = path(refs.Main, "MainContainer", "MainFrame")
	refs.CommandScroll = path(refs.Main, "MainContainer", "MainFrame", "ScrollingFrame")
	refs.CommandInput = path(refs.Main, "MainContainer", "CommandInputFrame", "CommandInput")
	refs.HintFrame = mainUi:FindFirstChild("HintFrame")
	refs.HintTitle = path(refs.HintFrame, "Title")
	refs.HintDescription = path(refs.HintFrame, "Description")
	refs.HintBottom = path(refs.HintFrame, "Bottom")
	refs.HintTitle2 = path(refs.HintFrame, "Title2")

	refs.SettingsBuilder = path(refs.Main, "MainContainer", "SettingsBuilder")
	refs.SettingsScroll = path(refs.SettingsBuilder, "ScrollingFrame")
	refs.SettingsBackButton = path(refs.SettingsBuilder, "BackButton")
	refs.SettingsTitle = path(refs.SettingsBuilder, "Title")
	refs.FullbrightEnabledMoving = path(refs.SettingsScroll, "ModuleExample1", "ToggleButton", "Moving")
	refs.FullbrightEnabledToggleButton = path(refs.SettingsScroll, "ModuleExample1", "ToggleButton")
	refs.FullbrightBindButton = path(refs.SettingsScroll, "ModuleExample5", "BindButton")
	refs.FullbrightBindedKey = path(refs.SettingsScroll, "ModuleExample5", "BindButton", "BindedKey")
	refs.FullbrightSliderBackground = path(refs.SettingsScroll, "ModuleExample3", "SliderBackground")
	refs.FullbrightSliderMoving = path(refs.SettingsScroll, "ModuleExample3", "SliderBackground", "Moving")
	refs.FullbrightInputTextBox = path(refs.SettingsScroll, "ModuleExample3", "InputBackground", "InputTextBox")

	if refs.SettingsScroll then
		local toggleModules = {}
		for _, child in ipairs(refs.SettingsScroll:GetChildren()) do
			if child.Name == "ModuleExample1" then
				toggleModules[#toggleModules + 1] = child
			end
		end

		table.sort(toggleModules, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)

		local dayModule = toggleModules[2]
		if dayModule then
			refs.FullbrightDayToggleButton = path(dayModule, "ToggleButton")
			refs.FullbrightDayMoving = path(dayModule, "ToggleButton", "Moving")
		end
	end
end

local function fixCriticalLayout()
	local refs = Runtime.Refs

	if refs.Main then
		refs.Main.Visible = false
		refs.Main.Position = UDim2.new(0.912, 0, 1.055, 0)
		refs.Main.ClipsDescendants = false
	end

	if refs.MainContainer then
		refs.MainContainer.ClipsDescendants = false
	end

	if refs.CommandScroll then
		refs.CommandScroll.ScrollingDirection = Enum.ScrollingDirection.Y
		configureTightScrollingFrame(refs.CommandScroll)
		updateScrollableCanvas(refs.CommandScroll)
	end

	if refs.SettingsScroll then
		refs.SettingsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
		configureTightScrollingFrame(refs.SettingsScroll)
		updateScrollableCanvas(refs.SettingsScroll)
	end

	if refs.CommandInput then
		refs.CommandInput.Text = ""
		refs.CommandInput.ClearTextOnFocus = false
	end

	if refs.HintFrame then
		refs.HintFrame.Visible = false
		refs.HintFrame.AnchorPoint = HintFollow.AnchorPoint
		refs.HintFrame.Position = UDim2.fromOffset(0, 0)
		refs.HintFrame.ClipsDescendants = false
		refs.HintFrame.ZIndex = 200
	end

	if refs.LoadingBar then
		refs.LoadingBar.Size = UDim2.fromScale(0, 1)
	end

	if refs.SettingsBuilder then
		refs.SettingsBuilder.Visible = false
		refs.SettingsBuilder.Position = UDim2.fromScale(0, 1)
	end
end

local FULLBRIGHT_LIGHTING_PROPERTIES = {
	"Ambient",
	"Brightness",
	"ClockTime",
	"ColorShift_Bottom",
	"ColorShift_Top",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"ExposureCompensation",
	"FogColor",
	"FogEnd",
	"FogStart",
	"GlobalShadows",
	"OutdoorAmbient",
	"ShadowSoftness",
}

local FULLBRIGHT_LIGHTING_GROUPS = {
	Ambient = { "Ambient" },
	OutdoorAmbient = { "OutdoorAmbient" },
	Brightness = { "Brightness" },
	ExposureCompensation = { "ExposureCompensation" },
	Fog = { "FogColor", "FogStart", "FogEnd" },
	Shadows = { "GlobalShadows", "ShadowSoftness" },
	ColorShifts = { "ColorShift_Bottom", "ColorShift_Top" },
	Environment = { "EnvironmentDiffuseScale", "EnvironmentSpecularScale" },
}

local function getInstanceProperty(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)

	if ok then
		return value, true
	end

	return nil, false
end

local function saveLighting()
	if Runtime.OriginalLighting then
		return
	end

	local data = {}
	for _, propertyName in ipairs(FULLBRIGHT_LIGHTING_PROPERTIES) do
		local value, ok = getInstanceProperty(Lighting, propertyName)
		if ok then
			data[propertyName] = value
		end
	end

	Runtime.OriginalLighting = data
	Runtime.FullbrightObjectStates = Runtime.FullbrightObjectStates or {}
end

local function rememberObjectState(object, properties)
	Runtime.FullbrightObjectStates = Runtime.FullbrightObjectStates or {}
	if Runtime.FullbrightObjectStates[object] then
		return
	end

	local state = {}
	for _, propertyName in ipairs(properties) do
		local value, ok = getInstanceProperty(object, propertyName)
		if ok then
			state[propertyName] = value
		end
	end

	Runtime.FullbrightObjectStates[object] = state
end


local POST_EFFECT_CLASSES = {
	BloomEffect = true,
	BlurEffect = true,
	ColorCorrectionEffect = true,
	DepthOfFieldEffect = true,
	SunRaysEffect = true,
}

local function isPostEffect(object)
	local ok, result = pcall(function()
		return object:IsA("PostEffect")
	end)

	if ok and result then
		return true
	end

	return POST_EFFECT_CLASSES[object.ClassName] == true
end

local function isAtmosphere(object)
	local ok, result = pcall(function()
		return object:IsA("Atmosphere")
	end)

	return ok and result
end

local function restoreLightingProperties(properties)
	local data = Runtime.OriginalLighting
	if not data then
		return
	end

	for _, propertyName in ipairs(properties or {}) do
		local savedValue = data[propertyName]
		if savedValue ~= nil then
			setInstanceProperty(Lighting, propertyName, savedValue)
		end
	end
end

local function restoreFullbrightObjectsWhere(predicate)
	for object, state in pairs(Runtime.FullbrightObjectStates or {}) do
		if typeof(object) == "Instance" and object.Parent and type(state) == "table" and predicate(object) then
			for propertyName, value in pairs(state) do
				setInstanceProperty(object, propertyName, value)
			end

			Runtime.FullbrightObjectStates[object] = nil
		end
	end
end

local function restoreFullbrightOverrideGroup(optionKey)
	if optionKey == "PostEffects" then
		restoreFullbrightObjectsWhere(isPostEffect)
		return
	end

	if optionKey == "Atmosphere" then
		restoreFullbrightObjectsWhere(isAtmosphere)
		return
	end

	restoreLightingProperties(FULLBRIGHT_LIGHTING_GROUPS[optionKey])
end

local function overrideFullbrightObjects(overrides)
	overrides = overrides or getFullbrightOverrideOptions()

	for _, object in ipairs(Lighting:GetDescendants()) do
		if isPostEffect(object) and overrides.PostEffects ~= false then
			rememberObjectState(object, { "Enabled" })
			setInstanceProperty(object, "Enabled", false)
		elseif isAtmosphere(object) and overrides.Atmosphere ~= false then
			rememberObjectState(object, { "Density", "Offset", "Color", "Decay", "Glare", "Haze" })
			setInstanceProperty(object, "Density", 0)
			setInstanceProperty(object, "Offset", 0)
			setInstanceProperty(object, "Glare", 0)
			setInstanceProperty(object, "Haze", 0)
			setInstanceProperty(object, "Color", Color3.fromRGB(255, 255, 255))
			setInstanceProperty(object, "Decay", Color3.fromRGB(255, 255, 255))
		end
	end
end

local function getFullbrightAmount()
	return clampNumber(getFullbrightSettings().Brightness, 0, 100)
end

local function applyFullbrightLighting()
	local settings = getFullbrightSettings()
	local overrides = getFullbrightOverrideOptions()
	local amount = getFullbrightAmount()
	local alpha = amount / 100
	local lightValue = math.clamp(math.floor(50 + (205 * alpha)), 0, 255)
	local fullbrightColor = Color3.fromRGB(lightValue, lightValue, lightValue)

	saveLighting()
	Runtime.FullbrightEnabled = true

	if overrides.Ambient ~= false then
		setInstanceProperty(Lighting, "Ambient", fullbrightColor)
	end

	if overrides.OutdoorAmbient ~= false then
		setInstanceProperty(Lighting, "OutdoorAmbient", fullbrightColor)
	end

	if overrides.Brightness ~= false then
		setInstanceProperty(Lighting, "Brightness", 1 + (alpha * 8))
	end

	if settings.ForceDay then
		setInstanceProperty(Lighting, "ClockTime", 15)
	elseif Runtime.OriginalLighting and Runtime.OriginalLighting.ClockTime then
		setInstanceProperty(Lighting, "ClockTime", Runtime.OriginalLighting.ClockTime)
	end

	if overrides.ColorShifts ~= false then
		setInstanceProperty(Lighting, "ColorShift_Bottom", Color3.fromRGB(0, 0, 0))
		setInstanceProperty(Lighting, "ColorShift_Top", Color3.fromRGB(0, 0, 0))
	end

	if overrides.Environment ~= false then
		setInstanceProperty(Lighting, "EnvironmentDiffuseScale", 1)
		setInstanceProperty(Lighting, "EnvironmentSpecularScale", 0)
	end

	if overrides.ExposureCompensation ~= false then
		setInstanceProperty(Lighting, "ExposureCompensation", alpha * 2)
	end

	if overrides.Fog ~= false then
		setInstanceProperty(Lighting, "FogColor", Color3.fromRGB(255, 255, 255))
		setInstanceProperty(Lighting, "FogStart", 0)
		setInstanceProperty(Lighting, "FogEnd", 1000000)
	end

	if overrides.Shadows ~= false then
		setInstanceProperty(Lighting, "GlobalShadows", false)
		setInstanceProperty(Lighting, "ShadowSoftness", 0)
	end

	overrideFullbrightObjects(overrides)
end

applyFullbrightState = function()
	if getFullbrightSettings().Enabled then
		applyFullbrightLighting()
	else
		restoreLighting()
	end
end

local function setFullbrightEnabled(enabled)
	getFullbrightSettings().Enabled = enabled == true
	commitSettings(true)
end

local function setFullbrightBrightness(value)
	getFullbrightSettings().Brightness = clampNumber(value, 0, 100)
	commitSettings(true)
end

local function setFullbrightForceDay(enabled)
	getFullbrightSettings().ForceDay = enabled == true
	commitSettings(true)
end

local function setFullbrightBind(keyName)
	getFullbrightSettings().BindKey = type(keyName) == "string" and keyName or ""
	commitSettings(false)
end

local function setFullbrightOverrideOption(optionKey, enabled)
	local options = getFullbrightOverrideOptions()
	if type(options[optionKey]) ~= "boolean" then
		return
	end

	options[optionKey] = enabled == true

	if not options[optionKey] and getFullbrightSettings().Enabled then
		restoreFullbrightOverrideGroup(optionKey)
	end

	commitSettings(true)
end

local function toggleFullbrightOverrideOption(optionKey)
	local options = getFullbrightOverrideOptions()
	if type(options[optionKey]) ~= "boolean" then
		return
	end

	setFullbrightOverrideOption(optionKey, not options[optionKey])
end

local function toggleFullbright()
	setFullbrightEnabled(not getFullbrightSettings().Enabled)
end

local function enableFullbright()
	setFullbrightEnabled(true)
end

local function disableFullbright()
	setFullbrightEnabled(false)
end

local function setClientShadows(enabled)
	setInstanceProperty(Lighting, "GlobalShadows", enabled == true)

	if enabled then
		setInstanceProperty(Lighting, "ShadowSoftness", Runtime.DefaultShadowSoftness or 0.2)
	else
		setInstanceProperty(Lighting, "ShadowSoftness", 0)
	end
end

local function disableShadows()
	setClientShadows(false)
end

local function enableShadows()
	setClientShadows(true)
end

local function extractCommandArgs(text)
	local raw = tostring(text or "")
	raw = raw:gsub("^%s+", "")
	raw = raw:gsub("%s+$", "")
	local command, args = raw:match("^(%S+)%s*(.*)$")
	return string.lower(command or ""), args or ""
end

local function setClientTimeFromCommand(text)
	local _, args = extractCommandArgs(text)
	local value = tonumber(args:match("%-?%d+%.?%d*"))
	if not value then
		return
	end

	setInstanceProperty(Lighting, "ClockTime", math.clamp(value, 0, 24))
end

local function resetClientTime()
	setInstanceProperty(Lighting, "ClockTime", Runtime.DefaultClockTime or 12)
end

local function sitOnce()
	local character = LocalPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.Sit = true
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Seated)
	end)
end

local function registerCommands()
	Runtime.Commands = {
		fullbright = enableFullbright,
		fb = enableFullbright,
		unfullbright = disableFullbright,
		unfb = disableFullbright,
		disableshadows = disableShadows,
		enableshadows = enableShadows,
		time = setClientTimeFromCommand,
		resettime = resetClientTime,
		sit = sitOnce,
	}
end

local function normalizeCommand(text)
	local raw = string.lower(text or "")
	raw = raw:gsub("^%s+", "")
	raw = raw:gsub("%s+$", "")
	return raw:match("^(%S+)") or ""
end

local function runCommand(text)
	local command = normalizeCommand(text)
	local handler = Runtime.Commands[command]

	if handler then
		handler(text)
	end

	return handler ~= nil
end

local function rowMatches(row, query)
	if query == "" then
		return true
	end

	return string.find(string.lower(row.Search), query, 1, true) ~= nil
end

local function filterCommands(text)
	local query = normalizeCommand(text)
	local visibleByCategory = {}

	for _, row in ipairs(Runtime.CommandRows) do
		local isVisible = rowMatches(row, query)
		if row.Frame then
			row.Frame.Visible = isVisible
		end

		if isVisible then
			local categoryName = row.Category or "Commands"
			visibleByCategory[categoryName] = (visibleByCategory[categoryName] or 0) + 1
		end
	end

	for _, category in ipairs(Runtime.CategoryRows) do
		if category.Frame then
			category.MatchCount = visibleByCategory[category.Category] or 0
			category.Frame.Visible = category.MatchCount > 0
		end
	end

	if Runtime.Refs.CommandScroll then
		updateScrollableCanvas(Runtime.Refs.CommandScroll)
	end
end

local function setToggleVisual(moving, enabled, instant)
	if not moving then
		return
	end

	local props = enabled and {
		Position = UDim2.fromScale(0.562, 0),
		BackgroundColor3 = Color3.fromRGB(93, 170, 79),
	} or {
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.fromRGB(170, 57, 57),
	}

	if instant then
		for key, value in pairs(props) do
			moving[key] = value
		end
		return
	end

	playTween(moving, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
end

local function getSliderTravelScale(slider, moving)
	if not slider or not moving or slider.AbsoluteSize.X <= 0 then
		return 1
	end

	local thumbScale = moving.AbsoluteSize.X / slider.AbsoluteSize.X
	return 1 - math.clamp(thumbScale, 0, 0.9)
end

local function setSliderVisual(value)
	local refs = Runtime.Refs
	local moving = refs.FullbrightSliderMoving
	local slider = refs.FullbrightSliderBackground

	if moving then
		local alpha = math.clamp(value / 100, 0, 1)
		moving.Position = UDim2.fromScale(alpha * getSliderTravelScale(slider, moving), 0.5)
	end
end

local function setDropdownOptionVisual(rowData, selected, open)
	if not rowData or not rowData.Frame then
		return
	end

	rowData.Frame.Visible = open == true
	rowData.Frame.Size = open and UDim2.fromScale(0.919, 0.045) or UDim2.fromScale(0, 0)
	rowData.Frame.BackgroundTransparency = selected and 0.9 or 0.97
end

local function updateFullbrightDropdownUi(instant)
	local refs = Runtime.Refs
	local open = Runtime.FullbrightDropdownOpen == true
	local options = getFullbrightOverrideOptions()
	local enabledCount = 0

	for _, option in ipairs(FULLBRIGHT_OVERRIDE_OPTIONS) do
		local selected = options[option.Key] ~= false
		if selected then
			enabledCount += 1
		end

		setDropdownOptionVisual(refs.FullbrightOverrideRows and refs.FullbrightOverrideRows[option.Key], selected, open)
	end

	if refs.FullbrightOverrideDropdownLabel then
		refs.FullbrightOverrideDropdownLabel.Text = string.format("Overrides: %d/%d enabled", enabledCount, #FULLBRIGHT_OVERRIDE_OPTIONS)
	end

	if refs.FullbrightOverrideDropdownState then
		local props = {
			Rotation = open and 180 or 0,
		}

		if instant then
			refs.FullbrightOverrideDropdownState.Rotation = props.Rotation
		else
			playTween(refs.FullbrightOverrideDropdownState, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		end
	end

	updateScrollableCanvas(refs.SettingsScroll)
end

refreshFullbrightSettingsUi = function(instant)
	local refs = Runtime.Refs
	local settings = getFullbrightSettings()

	setToggleVisual(refs.FullbrightEnabledMoving, settings.Enabled, instant)
	setToggleVisual(refs.FullbrightDayMoving, settings.ForceDay, instant)
	setSliderVisual(settings.Brightness)
	updateFullbrightDropdownUi(instant)

	if refs.FullbrightBindedKey then
		refs.FullbrightBindedKey.Text = Runtime.CapturingBind and "...." or (settings.BindKey ~= "" and settings.BindKey or "Bind...")
	end

	if refs.FullbrightInputTextBox and not Runtime.FullbrightInputUpdating then
		Runtime.FullbrightInputUpdating = true
		refs.FullbrightInputTextBox.Text = tostring(settings.Brightness)
		Runtime.FullbrightInputUpdating = false
	end

	updateScrollableCanvas(refs.CommandScroll)
	updateScrollableCanvas(refs.SettingsScroll)
end

local function openSettingsPage(pageName)
	if pageName ~= "fullbright" then
		return
	end

	local refs = Runtime.Refs
	if not refs.SettingsBuilder then
		return
	end

	Runtime.HintVisible = false
	Runtime.HintTarget = nil
	if refs.HintFrame then
		refs.HintFrame.Visible = false
	end
	Runtime.SettingsOpen = true
	Runtime.CapturingBind = false
	refs.SettingsBuilder.Visible = true
	refs.SettingsBuilder.Position = UDim2.fromScale(0, 1)
	refreshFullbrightSettingsUi(true)

	playTween(refs.SettingsBuilder, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0, 0),
	})
end

local function closeSettingsPage()
	local refs = Runtime.Refs
	if not refs.SettingsBuilder then
		return
	end

	Runtime.SettingsOpen = false
	Runtime.CapturingBind = false
	Runtime.FullbrightDropdownOpen = false
	refreshFullbrightSettingsUi(false)

	playTween(refs.SettingsBuilder, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0, 1),
	})

	task.delay(0.13, function()
		if Runtime.Alive and refs.SettingsBuilder and not Runtime.SettingsOpen then
			refs.SettingsBuilder.Visible = false
		end
	end)
end

local function sliderValueFromMouse()
	local slider = Runtime.Refs.FullbrightSliderBackground
	local moving = Runtime.Refs.FullbrightSliderMoving

	if not slider or slider.AbsoluteSize.X <= 0 then
		return getFullbrightAmount()
	end

	local thumbWidth = moving and moving.AbsoluteSize.X or 0
	local travel = math.max(slider.AbsoluteSize.X - thumbWidth, 1)
	local mouseX = UserInputService:GetMouseLocation().X
	local alpha = math.clamp((mouseX - slider.AbsolutePosition.X - (thumbWidth * 0.5)) / travel, 0, 1)
	return clampNumber(alpha * 100, 0, 100)
end

local function updateSliderFromMouse()
	setFullbrightBrightness(sliderValueFromMouse())
end

local function scaleUDim2(size, amount)
	return UDim2.new(
		size.X.Scale * amount,
		math.floor((size.X.Offset * amount) + 0.5),
		size.Y.Scale * amount,
		math.floor((size.Y.Offset * amount) + 0.5)
	)
end

local function tweenButtonSize(button, targetSize, duration)
	playTween(button, TweenInfo.new(duration or 0.055, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = targetSize,
	})
end

local function centerAnchorGui(button)
	if not button then
		return
	end

	local oldAnchor = button.AnchorPoint
	if oldAnchor == Vector2.new(0.5, 0.5) then
		return
	end

	local position = button.Position
	local size = button.Size
	local dx = 0.5 - oldAnchor.X
	local dy = 0.5 - oldAnchor.Y

	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(
		position.X.Scale + (size.X.Scale * dx),
		position.X.Offset + math.floor((size.X.Offset * dx) + 0.5),
		position.Y.Scale + (size.Y.Scale * dy),
		position.Y.Offset + math.floor((size.Y.Offset * dy) + 0.5)
	)
end

local function setupScaleClickEffect(button)
	if not button then
		return
	end

	centerAnchorGui(button)

	local normalSize = button.Size
	local hoverSize = scaleUDim2(normalSize, SettingsSizing.ButtonHoverScale)
	local pressSize = scaleUDim2(normalSize, SettingsSizing.ButtonPressScale)
	local hovering = false

	connect(button.MouseEnter, function()
		hovering = true
		tweenButtonSize(button, hoverSize, 0.055)
	end)

	connect(button.MouseLeave, function()
		hovering = false
		tweenButtonSize(button, normalSize, 0.055)
	end)

	connect(button.MouseButton1Down, function()
		tweenButtonSize(button, pressSize, 0.045)
	end)

	connect(button.MouseButton1Up, function()
		tweenButtonSize(button, hovering and hoverSize or normalSize, 0.055)
	end)

	connect(button.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			tweenButtonSize(button, hovering and hoverSize or normalSize, 0.055)
		end
	end)
end

local function setupCommandEditors()
	for _, row in ipairs(Runtime.CommandRows) do
		if row.EditButton and row.Data then
			setupScaleClickEffect(row.EditButton)
			connect(row.EditButton.MouseButton1Click, function()
				openSettingsPage(row.Data.SettingsPage)
			end)
		end
	end
end

local function setupSettingsBackButton()
	local backButton = Runtime.Refs.SettingsBackButton
	if backButton then
		setupScaleClickEffect(backButton)
		connect(backButton.MouseButton1Click, closeSettingsPage)
	end
end

local function connectGuiButtonClick(button, callback)
	if not button or not callback then
		return
	end

	if button:IsA("GuiButton") then
		connect(button.Activated, callback)
	end
end

local function setupFullbrightToggles()
	local refs = Runtime.Refs
	local function toggleDay()
		setFullbrightForceDay(not getFullbrightSettings().ForceDay)
	end

	connectGuiButtonClick(refs.FullbrightEnabledToggleButton, toggleFullbright)
	connectGuiButtonClick(refs.FullbrightDayToggleButton, toggleDay)
end

local function setupFullbrightBindButton()
	local button = Runtime.Refs.FullbrightBindButton
	if button then
		connect(button.MouseButton1Click, function()
			Runtime.CapturingBind = true
			if Runtime.Refs.FullbrightBindedKey then
				Runtime.Refs.FullbrightBindedKey.Text = "...."
			end
		end)
	end
end

local function setupFullbrightSlider()
	local refs = Runtime.Refs
	local moving = refs.FullbrightSliderMoving
	local slider = refs.FullbrightSliderBackground

	if moving then
		connect(moving.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				Runtime.DraggingSlider = true
				updateSliderFromMouse()
			end
		end)
	end

	if slider then
		connect(slider.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				Runtime.DraggingSlider = true
				updateSliderFromMouse()
			end
		end)
	end

	connect(UserInputService.InputChanged, function(input)
		if not Runtime.DraggingSlider then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			updateSliderFromMouse()
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Runtime.DraggingSlider = false
		end
	end)
end

local function setupFullbrightInput()
	local input = Runtime.Refs.FullbrightInputTextBox
	if not input then
		return
	end

	connect(input:GetPropertyChangedSignal("Text"), function()
		if Runtime.FullbrightInputUpdating then
			return
		end

		local raw = input.Text or ""
		local cleaned = raw:gsub("%D", "")

		if cleaned ~= raw then
			Runtime.FullbrightInputUpdating = true
			input.Text = cleaned
			Runtime.FullbrightInputUpdating = false
		end

		if cleaned ~= "" then
			setFullbrightBrightness(clampNumber(cleaned, 0, 100))
		end
	end)

	connect(input.FocusLost, function()
		refreshFullbrightSettingsUi(true)
	end)
end


local function setupFullbrightOverrideDropdown()
	local refs = Runtime.Refs

	connectGuiButtonClick(refs.FullbrightOverrideDropdownButton, function()
		Runtime.FullbrightDropdownOpen = not Runtime.FullbrightDropdownOpen
		refreshFullbrightSettingsUi(false)
	end)

	for _, option in ipairs(FULLBRIGHT_OVERRIDE_OPTIONS) do
		local rowData = refs.FullbrightOverrideRows and refs.FullbrightOverrideRows[option.Key]
		if rowData and rowData.Button then
			connectGuiButtonClick(rowData.Button, function()
				toggleFullbrightOverrideOption(option.Key)
			end)
		end
	end
end

local function setupFullbrightGlobalKeys()
	connect(UserInputService.InputBegan, function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if Runtime.CapturingBind then
			if input.KeyCode == Enum.KeyCode.Escape then
				Runtime.CapturingBind = false
				refreshFullbrightSettingsUi(false)
				return
			end

			if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				Runtime.CapturingBind = false
				setFullbrightBind("")
				return
			end

			if input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode ~= Enum.KeyCode.Semicolon then
				Runtime.CapturingBind = false
				setFullbrightBind(input.KeyCode.Name)
				return
			end
		end

		if processed or UserInputService:GetFocusedTextBox() then
			return
		end

		local bindKey = keyFromName(getFullbrightSettings().BindKey)
		if bindKey and input.KeyCode == bindKey then
			toggleFullbright()
		end
	end)
end

local function setupFullbrightMaintainer()
	connect(RunService.RenderStepped, function()
		if not getFullbrightSettings().Enabled then
			return
		end

		applyFullbrightLighting()
	end)
end

local function setupSettingsBuilder()
	setupCommandEditors()
	setupSettingsBackButton()
	setupFullbrightToggles()
	setupFullbrightBindButton()
	setupFullbrightSlider()
	setupFullbrightInput()
	setupFullbrightOverrideDropdown()
	setupFullbrightMaintainer()
	setupFullbrightGlobalKeys()
	refreshFullbrightSettingsUi(true)
end

local function resetSettingsPageInstant()
	local refs = Runtime.Refs
	Runtime.SettingsOpen = false
	Runtime.CapturingBind = false
	Runtime.DraggingSlider = false
	Runtime.FullbrightDropdownOpen = false

	if refs.SettingsScroll then
		refs.SettingsScroll.CanvasPosition = Vector2.new(0, 0)
	end

	if refs.SettingsBuilder then
		refs.SettingsBuilder.Visible = false
		refs.SettingsBuilder.Position = UDim2.fromScale(0, 1)
	end
end

local function tweenMain(opened)
	local refs = Runtime.Refs
	if not refs.Main then
		return
	end

	if not opened then
		resetSettingsPageInstant()
	end

	local goal = opened and UDim2.new(0.912, 0, 0.889, 0) or UDim2.new(0.912, 0, 1.090, 0)
	local duration = opened and 0.16 or 0.28
	local style = opened and Enum.EasingStyle.Quint or Enum.EasingStyle.Quad

	refs.Main.Visible = true
	playTween(refs.Main, TweenInfo.new(duration, style, Enum.EasingDirection.Out), {
		Position = goal,
	})
end

local function requestCloseMain(delayTime)
	Runtime.CloseStamp += 1
	local stamp = Runtime.CloseStamp

	task.delay(delayTime or 0.5, function()
		if not Runtime.Alive or stamp ~= Runtime.CloseStamp then
			return
		end

		if Runtime.HoveringMain or Runtime.InputFocused then
			return
		end

		tweenMain(false)
	end)
end

local function stripBlockedInputChars(text)
	return (text or ""):gsub("[;；]", "")
end

local function openCommandInput()
	local refs = Runtime.Refs
	tweenMain(true)

	if refs.CommandInput then
		refs.CommandInput.Text = stripBlockedInputChars(refs.CommandInput.Text)
		refs.CommandInput:CaptureFocus()
		task.defer(function()
			if Runtime.Alive and refs.CommandInput then
				refs.CommandInput.Text = stripBlockedInputChars(refs.CommandInput.Text)
			end
		end)
	end
end

local function getMouseScreenPosition()
	local mouse = UserInputService:GetMouseLocation()
	local inset = Vector2.new(0, 0)

	pcall(function()
		local topLeftInset = GuiService:GetGuiInset()
		inset = topLeftInset
	end)

	return Vector2.new(mouse.X - inset.X, mouse.Y - inset.Y)
end

local function isMouseInsideGui(guiObject)
	if not guiObject then
		return false
	end

	local mouse = getMouseScreenPosition()
	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize

	return mouse.X >= pos.X
		and mouse.X <= pos.X + size.X
		and mouse.Y >= pos.Y
		and mouse.Y <= pos.Y + size.Y
end

local function updateHintContent(data)
	local refs = Runtime.Refs
	if not data then
		return
	end

	local undoText = data.Undo or ""
	local hasUndo = undoText ~= ""

	if refs.HintTitle then
		refs.HintTitle.Text = data.Display or ""
	end

	if refs.HintDescription then
		refs.HintDescription.Text = data.Description or ""
		refs.HintDescription.Size = hasUndo and UDim2.fromScale(0.91, 0.405) or UDim2.fromScale(0.91, 0.63)
	end

	if refs.HintBottom then
		refs.HintBottom.Visible = hasUndo
	end

	if refs.HintTitle2 then
		refs.HintTitle2.Text = undoText
		refs.HintTitle2.Visible = hasUndo
	end
end

local function getMouseHintPosition()
	local mouse = getMouseScreenPosition()
	local offset = HintFollow.Offset

	return UDim2.fromOffset(mouse.X + offset.X, mouse.Y + offset.Y)
end

local function updateHintPosition()
	local refs = Runtime.Refs
	if refs.HintFrame and refs.HintFrame.Visible then
		refs.HintFrame.Position = getMouseHintPosition()
	end
end

local function showHint(data)
	local refs = Runtime.Refs
	if not refs.HintFrame then
		return
	end

	Runtime.HintVisible = true
	Runtime.HintTarget = data

	updateHintContent(data)

	refs.HintFrame.AnchorPoint = HintFollow.AnchorPoint
	refs.HintFrame.Visible = true
	refs.HintFrame.BackgroundTransparency = 1
	updateHintPosition()

	fadeFrame(refs.HintFrame, 0.1, 0)
end

local function hideHint()
	local refs = Runtime.Refs
	Runtime.HintVisible = false
	Runtime.HintTarget = nil

	if refs.HintFrame then
		refs.HintFrame.Visible = false
	end
end

local function beginHintDelay(row)
	Runtime.HintHoverStamp += 1
	local stamp = Runtime.HintHoverStamp
	Runtime.HintHoverRow = row

	task.delay(HINT_HOVER_DELAY, function()
		if not Runtime.Alive or Runtime.HintHoverStamp ~= stamp then
			return
		end

		if Runtime.HintHoverRow ~= row or not row.Frame or not isMouseInsideGui(row.Frame) then
			return
		end

		if row.EditButton and isMouseInsideGui(row.EditButton) then
			return
		end

		showHint(row.Data)
	end)
end

local function cancelHintDelay()
	Runtime.HintHoverStamp += 1
	Runtime.HintHoverRow = nil
end

local function setupHint()
	for _, row in ipairs(Runtime.CommandRows) do
		if row.Frame then
			connect(row.Frame.MouseEnter, function()
				beginHintDelay(row)
			end)

			connect(row.Frame.MouseMoved, function()
				if row.EditButton and isMouseInsideGui(row.EditButton) then
					cancelHintDelay()
					hideHint()
					return
				end

				if Runtime.HintVisible and Runtime.HintTarget == row.Data then
					updateHintPosition()
				end
			end)

			connect(row.Frame.MouseLeave, function()
				cancelHintDelay()
				hideHint()
			end)

			if row.EditButton then
				connect(row.EditButton.MouseEnter, function()
					cancelHintDelay()
					hideHint()
				end)

				connect(row.EditButton.MouseLeave, function()
					if row.Frame and isMouseInsideGui(row.Frame) then
						beginHintDelay(row)
					end
				end)
			end
		end
	end

	connect(RunService.RenderStepped, function()
		if Runtime.HintVisible then
			updateHintPosition()
		end
	end)
end

local function setupMainHover()
	local refs = Runtime.Refs
	if not refs.Main then
		return
	end

	connect(refs.Main.MouseEnter, function()
		Runtime.HoveringMain = true
		tweenMain(true)
	end)

	connect(refs.Main.MouseLeave, function()
		Runtime.HoveringMain = false
		requestCloseMain(0.5)
	end)
end

local function setupCommandInput()
	local refs = Runtime.Refs
	if not refs.CommandInput then
		return
	end

	connect(refs.CommandInput.Focused, function()
		Runtime.InputFocused = true
		tweenMain(true)
	end)

	connect(refs.CommandInput.FocusLost, function(enterPressed)
		Runtime.InputFocused = false

		if enterPressed then
			refs.CommandInput.Text = stripBlockedInputChars(refs.CommandInput.Text)
			runCommand(refs.CommandInput.Text)
			refs.CommandInput.Text = ""
			filterCommands("")
		end

		requestCloseMain(0.5)
	end)

	connect(refs.CommandInput:GetPropertyChangedSignal("Text"), function()
		if Runtime.SanitizingInput then
			return
		end

		local current = refs.CommandInput.Text
		local cleaned = stripBlockedInputChars(current)

		if cleaned ~= current then
			Runtime.SanitizingInput = true
			refs.CommandInput.Text = cleaned
			pcall(function()
				refs.CommandInput.CursorPosition = math.min(refs.CommandInput.CursorPosition, #cleaned + 1)
			end)
			Runtime.SanitizingInput = false
		end

		filterCommands(cleaned)
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if input.KeyCode == Enum.KeyCode.Semicolon then
			if UserInputService:GetFocusedTextBox() == refs.CommandInput then
				task.defer(function()
					if Runtime.Alive and refs.CommandInput then
						refs.CommandInput.Text = stripBlockedInputChars(refs.CommandInput.Text)
					end
				end)
				return
			end

			if not processed then
				openCommandInput()
			end
			return
		end

		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
	end)
end

local function startLoadingSpinner()
	local refs = Runtime.Refs
	if not refs.LoadingCircle then
		return
	end

	connect(RunService.RenderStepped, function(deltaTime)
		if refs.LoadingCircle and refs.LoadingCircle.Visible then
			refs.LoadingCircle.Rotation = (refs.LoadingCircle.Rotation + deltaTime * 420) % 360
		end
	end)
end

local function prepOnBoardingHidden()
	local refs = Runtime.Refs

	if refs.BackgroundDim then
		refs.BackgroundDim.Visible = false
	end

	if refs.OnBoarding then
		refs.OnBoarding.Visible = false
	end

	if refs.BoardGradient then
		refs.BoardGradient.Rotation = -90
	end

	setTextVisible(refs.BoardTitle, false)
	setTextVisible(refs.BoardVersion, false)
	setTextVisible(refs.Creator, false)
	setTextVisible(refs.LoadingStatus, false)
	setImageVisible(refs.LoadingCircle, false)
	setImageVisible(refs.Avatar, false)

	if refs.BoardDivider then
		refs.BoardDivider.Visible = true
		refs.BoardDivider.BackgroundTransparency = 1
	end

	if refs.BoardLoading then
		refs.BoardLoading.Visible = false
	end

	if refs.LoadingBar then
		refs.LoadingBar.Size = UDim2.fromScale(0, 1)
	end
end

local function revealIntroItems()
	local refs = Runtime.Refs
	task.wait(0.08)

	fadeText(refs.BoardTitle, 0.12, 0)
	task.wait(0.06)

	fadeFrame(refs.BoardDivider, 0.1, 0)
	task.wait(0.05)

	fadeText(refs.BoardVersion, 0.11, 0)
	fadeText(refs.Creator, 0.11, 0)
	task.wait(0.06)

	fadeImage(refs.Avatar, 0.14, 0)
end

local function runLoadingSteps()
	local refs = Runtime.Refs
	local steps = {
		"Initializing CFrame Zero and preparing the lightweight client runtime",
		"Loading command models and validating the required player services",
		"Fetching command APIs and connecting safe runtime references",
		"Preparing animation handlers, hover states, and command input focus",
		"Checking command modules and removing unused settings panels",
		"Loading visual assets, gradients, strokes, and scaled UI constraints",
		"Building the commands-only interface with compact command rows",
		"Connecting input, search filtering, hints, and execution handlers",
		"Finalizing cleanup hooks and restoring cached lighting safeguards",
		"Launching CFrame Zero with the scaled command UI ready to use",
	}

	if refs.BoardLoading then
		refs.BoardLoading.Visible = true
	end

	fadeText(refs.LoadingStatus, 0.1, 0)
	fadeImage(refs.LoadingCircle, 0.1, 0)
	startLoadingSpinner()

	for index, text in ipairs(steps) do
		if not Runtime.Alive then
			return
		end

		if refs.LoadingStatus then
			refs.LoadingStatus.Text = text
		end

		if refs.LoadingBar then
			playTween(refs.LoadingBar, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(index / #steps, 1),
			})
		end

		task.wait(Random.new():NextNumber(0.5, 0.85))
	end

	if refs.LoadingStatus then
		refs.LoadingStatus.Text = "Script successfully loaded!"
	end

	task.wait(0.55)
end

local function closeOnBoarding()
	local refs = Runtime.Refs
	if not refs.OnBoarding then
		return
	end

	local original = UDim2.new(0.4999, 0, 0.5, 0)
	local down = UDim2.new(0.4999, 0, 0.565, 0)

	waitTween(playTween(refs.OnBoarding, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = down,
		Size = UDim2.fromScale(0.238, 0.211),
	}))

	refs.OnBoarding.Visible = false
	refs.OnBoarding.Position = original
	refs.OnBoarding.Size = UDim2.fromScale(0.259, 0.2292)

	if refs.BackgroundDim then
		refs.BackgroundDim.Visible = false
	end

	disableOnBoardingBlur()
end

local function playOnBoarding()
	local refs = Runtime.Refs
	if not refs.OnBoarding then
		return
	end

	local original = UDim2.new(0.4999, 0, 0.5, 0)
	local start = UDim2.new(0.4999, 0, 0.56, 0)

	prepOnBoardingHidden()
	enableOnBoardingBlur()

	if refs.BackgroundDim then
		refs.BackgroundDim.Visible = true
	end

	refs.OnBoarding.Position = start
	refs.OnBoarding.Size = UDim2.fromScale(0.238, 0.211)
	refs.OnBoarding.Visible = true

	playTween(refs.OnBoarding, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = original,
		Size = UDim2.fromScale(0.259, 0.2292),
	})

	if refs.BoardGradient then
		playTween(refs.BoardGradient, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Rotation = 15,
		})
	end

	revealIntroItems()
	task.wait(0.15)

	runLoadingSteps()
	closeOnBoarding()
end

local function showMainAfterOnBoarding()
	local refs = Runtime.Refs
	if not refs.Main then
		return
	end

	refs.Main.Visible = true
	refs.Main.Position = UDim2.new(0.912, 0, 0.892, 0)

	task.delay(1, function()
		if Runtime.Alive and not Runtime.HoveringMain and not Runtime.InputFocused then
			tweenMain(false)
		end
	end)
end

local function startRuntime()
	cacheRefs()
	fixCriticalLayout()
	registerCommands()
	setupHint()
	setupMainHover()
	setupCommandInput()
	setupSettingsBuilder()
	applyFullbrightState()

	addThread(task.spawn(function()
		playOnBoarding()
		showMainAfterOnBoarding()
	end))
end

startRuntime()
