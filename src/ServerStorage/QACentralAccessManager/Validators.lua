local module = {}

local function ValidateArray(input: { any })
	local typeOfInput = typeof(input)
	
	if typeOfInput ~= "table" then
		error(`Table of {typeOfInput} expected`)
	end
end

function module:ValidateIDs(roles: { string })
	ValidateArray(roles)
	
	-- Check if all IDs are strings

	for i, id in pairs(roles) do		
		if typeof(id) ~= "string" then
			error(`{id} is not a valid ID`)
		end
	end
end

function module:ValidateGroupIDs(roles: { number })
	if game.CreatorType ~= Enum.CreatorType.Group then
		error("The game is not owned by a group")
	end
	
	ValidateArray(roles)
	
	-- Check if all IDs are numbers and in the range 0-255
	
	for i, id in pairs(roles) do
		if typeof(id) ~= "number" then
			error(`{id} is not a valid group ID`)
		end
		
		if not (id >= 0 and id <= 255) then
			error(`{id} is out of range`)
		end
	end
end

return module