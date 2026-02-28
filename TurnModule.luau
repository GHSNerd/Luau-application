local TurnModule = {}
local Players = game:GetService("Players")
local tileModule = require(game.ReplicatedStorage.TileModule)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local general_methods = require(game.Workspace.general_methods)
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
--//VARIABLES//--
if RunService:IsServer() then
	game.ReplicatedStorage:WaitForChild("RequestMove").OnServerEvent:Connect(function(player: Player, t) 
		if t then
			local p = TurnModule:GetMove(player.Character, t)
			if p then
				TurnModule:MoveModel(player.Character, p)
			end
		end
	end)
end
-- t is tile abbreviated
local function GetChangeInDirection(t1:BasePart, t2:BasePart, t3:BasePart) -- t1 is previous, t2 is current, t3 is next
	local directionalvector1 = t2.Position - t1.Position
	local directionalvector2 = t3.Position - t2.Position
	if (directionalvector1-directionalvector2).Magnitude > 0.1 then--there was a change in direction,
		--penalize since we want a straight path
		-- Just add a slight discount, number here would be increased if we REALLY didn't want a bendy path
		return 1
	else
		return 0
	end
end

--The following two functions are what constitute the 2d pathfinding module
--The first computes a raw path towards a goal tile, and the second function refines
--the path by cutting down based on a limited movement range
-- It also accounts for less optimal tiles, which are tiles that take more movement
-- to walk across. I used "mud" to denote such tiles, which take a longer time to walk across
-- For the demonstration in the link, the tiles with large bushes are "muddy" tiles
local detectingtable = {}
-- Here is the standard djikstra's algorithm and A* pathfinding
--@param model to move, final destination tile
function TurnModule:GetMove(model:Model, goal:Part)
	if goal == nil then
		return
	end
	if goal:GetAttribute("Traversable") == false then -- Checks if the tile is filled
		-- which can be a wall or something
		return
	end

	local marker; -- SO A POSMARKER IS ESSENTIAL
	-- it is what we use to denote the character's position in 
	-- the grid
	if model.Name == "PosMarker" then
		marker = model
		model = marker.parent.Value
	else
		local posMarkers = CollectionService:GetTagged(tostring(4745937528))
		for index = 1, #posMarkers do 
			if posMarkers[index].parent.Value == model then
				marker = posMarkers[index]
			end
		end
	end	
	local params:RaycastParams = RaycastParams.new()
	params.FilterDescendantsInstances = CollectionService:GetTagged(9069336078)
	params.FilterType = Enum.RaycastFilterType.Include
	local tile:RaycastResult = workspace:Raycast(marker.Position + Vector3.new(0,2,0), Vector3.new(0,-20,0), params) -- starting position
	if goal == tile.Instance then
		return {} -- would be stack overflow if otherwise
	end
	
	local openlist= {}
	local closedlist = {}
	local parentTable = {}
	local FValueTable = {} -- f value is the estimated cost of the path to the goal + path to the tile
	local GValueTable = {[tile.Instance] = 0} -- G value is total cost of a path towards this tile 
	local HValueTable = {} -- heuristic value is the estimated cost from a tile to the goal
	-- recursively backtrack the GValue, which is the total cost for a path towards a
	--specific tile by adding up all those tiles previous to it, inclusive
	local function recallG(t)
		if parentTable[t] == tile.Instance then
			return 0 
		end
		return GValueTable[t] + recallG(parentTable[t]) 
	end

	local isPlayer = false
	if Players:GetPlayerFromCharacter(model) then
		isPlayer = true
	end
	local strength = 30 -- Limit how many searches our algorithm can do. Incase we attempt to path to an area
	-- COMPLETELY blocked off, and given that the map is large enough, the pathfinding algorithm will 
	-- waste resources trying to find a valid path towards the goal by checking all tiles on the map
	local function recall(_tile, strength)
		if strength == 0 then
			return false
		end
		strength -= 1 -- reduce strength

		if _tile == goal then
			FValueTable[_tile] = 0 
			return true -- start the backtrack (returning the path in the form of a table) if we have reached the goal
		end

		local surrounding = tileModule:getTilesWithinRange(_tile.Position+Vector3.new(0,1,0),
			1,nil,nil) -- get the tiles around the current one by 1 (north, south, east, west)
		table.remove(surrounding, table.find(surrounding,_tile)) -- Refer to the TileModule file
		-- a function that loops through all the tiles surrounding in the grid
		-- since the grid is limited, we can not assume that there will always be a surrounding tile in all directions
		
		if table.find(openlist, _tile) then
			table.remove(openlist, table.find(openlist, _tile))
		end -- Remove the current tile from the search list to prevent this tile from being
		-- chosen as our current tile again. We are able to do this under the assumption that 
		-- the previous calculated path to this tile will always be the most efficient path given how this algorithm works
		table.insert(closedlist, _tile)
		
		local opentiles = {}
		for i, t in pairs(surrounding) do -- Checks the attributes of the tiles (If they're able to be walked on
			-- or if the tile is being occupied by a wall or something
			if t.Occupying.Value == nil and t:GetAttribute("Traversable") and not table.find(closedlist, t)then
				table.insert(opentiles, t)
			end
		end
		
		for _, t in pairs(opentiles) do -- Loop through the tiles surrounding the current tile
			local expecteddist = tileModule:GetTileDistance(_tile, t)
			if table.find(t:GetTags(),"Mud") then -- some tiles have a higher "cost" which makes the pathfinding algorithm 
				--prioritize them less and avoid them. 
				-- I use tags to keep track of if a tile is muddy, by the way
				expecteddist = expecteddist *2
				
			end
			if not table.find(openlist, t) then -- this is how the path is calculated.
				-- what is happening here is that the surrounding tiles are being "parented", not in the 
				-- workspace, but rather in the table.
				-- each tile has a parent which comes before it. As we continue to get the surrounding tiles
				-- we will reparent any tiles which are A. Closer to the goal and B. have a lower cost to path towards
				-- than the previous parent.
				table.insert(openlist, t)
				parentTable[t] = _tile
				if parentTable[_tile] then -- if the tile is not in the open list, we quickly compute the tile's f, g, and h values
					-- and parent it to this current tile. 
					GValueTable[t] = GValueTable[_tile] + expecteddist + GetChangeInDirection(parentTable[_tile], _tile, t)
				else
					GValueTable[t] = GValueTable[_tile] + expecteddist 
				end
				HValueTable[t] = tileModule:GetTileDistance(t, goal) 
				FValueTable[t] = GValueTable[t] + HValueTable[t]
			else
				if GValueTable[t] > GValueTable[_tile] + expecteddist then  -- here's where reparent any adjacent tiles
					-- if the tile path is more efficient. Sometimes, pathfinding can lead the wrong way, but 
					-- we are able to correct this by constantly reevaluating the path 
					parentTable[t] = _tile
					if parentTable[_tile] then
						GValueTable[t] = GValueTable[_tile] + expecteddist + GetChangeInDirection(parentTable[_tile], _tile, t)
					else
						GValueTable[t] = GValueTable[_tile] + expecteddist 
					end
					GValueTable[t] = GValueTable[_tile] + expecteddist
					HValueTable[t] = tileModule:GetTileDistance(t, goal) 
					FValueTable[t] = GValueTable[t] + HValueTable[t]
				end
			end
		end
		local lowest = math.huge
		local index = nil
		for _, t:BasePart in pairs(openlist) do -- by looking at the lowest F-value, we start our next search looking for the lowest
			-- F-value tile. This process will lead to the most efficient path
			if FValueTable[t] < lowest then
				lowest = FValueTable[t]
				index=t 
			elseif FValueTable[t] == lowest then
				if GValueTable[t] < GValueTable[index] then
					index = t
					lowest = FValueTable[t]
				end
			end	
		end
		if not index then
			return false
		end
		return recall(index, strength)
	end
	local result = recall(tile.Instance, strength)
	-- start the backtrack from the lowest f value tile. 
	if result == false then -- either we've gone through the entire openlist and found no path, or we've found the path
		return nil
	end
	local lowest = math.huge
	local index = nil
	for t:BasePart, n:number in pairs(FValueTable) do
		if n < lowest then
			lowest = n 
			index = t 
		end	
	end
	local tilepath = {}
	local function backtrack(passed) -- recursively go back in tiles until we have the final path
		if parentTable[passed] and parentTable[passed] ~= tile.Instance then
			backtrack(parentTable[passed])
		end
		table.insert(tilepath, passed)
	end
	backtrack(index)
	return tilepath 	-- return the path
end
function TurnModule:CalculatePath(model: Model, tilePath) -- returns a tilePath that is the actual limit of how far a model goes
	local posMarker = TurnModule:GetPosMarker(model) -- poss
	if tilePath and posMarker then
		local moveTiles = model:FindFirstChild("moveTiles")
		if moveTiles.Value == 0 then
			return
		end -- Simple check in case the model is out of available movement 
		local goalIndex = 1 -- start at 1 since LUA. The tile list is sorted from 1 (first tile to be walked on)
		-- to #tilepath, which is the last tile to be walked on. We increase this number until
		-- we run out of movement tiles or we reach the end
		local totalTiles = moveTiles.Value
		for i, v in pairs(tilePath) do
			if totalTiles > 0 then  -- check if we need to keep going. End if we don't
				local tags = CollectionService:GetTags(v)
				if table.find(tags, "Mud") then
					if totalTiles > 1 then
						totalTiles = totalTiles - 2
					else -- If the next tile is mud, we need to take two steps to get there
						-- so this index thing corrects the overshoot.
						-- If it doens't make sense, I relate.
						-- Somehow this fixes the issue of overshooting
						goalIndex -= 1 
						break
					end
				else
					-- We detrack from the total movement we have
					totalTiles = totalTiles - 1
				end
			else
				break
			end
			goalIndex = i -- sset the new goal index
		end
		for index = #tilePath, goalIndex+1, -1 do  -- remove tiles according to maximum pathlength
			table.remove(tilePath, index)
		end
		return tilePath
	end
end
-- Move the model along the path by tweening the model's primary part's cframe
function TurnModule:TweenModelPosition(model:Model, tile, speed)	
	local easingstyle = Enum.EasingStyle.Linear
	if speed > 1 then
		speed = math.clamp(speed, 1, 2)
	end
	local offset = model.PrimaryPart.Position.Y- tile.Position.Y
	-- offset keeps the model from phasing into the tile
	model.PrimaryPart.CFrame= CFrame.lookAt(model.PrimaryPart.Position, tile.Position +Vector3.new(0,offset,0)) 
	local tween = TweenService:Create(model.PrimaryPart,TweenInfo.new(speed, easingstyle, Enum.EasingDirection.Out),
		{CFrame = CFrame.new(tile.Position + Vector3.new(0,offset,0)) *model.PrimaryPart.CFrame.Rotation})
	return tween
end
-- rotate the model if there's a turn in the path
function TurnModule:FaceTile(model,tile)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = CollectionService:GetTagged(9069336078)
	params.FilterType= Enum.RaycastFilterType.Include
	local standing = workspace:Raycast(model.PrimaryPart.Position+Vector3.new(0,2,0), Vector3.new(0,-25,0), params).Instance
	
	local extradist = model.PrimaryPart.Position - tile.Position
	local extravector = Vector3.new(extradist.X, 0, extradist.Z) * Vector3.new(0.2,0,0.2)
	local offset =model.PrimaryPart.Position-standing.Position
	return TweenService:Create(model.PrimaryPart, TweenInfo.new(0.2,Enum.EasingStyle.Linear),
		{CFrame = CFrame.lookAt(model.PrimaryPart.Position, tile.Position+offset-extravector)})
end
-- This is the function that loops through the above two functions 
-- Organizes the code. Also, since movement is limited, it will check the path using the function 
-- below this one and only move up until the valid amount of tiles have been reached
function TurnModule:MoveModel(model:Model, tilePath)
	if tilePath then
		if model.Moving.Value then return end
		local moveTiles = model:FindFirstChild("moveTiles")
		if moveTiles.Value == 0 then
			return 1
		end

		local posMarker:Part= TurnModule:GetPosMarker(model)		
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = CollectionService:GetTagged(9069336078)
		params.FilterType = Enum.RaycastFilterType.Include
		local inittile = workspace:Raycast(TurnModule:GetPosMarker(model).Position+Vector3.new(0,2,0), Vector3.new(0, -1000, 0), params)

		if posMarker then
			local newPath = TurnModule:CalculatePath(model, tilePath)
			local GoalIndex = 0
			print(tilePath)
			for i, t in pairs(newPath) do
				if t.Occupying.Value == nil and t:GetAttribute("Traversable") then
					GoalIndex = i
				else
					break
				end
			end
			if GoalIndex == 0 then
				return 2
			else
				for index = #newPath, GoalIndex+1, -1 do 
					table.remove(newPath, index)
				end
			end
			if newPath == nil or not newPath[1] then return 3 end
			posMarker.Position = newPath[#newPath].Position
			tileModule:CheckOccupying()
		end
	
		local request:RemoteEvent = model:FindFirstChild("ServerRequestRemote")
		local human:Humanoid = model:FindFirstChild("Humanoid")
		human:SetAttribute("OriginalWalkSpeed", 16)
		model:FindFirstChild("Moving").Value = true
		
		if human then			
			for i, v in pairs(tilePath) do
				if moveTiles.Value > 0 then
					local tags =CollectionService:GetTags(v)
					if table.find(tags, "Mud") then
						if moveTiles.Value  > 1 then
							human.WalkSpeed = 8
							moveTiles.Value -= 1
						end
					else
						human.WalkSpeed = human:GetAttribute("OriginalWalkSpeed")
					end
					moveTiles.Value -= 1
				else -- add a check for each update in position to get what can be seen or cannot be seen
					break
				end

				if tilePath[i-2] and tilePath[i-1] then
					if GetChangeInDirection(tilePath[i-2], tilePath[i-1],v) == 1 then
						local ft = TurnModule:FaceTile(model, v)
						ft:Play()
						ft.Completed:Wait()
					end
				elseif tilePath[i-2] == nil and tilePath[i-1] ~= nil then
					print(tilePath[i-2], tilePath[i-1], v)
					if GetChangeInDirection(inittile.Instance, tilePath[i-1],v) == 1 then
						local ft = TurnModule:FaceTile(model, v)
						ft:Play()
						ft.Completed:Wait()
					end
				end 
				local tween:Tween= self:TweenModelPosition(model, v, (.7/(human.WalkSpeed/10)))
				tween:Play()
				tween.Completed:Wait()
			end
			model:FindFirstChild("Moving").Value = false
		end
	end
end

-- auxilary function, shortens the amount of repeating lines
function TurnModule:GetPosMarker(model)
	local posMarkers = CollectionService:GetTagged(tostring(4745937528))
	local marker;
	for index = 1, #posMarkers do 
		if posMarkers[index].parent.Value == model then
			marker = posMarkers[index]
		end
	end
	return marker
end

-- auxilary, just to show the updating path for testing
function TurnModule:DrawPath(model, tilePath)
	if tilePath then
		if not tilePath[1] then
			return 
		end
		tilePath = TurnModule:CalculatePath(model, tilePath)
		if tilePath == nil or not tilePath[1] then
			local folder = game.Workspace:FindFirstChild("arrowFolder")
			if folder then
				folder:Destroy()
			end
			return
		end
		local color = Color3.new(0,.5,0)
		if #tilePath > model:FindFirstChild("moveTiles").Value then
			color = Color3.new(.75,0,0)
		end
		local folder = game.Workspace:FindFirstChild("arrowFolder")

		if folder then
			folder:Destroy()
		end

		local folder = Instance.new("Folder", workspace)
		folder.Name = "arrowFolder"
		game:GetService("Debris"):AddItem(folder, .6)
		local size =  tilePath[1].Size
		local arrowModel = Instance.new("Model",folder)
		local arrowConnection = Instance.new("Part", arrowModel)
		arrowConnection.CanCollide = false
		arrowConnection.CanQuery = false
		arrowConnection.CanTouch= false
		arrowConnection.Anchored = true
		arrowConnection.Size = Vector3.new(1, 3, size.Z)
		arrowConnection.Color = color
		arrowConnection.Material = Enum.Material.Neon
		local part = Instance.new("Part", arrowModel)
		part.Anchored = true
		part.Size = Vector3.new(1,1,1)
		part.CanQuery = false
		part.CanCollide =false
		part.CanTouch = false
		arrowModel.PrimaryPart = part
		local params:RaycastParams = RaycastParams.new()
		params.FilterDescendantsInstances = CollectionService:GetTagged(9069336078)
		params.FilterType = Enum.RaycastFilterType.Include
		local mark;
		local marks = CollectionService:GetTagged(4745937528)
		for index = 1, #marks do
			if marks[index].parent.Value == model then
				mark = marks[index]
			end
		end
		local found:RaycastResult = workspace:Raycast(mark.Position+Vector3.new(0,3,0), Vector3.new(0,-10,0), params)
		local goalVector = (tilePath[1].Position - found.Instance.Position) * Vector3.new(0.5, 0, 0.5)
		arrowModel:PivotTo(CFrame.lookAt(found.Position +goalVector , tilePath[1].Position))

		for index = 1, #tilePath -1 do
			local arrowModel = Instance.new("Model",folder)
			local arrowConnection = Instance.new("Part", arrowModel)
			arrowConnection.CanCollide = false
			arrowConnection.CanQuery = false
			arrowConnection.CanTouch= false
			arrowConnection.Anchored = true
			arrowConnection.Size = Vector3.new(1, 3, size.Z)
			arrowConnection.Color =color
			arrowConnection.Material = Enum.Material.Neon
			local part = Instance.new("Part", arrowModel)
			part.Anchored = true
			part.Size = Vector3.new(1,1,1)
			part.CanQuery = false
			part.CanCollide =false
			part.CanTouch = false
			arrowModel.PrimaryPart = part
			local goalVector = (tilePath[index+1].Position - tilePath[index].Position) * Vector3.new(0.5, 0, 0.5)
			arrowModel:PivotTo(CFrame.lookAt(tilePath[index].Position +goalVector, tilePath[index+1].Position))

		end
		local sphere = Instance.new("Part", folder)
		sphere.Anchored = true
		sphere.Size = Vector3.new(4,4,4)
		sphere.CanQuery = false
		sphere.CanCollide =false
		sphere.CanTouch = false
		sphere.Color = color
		sphere.Shape = Enum.PartType.Ball
		sphere.Material = Enum.Material.Neon
		sphere.Position = tilePath[#tilePath].Position
		sphere.Transparency = .25
		sphere.Name = "sphere"
		
	end
end

return TurnModule
