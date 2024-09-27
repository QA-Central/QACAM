--!strict

type WrapperConfiguration = {
	allowed_roles: {
		[string]: {
			allow_at: number
		}
	},
	allowed_group_roles: { number },
	host: string,
	access_denied_message: string
}

local HttpService = game:GetService("HttpService")
local validators = require(script:WaitForChild("Validators"))

local module = {
	configuration = {
		roles = {
			defaults = {
				ALL_DEFAULTS = {
					"1070596691503366225",
					"975055474074468422",
					"979068617381535844"
				},
				ORGANIZERS = "1070596691503366225",
				ADMINS = "975055474074468422",
				QA_LEAD = "979068617381535844"
			}
		}
	}
}
local wrapper: WrapperConfiguration = {
	allowed_roles = {},
	allowed_group_roles = {
		255
	},
	host = "https://api.qacentral.org",
	access_denied_message = "No access"
}

type APIAccessResult = {
	value: boolean,
	message: string,
	matchedRoles: { number }
}

function module.configuration:SetAccessDeniedMessage(message: string)
	if typeof(message) ~= "string" then
		error("Access denied message must be a string")
	end
	
	wrapper.access_denied_message = message
end

function module.configuration:AllowRoles(roles: { string }, unix_epoch: number?)
	-- Ensure that all IDs are strings
	
	validators:ValidateIDs(roles)
	
	local epoch = -1 -- Always
	
	if unix_epoch then
		if typeof(unix_epoch) ~= "number" or math.floor(unix_epoch) ~= unix_epoch then
			error("Unix epoch must be an integer")
		end
		
		if unix_epoch < 0 then
			error("Unix epoch cannot be negative")
		end
		
		epoch = unix_epoch
	end
	
	-- Push all roles IDs to the allowed roles array
	
	for i, id in pairs(roles) do
		-- Update already allowed IDs
		
		local foundID = wrapper.allowed_roles[id]
		
		if foundID then
			foundID.allow_at = epoch
			
			continue
		end
		
		-- Add role to array
		
		wrapper.allowed_roles[id] = {
			allow_at = epoch
		}
	end
end

function module.configuration:DisallowRoles(roles: { string })
	-- Ensure that all IDs are strings
	
	validators:ValidateIDs(roles)
	
	for i, id in pairs(roles) do
		local foundID = wrapper.allowed_roles[id]
		
		if foundID then
			wrapper.allowed_roles[id] = nil
		end
	end
end

function module.configuration:AllowGroupRoles(roles: { number })	
	-- Ensure that all IDs are numbers in the range 0-255
	
	validators:ValidateGroupIDs(roles)
	
	for i, id in pairs(roles) do
		if table.find(wrapper.allowed_group_roles, id) then
			continue
		end
		
		table.insert(wrapper.allowed_group_roles, id)
	end
end

function module.configuration:DisallowGroupRoles(roles: { number })	
	-- Ensure that all IDs are numbers in the range 0-255
	
	validators:ValidateGroupIDs(roles)
	
	for i, id in pairs(roles) do
		local foundID = table.find(wrapper.allowed_group_roles, id)
		
		if foundID then
			table.remove(wrapper.allowed_group_roles, id)
		end
	end
end

function module:GetAccessForPlayer(Player: Player): APIAccessResult
	-- Check if the player is allowed to join because they have an allowed group role or if they are the owner of the game
	
	if game.CreatorType == Enum.CreatorType.Group then
		local groupId = game.CreatorId
		
		if Player:IsInGroup(groupId) then
			if table.find(wrapper.allowed_group_roles, Player:GetRankInGroup(groupId)) then
				return {
					value = true,
					message = "",
					matchedRoles = {}
				}
			end
		end
	else		
		-- The game is owned by a user
		
		if Player.UserId == game.CreatorId then
			return {
				value = true,
				message = "",
				matchedRoles = {}
			}
		end
	end
	
	-- Generate a query string from the allowed roles array
	
	local allowedRoles = wrapper.allowed_roles
	local query = ""
	
	for id, _ in pairs(allowedRoles) do		
		if query == "" then
			query = `roleIds={id}`
		else
			query = `{query}&roleIds={id}`
		end
	end
	
	-- Check if at least one role is allowed
	-- query will be an empty string if no role is allowed because the for loop above will iterate 0 times hence leaving it to its initial value
	
	if query == "" then
		return {
			value = false,
			message = wrapper.access_denied_message,
			matchedRoles = {}
		}
	end
	
	local success, res = pcall(function()
		return HttpService:RequestAsync({
			Url = `{wrapper.host}/v1/game-access/{Player.UserId}?{query}`,
			Method = "GET"
		})
	end)
	
	if not success then
		warn(res)
		
		return {
			value = false,
			message = "Unable to verify access",
			matchedRoles = {}
		}
	end

	if not res.Success then
		warn(`Access query failed with status code {res.StatusCode}`)
		warn(HttpService:JSONDecode(res.Body))
		
		return {
			value = false,
			message = "Unable to verify access",
			matchedRoles = {}
		}
	end

	local body = HttpService:JSONDecode(res.Body)
	local matchedRoles = body.matchedRoles
	local message = ""
	
	-- Check if the player has meets at least one requirement
	
	if not body.meetsRequirement then
		message = wrapper.access_denied_message
	else		
		-- Check if the user is allowed to join based on the time
		
		local unscheduledRoles = 0
		local scheduledRoles = {}
		
		-- Count all matched unscheduled roles and push all the scheduled ones into the scheduledRoles array
		
		for i, id in pairs(matchedRoles) do
			-- allow_at will be greater than -1 if the role was scheduled
			
			if wrapper.allowed_roles[id].allow_at > -1 then
				table.insert(scheduledRoles, wrapper.allowed_roles[id])
			else
				unscheduledRoles += 1
			end
		end
		
		-- If the player has at least one unscheduled role let them join right away
		
		if unscheduledRoles > 0 then
			return {
				value = true,
				message = "",
				matchedRoles = matchedRoles
			}
		else
			-- Allow the player to join at the closest time
			-- Sort in ascending order
			
			table.sort(scheduledRoles, function(a, b)
				return a.allow_at < b.allow_at
			end)
			
			local smallestTimeRole = scheduledRoles[1]
			
			if os.time() >= smallestTimeRole.allow_at then
				return {
					value = true,
					message = "",
					matchedRoles = matchedRoles
				}
			else
				return {
					value = false,
					message = `You are not allowed to join yet, please try again on {os.date("%x at %H:%M", smallestTimeRole.allow_at)}.`,
					matchedRoles = matchedRoles
				}
			end
		end
	end
	
	-- Return false because it means that the player does not have any matching role
	
	return {
		value = false,
		message = message,
		matchedRoles = matchedRoles
	}
end

return module