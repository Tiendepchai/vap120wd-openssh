local ec_char = {}
function is_special_char(c)
	if c == ">"
	or c == "<"
	or c == "&"
	or c == "\'" 
	or c == "\""
	then
		return true
	else 
		return false
	end
end

function convert_special_char(c)
	if c == ">" then
		return "&gt;"
	elseif c == "<" then
		return "&lt;"
	elseif c == "&" then
		return "&amp;"
	elseif c == "\'" then
		return "&#39;"
	elseif c == "\"" then
		return "&quot;"
	end
end

function ec_char.escape_string_data(data)
	local escape_data = {}
	if data and #data > 0 then
		-- nixio.syslog("debug", "[fanwar] escape string "..data)
		for i = 1, #data do
			local c = data:sub(i,i)
			if is_special_char(c) then
				-- nixio.syslog("debug", "[fanwar] ascii number = "..string.byte(c))
				table.insert(escape_data, convert_special_char(c))
			else
				table.insert(escape_data, c)
			end
		end
	else 
		return ""
	end
	-- nixio.syslog("debug", "[fanwar]escape string="..table.concat(escape_data))
	return table.concat(escape_data)
end

return ec_char
