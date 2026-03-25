notify("Zombie Attack", "Initialized", 3)

local RunService = {}

local t_insert  = table.insert
local t_remove  = table.remove
local t_sort    = table.sort
local m_min     = math.min
local m_max     = math.max
local str_fmt   = string.format
local sys_clock = os.clock
local sys_yield = coroutine.yield
local sys_run   = coroutine.running

local Render_Step_Priority_Bindings = {}
local Cache_Sorted_Binding_Registry = {}

local Thread_Execution_Active_State = true
local Performance_Last_Tick_Timestamp = sys_clock()
local Error_Tracking_Current_Count = 0

local Error_Handling_Max_Threshold_Limit = 100
local Bindings_Require_Resort = false

local function Signal()
    local SignalObject = { ActiveConnections = {} }

    function SignalObject:Connect(CallbackFunction)
        local ConnectionObject = { Function = CallbackFunction, Connected = true }
        t_insert(self.ActiveConnections, ConnectionObject)
        return {
            Disconnect = function()
                ConnectionObject.Connected = false
                ConnectionObject.Function = nil
            end
        }
    end

    function SignalObject:Fire(...)
        local conns = self.ActiveConnections
        local i = 1
        while i <= #conns do
            local conn = conns[i]
            if conn.Connected then
                local success = pcall(conn.Function, ...)
                    if Error_Tracking_Current_Count >= Error_Handling_Max_Threshold_Limit then
                        Thread_Execution_Active_State = false
                        return
                    end
                i = i + 1
            else
                t_remove(conns, i)
            end
        end
    end

    function SignalObject:Wait()
        local CurrentThread = sys_run()
        local WaitConnection
        WaitConnection = self:Connect(function(...)
            if WaitConnection then
                WaitConnection:Disconnect()
            end
            task.spawn(CurrentThread, ...)
        end)
        return sys_yield()
    end

    return SignalObject
end

RunService.Heartbeat    = Signal()
RunService.RenderStepped = Signal()
RunService.Stepped      = Signal()

function RunService:BindToRenderStep(BindName, BindPriority, BindFunction)
    if type(BindName) ~= "string" or type(BindFunction) ~= "function" then
        return
    end
    Render_Step_Priority_Bindings[BindName] = { Priority = BindPriority or 0, Function = BindFunction }
    Bindings_Require_Resort = true
end

function RunService:UnbindFromRenderStep(BindName)
    if Render_Step_Priority_Bindings[BindName] then
        Render_Step_Priority_Bindings[BindName] = nil
        Bindings_Require_Resort = true
    end
end

function RunService:IsRunning()
    return Thread_Execution_Active_State
end

local function CoreRenderFrame()
    local Timing_Current_Frame_Timestamp = sys_clock()
    local Timing_Delta_Frame_Interval = m_min(Timing_Current_Frame_Timestamp - Performance_Last_Tick_Timestamp, 1)
    Performance_Last_Tick_Timestamp = Timing_Current_Frame_Timestamp

    if Thread_Execution_Active_State then
        RunService.Stepped:Fire(Timing_Current_Frame_Timestamp, Timing_Delta_Frame_Interval)
    end

    if Thread_Execution_Active_State then
        if Bindings_Require_Resort then
            Cache_Sorted_Binding_Registry = {}
            for _, Bind_Data in pairs(Render_Step_Priority_Bindings) do
                if Bind_Data and type(Bind_Data.Function) == "function" then
                    t_insert(Cache_Sorted_Binding_Registry, Bind_Data)
                end
            end

            t_sort(Cache_Sorted_Binding_Registry, function(Bind_A, Bind_B)
                return Bind_A.Priority < Bind_B.Priority
            end)
            
            Bindings_Require_Resort = false
        end

        local registry = Cache_Sorted_Binding_Registry
        for i = 1, #registry do
            if not Thread_Execution_Active_State then break end
            local bind = registry[i]
            if bind and bind.Function then
                pcall(bind.Function, Timing_Delta_Frame_Interval)
            end
        end
    end

    if Thread_Execution_Active_State then
        RunService.RenderStepped:Fire(Timing_Delta_Frame_Interval)
    end

    if Thread_Execution_Active_State then
        RunService.Heartbeat:Fire(Timing_Delta_Frame_Interval)
    end
end

task.spawn(function()
    while Thread_Execution_Active_State do
        local success, err = pcall(CoreRenderFrame)

        if not success then
            Error_Tracking_Current_Count = Error_Tracking_Current_Count + 1
            if Error_Tracking_Current_Count >= Error_Handling_Max_Threshold_Limit then
                Thread_Execution_Active_State = false
                break
            end
        else
            Error_Tracking_Current_Count = m_max(0, Error_Tracking_Current_Count - 1)
        end

        if Thread_Execution_Active_State then
            task.wait() -- Back to default minimum wait for maximum smoothness
        end
    end
end)

local lp = game.Players.LocalPlayer
local workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local memory_read = memory_read or function() end 

local function IsWindowFocused()
    return isrbxactive()
end

local function ReadCFrame(instance)
    local result = nil
    pcall(function()
        local prim = memory_read("uintptr_t", instance.Address + 0x148)
        local cf_base = prim + 0xC0
        result = {
            X   = memory_read("float", cf_base + 36),
            Y   = memory_read("float", cf_base + 40),
            Z   = memory_read("float", cf_base + 44),
            r02 = memory_read("float", cf_base + 8),
            r12 = memory_read("float", cf_base + 20),
            r22 = memory_read("float", cf_base + 32),
        }
    end)
    return result
end

local Config = {
    Enabled = false,
    FullAuto = false,
    HitboxEnabled = false,
    MoveStyle = 0,
    DISTANCE = 9,
    HEIGHT = 14,
    SPEED = 6,
    HITBOX_SIZE = Vector3.new(5, 5, 5),
    DEFAULT_HEAD_SIZE = Vector3.new(2, 1, 1)
}

local MouseIsDown = false

    UI.AddTab("Zombie Attack", function(tab)
        local combat = tab:Section("Combat", "Left")
        combat:Toggle("enabled", "Auto Farm", Config.Enabled, function(v) Config.Enabled = v end)
        combat:Toggle("full_auto", "Full Auto", Config.FullAuto, function(v) Config.FullAuto = v end)
        combat:Toggle("hbe", "Hitbox Expander", Config.HitboxEnabled, function(v) Config.HitboxEnabled = v end)
        
        local move = tab:Section("Movement", "Right")
        move:Combo("move_style", "Style", {"Orbit", "Fixed"}, Config.MoveStyle, function(idx) Config.MoveStyle = idx end)
        move:SliderInt("dist", "Distance", 1, 50, Config.DISTANCE, function(v) Config.DISTANCE = v end)
        move:SliderInt("height", "Height", 1, 50, Config.HEIGHT, function(v) Config.HEIGHT = v end)
        
        if Config.MoveStyle == 0 then
            move:SliderInt("speed", "Orbit Speed", 1, 20, Config.SPEED, function(v) Config.SPEED = v end)
        end
        
        local info = tab:Section("Info", "Left")
        info:Text("Hi, I appreciate you!")
        info:Text("F1: Farm | F2: Auto | F3: Hitbox Expander | F4: Movement")
        info:Button("Reset Settings", function()
            UI.SetValue("enabled", false)
            UI.SetValue("full_auto", false)
            UI.SetValue("hbe", false)
            UI.SetValue("move_style", 0)
            UI.SetValue("dist", 9)
            UI.SetValue("height", 14)
            UI.SetValue("speed", 6)
        end)
    end)

local keyPressed = {
    [0x70] = false,
    [0x71] = false,
    [0x72] = false,
    [0x73] = false
}

task.spawn(function()
    while true do
        if iskeypressed(0x70) then 
            if not keyPressed[0x70] then
                keyPressed[0x70] = true
                Config.Enabled = not Config.Enabled
                if not Config.Enabled and MouseIsDown then 
                    mouse1release() 
                    MouseIsDown = false
                end
                UI.SetValue("enabled", Config.Enabled)
                notify("Auto Farm", Config.Enabled and "ON" or "OFF", 3)
            end
        else
            keyPressed[0x70] = false
        end

        if iskeypressed(0x71) then 
            if not keyPressed[0x71] then
                keyPressed[0x71] = true
                Config.FullAuto = not Config.FullAuto
                if not Config.FullAuto and MouseIsDown then 
                    mouse1release() 
                    MouseIsDown = false
                end
                UI.SetValue("full_auto", Config.FullAuto)
                notify("Fire Mode", Config.FullAuto and "Full Auto" or "Single", 3)
            end
        else
            keyPressed[0x71] = false
        end

        if iskeypressed(0x72) then 
            if not keyPressed[0x72] then
                keyPressed[0x72] = true
                Config.HitboxEnabled = not Config.HitboxEnabled
                UI.SetValue("hbe", Config.HitboxEnabled)
                notify("Hitbox Expander", Config.HitboxEnabled and "ON" or "OFF", 3)
            end
        else
            keyPressed[0x72] = false
        end

        if iskeypressed(0x73) then 
            if not keyPressed[0x73] then
                keyPressed[0x73] = true
                Config.MoveStyle = (Config.MoveStyle + 1) % 2
                UI.SetValue("move_style", Config.MoveStyle)
                local styleName = Config.MoveStyle == 0 and "Orbit" or "Fixed"
                notify("Movement Style", styleName, 3)
            end
        else
            keyPressed[0x73] = false
        end
        
        task.wait()
    end
end)

task.spawn(function()
    while true do
        local folders = {workspace:FindFirstChild("BossFolder"), workspace:FindFirstChild("enemies")}
        for _, folder in pairs(folders) do
            if folder then
                for _, model in pairs(folder:GetChildren()) do
                    if model:IsA("Model") then
                        local head = model:FindFirstChild("Head")
                        if head and head:IsA("BasePart") then
                            local mesh = head:FindFirstChildWhichIsA("SpecialMesh") or head:FindFirstChildWhichIsA("DataModelMesh")
                            if Config.HitboxEnabled then
                                head.Size = Config.HITBOX_SIZE
                                head.CanCollide = false
                                if mesh then
                                    pcall(function()
                                        mesh.Scale = Vector3.new(
                                            Config.DEFAULT_HEAD_SIZE.X / Config.HITBOX_SIZE.X,
                                            Config.DEFAULT_HEAD_SIZE.Y / Config.HITBOX_SIZE.Y,
                                            Config.DEFAULT_HEAD_SIZE.Z / Config.HITBOX_SIZE.Z
                                        )
                                    end)
                                end
                            else
                                head.Size = Config.DEFAULT_HEAD_SIZE
                                head.CanCollide = true
                                if mesh then
                                    pcall(function() mesh.Scale = Vector3.new(1, 1, 1) end)
                                end
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.5)
    end
end)

local function SafeWorldToScreen(pos)
    local screen_pos, on_screen = WorldToScreen(pos)
    if not on_screen then return Vector2.new(0,0), false end
    
    local viewSize = workspace.CurrentCamera.ViewportSize
    -- Increased margins to 50px to prevent hitting Title Bar (30px) or Taskbar (40px)
    -- This prevents the window from resizing/minimizing when clicking near edges.
    local inBounds = screen_pos.X > 50 and screen_pos.X < viewSize.X - 50 and screen_pos.Y > 50 and screen_pos.Y < viewSize.Y - 50
    return screen_pos, inBounds
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function GetDistance(p1, p2)
    local diff = p1 - p2
    return math.sqrt(diff.X^2 + diff.Y^2 + diff.Z^2)
end

local function GetTarget()
    local folders = {workspace:FindFirstChild("BossFolder"), workspace:FindFirstChild("enemies")}
    for _, f in pairs(folders) do
        if f then
            for _, v in pairs(f:GetChildren()) do
                local hum = v:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0.1 then 
                    return v, hum 
                end
            end
        end
    end
    return nil, nil
end

task.spawn(function()
    local angle = 0
    while true do
        local success, err = pcall(function()
            if Config.Enabled then
                local target, humanoid = GetTarget()
                if target and humanoid then
                    local cameraLerpPos = workspace.CurrentCamera.Position
                    while Config.Enabled and target and target.Parent and humanoid.Health > 0.1 do
                        local char = lp.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        local targetAnchor = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
                        
                        if targetAnchor and targetAnchor.Name == "Head" then
                            targetAnchor = target:FindFirstChild("Torso") or target:FindFirstChild("LowerTorso") or targetAnchor
                        end

                        if hrp and targetAnchor and targetAnchor.Parent then
                            local rawTargetPos = targetAnchor.Position
                            local lerpTargetPos = rawTargetPos
                            
                            if Config.MoveStyle == 0 then -- Orbit
                                angle = (angle or 0) + ((Config.SPEED or 6) / 100)
                                local offsetX = math.cos(angle) * (Config.DISTANCE or 9)
                                local offsetZ = math.sin(angle) * (Config.DISTANCE or 9)
                                lerpTargetPos = rawTargetPos + Vector3.new(offsetX, (Config.HEIGHT or 14), offsetZ)
                            elseif Config.MoveStyle == 1 then -- Fixed
                                local cf = ReadCFrame(targetAnchor)
                                if cf then
                                    local lv = Vector3.new(-cf.r02, -cf.r12, -cf.r22)
                                    lerpTargetPos = Vector3.new(cf.X, cf.Y, cf.Z) - (lv * (Config.DISTANCE or 9)) + Vector3.new(0, (Config.HEIGHT or 14), 0)
                                else
                                    lerpTargetPos = rawTargetPos + Vector3.new((Config.DISTANCE or 9), (Config.HEIGHT or 14), 0)
                                end
                            end

                            -- Ultra-Smooth Staggered Lerp (Y is highly stabilized)
                            local currentPos = hrp.Position
                            local nextStep = Lerp(currentPos, lerpTargetPos, 0.1)
                            local nextY = Lerp(currentPos.Y, lerpTargetPos.Y, 0.05)
                            hrp.Position = Vector3.new(nextStep.X, nextY, nextStep.Z)

                            -- Aimbot (Simplified to User's "Perfect" Logic)
                            local screenPos, onScreen = SafeWorldToScreen(rawTargetPos)
                            if onScreen and IsWindowFocused() then
                                mousemoveabs(screenPos.X, screenPos.Y)
                                if Config.FullAuto then 
                                    if not MouseIsDown then
                                        mouse1press() 
                                        MouseIsDown = true
                                    end
                                else 
                                    mouse1click() 
                                end
                            else
                                if MouseIsDown then
                                    mouse1release()
                                    MouseIsDown = false
                                end
                            end
                        end
                        RunService.Heartbeat:Wait()
                    end
                    if MouseIsDown then
                        mouse1release()
                        MouseIsDown = false
                    end
                else
                    task.wait(0.1)
                end
            end
        end)
        
        if not success then
            task.wait(1)
        end
        
        RunService.Heartbeat:Wait()
    end
end)
