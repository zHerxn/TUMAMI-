-- ═══════════════════════════════════════════════════════════════
-- 📦 SERVICIOS DE ROBLOX
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════
-- 🎨 CARGAR RAYFIELD UI LIBRARY
-- ═══════════════════════════════════════════════════════════════

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- ═══════════════════════════════════════════════════════════════
-- 🔧 VARIABLES DE CONFIGURACIÓN
-- ═══════════════════════════════════════════════════════════════

local AimbotConfig = {
    -- Estado general
    Enabled = false,
    
    -- Configuración de targeting
    TargetPart = "Head", -- Parte del cuerpo objetivo
    MaxDistance = 500, -- Distancia máxima en studs
    FOV = 90, -- Campo de visión en grados
    
    -- Configuración de suavizado
    Smoothness = 0.1, -- 0.1 = muy suave, 1 = instantáneo
    PredictMovement = false, -- Predicción de movimiento
    PredictionMultiplier = 1.5,
    
    -- Prioridades
    PriorityMode = "Closest", -- "Closest", "Lowest Health", "Looking At Me"
    
    -- Filtros
    IgnoreInvisible = true,
    IgnoreForceField = true,
    MinHealthPercent = 0, -- 0-100
    
    -- Controles
    AimbotKey = Enum.KeyCode.E, -- Tecla para activar/desactivar
    HoldToAim = false, -- true = mantener presionado, false = toggle
    
    -- Visuales
    ShowFOVCircle = true,
    FOVCircleColor = Color3.fromRGB(255, 255, 255),
    FOVCircleTransparency = 0.8
}

-- Variables de estado interno
local CurrentTarget = nil
local AimbotConnection = nil
local FOVCircle = nil
local TargetList = {}

-- ═══════════════════════════════════════════════════════════════
-- 🎯 FUNCIONES PRINCIPALES DEL AIMBOT
-- ═══════════════════════════════════════════════════════════════

--[[
    🔍 Función: GetValidTargets()
    Propósito: Busca y filtra todos los objetivos válidos en el juego
    Retorna: Tabla con todos los objetivos válidos
--]]
local function GetValidTargets()
    local targets = {}
    local myCharacter = LocalPlayer.Character
    
    if not myCharacter or not myCharacter:FindFirstChild("HumanoidRootPart") then
        return targets
    end
    
    local myPosition = myCharacter.HumanoidRootPart.Position
    
    -- Buscar jugadores
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local character = player.Character
            local humanoid = character:FindFirstChild("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local targetPart = character:FindFirstChild(AimbotConfig.TargetPart)
            
            if humanoid and rootPart and targetPart then
                -- Filtrar por distancia
                local distance = (myPosition - rootPart.Position).Magnitude
                if distance <= AimbotConfig.MaxDistance then
                    
                    -- Filtrar por salud mínima
                    local healthPercent = (humanoid.Health / humanoid.MaxHealth) * 100
                    if healthPercent >= AimbotConfig.MinHealthPercent then
                        
                        -- Filtrar invisibles (si están habilitados los filtros)
                        if not AimbotConfig.IgnoreInvisible or targetPart.Transparency < 1 then
                            
                            -- Filtrar ForceField
                            if not AimbotConfig.IgnoreForceField or not character:FindFirstChild("ForceField") then
                                
                                table.insert(targets, {
                                    Player = player,
                                    Character = character,
                                    Humanoid = humanoid,
                                    RootPart = rootPart,
                                    TargetPart = targetPart,
                                    Distance = distance,
                                    HealthPercent = healthPercent
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Buscar NPCs (entidades con Humanoid que no sean jugadores)
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent ~= myCharacter then
            local character = obj.Parent
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local targetPart = character:FindFirstChild(AimbotConfig.TargetPart)
            
            -- Verificar que no sea un jugador
            local isPlayer = false
            for _, player in pairs(Players:GetPlayers()) do
                if player.Character == character then
                    isPlayer = true
                    break
                end
            end
            
            if not isPlayer and rootPart and targetPart and obj.Health > 0 then
                local distance = (myPosition - rootPart.Position).Magnitude
                if distance <= AimbotConfig.MaxDistance then
                    local healthPercent = (obj.Health / obj.MaxHealth) * 100
                    if healthPercent >= AimbotConfig.MinHealthPercent then
                        if not AimbotConfig.IgnoreInvisible or targetPart.Transparency < 1 then
                            table.insert(targets, {
                                Player = nil, -- NPCs no tienen Player
                                Character = character,
                                Humanoid = obj,
                                RootPart = rootPart,
                                TargetPart = targetPart,
                                Distance = distance,
                                HealthPercent = healthPercent
                            })
                        end
                    end
                end
            end
        end
    end
    
    return targets
end

--[[
    📐 Función: IsInFOV(targetPosition)
    Propósito: Verifica si un objetivo está dentro del campo de visión
    Parámetros: targetPosition (Vector3) - Posición del objetivo
    Retorna: boolean - true si está en FOV
--]]
local function IsInFOV(targetPosition)
    local screenPoint, onScreen = Camera:WorldToScreenPoint(targetPosition)
    if not onScreen then return false end
    
    local centerX = Camera.ViewportSize.X / 2
    local centerY = Camera.ViewportSize.Y / 2
    local distance = math.sqrt((screenPoint.X - centerX)^2 + (screenPoint.Y - centerY)^2)
    
    -- Convertir FOV a píxeles (aproximación)
    local fovPixels = (AimbotConfig.FOV / 90) * (Camera.ViewportSize.X / 4)
    
    return distance <= fovPixels
end

--[[
    🎯 Función: GetBestTarget(targets)
    Propósito: Selecciona el mejor objetivo basado en la prioridad configurada
    Parámetros: targets (tabla) - Lista de objetivos válidos
    Retorna: tabla - El mejor objetivo o nil
--]]
local function GetBestTarget(targets)
    if #targets == 0 then return nil end
    
    local myCharacter = LocalPlayer.Character
    if not myCharacter or not myCharacter:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local myPosition = myCharacter.HumanoidRootPart.Position
    local myLookDirection = Camera.CFrame.LookVector
    
    -- Filtrar por FOV
    local fovTargets = {}
    for _, target in pairs(targets) do
        if IsInFOV(target.TargetPart.Position) then
            table.insert(fovTargets, target)
        end
    end
    
    if #fovTargets == 0 then return nil end
    
    -- Aplicar lógica de prioridad
    if AimbotConfig.PriorityMode == "Closest" then
        table.sort(fovTargets, function(a, b) return a.Distance < b.Distance end)
        return fovTargets[1]
        
    elseif AimbotConfig.PriorityMode == "Lowest Health" then
        table.sort(fovTargets, function(a, b) return a.HealthPercent < b.HealthPercent end)
        return fovTargets[1]
        
    elseif AimbotConfig.PriorityMode == "Looking At Me" then
        local bestTarget = nil
        local bestAngle = math.huge
        
        for _, target in pairs(fovTargets) do
            -- Calcular si el objetivo me está mirando
            local targetLookDirection = target.Character.Head.CFrame.LookVector
            local directionToMe = (myPosition - target.RootPart.Position).Unit
            local angle = math.acos(targetLookDirection:Dot(directionToMe))
            
            if angle < bestAngle then
                bestAngle = angle
                bestTarget = target
            end
        end
        
        return bestTarget
    end
    
    return fovTargets[1] -- Fallback al más cercano
end

--[[
    🎯 Función: PredictTargetPosition(target)
    Propósito: Predice la posición futura del objetivo basada en su velocidad
    Parámetros: target (tabla) - Objetivo actual
    Retorna: Vector3 - Posición predicha
--]]
local function PredictTargetPosition(target)
    if not AimbotConfig.PredictMovement then
        return target.TargetPart.Position
    end
    
    local targetVelocity = target.RootPart.Velocity
    local distance = (LocalPlayer.Character.HumanoidRootPart.Position - target.RootPart.Position).Magnitude
    
    -- Calcular tiempo que tarda en llegar (simulación básica)
    local timeToTarget = distance / 1000 -- Velocidad estimada de bala/hitscan
    
    -- Predecir posición futura
    local predictedPosition = target.TargetPart.Position + (targetVelocity * timeToTarget * AimbotConfig.PredictionMultiplier)
    
    return predictedPosition
end

--[[
    🎮 Función: AimAtTarget(target)
    Propósito: Mueve la cámara hacia el objetivo con suavizado
    Parámetros: target (tabla) - Objetivo seleccionado
--]]
local function AimAtTarget(target)
    if not target or not target.TargetPart then return end
    
    local myCharacter = LocalPlayer.Character
    if not myCharacter or not myCharacter:FindFirstChild("HumanoidRootPart") then return end
    
    -- Obtener posición objetivo (con predicción si está habilitada)
    local targetPosition = PredictTargetPosition(target)
    
    -- Calcular la dirección hacia el objetivo
    local direction = (targetPosition - Camera.CFrame.Position).Unit
    local newCFrame = CFrame.lookAt(Camera.CFrame.Position, Camera.CFrame.Position + direction)
    
    -- Aplicar suavizado
    if AimbotConfig.Smoothness < 1 then
        Camera.CFrame = Camera.CFrame:Lerp(newCFrame, AimbotConfig.Smoothness)
    else
        Camera.CFrame = newCFrame
    end
end

--[[
    🔄 Función: AimbotLoop()
    Propósito: Bucle principal del aimbot que se ejecuta cada frame
--]]
local function AimbotLoop()
    if not AimbotConfig.Enabled then return end
    
    -- Obtener objetivos válidos
    local targets = GetValidTargets()
    TargetList = targets -- Guardar para la UI
    
    -- Seleccionar el mejor objetivo
    local bestTarget = GetBestTarget(targets)
    CurrentTarget = bestTarget
    
    -- Apuntar al objetivo si existe
    if bestTarget then
        AimAtTarget(bestTarget)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 👁️ SISTEMA VISUAL (FOV CIRCLE)
-- ═══════════════════════════════════════════════════════════════

--[[
    🎨 Función: CreateFOVCircle()
    Propósito: Crea el círculo visual del campo de visión
--]]
local function CreateFOVCircle()
    if FOVCircle then FOVCircle:Remove() end
    
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Color = AimbotConfig.FOVCircleColor
    FOVCircle.Transparency = AimbotConfig.FOVCircleTransparency
    FOVCircle.Filled = false
    FOVCircle.Thickness = 2
    FOVCircle.NumSides = 100
end

--[[
    🔄 Función: UpdateFOVCircle()
    Propósito: Actualiza la posición y tamaño del círculo FOV
--]]
local function UpdateFOVCircle()
    if not AimbotConfig.ShowFOVCircle or not FOVCircle then return end
    
    local centerX = Camera.ViewportSize.X / 2
    local centerY = Camera.ViewportSize.Y / 2
    local radius = (AimbotConfig.FOV / 90) * (Camera.ViewportSize.X / 4)
    
    FOVCircle.Position = Vector2.new(centerX, centerY)
    FOVCircle.Radius = radius
    FOVCircle.Visible = AimbotConfig.ShowFOVCircle
    FOVCircle.Color = AimbotConfig.FOVCircleColor
    FOVCircle.Transparency = AimbotConfig.FOVCircleTransparency
end

-- ═══════════════════════════════════════════════════════════════
-- 🎮 SISTEMA DE CONTROLES
-- ═══════════════════════════════════════════════════════════════

--[[
    ⌨️ Función: HandleInput(key, gameProcessed)
    Propósito: Maneja la entrada de teclado para activar/desactivar el aimbot
--]]
local function HandleInput(key, gameProcessed)
    if gameProcessed then return end
    
    if key.KeyCode == AimbotConfig.AimbotKey then
        if AimbotConfig.HoldToAim then
            AimbotConfig.Enabled = true
        else
            AimbotConfig.Enabled = not AimbotConfig.Enabled
        end
        
        -- Notificación de estado
        Rayfield:Notify({
            Title = AimbotConfig.Enabled and "🎯 Aimbot Activado" or "❌ Aimbot Desactivado",
            Content = "Estado: " .. (AimbotConfig.Enabled and "ON" or "OFF"),
            Duration = 2,
            Image = 4483362458
        })
    end
end

--[[
    ⌨️ Función: HandleInputEnd(key, gameProcessed)
    Propósito: Maneja cuando se suelta una tecla (para modo hold)
--]]
local function HandleInputEnd(key, gameProcessed)
    if gameProcessed then return end
    
    if key.KeyCode == AimbotConfig.AimbotKey and AimbotConfig.HoldToAim then
        AimbotConfig.Enabled = false
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 🎨 INTERFAZ GRÁFICA CON RAYFIELD
-- ═══════════════════════════════════════════════════════════════

-- Crear ventana principal
local Window = Rayfield:CreateWindow({
    Name = "🎯 Universal Aimbot Pro v2.0",
    LoadingTitle = "Cargando Aimbot...",
    LoadingSubtitle = "Inicializando sistemas...",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "UniversalAimbot",
        FileName = "config"
    },
    Discord = {
        Enabled = false,
        Invite = "",
        RememberJoins = false
    },
    KeySystem = false
})

-- Crear pestañas
local MainTab = Window:CreateTab("🎯 Principal", 4483362458)
local TargetingTab = Window:CreateTab("🎯 Targeting", 4483362458)
local VisualsTab = Window:CreateTab("👁️ Visuales", 4483362458)
local SettingsTab = Window:CreateTab("⚙️ Configuración", 4483362458)

-- ═══════════════════════════════════════════════════════════════
-- 📋 PESTAÑA PRINCIPAL
-- ═══════════════════════════════════════════════════════════════

local MainSection = MainTab:CreateSection("🎮 Control Principal")

-- Toggle principal del aimbot
local AimbotToggle = MainTab:CreateToggle({
    Name = "🎯 Activar Aimbot",
    CurrentValue = AimbotConfig.Enabled,
    Flag = "AimbotToggle",
    Callback = function(Value)
        AimbotConfig.Enabled = Value
        
        -- Iniciar o detener el bucle principal
        if Value then
            if not AimbotConnection then
                AimbotConnection = RunService.Heartbeat:Connect(AimbotLoop)
            end
            Rayfield:Notify({
                Title = "✅ Aimbot Activado",
                Content = "El aimbot está ahora activo",
                Duration = 3,
                Image = 4483362458
            })
        else
            if AimbotConnection then
                AimbotConnection:Disconnect()
                AimbotConnection = nil
            end
            CurrentTarget = nil
            Rayfield:Notify({
                Title = "❌ Aimbot Desactivado", 
                Content = "El aimbot ha sido desactivado",
                Duration = 3,
                Image = 4483362458
            })
        end
    end,
})

-- Modo de control (Hold vs Toggle)
local HoldModeToggle = MainTab:CreateToggle({
    Name = "🔒 Modo Mantener Presionado",
    CurrentValue = AimbotConfig.HoldToAim,
    Flag = "HoldModeToggle",
    Callback = function(Value)
        AimbotConfig.HoldToAim = Value
    end,
})

-- Selector de tecla (simulado con dropdown)
local KeyDropdown = MainTab:CreateDropdown({
    Name = "⌨️ Tecla de Activación",
    Options = {"E", "Q", "F", "C", "X", "Z", "T", "G", "H", "Mouse1", "Mouse2"},
    CurrentOption = {"E"},
    MultipleOptions = false,
    Flag = "KeyDropdown",
    Callback = function(Option)
        local keyMap = {
            ["E"] = Enum.KeyCode.E,
            ["Q"] = Enum.KeyCode.Q,
            ["F"] = Enum.KeyCode.F,
            ["C"] = Enum.KeyCode.C,
            ["X"] = Enum.KeyCode.X,
            ["Z"] = Enum.KeyCode.Z,
            ["T"] = Enum.KeyCode.T,
            ["G"] = Enum.KeyCode.G,
            ["H"] = Enum.KeyCode.H,
            ["Mouse1"] = Enum.UserInputType.MouseButton1,
            ["Mouse2"] = Enum.UserInputType.MouseButton2
        }
        AimbotConfig.AimbotKey = keyMap[Option[1]] or Enum.KeyCode.E
    end,
})

-- Label de estado
local StatusLabel = MainTab:CreateLabel("🔄 Estado: Inactivo")

-- Información de objetivo actual
local TargetLabel = MainTab:CreateLabel("🎯 Objetivo: Ninguno")

-- ═══════════════════════════════════════════════════════════════
-- 🎯 PESTAÑA TARGETING
-- ═══════════════════════════════════════════════════════════════

local TargetingSection = TargetingTab:CreateSection("🎯 Configuración de Objetivos")

-- Parte del cuerpo objetivo
local TargetPartDropdown = TargetingTab:CreateDropdown({
    Name = "🎯 Parte del Cuerpo Objetivo",
    Options = {"Head", "Torso", "HumanoidRootPart", "UpperTorso", "LowerTorso"},
    CurrentOption = {AimbotConfig.TargetPart},
    MultipleOptions = false,
    Flag = "TargetPartDropdown",
    Callback = function(Option)
        AimbotConfig.TargetPart = Option[1]
    end,
})

-- Distancia máxima
local MaxDistanceSlider = TargetingTab:CreateSlider({
    Name = "📏 Distancia Máxima",
    Range = {50, 2000},
    Increment = 10,
    Suffix = " studs",
    CurrentValue = AimbotConfig.MaxDistance,
    Flag = "MaxDistanceSlider",
    Callback = function(Value)
        AimbotConfig.MaxDistance = Value
    end,
})

-- Campo de visión
local FOVSlider = TargetingTab:CreateSlider({
    Name = "👁️ Campo de Visión (FOV)",
    Range = {10, 180},
    Increment = 1,
    Suffix = "°",
    CurrentValue = AimbotConfig.FOV,
    Flag = "FOVSlider",
    Callback = function(Value)
        AimbotConfig.FOV = Value
    end,
})

-- Modo de prioridad
local PriorityDropdown = TargetingTab:CreateDropdown({
    Name = "⭐ Modo de Prioridad",
    Options = {"Closest", "Lowest Health", "Looking At Me"},
    CurrentOption = {AimbotConfig.PriorityMode},
    MultipleOptions = false,
    Flag = "PriorityDropdown",
    Callback = function(Option)
        AimbotConfig.PriorityMode = Option[1]
    end,
})

-- Sección de suavizado
local SmoothingSection = TargetingTab:CreateSection("🎮 Suavizado y Predicción")

-- Suavizado
local SmoothnessSlider = TargetingTab:CreateSlider({
    Name = "🎛️ Suavizado",
    Range = {0.01, 1},
    Increment = 0.01,
    Suffix = "",
    CurrentValue = AimbotConfig.Smoothness,
    Flag = "SmoothnessSlider",
    Callback = function(Value)
        AimbotConfig.Smoothness = Value
    end,
})

-- Predicción de movimiento
local PredictionToggle = TargetingTab:CreateToggle({
    Name = "🔮 Predicción de Movimiento",
    CurrentValue = AimbotConfig.PredictMovement,
    Flag = "PredictionToggle",
    Callback = function(Value)
        AimbotConfig.PredictMovement = Value
    end,
})

-- Multiplicador de predicción
local PredictionSlider = TargetingTab:CreateSlider({
    Name = "⚡ Multiplicador de Predicción",
    Range = {0.1, 5},
    Increment = 0.1,
    Suffix = "x",
    CurrentValue = AimbotConfig.PredictionMultiplier,
    Flag = "PredictionSlider",
    Callback = function(Value)
        AimbotConfig.PredictionMultiplier = Value
    end,
})

-- ═══════════════════════════════════════════════════════════════
-- 👁️ PESTAÑA VISUALES
-- ═══════════════════════════════════════════════════════════════

local VisualsSection = VisualsTab:CreateSection("👁️ Elementos Visuales")

-- Mostrar círculo FOV
local FOVCircleToggle = VisualsTab:CreateToggle({
    Name = "⭕ Mostrar Círculo FOV",
    CurrentValue = AimbotConfig.ShowFOVCircle,
    Flag = "FOVCircleToggle",
    Callback = function(Value)
        AimbotConfig.ShowFOVCircle = Value
        if Value and not FOVCircle then
            CreateFOVCircle()
        elseif FOVCircle then
            FOVCircle.Visible = Value
        end
    end,
})

-- Color del círculo FOV
local FOVColorPicker = VisualsTab:CreateColorPicker({
    Name = "🎨 Color del Círculo FOV",
    Color = AimbotConfig.FOVCircleColor,
    Flag = "FOVColorPicker",
    Callback = function(Value)
        AimbotConfig.FOVCircleColor = Value
    end
})

-- Transparencia del círculo
local FOVTransparencySlider = VisualsTab:CreateSlider({
    Name = "👻 Transparencia del Círculo",
    Range = {0, 1},
    Increment = 0.1,
    Suffix = "",
    CurrentValue = AimbotConfig.FOVCircleTransparency,
    Flag = "FOVTransparencySlider",
    Callback = function(Value)
        AimbotConfig.FOVCircleTransparency = Value
    end,
})

-- ═══════════════════════════════════════════════════════════════
-- ⚙️ PESTAÑA CONFIGURACIÓN
-- ═══════════════════════════════════════════════════════════════

local FiltersSection = SettingsTab:CreateSection("🔍 Filtros")

-- Ignorar invisibles
local IgnoreInvisibleToggle = SettingsTab:CreateToggle({
    Name = "👻 Ignorar Objetivos Invisibles",
    CurrentValue = AimbotConfig.IgnoreInvisible,
    Flag = "IgnoreInvisibleToggle",
    Callback = function(Value)
        AimbotConfig.IgnoreInvisible = Value
    end,
})

-- Ignorar ForceField
local IgnoreForceFieldToggle = SettingsTab:CreateToggle({
    Name = "🛡️ Ignorar ForceField",
    CurrentValue = AimbotConfig.IgnoreForceField,
    Flag = "IgnoreForceFieldToggle",
    Callback = function(Value)
        AimbotConfig.IgnoreForceField = Value
    end,
})

-- Porcentaje mínimo de salud
local MinHealthSlider = SettingsTab:CreateSlider({
    Name = "❤️ Salud Mínima (%)",
    Range = {0, 100},
    Increment = 1,
    Suffix = "%",
    CurrentValue = AimbotConfig.MinHealthPercent,
    Flag = "MinHealthSlider",
    Callback = function(Value)
        AimbotConfig.MinHealthPercent = Value
    end,
})

-- Sección de utilidades
local UtilitiesSection = SettingsTab:CreateSection("🛠️ Utilidades")

-- Botón para resetear configuración
local ResetButton = SettingsTab:CreateButton({
    Name = "🔄 Resetear Configuración",
    Callback = function()
        Rayfield:Notify({
            Title = "⚠️ Confirmación",
            Content = "¿Seguro que quieres resetear?",
            Duration = 5,
            Actions = {
                Ignore = {
                    Name = "❌ Cancelar",
                    Callback = function()
                        print("Reset cancelado")
                    end
                },
                Confirm = {
                    Name = "✅ Confirmar",
                    Callback = function()
                        -- Resetear todas las configuraciones
                        AimbotConfig.Enabled = false
                        AimbotConfig.TargetPart = "Head"
                        AimbotConfig.MaxDistance = 500
                        AimbotConfig.FOV = 90
                        AimbotConfig.Smoothness = 0.1
                        AimbotConfig.PredictMovement = false
                        AimbotConfig.PriorityMode = "Closest"
                        
                        -- Actualizar UI
                        AimbotToggle:Set(false)
                        TargetPartDropdown:Set({"Head"})
                        MaxDistanceSlider:Set(500)
                        FOVSlider:Set(90)
                        SmoothnessSlider:Set(0.1)
                        
                        Rayfield:Notify({
                            Title = "✅ Reseteo Completo",
                            Content = "Configuración restaurada",
                            Duration = 3
                        })
                    end
                }
            }
        })
    end,
})

-- ═══════════════════════════════════════════════════════════════
-- 🔄 BUCLES Y CONEXIONES
-- ═══════════════════════════════════════════════════════════════

-- Crear círculo FOV inicial
CreateFOVCircle()

-- Conexión para actualizar la UI cada segundo
RunService.Heartbeat:Connect(function()
    -- Actualizar labels de estado
    local targetCount = #TargetList
    
    StatusLabel:Set("🔄 Estado: " .. (AimbotConfig.Enabled and "✅ Activo" or "❌ Inactivo") .. " | Objetivos: " .. targetCount)
    
    if CurrentTarget then
        local targetName = "Desconocido"
        if CurrentTarget.Player then
            targetName = CurrentTarget.Player.DisplayName or CurrentTarget.Player.Name
        elseif CurrentTarget.Character then
            targetName = CurrentTarget.Character.Name
        end
        local distance = math.floor(CurrentTarget.Distance)
        local health = math.floor(CurrentTarget.HealthPercent)
        TargetLabel:Set("🎯 Objetivo: " .. targetName .. " | Distancia: " .. distance .. " | Salud: " .. health .. "%")
    else
        TargetLabel:Set("🎯 Objetivo: Ninguno")
    end
    
    -- Actualizar círculo FOV
    UpdateFOVCircle()
end)

-- Conexiones de entrada
UserInputService.InputBegan:Connect(HandleInput)
UserInputService.InputEnded:Connect(HandleInputEnd)

-- ═══════════════════════════════════════════════════════════════
-- 🚀 INICIALIZACIÓN Y FUNCIONES DE LIMPIEZA
-- ═══════════════════════════════════════════════════════════════

--[[
    🧹 Función: CleanupAimbot()
    Propósito: Limpia todos los recursos del aimbot al desactivarlo
--]]
local function CleanupAimbot()
    -- Desconectar bucle principal
    if AimbotConnection then
        AimbotConnection:Disconnect()
        AimbotConnection = nil
    end
    
    -- Remover círculo FOV
    if FOVCircle then
        FOVCircle:Remove()
        FOVCircle = nil
    end
    
    -- Limpiar variables
    CurrentTarget = nil
    TargetList = {}
    
    print("🧹 Aimbot limpiado correctamente")
end

--[[
    ⚠️ Función de seguridad: Detección de cambios de juego
    Propósito: Desactiva el aimbot si el jugador cambia de juego
--]]
game.Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        CleanupAimbot()
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- 📊 FUNCIONES DE DEBUG Y ESTADÍSTICAS
-- ═══════════════════════════════════════════════════════════════

--[[
    📊 Función: GetAimbotStats()
    Propósito: Devuelve estadísticas actuales del aimbot
    Retorna: tabla con estadísticas
--]]
local function GetAimbotStats()
    return {
        Enabled = AimbotConfig.Enabled,
        CurrentTarget = CurrentTarget and (CurrentTarget.Player and CurrentTarget.Player.Name or CurrentTarget.Character.Name) or "None",
        TargetCount = #TargetList,
        FOV = AimbotConfig.FOV,
        MaxDistance = AimbotConfig.MaxDistance,
        Smoothness = AimbotConfig.Smoothness,
        PriorityMode = AimbotConfig.PriorityMode
    }
end

-- Añadir botón de estadísticas en la pestaña de configuración
local StatsButton = SettingsTab:CreateButton({
    Name = "📊 Mostrar Estadísticas",
    Callback = function()
        local stats = GetAimbotStats()
        local statsText = string.format(
            "Estado: %s\nObjetivo Actual: %s\nObjetivos Detectados: %d\nFOV: %d°\nDistancia Máx: %d\nSuavizado: %.2f\nPrioridad: %s",
            stats.Enabled and "Activo" or "Inactivo",
            stats.CurrentTarget,
            stats.TargetCount,
            stats.FOV,
            stats.MaxDistance,
            stats.Smoothness,
            stats.PriorityMode
        )
        
        Rayfield:Notify({
            Title = "📊 Estadísticas del Aimbot",
            Content = statsText,
            Duration = 8,
            Image = 4483362458
        })
    end,
})

-- ═══════════════════════════════════════════════════════════════
-- 🔧 FUNCIONES ADICIONALES DE UTILIDAD
-- ═══════════════════════════════════════════════════════════════

--[[
    🎯 Función: ManualTarget(playerName)
    Propósito: Permite apuntar manualmente a un jugador específico
    Parámetros: playerName (string) - Nombre del jugador
--]]
local function ManualTarget(playerName)
    local targetPlayer = Players:FindFirstChild(playerName)
    if targetPlayer and targetPlayer.Character then
        local character = targetPlayer.Character
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        local targetPart = character:FindFirstChild(AimbotConfig.TargetPart)
        
        if humanoid and rootPart and targetPart then
            CurrentTarget = {
                Player = targetPlayer,
                Character = character,
                Humanoid = humanoid,
                RootPart = rootPart,
                TargetPart = targetPart,
                Distance = (LocalPlayer.Character.HumanoidRootPart.Position - rootPart.Position).Magnitude,
                HealthPercent = (humanoid.Health / humanoid.MaxHealth) * 100
            }
            
            Rayfield:Notify({
                Title = "🎯 Objetivo Manual",
                Content = "Apuntando a: " .. playerName,
                Duration = 3
            })
            return true
        end
    end
    
    Rayfield:Notify({
        Title = "❌ Error",
        Content = "No se pudo encontrar al jugador: " .. playerName,
        Duration = 3
    })
    return false
end

-- Input para objetivo manual
local ManualTargetInput = SettingsTab:CreateInput({
    Name = "🎯 Objetivo Manual",
    PlaceholderText = "Nombre del jugador...",
    RemoveTextAfterFocusLost = false,
    Flag = "ManualTargetInput",
    Callback = function(Text)
        if Text and Text ~= "" then
            ManualTarget(Text)
        end
    end,
})

--[[
    🔄 Función: ToggleAimbotQuick()
    Propósito: Función rápida para toggle desde otros scripts
--]]
_G.ToggleAimbot = function()
    AimbotConfig.Enabled = not AimbotConfig.Enabled
    AimbotToggle:Set(AimbotConfig.Enabled)
    return AimbotConfig.Enabled
end

--[[
    ⚙️ Función: SetAimbotConfig()
    Propósito: Permite cambiar configuración desde otros scripts
--]]
_G.SetAimbotConfig = function(config)
    for key, value in pairs(config) do
        if AimbotConfig[key] ~= nil then
            AimbotConfig[key] = value
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 🎉 MENSAJE DE INICIALIZACIÓN
-- ═══════════════════════════════════════════════════════════════

-- Información adicional en la interfaz
local InfoParagraph = MainTab:CreateParagraph({
    Title = "ℹ️ Información del Aimbot",
    Content = "Este aimbot universal funciona en cualquier juego de Roblox. Detecta automáticamente jugadores y NPCs como objetivos. Usa los controles de las pestañas para configurar según tus preferencias."
})

-- Instrucciones de uso
local InstructionsParagraph = SettingsTab:CreateParagraph({
    Title = "📋 Instrucciones de Uso",
    Content = "1. Activa el aimbot con el toggle principal\n2. Configura la tecla de activación\n3. Ajusta el FOV y la distancia máxima\n4. Selecciona el modo de prioridad\n5. Ajusta el suavizado según tu preferencia\n6. ¡Listo para usar!"
})

-- Notificación de carga completa
wait(1) -- Pequeña pausa para que cargue todo

Rayfield:Notify({
    Title = "🎉 ¡Aimbot Cargado!",
    Content = "Universal Aimbot Pro v2.0 está listo para usar. Presiona " .. (AimbotConfig.AimbotKey.Name or "E") .. " para activar.",
    Duration = 5,
    Image = 4483362458
})
