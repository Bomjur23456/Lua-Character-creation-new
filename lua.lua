local module = {}
module.__index = module

-- \\ variables
--
local list = {}
local dialogueNpcs = {}

-- services
local runService = game:GetService("RunService")
local players = game:GetService("Players")
local uis = game:GetService("UserInputService")

-- constants
local plr = players.LocalPlayer

local prefix = "[CHARACTERS]"
local templates = script.TEMPLATES

local hash = Instance.new("Folder")

module.VECTORS = {
	up = Vector3.new(0, 1, 0),
	left = Vector3.new(-1, 0, 0),
	right = Vector3.new(1, 0, 0),
	down = Vector3.new(0, -1, 0),
	forward = Vector3.new(0, 0, -1),
	backward = Vector3.new(0, 0, 1)
}

module.updateSpeed = 0.15

-- \\ functions
function msg(...)
	print(prefix .. " " .. ...)
end

function fatal(...)
	warn(prefix .. " FATAL MESSAGE: " .. ...)
end

function getSize(images)
	local out = images + 1
	
	if out >= 7 then
		out += math.max(0.5 * (out - 6), 0)
	end
	
	return math.min(out, 10)
end

function wrongType(name, type)
	msg("Got wrong type of " .. name .. " (" .. type .. " expected)")
end

function animate(self, animation)
	if typeof(animation) ~= "string" then
		return wrongType("Animation", "string")
	end
	
	local animModule = self.module.Animations[animation]

	if not animModule or not animModule:IsA("ModuleScript") then
		return msg("Got no animations with name " .. animation)
	end

	local req = require(animModule)
	local image = `rbxassetid://{req.id}`
	local size = getSize(req.images)
	local billboard = self.billboard
	local imageLabel:ImageLabel = billboard.ImageLabel

	imageLabel.Image = image
	imageLabel.Position = UDim2.fromScale(0, 0)
	imageLabel.Size = UDim2.fromScale(size, 1)

	if self.lastAnimationThread then
		task.cancel(self.lastAnimationThread)
	end

	local thread = task.spawn(function()
		local i = 0
		
		-- \\ updating image (animation)
		while task.wait(self.req.customUpdateSpeed or module.updateSpeed) do
			local lookingLeft = self.lookDir == -1
			local step = lookingLeft and -1.33 or -1.25
			
			i += 1

			if i >= req.images then
				i = 0
			end
			
			billboard.StudsOffset = Vector3.new(lookingLeft and 0 or -0.35, .5, 0)

			if not lookingLeft then
				imageLabel.ImageRectOffset = Vector2.new(0, 0)
				imageLabel.ImageRectSize = Vector2.new(0, 0)
			else
				imageLabel.ImageRectOffset = Vector2.new(1024, 0)
				imageLabel.ImageRectSize = Vector2.new(-1024, 1024)
			end
			
			imageLabel.Position = UDim2.fromScale(
				lookingLeft and step * (req.images - 1) - step * i
					or step * i,
				0)
		end
	end)

	self.lastAnimationThread = thread
end

-- \\ main functions
module.create = function(name:string, params)
	local parent = params.parent
	local origCf = params.origCf
	local origChar = params.char
	local dialogue = params.dialogue
	
	if typeof(name) ~= "string" then
		return wrongType("Name", "string")
	end
	
	local charModule = script:FindFirstChild(name)
	
	if not charModule or not charModule:IsA("ModuleScript") then
		return msg("Wrong Character name")
	end
	
	local req = require(charModule)
	local animations = charModule:FindFirstChild("Animations")
	
	if not animations or not animations:IsA("Folder") then
		return fatal("couldnt find Animations folder for " .. name .. " character")
	end
	
	if typeof(origCf) ~= "CFrame" then
		origCf = nil
	end
	
	if origCf and (not parent and not origChar) then
		msg("origCf is not used (parent is nil)")
		origCf = nil
	end
	
	if dialogue and typeof(dialogue) ~= "table" then
		msg("dialogue data is not used (table type expected)")
		dialogue = nil
	end
	
	local self = {}
	
	local char = origChar or templates.model:Clone()
	local billboard = templates.BillboardGui:Clone()
	local hum = char:WaitForChild("Humanoid")
	local root = char:WaitForChild("HumanoidRootPart")
	
	-- \\ setting up character
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.zero
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Parent = root
	
	local att = Instance.new("Attachment", root)

	local ao = Instance.new("AlignOrientation", root)
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxAngularVelocity = math.huge
	ao.MaxTorque = math.huge
	ao.Responsiveness = math.huge
	
	if not origChar then
		char.Name = name
	end
	
	billboard.Parent = root
	
	root.CollisionGroup = "char"
	
	if parent then
		char.Parent = parent
	end
	
	if origCf then
		char:PivotTo(origCf * CFrame.new(0, root.Size.Y / 2, 0))
	end
	
	-- \\ self variables
	self.char = origChar or char
	self.billboard = billboard
	self.velocity = bv
	self.name = name
	self.req = req
	self.module = charModule
	self.state = "Idle"
	self.lookDir = 1
	self.jumping = false
	self.jumpProceed = false
	self.walking = false
	self.running = false
	self.dashing = false
	self.onGround = false
	self.inDialogue = false
	self.dialogue = dialogue
	self.canDialogueWith = nil
	self.params = {
		walkSpeed = 7,
		runSpeed = 10,
		slowWalkSpeed = 4,
		jumpPower = 5,
		dashPower = 20,
	}
	self.humanoid = {}
	
	local humanoidParams = {
		"walkSpeed",
		"jumpPower",
		"dashPower"
	}
	
	for i,v in humanoidParams do
		local value = self.params[v]
		self.humanoid[v] = value
	end
	
	local lastState = ""
	
	local dialogueBilldboards = {
		questionMark = dialogue and templates.QuestionMark:Clone() or nil,
		button = dialogue and templates.Button:Clone() or nil
	}
	
	-- \\ character updater
	self.update = runService.Heartbeat:Connect(function(dt)
		local function checkFloor()
			local floor = workspace:Raycast(root.Position, Vector3.new(0, -(root.Size.Y / 2 + .1), 0))

			self.onGround = floor ~= nil
		end
		
		local function gravity()
			if self.jumpProceed then return end
			
			if not self.onGround then
				bv.Velocity -= Vector3.new(0, 1, 0)
			else
				self.jumping = false
				bv.Velocity = Vector3.new(bv.Velocity.X, 0, bv.Velocity.Z)
			end
		end

		local function statesUpdater()
			if self.inDialogue then
				self:idle()
				self.state = "Idle"
				self.humanoid.walkSpeed = 0
			elseif self.dashing then
				self.state = "Dash"
				self.humanoid.walkSpeed = 0
			elseif self.jumping then
				self.state = "Jump"
				self.humanoid.walkSpeed = self.params.slowWalkSpeed
			elseif self.walking and not self.running then
				self.state = "Walk"
				self.humanoid.walkSpeed = self.params.walkSpeed
			elseif self.walking and self.running then
				self.state = "Run"
				self.humanoid.walkSpeed = self.params.runSpeed
			else
				self.state = "Idle"
				self.humanoid.walkSpeed = self.params.walkSpeed
			end

			if lastState == self.state then return end

			lastState = self.state
			animate(self, self.state)
		end
		
		local function dialogueUpdater()
			if not dialogue then return end

			if self.inDialogue then
				dialogueBilldboards.questionMark.Parent = hash
				dialogueBilldboards.button.Parent = hash

				return
			end

			if not dialogueNpcs[char] then
				dialogueNpcs[char] = true
			end
			
			local pChar = plr.Character
			
			if not pChar then return end
			
			local pRoot:BasePart = pChar:FindFirstChild("HumanoidRootPart")
			
			if not pRoot then return end
			
			local closest = {
				m = nil,
				d = math.huge
			}
			
			for c, _ in dialogueNpcs do
				local d = (c.HumanoidRootPart.Position - pRoot.Position).Magnitude
				
				if d <= 3 and d < closest.d then
					closest.m = c
					closest.d = d
				end
			end
			
			if closest.m == nil then
				list[pChar].canDialogueWith = nil
			end

			if closest.m ~= char then
				dialogueBilldboards.questionMark.Parent = root
				dialogueBilldboards.button.Parent = hash
			else
				list[pChar].canDialogueWith = self
				dialogueBilldboards.questionMark.Parent = hash
				dialogueBilldboards.button.Parent = root
			end
		end

		for i,v in {statesUpdater, gravity, checkFloor, dialogueUpdater} do
			v()
		end
	end)
	
	list[char] = self
	
	char.Destroying:Once(function()
		self:destroy()
	end)
	
	return setmetatable(self, module)
end

module.getByModel = function(char:Model)
	if not char or not char:IsA("Model") then
		return wrongType("Character Model", "Model")
	end

	return list[char]
end

-- \\ character functions
function module:destroy()
	if self.char:IsDescendantOf(workspace) then
		self.char:Destroy()
	end
	
	list[self.char] = nil
	self = nil
end

function module:updateVelocity(dir)
	self.velocity.Velocity = dir
end

function module:setLookDirByVector(dir)
	if dir.X >= 1 then
		self.lookDir = 1
	elseif dir.X <= -1 then
		self.lookDir = -1		
	end
end

function module:move(moveDir)
	if typeof(moveDir) ~= "Vector3" then
		return wrongType("Move Direction", "Vector3")
	end
	
	if self.dashing or self.inDialogue then return end
	
	moveDir *= self.humanoid.walkSpeed
	
	self:setLookDirByVector(moveDir)
	
	self:updateVelocity(Vector3.new(moveDir.X, self.velocity.Velocity.Y, moveDir.Z))

	self.walking = true
	self.idleSet = false
end

function module:idle()
	if self.dashing or self.jumping then return end
	
	if not self.idleSet then
		self:updateVelocity(Vector3.zero)
		self.idleSet = true
	end

	self.walking = false
end

function module:startDialogue(otherSelf)
	if not self.canDialogueWith
		or self.inDialogue
		or otherSelf.inDialogue
		or not otherSelf.dialogue
	then
		return
	end
	
	self.inDialogue = true
	otherSelf.inDialogue = true

	local billboard = templates.Dialogue:Clone()
	local frame = billboard:WaitForChild("Frame")
	billboard.Parent = otherSelf.char.HumanoidRootPart
	
	local animThread, inputConnection, currentText
	local canProceed = false
	local continueDialogue = false
	
	local function animateText(text)
		frame.DialogueLabel.Text = ""
		
		continueDialogue = false
		canProceed = false
		
		animThread = task.spawn(function()
			for i = 1, #text do
				frame.DialogueLabel.Text = string.sub(text, 1, i)
				task.wait(0.05)
			end
			
			canProceed = true
		end)
	end
	
	inputConnection = uis.InputBegan:Connect(function(inp, gpe)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			if canProceed then
				continueDialogue = true
			else
				if animThread then
					task.cancel(animThread)
				end
				
				canProceed = true
			end
		end
	end)
	
	for i,v in otherSelf.dialogue do
		currentText = v
		animateText(v)
		
		repeat task.wait() until canProceed

		frame.DialogueLabel.Text = currentText
		
		repeat task.wait() until continueDialogue
	end
	
	inputConnection:Disconnect()
	billboard:Destroy()

	self.inDialogue = false
	otherSelf.inDialogue = false
end

function module:jump()
	if not self.onGround
		or self.jumping
		or self.jumpProceed
		or self.dashing
		or self.inDialogue
	then return end
	
	self.jumpProceed = true
	self.jumping = true
	
	local heartbeat
	
	task.spawn(function()
		local total = 0
		local steps = {
			[1] = .4,
			[2] = .65
		}
		
		local root:BasePart = self.char.HumanoidRootPart
		
		local function stop()
			self.jumpProceed = false
			heartbeat:Disconnect()
		end
		
		heartbeat = runService.Heartbeat:Connect(function(dt)
			self.jumping = true
			
			if total >= steps[1] and total < steps[2] then
				local newVelo = module.VECTORS.up * self.humanoid.jumpPower
				self:updateVelocity(Vector3.new(
					self.velocity.Velocity.X,
					newVelo.Y,
					self.velocity.Velocity.Z
					))
			elseif total >= steps[2] then
				stop()
			end
			
			total += dt
		end)
	end)
	
	self.idleSet = false
end

function module:dash(dir)
	if self.dashing
		or self.jumping
		or self.inDialogue
	then return end
	
	if not dir or typeof(dir) ~= "Vector3" then
		return wrongType("Dash Direction", "Vector3")
	end
	
	local heartbeat
	local total = 0
	local dashTime = .4
	
	local function stop()
		heartbeat:Disconnect()
		self.dashing = false
		self:idle()
	end
	
	dir *= self.humanoid.dashPower

	self.dashing = true

	heartbeat = runService.Heartbeat:Connect(function(dt)
		if total >= dashTime then
			stop()
		else
			self.dashing = true
			self.moving = false
			
			self:setLookDirByVector(dir)
			
			self:updateVelocity(Vector3.new(
				dir.X,
				self.velocity.Velocity.Y,
				dir.Z
				))
		end
		
		total += dt
	end)

	self.idleSet = false
end

return module