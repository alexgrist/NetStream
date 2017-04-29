--[[
	NetStream - 2.1.0

	Alexander Grist-Hucker
	http://www.revotech.org
	
	Credits to:
		thelastpenguin for pON.
		https://github.com/thelastpenguin/gLUA-Library/tree/master/pON
--]]


local type, error, pcall, pairs, _player = type, error, pcall, pairs, player;

if (!pon) then
	error("NetStream: Unable to find pON!");
end;

AddCSLuaFile();

netstream = netstream or {};

local stored = netstream.stored or {};
netstream.stored = stored;

local cache = netstream.cache or {};
netstream.cache = cache;

-- A function to split data for a data stream.
function netstream.Split(data)
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

-- A function to hook a net stream.
function netstream.Hook(name, Callback)
	stored[name] = Callback;
end;

if (SERVER) then
	util.AddNetworkString("NetStreamDS");
	util.AddNetworkString("NetStreamHeavy");

	-- A function to start a net stream.
	function netstream.Start(player, name, ...)
		local recipients = {};
		local bShouldSend = false;

		if (!istable(player)) then
			if (!IsValid(player)) then
				player = _player.GetAll();
			else
				player = {player};
			end;
		end;

		for k, v in ipairs(player) do
			if (type(v) == "Player") then
				recipients[#recipients + 1] = v;

				bShouldSend = true;
			end;
		end;

		local encodedData = pon.encode({...});

		if (encodedData and #encodedData > 0 and bShouldSend) then
			net.Start("NetStreamDS");
				net.WriteString(name);
				net.WriteUInt(#encodedData, 32);
				net.WriteData(encodedData, #encodedData);
			net.Send(recipients);
		end;
	end;

	-- A function to start a > 64KB net stream.
	function netstream.Heavy(player, name, ...)
		local recipients = {};
		local bShouldSend = false;

		if (!istable(player)) then
			if (!IsValid(player)) then
				player = _player.GetAll();
			else
				player = {player};
			end;
		end;

		for k, v in ipairs(player) do
			if (type(v) == "Player") then
				recipients[#recipients + 1] = v;

				bShouldSend = true;
			end;
		end;

		local encodedData = pon.encode({...});
		local split = netstream.Split(encodedData);

		if (encodedData and #encodedData > 0 and bShouldSend) then
			for k, v in ipairs(split) do
				net.Start("NetStreamHeavy");
					net.WriteString(name);
					net.WriteUInt(#v, 32);
					net.WriteData(v, #v);
					net.WriteUInt(k, 8);
					net.WriteUInt(#split, 8);
				net.Send(recipients);
			end;
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
					local bStatus, value = pcall(pon.decode, player.nsDataStreamData);

					if (bStatus) then
						stored[player.nsDataStreamName](player, unpack(value));
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

	net.Receive("NetStreamHeavy", function(length, player)
		local NS_DS_NAME = net.ReadString();
		local NS_DS_LENGTH = net.ReadUInt(32);
		local NS_DS_DATA = net.ReadData(NS_DS_LENGTH);
		local NS_DS_PIECE = net.ReadUInt(8);
		local NS_DS_TOTAL = net.ReadUInt(8);

		if (NS_DS_NAME and NS_DS_DATA and NS_DS_LENGTH) then
			player.nsDataStreamName = NS_DS_NAME;
			player.nsDataStreamData = "";

			if (!cache[player.nsDataStreamName]) then
				cache[player.nsDataStreamName] = "";
			end;

			if (player.nsDataStreamName and player.nsDataStreamData) then
				player.nsDataStreamData = NS_DS_DATA;

				if (NS_DS_PIECE < NS_DS_TOTAL) then
					if (NS_DS_PIECE == 1) then
						cache[player.nsDataStreamName] = "";
					end;

					cache[player.nsDataStreamName] = cache[player.nsDataStreamName]..player.nsDataStreamData;
				else
					cache[player.nsDataStreamName] = cache[player.nsDataStreamName]..player.nsDataStreamData;

					if (stored[player.nsDataStreamName]) then
						local bStatus, value = pcall(pon.decode, cache[player.nsDataStreamName]);

						if (bStatus) then
							stored[player.nsDataStreamName](player, unpack(value));
						else
							ErrorNoHalt("NetStream: '"..NS_DS_NAME.."'\n"..value.."\n");
						end;
					end;

					cache[player.nsDataStreamName] = nil;
					player.nsDataStreamName = nil;
					player.nsDataStreamData = nil;
				end;
			end;
		end;

		NS_DS_NAME, NS_DS_DATA, NS_DS_LENGTH, NS_DS_PIECE, NS_DS_TOTAL = nil, nil, nil, nil, nil;
	end);
else
	-- A function to start a net stream.
	function netstream.Start(name, ...)
		local encodedData = pon.encode({...});

		if (encodedData and #encodedData > 0) then
			net.Start("NetStreamDS");
				net.WriteString(name);
				net.WriteUInt(#encodedData, 32);
				net.WriteData(encodedData, #encodedData);
			net.SendToServer();
		end;
	end;

	-- A function to start a >64KB net stream.
	function netstream.Heavy(name, ...)
		local dataTable = {...};
		local encodedData = pon.encode(dataTable);
		local split = netstream.Split(encodedData);

		if (encodedData and #encodedData > 0) then
			for k, v in ipairs(split) do
				net.Start("NetStreamHeavy");
					net.WriteString(name);
					net.WriteUInt(#v, 32);
					net.WriteData(v, #v);
					net.WriteUInt(k, 8);
					net.WriteUInt(#split, 8);
				net.SendToServer();
			end;
		end;
	end;

	net.Receive("NetStreamDS", function(length)
		local NS_DS_NAME = net.ReadString();
		local NS_DS_LENGTH = net.ReadUInt(32);
		local NS_DS_DATA = net.ReadData(NS_DS_LENGTH);

		if (NS_DS_NAME and NS_DS_DATA and NS_DS_LENGTH) then
			if (stored[NS_DS_NAME]) then
				local bStatus, value = pcall(pon.decode, NS_DS_DATA);

				if (bStatus) then
					stored[NS_DS_NAME](unpack(value));
				else
					ErrorNoHalt("NetStream: '"..NS_DS_NAME.."'\n"..value.."\n");
				end;
			end;
		end;

		NS_DS_NAME, NS_DS_DATA, NS_DS_LENGTH = nil, nil, nil;
	end);

	net.Receive("NetStreamHeavy", function(length)
		local NS_DS_NAME = net.ReadString();
		local NS_DS_LENGTH = net.ReadUInt(32);
		local NS_DS_DATA = net.ReadData(NS_DS_LENGTH);
		local NS_DS_PIECE = net.ReadUInt(8);
		local NS_DS_TOTAL = net.ReadUInt(8);

		if (!cache[NS_DS_NAME]) then
			cache[NS_DS_NAME] = "";
		end;

		if (NS_DS_NAME and NS_DS_DATA and NS_DS_LENGTH) then
			if (NS_DS_PIECE < NS_DS_TOTAL) then
				if (NS_DS_PIECE == 1) then
					cache[NS_DS_NAME] = "";
				end;

				cache[NS_DS_NAME] = cache[NS_DS_NAME]..NS_DS_DATA;
			else
				cache[NS_DS_NAME] = cache[NS_DS_NAME]..NS_DS_DATA;

				if (stored[NS_DS_NAME]) then
					local bStatus, value = pcall(pon.decode, cache[NS_DS_NAME]);

					if (bStatus) then
						stored[NS_DS_NAME](unpack(value));
					else
						ErrorNoHalt("NetStream Heavy: '"..NS_DS_NAME.."'\n"..value.."\n");
					end;

					cache[NS_DS_NAME] = nil;
				end;
			end;
		end;

		NS_DS_NAME, NS_DS_DATA, NS_DS_LENGTH, NS_DS_PIECE, NS_DS_TOTAL = nil, nil, nil, nil, nil;
	end);
end;
