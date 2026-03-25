if _G.DoorsCleanup then _G.DoorsCleanup() end
local ScriptActive = true
_G.DoorsCleanup = function() ScriptActive = false end

task.wait(0.1)

local workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local player = players.LocalPlayer
local rooms = workspace:FindFirstChild("CurrentRooms")
local InputService = game:GetService("UserInputService")

local RunService = (function()
    local t_insert, t_remove, t_sort = table.insert, table.remove, table.sort
    local m_min, m_max = math.min, math.max
    local sys_clock = os.clock
    local sys_yield, sys_run = coroutine.yield, coroutine.running

    local Performance_Last_Tick_Timestamp = sys_clock()
    local Error_Tracking_Current_Count = 0
    local Error_Handling_Max_Threshold_Limit = 10
    local Bindings_Require_Resort = false
    local Render_Step_Priority_Bindings = {}
    local Cache_Sorted_Binding_Registry = {}

    local function Signal()
        local self = { ActiveConnections = {} }
        function self:Connect(CallbackFunction)
            local ConnectionObject = { Function = CallbackFunction, Connected = true }
            t_insert(self.ActiveConnections, ConnectionObject)
            return {
                Disconnect = function()
                    ConnectionObject.Connected = false
                    ConnectionObject.Function = nil
                end
            }
        end
        function self:Fire(...)
            local conns = self.ActiveConnections
            local i = 1
            while i <= #conns do
                local conn = conns[i]
                if conn.Connected then
                    local success = pcall(conn.Function, ...)
                    if not success then
                        Error_Tracking_Current_Count = Error_Tracking_Current_Count + 1
                        if Error_Tracking_Current_Count >= Error_Handling_Max_Threshold_Limit then
                            ScriptActive = false
                            return
                        end
                    end
                    i = i + 1
                else
                    t_remove(conns, i)
                end
            end
        end
        function self:Wait()
            local CurrentThread = sys_run()
            local WaitConnection
            WaitConnection = self:Connect(function(...)
                if WaitConnection then WaitConnection:Disconnect() end
                task.spawn(CurrentThread, ...)
            end)
            return sys_yield()
        end
        return self
    end

    local RS = {
        Heartbeat = Signal(),
        RenderStepped = Signal(),
        Stepped = Signal()
    }

    function RS:BindToRenderStep(Name, Priority, Function)
        Render_Step_Priority_Bindings[Name] = { Priority = Priority or 0, Function = Function }
        Bindings_Require_Resort = true
    end

    function RS:UnbindFromRenderStep(Name)
        if Render_Step_Priority_Bindings[Name] then
            Render_Step_Priority_Bindings[Name] = nil
            Bindings_Require_Resort = true
        end
    end

    local function CoreRenderFrame()
        local now = sys_clock()
        local delta = m_min(now - Performance_Last_Tick_Timestamp, 1)
        Performance_Last_Tick_Timestamp = now

        if ScriptActive then RS.Stepped:Fire(now, delta) end

        if ScriptActive then
            if Bindings_Require_Resort then
                Cache_Sorted_Binding_Registry = {}
                for _, data in pairs(Render_Step_Priority_Bindings) do
                    if data and type(data.Function) == "function" then
                        t_insert(Cache_Sorted_Binding_Registry, data)
                    end
                end
                t_sort(Cache_Sorted_Binding_Registry, function(a, b) return a.Priority < b.Priority end)
                Bindings_Require_Resort = false
            end
            local registry = Cache_Sorted_Binding_Registry
            for i = 1, #registry do
                if not ScriptActive then break end
                pcall(registry[i].Function, delta)
            end
        end

        if ScriptActive then RS.RenderStepped:Fire(delta) end
        if ScriptActive then RS.Heartbeat:Fire(delta) end
    end

    task.spawn(function()
        while ScriptActive do
            local success, err = pcall(CoreRenderFrame)
            if not success then
                Error_Tracking_Current_Count = Error_Tracking_Current_Count + 1
                warn("Doors RS Error [" .. Error_Tracking_Current_Count .. "/" .. Error_Handling_Max_Threshold_Limit .. "]: " .. tostring(err))
                if Error_Tracking_Current_Count >= Error_Handling_Max_Threshold_Limit then
                    warn("Doors RS: Max errors reached. Stopping.")
                    ScriptActive = false
                    break
                end
            else
                Error_Tracking_Current_Count = math.max(0, Error_Tracking_Current_Count - 0.1)
            end
            task.wait()
        end
    end)

    return RS
end)()

local Config = {
    Enabled = true,
    ShowDoors = true,
    ShowKeys = true,
    ShowTracers = true,
    ShowPath = true,
    NotifyEntities = true,
    ESP_Color = Color3.fromRGB(50, 255, 128),
    Key_Color = Color3.fromRGB(255, 200, 50),
    Path_Color = Color3.fromRGB(0, 170, 255),
    Font = Drawing.Fonts.System,
    TextSize = 20,
    DoorRange = 100,
    BehindFilterRange = 15
}

local drawings = {
    Doors = {},
    Keys = {},
    Paths = {},
    Tracers = {},
    PathConnector = nil
}
local cachedNextRoomNodes = {}
local camera = workspace.CurrentCamera

local function getdistance(targetPos)
    local character = player.Character
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart"))
    if not root then return 99999 end
    local delta = root.Position - targetPos
    return math.round(vector.magnitude(vector.create(delta.X, delta.Y, delta.Z)))
end

local function WorldToScreenChecked(pos)
    return WorldToScreen(pos)
end

local function getrooms(folder)
    local f = folder or workspace:FindFirstChild("CurrentRooms")
    if not f then return {current = 0, next = 0} end
    local highest = 0
    for _, v in pairs(f:GetChildren()) do
        local n = tonumber(v.Name)
        if n and n > highest then highest = n end
    end

    local char = player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
    local actualCurrent = math.max(0, highest - 1)
    
    if root then
        local pPos = root.Position
        local bestDist = math.huge
        for i = math.max(0, highest - 5), highest do
            local r = f:FindFirstChild(tostring(i))
            local ref = r and (r:FindFirstChild("RoomStart") or r:FindFirstChild("Entrance") or r:FindFirstChildWhichIsA("BasePart", true))
            if ref then
                local d = getdistance(ref.Position)
                if d < bestDist then
                    bestDist = d
                    actualCurrent = i
                end
            end
        end
    end

    return {current = actualCurrent, next = actualCurrent + 1}
end

local function getPathNodes(folder, currentRoom, nextRoom)
    local allNodes = {}
    for i = currentRoom, nextRoom do
        if not cachedNextRoomNodes[i] then
            local room = folder:FindFirstChild(tostring(i))
            local nodesFolder = room and room:FindFirstChild("PathfindNodes")
            if nodesFolder then
                local nodes = {}
                local children = nodesFolder:GetChildren()
                table.sort(children, function(a, b) return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0) end)
                for _, n in ipairs(children) do
                    nodes[#nodes + 1] = n.Position
                end
                cachedNextRoomNodes[i] = nodes
            end
        end
        if cachedNextRoomNodes[i] then
            for _, pos in ipairs(cachedNextRoomNodes[i]) do
                allNodes[#allNodes + 1] = pos
            end
        end
    end
    
    for roomNum, _ in pairs(cachedNextRoomNodes) do
        if roomNum < currentRoom - 1 then
            cachedNextRoomNodes[roomNum] = nil
        end
    end
    
    return allNodes
end

local function getBestPart(parent)
    if not parent then return nil end
    if parent:IsA("BasePart") then return parent end
    local h = parent:FindFirstChild("Hitbox") or parent:FindFirstChild("hitbox")
    if h and h:IsA("BasePart") then return h end
    return parent:FindFirstChildWhichIsA("BasePart", true)
end

local function createText()
    local t = Drawing.new("Text")
    t.Size = Config.TextSize
    t.Outline = true
    t.Center = true
    t.Font = Config.Font
    t.Visible = false
    return t
end

local function createLine()
    local l = Drawing.new("Line")
    l.Thickness = 2
    l.Visible = false
    return l
end

local notifiedEntities = {}

local function flashWarning(text)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vSize = cam.ViewportSize
    local warning = Drawing.new("Text")
    warning.Text = text
    warning.Size = 200
    warning.Color = Color3.fromRGB(255, 0, 0)
    warning.Outline = true
    warning.Center = true
    warning.Position = Vector2.new(vSize.X / 2, vSize.Y / 2)
    warning.Font = Config.Font
    warning.Visible = true

    task.spawn(function()
        task.wait(2)
        warning:Remove()
    end)
end

local function detectentities()
    local entities = {}
    
    for _, v in pairs(workspace:GetChildren()) do
        if v.Name == "RushMoving" or v.Name == "AmbushMoving" or v.Name == "SeekMoving" or v.Name == "Seek" or v.Name == "A60Moving" or v.Name == "A120Moving" then
             local name = v.Name:gsub("Moving", "")
             table.insert(entities, {name = name, instance = v, title = (name == "Rush" or name == "Ambush") and "Rush / Ambush SPAWNED!" or "ENTITY SPAWNED!"})
        end
    end

    if rooms then
        for _, room in pairs(rooms:GetChildren()) do
            local rush = room:FindFirstChild("RushMoving") or room:FindFirstChild("AmbushMoving")
            if rush then
                local name = rush.Name:gsub("Moving", "")
                table.insert(entities, {name = name, instance = rush, title = "Rush / Ambush SPAWNED!"})
            end
        end
    end
    
    local cam = workspace.CurrentCamera
    if cam then
        local s = cam:FindFirstChild("Screech")
        if s then table.insert(entities, {name = "Screech", instance = s, title = "SCREECH!"}) end
    end

    return entities
end

task.spawn(function()
    while ScriptActive do
        local success, err = pcall(function()
            if not Config.Enabled or not Config.NotifyEntities then return end
            
            for ent in pairs(notifiedEntities) do
                if not ent or not ent.Parent then notifiedEntities[ent] = nil end
            end

            local found = detectentities()
            for _, v in pairs(found) do
                local id = v.instance
                if not notifiedEntities[id] then
                    notifiedEntities[id] = true
                    notify(v.title, v.name, 5)
                    flashWarning(v.name:upper() .. " SPAWNED!")
                end
            end
        end)
        task.wait(0.2)
    end
end)

RunService.RenderStepped:Connect(function()
    pcall(function()
        if not Config.Enabled then
            for _, set in pairs(drawings) do
                for _, d in pairs(set) do d.Visible = false end
            end
            return
        end

        local roomsFolder = workspace:FindFirstChild("CurrentRooms") or workspace:FindFirstChild("Rooms")
        if not roomsFolder then return end
        
        local cam = workspace.CurrentCamera
        if not cam then return end

        local vSize = cam.ViewportSize
        local tracerOrigin = Vector2.new(vSize.X / 2, vSize.Y)
        local roomInfo = getrooms(roomsFolder)
        local currentRoom, nextRoom = roomInfo.current, roomInfo.next
        
        local pathNodes = getPathNodes(roomsFolder, currentRoom, nextRoom)

        if Config.ShowDoors then
            local activeDoors = {}
            for i = currentRoom, nextRoom do
                local room = roomsFolder:FindFirstChild(tostring(i))
                local doorModel = room and (room:FindFirstChild("Door") or room:FindFirstChild("Entrance") or room:FindFirstChild("Exit") or room:FindFirstChild("Door_Hold"))
                local collision = (doorModel and (doorModel:FindFirstChild("Collision") or doorModel:FindFirstChildWhichIsA("BasePart"))) or (room and room:FindFirstChild("Exit"))
                
                if collision and collision:IsA("BasePart") then
                    local color = Config.ESP_Color
                    local screenPos, onScreen = WorldToScreenChecked(collision.Position)
                    local id = "Door_" .. i
                    if not drawings.Doors[id] then drawings.Doors[id] = createText() end
                    if not drawings.Tracers[id] then drawings.Tracers[id] = createLine() end
                    local label, tracer = drawings.Doors[id], drawings.Tracers[id]

                    if onScreen then
                        activeDoors[id] = true
                        label.Text = "Door " .. (i + 1) .. (room:GetAttribute("RequiresKey") and "\n[LOCKED]" or "") .. "\n[" .. getdistance(collision.Position) .. "m]"
                        label.Position, label.Color, label.Visible = screenPos, color, true
                        if Config.ShowTracers then
                            tracer.From, tracer.To, tracer.Color, tracer.Visible = tracerOrigin, screenPos, color, true
                        else tracer.Visible = false end
                    else label.Visible, tracer.Visible = false, false end
                end
            end
            for id, d in pairs(drawings.Doors) do
                if not activeDoors[id] then d.Visible = false if drawings.Tracers[id] then drawings.Tracers[id].Visible = false end end
            end
        else for _, v in pairs(drawings.Doors) do v.Visible = false end end

        if Config.ShowKeys then
            local activeKeys = {}
            for i = currentRoom, nextRoom do
                local room = roomsFolder:FindFirstChild(tostring(i))
                if room then
                    local assets = room:FindFirstChild("Assets") or room
                    local targetObj = assets:FindFirstChild("KeyObtain") or assets:FindFirstChild("Key", true) or room:FindFirstChild("Key", true) or assets:FindFirstChild("LeverForGate") or room:FindFirstChild("LeverForGate", true)
                    local hitbox = targetObj and (targetObj:FindFirstChild("Hitbox") or targetObj:FindFirstChild("hitbox") or targetObj:FindFirstChild("Main") or getBestPart(targetObj))
                    
                    if hitbox and hitbox:IsA("BasePart") then
                        local screenPos, onScreen = WorldToScreenChecked(hitbox.Position)
                        local id = "Key_" .. room.Name
                        activeKeys[id] = true
                        if not drawings.Keys[id] then drawings.Keys[id] = createText() end
                        if not drawings.Tracers[id] then drawings.Tracers[id] = createLine() end
                        local label, tracer = drawings.Keys[id], drawings.Tracers[id]

                        if onScreen then
                            local isLever = string.find(targetObj.Name:lower(), "lever")
                            label.Text = (isLever and "Lever" or "Key") .. " (Room " .. room.Name .. ")\n[" .. getdistance(hitbox.Position) .. "m]"
                            label.Position, label.Color, label.Visible = screenPos, Config.Key_Color, true
                            if Config.ShowTracers then tracer.From, tracer.To, tracer.Color, tracer.Visible = tracerOrigin, screenPos, Config.Key_Color, true
                            else tracer.Visible = false end
                        else label.Visible, tracer.Visible = false, false end
                    end
                end
            end
            for id, k in pairs(drawings.Keys) do
                if not activeKeys[id] then k.Visible = false if drawings.Tracers[id] then drawings.Tracers[id].Visible = false end end
            end
        else for _, v in pairs(drawings.Keys) do v.Visible = false end end

        if Config.ShowPath and pathNodes and #pathNodes >= 0 then
            local char = player.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
            
            local fullPoints = {}
            if root then table.insert(fullPoints, root.Position) end
            for _, pos in ipairs(pathNodes) do table.insert(fullPoints, pos) end

            local nextDoorRoom = roomsFolder:FindFirstChild(tostring(roomInfo.next))
            local doorModel = nextDoorRoom and (nextDoorRoom:FindFirstChild("Door") or nextDoorRoom:FindFirstChild("Entrance") or nextDoorRoom:FindFirstChild("Door_Hold"))
            local doorPart = doorModel and (doorModel:FindFirstChild("Collision") or doorModel:FindFirstChildWhichIsA("BasePart"))
            if doorPart then table.insert(fullPoints, doorPart.Position) end

            local segmentCount = math.max(0, #fullPoints - 1)
            for i = 1, segmentCount do
                local s1, o1 = WorldToScreenChecked(fullPoints[i])
                local s2, o2 = WorldToScreenChecked(fullPoints[i+1])
                
                if not drawings.Paths[i] then 
                    drawings.Paths[i] = createLine() 
                    drawings.Paths[i].Thickness = 3
                end
                
                if o1 and o2 then
                    drawings.Paths[i].From, drawings.Paths[i].To, drawings.Paths[i].Color, drawings.Paths[i].Visible = s1, s2, Config.Path_Color, true
                else drawings.Paths[i].Visible = false end
            end
            
            for i = segmentCount + 1, #drawings.Paths do
                if drawings.Paths[i] then drawings.Paths[i].Visible = false end
            end
            if drawings.PathConnector then drawings.PathConnector.Visible = false end
        else
            if drawings.PathConnector then drawings.PathConnector.Visible = false end
            for _, v in pairs(drawings.Paths) do v.Visible = false end
        end
    end)
end)

notify("DOORS", "Initialized", 3)
