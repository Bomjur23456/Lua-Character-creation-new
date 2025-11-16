local module = {}
module.__index = module -- sets the metatable so module functions can be accessed through instances

-- variables
local list = {} -- stores all created characters indexed by model
local dialogueNpcs = {} -- stores characters that can be interacted with via dialogue

-- services
local runService = game:GetService("RunService") -- allows connection to Heartbeat for frame updates
local players = game:GetService("Players") -- service for accessing player instances
local uis = game:GetService("UserInputService") -- service for detecting user input

-- constants
local plr = players.LocalPlayer -- reference to the local player
local prefix = "[CHARACTERS]" -- prefix for printed messages
local templates = script.TEMPLATES -- folder containing GUI and model templates
local hash = Instance.new("Folder") -- a folder used to temporarily hide billboard elements

-- predefined vector directions
module.VECTORS = {
	up = Vector3.new(0, 1, 0), -- upward direction
	left = Vector3.new(-1, 0, 0), -- left direction
	right = Vector3.new(1, 0, 0), -- right direction
	down = Vector3.new(0, -1, 0), -- downward direction
	forward = Vector3.new(0, 0, -1), -- forward direction
	backward = Vector3.new(0, 0, 1) -- backward direction
}

module.updateSpeed = 0.15 -- default animation update speed

-- function to print messages
function msg(...)
	print(prefix .. " " .. ...) -- prints message with prefix
end

-- function to print warnings
function fatal(...)
	warn(prefix .. " FATAL MESSAGE: " .. ...) -- prints fatal warning message
end

-- function to calculate the visual size based on frame count
function getSize(images)
	local out = images + 1 -- base size scaling from number of images
	if out >= 7 then
		out += math.max(0.5 * (out - 6), 0) -- increases size slightly when animations exceed 6 frames
	end
	return math.min(out, 10) -- ensures the size never exceeds 10
end

-- prints wrong argument type
function wrongType(name, type)
	msg("Got wrong type of " .. name .. " (" .. type .. " expected)")
end

-- main animation handler
function animate(self, animation)
	if typeof(animation) ~= "string" then
		return wrongType("Animation", "string") -- animation name must be string
	end
	
	local animModule = self.module.Animations[animation] -- attempts to find animation module

	if not animModule or not animModule:IsA("ModuleScript") then
		return msg("Got no animations with name " .. animation) -- prints if animation not found
	end

	local req = require(animModule) -- loads animation data
	local image = `rbxassetid://{req.id}` -- builds image path
	local size = getSize(req.images) -- calculates sprite width
	local billboard = self.billboard -- billboard GUI containing sprite frame
	local imageLabel = billboard.ImageLabel -- the ImageLabel displaying the sprite
	
	imageLabel.Image = image -- applies sprite sheet image
	imageLabel.Position = UDim2.fromScale(0, 0) -- resets position
	imageLabel.Size = UDim2.fromScale(size, 1) -- sets width based on frame count

	if self.lastAnimationThread then
		task.cancel(self.lastAnimationThread) -- cancel previously running animation thread
	end

	-- thread for animation playback
	local thread = task.spawn(function()
		local i = 0 -- frame index

		while task.wait(self.req.customUpdateSpeed or module.updateSpeed) do
			local lookingLeft = self.lookDir == -1 -- checks if character should face left
			local step = lookingLeft and -1.33 or -1.25 -- determines sprite offset

			i += 1 -- advance frame
			if i >= req.images then
				i = 0 -- loop animation
			end
			
			billboard.StudsOffset = Vector3.new(lookingLeft and 0 or -0.35, .5, 0) -- shifts sprite depending on facing
			
			if not lookingLeft then
				-- facing right: use original frame orientation
				imageLabel.ImageRectOffset = Vector2.new(0, 0)
				imageLabel.ImageRectSize = Vector2.new(0, 0)
			else
				-- facing left: horizontally mirrored frame
				imageLabel.ImageRectOffset = Vector2.new(1024, 0)
				imageLabel.ImageRectSize = Vector2.new(-1024, 1024)
			end
			
			-- updates image offset per frame
			imageLabel.Position = UDim2.fromScale(
				lookingLeft and step * (req.images - 1) - step * i
				or step * i,
				0)
		end
	end)

	self.lastAnimationThread = thread -- save thread reference
end

-- MAIN CREATION FUNCTION
module.create = function(name, params)
	local parent = params.parent -- parent object of character model
	local origCf = params.origCf -- original CFrame position
	local origChar = params.char -- pre-existing model
	local dialogue = params.dialogue -- dialogue data table

	if typeof(name) ~= "string" then
		return wrongType("Name", "string")
	end

	local charModule = script:FindFirstChild(name) -- locate character definition module

	if not charModule or not charModule:IsA("ModuleScript") then
		return msg("Wrong Character name") -- module not found
	end

	local req = require(charModule) -- loads module data
	local animations = charModule:FindFirstChild("Animations") -- animations folder

	if not animations or not animations:IsA("Folder") then
		return fatal("couldnt find Animations folder for " .. name .. " character") -- fatal if missing
	end

	if typeof(origCf) ~= "CFrame" then
		origCf = nil -- clears invalid origCf
	end

	if origCf and (not parent and not origChar) then
		msg("origCf is not used (parent is nil)") -- warns if origCf is unused
		origCf = nil
	end

	if dialogue and typeof(dialogue) ~= "table" then
		msg("dialogue data is not used (table type expected)") -- warns if dialogue is invalid
		dialogue = nil
	end

	local self = {} -- creates new character table

	local char = origChar or templates.model:Clone() -- clones template model
	local billboard = templates.BillboardGui:Clone() -- creates billboard GUI
	local hum = char:WaitForChild("Humanoid") -- humanoid reference
	local root = char:WaitForChild("HumanoidRootPart") -- root part reference

	-- physics setup
	local bv = Instance.new("BodyVelocity") -- body velocity for movement
	bv.Velocity = Vector3.zero
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge) -- infinite forces
	bv.Parent = root
	
	-- orientation stabilization
	local att = Instance.new("Attachment", root) -- used for orientation alignment

	local ao = Instance.new("AlignOrientation", root) -- keeps character upright
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxAngularVelocity = math.huge
	ao.MaxTorque = math.huge
	ao.Responsiveness = math.huge

	if not origChar then
		char.Name = name -- assigns name if newly cloned
	end

	billboard.Parent = root -- attach billboard to root

	root.CollisionGroup = "char" -- assigns collision group

	if parent then
		char.Parent = parent -- parent model if provided
	end

	if origCf then
		char:PivotTo(origCf * CFrame.new(0, root.Size.Y / 2, 0)) -- position character
	end

	-- store character data inside self\_table
	self.char = origChar or char
	self.billboard = billboard
	self.velocity = bv
	self.name = name
	self.req = req
	self.module = charModule
	self.state = "Idle" -- starting animation state
	self.lookDir = 1 -- facing right initially
	self.jumping = false -- jumping state
	self.jumpProceed = false -- prevents double jump
	self.walking = false
	self.running = false
	self.dashing = false
	self.onGround = false
	self.inDialogue = false
	self.dialogue = dialogue
	self.canDialogueWith = nil -- reference to NPC you can talk to

	self.params = { -- parameters for movement
		walkSpeed = 7,
		runSpeed = 10,
		slowWalkSpeed = 4,
		jumpPower = 5,
		dashPower = 20,
	}
	
	self.humanoid = {} -- stores values exposed to humanoid

	local humanoidParams = { -- list of params copied to humanoid proxy
		"walkSpeed",
		"jumpPower",
		"dashPower"
	}

	for i,v in humanoidParams do
		local value = self.params[v]
		self.humanoid[v] = value -- copies parameter
	end

	local lastState = "" -- stores last state for animation switching

	local dialogueBilldboards = { -- UI elements depending on state
		questionMark = dialogue and templates.QuestionMark:Clone() or nil,
		button = dialogue and templates.Button:Clone() or nil
	}

	-- frame update loop
	self.update = runService.Heartbeat:Connect(function(dt)
		-- checks if character is standing on ground
		local function checkFloor()
			local floor = workspace:Raycast(root.Position, Vector3.new(0, -(root.Size.Y / 2 + .1), 0)) -- raycast downward
			self.onGround = floor ~= nil -- true if ray hits
		end

		-- manual gravity system because BodyVelocity disables default physics
		local function gravity()
			if self.jumpProceed then return end
			
			if not self.onGround then
				bv.Velocity -= Vector3.new(0, 1, 0) -- apply downward force
			else
				self.jumping = false
				bv.Velocity = Vector3.new(bv.Velocity.X, 0, bv.Velocity.Z) -- reset vertical velocity
			end
		end

		-- selects animation state
		local function statesUpdater()
			if self.inDialogue then -- dialogue disables movement
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

			if lastState == self.state then return end -- prevent re-triggering animation

			lastState = self.state
			animate(self, self.state) -- plays animation
		end

		-- dialogue handling: decides when player can approach NPC
		local function dialogueUpdater()
			if not dialogue then return end -- skip if character has no dialogue

			if self.inDialogue then
				dialogueBilldboards.questionMark.Parent = hash -- hide question mark
				dialogueBilldboards.button.Parent = hash -- hide interaction button
				return
			end

			if not dialogueNpcs[char] then
				dialogueNpcs[char] = true -- register character as dialogue NPC
			end

			local pChar = plr.Character
			if not pChar then return end

			local pRoot = pChar:FindFirstChild("HumanoidRootPart")
			if not pRoot then return end

			local closest = {m = nil, d = math.huge} -- finds closest NPC

			for c,_ in dialogueNpcs do
				local d = (c.HumanoidRootPart.Position - pRoot.Position).Magnitude -- distance check
				if d <= 3 and d < closest.d then -- within talking range
					closest.m = c
					closest.d = d
				end
			end

			if closest.m == nil then
				list[pChar].canDialogueWith = nil -- no NPC nearby
			end

			if closest.m ~= char then
				dialogueBilldboards.questionMark.Parent = root -- show?
				dialogueBilldboards.button.Parent = hash
			else
				list[pChar].canDialogueWith = self
				dialogueBilldboards.questionMark.Parent = hash
				dialogueBilldboards.button.Parent = root
			end
		end
		
		-- call frame functions in order
		for i,v in {statesUpdater, gravity, checkFloor, dialogueUpdater} do
			v() -- executes each function
		end
	end)

	list[char] = self -- register character into global list

	char.Destroying:Once(function()
		self:destroy() -- cleanup when model is removed
	end)

	return setmetatable(self, module) -- enables OOP style behavior
end

-- retrieve character object by its model
module.getByModel = function(char)
	if not char or not char:IsA("Model") then
		return wrongType("Character Model", "Model") -- validation
	end
	return list[char]
end

-- destroys character instance
function module:destroy()
	if self.char:IsDescendantOf(workspace) then
		self.char:Destroy() -- remove model
	end
	list[self.char] = nil -- remove from list
	self = nil -- clear reference
end

-- updates velocity using BodyVelocity
function module:updateVelocity(dir)
	self.velocity.Velocity = dir
end

-- determines facing direction by movement
function module:setLookDirByVector(dir)
	if dir.X >= 1 then
		self.lookDir = 1 -- facing right
	elseif dir.X <= -1 then
		self.lookDir = -1 -- facing left
	end
end

-- general movement handler
function module:move(moveDir)
	if typeof(moveDir) ~= "Vector3" then
		return wrongType("Move Direction", "Vector3")
	end

	if self.dashing or self.inDialogue then return end
	
	moveDir *= self.humanoid.walkSpeed -- scale movement by speed

	self:setLookDirByVector(moveDir) -- update facing

	self:updateVelocity(Vector3.new(moveDir.X, self.velocity.Velocity.Y, moveDir.Z)) -- preserve vertical

	self.walking = true
	self.idleSet = false
end

-- idle state handler
function module:idle()
	if self.dashing or self.jumping then return end

	if not self.idleSet then
		self:updateVelocity(Vector3.zero) -- stop movement
		self.idleSet = true
	end

	self.walking = false
end

-- dialogue starting function
function module:startDialogue(otherSelf)
	if not self.canDialogueWith
		or self.inDialogue
		or otherSelf.inDialogue
		or not otherSelf.dialogue
	then
		return
	end

	self.inDialogue = true -- freeze states
	otherSelf.inDialogue = true

	local billboard = templates.Dialogue:Clone() -- dialogue UI
	local frame = billboard:WaitForChild("Frame")
	billboard.Parent = otherSelf.char.HumanoidRootPart

	local animThread, inputConnection, currentText
	local canProceed = false
	local continueDialogue = false

    local function animateText(text)
        -- This function animates text by revealing it letter by letter.

        frame.DialogueLabel.Text = ""
        -- clear dialogue label before new text animation starts

        continueDialogue = false
        -- user should not be able to continue during animation

        canProceed = false
        -- animation hasn't completed yet

        animThread = task.spawn(function()
            -- start asynchronous animation thread
            for i = 1, #text do
                -- loop from first character to last
                frame.DialogueLabel.Text = string.sub(text, 1, i)
                -- show substring of text up to index i (typewriter effect)
                
                task.wait(0.05)
                -- delay between each character
            end

            canProceed = true
            -- animation finished → now the user can continue
        end)
    end

    inputConnection = uis.InputBegan:Connect(function(inp, gpe)
        -- connect to input event — triggers on user pressing a key or mouse button

        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            -- only respond to left mouse click

            if canProceed then
                -- if animation already finished → move to next dialogue line
                continueDialogue = true
            else
                -- animation is still running → skip it

                if animThread then
                    task.cancel(animThread)
                    -- stop the typewriter animation immediately
                end

                canProceed = true
                -- allow proceeding and instantly show full text
            end
        end
    end)

    for i, v in otherSelf.dialogue do
        -- iterate through all dialogue lines (i = index, v = text)

        currentText = v
        -- store current dialogue line

        animateText(v)
        -- start text animation for this dialogue line

        repeat task.wait() until canProceed
        -- wait until:
        -- (1) animation finishes OR
        -- (2) player clicks to skip animation

        frame.DialogueLabel.Text = currentText
        -- ensure full text is visible after animation ends

        repeat task.wait() until continueDialogue
        -- wait until player clicks to continue to next line
    end

    inputConnection:Disconnect()
    -- disconnect input listener once dialogue ends

    billboard:Destroy()
    -- remove dialogue UI from screen

    self.inDialogue = false
    -- mark this character as no longer in dialogue

    otherSelf.inDialogue = false
    -- also mark the other character as no longer in dialogue
end



------------------------------------------------------------
-- JUMP FUNCTION
------------------------------------------------------------
function module:jump()
    -- this function makes the character jump

    if not self.onGround
        or self.jumping
        or self.jumpProceed
        or self.dashing
        or self.inDialogue
    then return end
    -- Conditions preventing jump:
    -- 1. not onGround → can't jump in air
    -- 2. already jumping
    -- 3. jump in progress
    -- 4. dashing
    -- 5. in dialogue (movement disabled)

    self.jumpProceed = true
    -- jump procedure started → prevents double jump

    self.jumping = true
    -- sets jumping animation state

    local heartbeat
    -- variable to store Heartbeat connection

    task.spawn(function()
        -- asynchronous jump process

        local total = 0
        -- total elapsed time since jump started

        local steps = {
            [1] = .4, -- moment when upward force starts
            [2] = .65 -- moment when upward force stops
        }

        local root:BasePart = self.char.HumanoidRootPart
        -- shortcut to root part

        local function stop()
            -- stop jump logic
            self.jumpProceed = false
            heartbeat:Disconnect()
        end

        heartbeat = runService.Heartbeat:Connect(function(dt)
            -- loop running every frame
            self.jumping = true

            if total >= steps[1] and total < steps[2] then
                -- time window where upward velocity should be applied

                local newVelo = module.VECTORS.up * self.humanoid.jumpPower
                -- calculate upward velocity using jumpPower

                self:updateVelocity(Vector3.new(
                    self.velocity.Velocity.X,
                    newVelo.Y,
                    self.velocity.Velocity.Z
                ))
                -- update only Y velocity while preserving X and Z (movement direction)
            
            elseif total >= steps[2] then
                -- jump upward force duration finished
                stop()
            end

            total += dt
            -- accumulate delta time into total elapsed time
        end)
    end)

    self.idleSet = false
    -- ensure idle state isn't activated during jump
end



------------------------------------------------------------
-- DASH FUNCTION
------------------------------------------------------------
function module:dash(dir)
    -- this function makes the character perform a dash movement

    if self.dashing
        or self.jumping
        or self.inDialogue
    then return end
    -- cannot dash while:
    -- already dashing, jumping, or in dialogue

    if not dir or typeof(dir) ~= "Vector3" then
        return wrongType("Dash Direction", "Vector3")
        -- dash direction argument must be a Vector3
    end

    local heartbeat
    local total = 0
    local dashTime = .4
    -- dash lasts exactly 0.4 seconds

    local function stop()
        -- stop dash behavior
        heartbeat:Disconnect()
        self.dashing = false
        self:idle()
        -- return to idle state
    end
    
    dir *= self.humanoid.dashPower
    -- multiply direction vector by dash power to produce dash speed

    self.dashing = true
    -- enter dash state

    heartbeat = runService.Heartbeat:Connect(function(dt)
        -- dash loop executed every frame

        if total >= dashTime then
            -- dash ended
            stop()
        else
            self.dashing = true      -- keep dash state active
            self.moving = false      -- disable walking animation

            self:setLookDirByVector(dir)
            -- update character facing direction based on dash direction

            self:updateVelocity(Vector3.new(
                dir.X,
                self.velocity.Velocity.Y,
                dir.Z
            ))
            -- override horizontal speed (X,Z) while keeping vertical (Y)
        end

        total += dt
        -- accumulate elapsed time
    end)

    self.idleSet = false
    -- ensure idle does not trigger during dash
end

return module
-- return the module table to allow requiring it from other scripts
