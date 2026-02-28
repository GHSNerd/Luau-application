local tileModule = {}
--//SERVICES//--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Tile = require(script.Tile)
--//VARIABLES//--
local tileDim:Vector3 = game.Workspace.Playfield_Swamp:WaitForChild("tile_base2"):WaitForChild("Base_code").Size


local presets = {} -- premade tile modules
for i, v in pairs(script.Tile:GetChildren()) do
	presets[v.Name] = require(v)
end


function tileModule:CheckOccupying(array) -- to prevent overlapping tile movements
	if array then
		local tiles = array
		local hitboxFolder = Instance.new("Folder")
		hitboxFolder.Parent=game.Workspace

		local hitbox = Instance.new("Part")
		hitbox.Size = Vector3.new(tileDim.Z,5,tileDim.Z)
		hitbox.Name = "hitbox"
		hitbox.CanCollide = false
		hitbox.CanQuery = false
		hitbox.CanTouch = false
		hitbox.Anchored = true
		hitbox.CastShadow = false
		hitbox.Massless = true
		hitbox.Transparency = 0.5
		hitbox.Parent = hitboxFolder
		hitbox.Material = Enum.Material.ForceField
		local returnTable = {}
		for index = 1, #tiles do 
			local hitboxClone = hitbox:Clone()
			hitboxClone.Parent = hitboxFolder
			hitboxClone.Position = tiles[index].Position + Vector3.new(0,hitbox.Size.Y/2, 0) - Vector3.new(0,1,0)

			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params:AddToFilter(tiles)
			local firstTable = workspace:GetPartsInPart(hitbox, params)
			for i,v in pairs(firstTable) do
				if not table.find(returnTable, v.parent.Value) then
					if v.Name == "PosMarker" then
						table.insert(returnTable, v.parent.Value)
					end
				end
			end
		end
		hitboxFolder:Destroy()
		return returnTable
	else
		local destroy = CollectionService:GetTagged("2902487912")
		for i, v in pairs(destroy) do
			v:Destroy()
		end

		local tiles = CollectionService:GetTagged(9069336078)
		for i, v in pairs(tiles) do
			v:FindFirstChild("Occupying").Value = nil
		end

		local hitboxFolder = Instance.new("Folder")
		hitboxFolder.Parent=game.Workspace
		local markers=  workspace.PosMarkers:GetChildren()
		for _, marker:BasePart in pairs(markers)do
			if marker.CanQuery == false then continue end


			local hitTable = {}
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = tiles
			params.FilterType = Enum.RaycastFilterType.Include

			local tile = workspace:Raycast(marker.Position+Vector3.new(0,1,0),Vector3.new(0,-20,0), params)
			if tile then
				tile = tile.Instance
				if not table.find(hitTable, marker.parent.Value) then
					table.insert(hitTable, marker.parent.Value)
					tile:FindFirstChild("Occupying").Value = marker.parent.Value 
					local part = Instance.new("Part")
					part.Size = tileDim + Vector3.new(-1,5,-1)
					part.Position = marker.Position + Vector3.new(0,part.Size.Y/2+0, 0)
					part.Name = "occupancy"
					part.CanCollide = false
					part.CanQuery = true
					part.CanTouch = false
					part.Anchored = true
					part.CastShadow = false
					part.Massless = true
					part.Transparency = 1
					part.Parent = tile.Parent
					part.Color = Color3.new(1,0,0)
					CollectionService:AddTag(part, "2902487912")
					--ONLY CHECKS FOR HUMANOIDS RN, WE NEED TO ADD A CHECK FOR HAZARD PARTS
				end
			end
		end
	end
end

-- creates the map 
function tileModule:GenerateMap(TwoDArrayList:{{[number]: string}}, SpawnCoords)--Pass a two dimensional list with the x and y values being coordinates to pass 
	local folder=  Instance.new("Folder")
	folder.Parent = game.Workspace.Playfield_Swamp
	folder.Name = "SpecialTiles"
	--spawn coords should also be a table with indexes 1, 2, 3, and 4. Each index has a list with {x, y}
	for y, v in pairs(TwoDArrayList) do
		--{{}} [1][1]
		for x, tileInfo:string in pairs(v) do --tileinfo should be a string
			if tileInfo == "" then continue end -- since lua tables start at 1 instead of 0, subtract 1 from the index
			if script.Tile:FindFirstChild(tileInfo) then
				local newTile = presets[tileInfo].new(x-1, y-1)
			end
		end
	end

	for i, v in pairs(SpawnCoords) do
		local hit = tileModule:GetGridCoordinate(v[1], v[2])
		if hit then
			hit.Parent.Parent = folder
			hit.Parent.Name = "Spawn" .. i
		end
	end
end

function tileModule:GetTileCoordinate(tile:BasePart)--returns the x,y coordinate of the tile starting from 0,0
	local Origin = game.Workspace.Playfield_Swamp.Origin.Value
	local x = math.round((tile.Position.X - Origin.Position.X)/tile.Size.Z)
	local y = math.round(-(tile.Position.Z - Origin.Position.Z)/tile.Size.Z)
	return x, y
end
function tileModule:GetGridCoordinate(x:number, y:number)
	local Origin = game.Workspace.Playfield_Swamp.Origin.Value
	local params =RaycastParams.new()
	params.FilterDescendantsInstances = CollectionService:GetTagged(9069336078)
	params.FilterType= Enum.RaycastFilterType.Include
	local result= workspace:Raycast(Origin.Position + Vector3.new(x*Origin.Size.X, 20,-y*Origin.Size.X), Vector3.new(0,-1000,0), params)
	if result then
		return result.Instance
	else
		return nil
	end
end
function tileModule:GetTileFromVector(v3:Vector3)
	local params =RaycastParams.new()
	params.FilterDescendantsInstances = CollectionService:GetTagged(9069336078)
	params.FilterType= Enum.RaycastFilterType.Include
	local result= workspace:Raycast(v3 + Vector3.new(0,2,0), Vector3.new(0,-1000,0), params)
	if result then
		return result.Instance
	else
		return nil
	end
end
function tileModule:GetTileDistance(tile1, tile2) -- returns how many tiles of movement between two tiles
	local xDistance = math.abs((tile1.Position.X - tile2.Position.X) / tile1.Size.X)
	local zDistance = math.abs((tile1.Position.Z - tile2.Position.Z) / tile1.Size.Z)

	return math.round(xDistance + zDistance)
end
--//works for both server and client
function tileModule:getTilesWithinRange(passed:Vector3, range:number, key, PartMark)
	if passed then
		local i = range
		local params = RaycastParams.new()
		local gridList = {}
		params.FilterDescendantsInstances = CollectionService:GetTagged(tostring(9069336078))
		params.FilterType = Enum.RaycastFilterType.Include
		params.IgnoreWater = true
		local selftile = workspace:Raycast(passed, Vector3.new(0,-20,0), params)
		if selftile then
			table.insert(gridList,selftile.Instance)
		end
		while i > 0 do 
			local j = 0
			local k = i
			
			while j < i do
				local destination = passed + Vector3.new(-k*tileDim.Z,0,-j*tileDim.Z)
				local hit = workspace:Raycast(destination, Vector3.new(0,-20,0), params)
				if hit then
					table.insert(gridList, hit.Instance)
				end
				j += 1
				k -= 1
			end
			while k < i do
				local destination = passed + Vector3.new(k*tileDim.Z,0,-j*tileDim.Z)
				local hit = workspace:Raycast(destination, Vector3.new(0,-20,0), params)
				if hit then
					table.insert(gridList, hit.Instance)
				end
				j -= 1 
				k += 1
			end
			while j < i  do
				local destination = passed + Vector3.new(k*tileDim.Z,0,j*tileDim.Z)
				local hit = workspace:Raycast(destination, Vector3.new(0,-20,0), params)
				if hit then
					table.insert(gridList, hit.Instance)
				end
				j += 1
				k -= 1
			end
			while k < i do
				local destination = passed + Vector3.new(-k*tileDim.Z,0,j*tileDim.Z)
				local hit = workspace:Raycast(destination, Vector3.new(0,-20,0), params)
				if hit then
					table.insert(gridList, hit.Instance)
				end
				j -= 1
				k += 1
			end
			i -= 1
		end
		return gridList
	end
end
return tileModule
