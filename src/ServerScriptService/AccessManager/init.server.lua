--!strict

local API = require(game:GetService("ServerStorage").QACentralAccessManager)

API.configuration:AllowRoles(API.configuration.roles.defaults.ALL_DEFAULTS)
-- API.configuration:AllowRoles({API.configuration.roles.defaults.QA_LEAD}, 1706973754 + 10000)
API.configuration:SetAccessDeniedMessage("You do not have permission to join this game")

game:GetService("Players").PlayerAdded:Connect(function(Player)
	local AccessResult = API:GetAccessForPlayer(Player)
	
	if not AccessResult.value then
		Player:Kick(AccessResult.message)
	end
end)