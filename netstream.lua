--[[
	NetStream - 1.0.2

	Alexander Grist-Hucker
	http://www.revotech.org
	
	Credits to:
		Alexandru-Mihai Maftei aka Vercas for vON.
		https://github.com/vercas/vON
--]]


local type, error, pcall, pairs, AddCSLuaFile, _player = type, error, pcall, pairs, AddCSLuaFile, player;

--[[
	AddCSLuaFile("includes/modules/von.lua");
	require("von");
--]]

if (!von) then
	error("NetStream: Unable to find vON!");
end;

AddCSLuaFile();

netstream = {};

local stored = {};

-- A function to split data for a data stream.
local function split(data)
	local index = 1;
	local result = {};
	local buffer = {};

	for i = 0, string.len(data) do
		buffer[#buffer + 1] = string.sub(data, i, i);
				
		if (#buffer == 32768) then
			result[#result + 1] = table.concat(buffer);
				index = index + 1;
			buffer = {};
		end;
	end;
			
	result[#result + 1] = table.concat(buffer);
	
	return result;
end;

-- A function to hook a data stream.
function netstream.Hook(name, Callback)
	stored[name] = Callback;
end;

if (SERVER) then
	util.AddNetworkString("NetStreamDS");

	-- A function to start a net stream.
	function netstream.Start(player, name, data)
		local recipients = {};
		local bShouldSend = false;
	
		if (type(player) != "table") then
			if (!player) then
				player = _player.GetAll();
			else
				player = {player};
			end;
		end;
		
		for k, v in pairs(player) do
			if (type(v) == "Player") then
				recipients[#recipients + 1] = v;
				
				bShouldSend = true;
			elseif (type(k) == "Player") then
				recipients[#recipients + 1] = k;
			
				bShouldSend = true;
			end;
		end;
		
		local dataTable = {data = (data or 0)};
		local vonData = von.serialize(dataTable);
			
		if (vonData and #vonData > 0 and bShouldSend) then
			net.Start("NetStreamDS");
				net.WriteString(name);
				net.WriteUInt(#vonData, 32);
				net.WriteData(vonData, #vonData);
			net.Send(recipients);
		end;
	end;
	
	net.Receive("NetStreamDS", function(length, player)
		local NS_DS_NAME = net.ReadString();
		local NS_DS_LENGTH = net.ReadUInt(32);
		local NS_DS_DATA = net.ReadData(NS_DS_LENGTH);
		
		if (NS_DS_NAME and NS_DS_DATA and NS_DS_LENGTH) then
			player.nsDataStreamName = NS_DS_NAME;
			player.nsDataStreamData = "";
			
			if (player.nsDataStreamName and player.nsDataStreamData) then
				player.nsDataStreamData = NS_DS_DATA;
								
				if (stored[player.nsDataStreamName]) then
					local bStatus, value = pcall(von.deserialize, player.nsDataStreamData);
					
					if (bStatus) then
						stored[player.nsDataStreamName](player, value.data);
					else
						ErrorNoHalt("NetStream: '"..NS_DS_NAME.."'\n"..value.."\n");
					end;
				end;
				
				player.nsDataStreamName = nil;
				player.nsDataStreamData = nil;
			end;
		end;
		
		NS_DS_NAME, NS_DS_DATA, NS_DS_LENGTH = nil, nil, nil;
	end);
else
	-- A function to start a net stream.
	function netstream.Start(name, data)
		local dataTable = {data = (data or 0)};
		local vonData = von.serialize(dataTable);
		
		if (vonData and #vonData > 0) then
			net.Start("NetStreamDS");
				net.WriteString(name);
				net.WriteUInt(#vonData, 32);
				net.WriteData(vonData, #vonData);
			net.SendToServer();
		end;
	end;
	
	net.Receive("NetStreamDS", function(length)
		local NS_DS_NAME = net.ReadString();
		local NS_DS_LENGTH = net.ReadUInt(32);
		local NS_DS_DATA = net.ReadData(NS_DS_LENGTH);
		
		if (NS_DS_NAME and NS_DS_DATA and NS_DS_LENGTH) then
			if (stored[NS_DS_NAME]) then
				local bStatus, value = pcall(von.deserialize, NS_DS_DATA);
			
				if (bStatus) then
					stored[NS_DS_NAME](value.data);
				else
					ErrorNoHalt("NetStream: '"..NS_DS_NAME.."'\n"..value.."\n");
				end;
			end;
		end;
		
		NS_DS_NAME, NS_DS_DATA, NS_DS_LENGTH = nil, nil, nil;
	end);
end;