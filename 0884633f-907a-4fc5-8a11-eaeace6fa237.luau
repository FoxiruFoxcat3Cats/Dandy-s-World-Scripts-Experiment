-- Prevent duplicate scripts and GUI buttons.
if _G.BypassJumpScript then
	_G.BypassJumpScript:Destroy()
end
_G.BypassJumpScript = script

local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local gravity = workspace.Gravity

local player = Players.LocalPlayer

-- Update character references on spawn/respawn.
local char, humanoid, hrp, head
local function updateCharacter(character)
	char = character
	humanoid = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
	head = char:FindFirstChild("Head") or hrp
end
if player.Character then
	updateCharacter(player.Character)
end
player.CharacterAdded:Connect(function(character)
	updateCharacter(character)
end)

-- Set up GUI button.
local screenGui = player:WaitForChild("PlayerGui")
local sg = screenGui:FindFirstChildOfClass("ScreenGui") or Instance.new("ScreenGui", screenGui)
local existingButton = sg:FindFirstChild("BypassJumpButton")
if existingButton then
	existingButton:Destroy()
end
local button = Instance.new("TextButton")
button.Name = "BypassJumpButton"
button.Size = UDim2.new(0,70,0,70)
button.Position = UDim2.new(0.5,-50,0.8,0)
button.BackgroundColor3 = Color3.fromRGB(0,0,0)
button.BackgroundTransparency = 0.4
button.Text = "BypassJump"
button.TextColor3 = Color3.fromRGB(255,255,255)
button.Parent = sg

local uicorner = Instance.new("UICorner")
uicorner.CornerRadius = UDim.new(0,10)
uicorner.Parent = button

local dragging, dragInput, dragStart, startPos
button.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = button.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)
button.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)
UIS.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart
		button.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local function isOnGround()
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Seated or 
		   state == Enum.HumanoidStateType.Running or 
		   state == Enum.HumanoidStateType.Landed or 
		   state == Enum.HumanoidStateType.RunningNoPhysics
end

-- Continuously record the last nonzero MoveDirection (for mobile/keyboard).
local lastControllerInput = Vector3.new(1, 0, 0)
RunService.Heartbeat:Connect(function()
	if humanoid and humanoid.MoveDirection then
		local moveDir = humanoid.MoveDirection
		if moveDir.Magnitude > 0.1 then
			lastControllerInput = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
		end
	end
end)

button.MouseButton1Click:Connect(function()
	if humanoid and hrp and head and isOnGround() then
		-- Use current move direction if available; otherwise, fallback to the last recorded.
		local moveDir = humanoid.MoveDirection
		if moveDir.Magnitude > 0.1 then
			moveDir = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
			lastControllerInput = moveDir
		else
			moveDir = lastControllerInput or Vector3.new(1, 0, 0)
		end
		
		-- For linear push, follow the controller input.
		local pushMagnitude = 75
		local pushVec = moveDir * pushMagnitude
		
		-- Compare moveDir with head's horizontal forward vector.
		local headForward = Vector3.new(head.CFrame.LookVector.X, 0, head.CFrame.LookVector.Z)
		if headForward.Magnitude == 0 then
			headForward = Vector3.new(0, 0, -1)
		end
		headForward = headForward.Unit
		
		local dot = moveDir:Dot(headForward)
		local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
		local cross = headForward:Cross(moveDir)
		local sign = (cross.Y < 0) and -1 or 1
		angle = angle * sign
		
		-- Determine angular flip axis based on the angle.
		local angularAxis = Vector3.new(0, 0, 0)
		if math.abs(angle) < 45 then
			angularAxis = -head.CFrame.RightVector  -- front flip
		elseif math.abs(angle) > 135 then
			angularAxis = head.CFrame.RightVector   -- back flip
		elseif angle >= 45 and angle <= 135 then
			angularAxis = -head.CFrame.LookVector     -- right side flip
		elseif angle <= -45 and angle >= -135 then
			angularAxis = head.CFrame.LookVector      -- left side flip
		else
			angularAxis = -head.CFrame.RightVector
		end
		
		-- Calculate jump velocity (with ceiling check) and original flight time.
		local desiredVel = 100
		local safetyMargin = 1.0
		local rayOrigin = head.Position
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {char}
		rayParams.FilterType = Enum.RaycastFilterType.Blacklist
		local jumpHeight = (desiredVel^2) / (2 * gravity)
		local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, jumpHeight + safetyMargin, 0), rayParams)
		local chosenVel = desiredVel
		if rayResult then
			local hitDist = rayResult.Distance - safetyMargin
			local allowedVel = math.sqrt(2 * gravity * hitDist)
			chosenVel = math.min(desiredVel, allowedVel)
		end
		
		-- Original flight time based on vertical jump.
		local originalFlightTime = (2 * chosenVel) / gravity
		
		-- For movement, use the push vector computed from the controller.
		hrp.AssemblyLinearVelocity = Vector3.new(pushVec.X, chosenVel, pushVec.Z)
		
		-- For flip calculation, always use the original flight time.
		local flightTimeForFlip = originalFlightTime
		
		-- Determine flip count based on jump height:
		-- High jump (chosenVel high) → 4 flips; otherwise 2–3 flips.
		local flipCount
		if chosenVel >= (chosenVel/1.11) then
			flipCount = math.random(1, 4)
		else
			flipCount = math.random(2, 3)
		end
		-- If a ceiling is detected, reduce flip count by 1.
		if rayResult then
			flipCount = math.max(1, flipCount - 1)
		end
		
		local totalAngle = 2 * math.pi * flipCount
		
		-- Set up BodyAngularVelocity for the flip.
		local bav = Instance.new("BodyAngularVelocity")
		bav.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
		bav.AngularVelocity = Vector3.new(0, 0, 0)
		bav.Parent = hrp
		
		local startTime = tick()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local elapsed = tick() - startTime
			if elapsed >= flightTimeForFlip then
				conn:Disconnect()
				bav:Destroy()
				hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			else
				-- Sine-eased angular velocity so that the integrated rotation over flightTimeForFlip equals totalAngle.
				local instantaneousAngularVel = (totalAngle * math.pi) / (2 * flightTimeForFlip) * math.sin(math.pi * elapsed / flightTimeForFlip)
				bav.AngularVelocity = angularAxis * instantaneousAngularVel
			end
		end)
	end
end)