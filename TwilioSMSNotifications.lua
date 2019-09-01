luanet.load_assembly("System");
luanet.load_assembly("System.Xml");

local types = {};
types["System.Uri"] = luanet.import_type("System.Uri");
types["System.Collections.Specialized.NameValueCollection"] = luanet.import_type("System.Collections.Specialized.NameValueCollection");
types["System.IO.MemoryStream"] = luanet.import_type("System.IO.MemoryStream");
types["System.IO.StreamReader"] = luanet.import_type("System.IO.StreamReader");
types["System.Net.WebClient"] = luanet.import_type("System.Net.WebClient");
types["System.Net.CredentialCache"] = luanet.import_type("System.Net.CredentialCache");
types["System.Net.NetworkCredential"] = luanet.import_type("System.Net.NetworkCredential");
types["System.Net.WebException"] = luanet.import_type("System.Net.WebException");
types["System.Text.Encoding"] = luanet.import_type("System.Text.Encoding");
types["System.Type"] = luanet.import_type("System.Type");
types["System.Xml.XmlDocument"] = luanet.import_type("System.Xml.XmlDocument");
types["System.Xml.XmlNamespaceManager"] = luanet.import_type("System.Xml.XmlNamespaceManager");

local TWILIO_API = "https://api.twilio.com/2010-04-01";

function StringSplit(delimiter, text)
	local list = {};
	local pos = 1;
	
	if string.find("", delimiter, 1) then -- this would result in endless loops
		error("Delimiter cannot be an empty string.");
	end

	while 1 do
		local first,last = string.find(text, delimiter, pos);
		
		if first then -- found?
			table.insert(list, string.sub(text, pos, first-1));
			pos = last+1;
		else
			table.insert(list, string.sub(text, pos));
			break;
		end
	end

	return list;
end

function CreateDefaultNamespaceManager(document)
	local namespaceManager = types["System.Xml.XmlNamespaceManager"](document.NameTable);		
	return namespaceManager;
end

local function IsType(o, t)
	if ((o and type(o) == "userdata") and (t and type(t) == "string")) then
		local comparisonType = types["System.Type"].GetType(t);

		if (comparisonType) then
			-- The comparison type was successfully loaded so we can do a check
			-- that the object can be assigned to the comparison type.
			return comparisonType:IsAssignableFrom(o:GetType()), true;
		else
			-- The comparison type was could not be loaded so we can only check
			-- based on the names of the types.
			return (o:GetType().FullName == t), false;
		end
	end

	return false, false;
end

local client = nil;
local Settings = {};
Settings.AccountSID = GetSetting("AccountSID");
Settings.AuthToken = GetSetting("AuthToken");
Settings.FromNumber = GetSetting("FromNumber");
Settings.ActiveNVTGC = StringSplit(",",GetSetting("ActiveNVTGC"));

local sharedServerSupport = false;

function InitializeSharedServerSupport()
    local connection = CreateManagedDatabaseConnection();

    connection.QueryString = "SELECT Value FROM Customization WHERE CustKey = 'SharedServerSupport' AND NVTGC = 'ILL'";
    connection:Connect();

    local value = connection:ExecuteScalar();

    connection:Disconnect();

    if (value == "Yes") then
        LogDebug('Shared Server Support enabled for Twilio SMS Notification addon');
        sharedServerSupport = true;
    else
        LogDebug('Shared Server Support not enabled for Twilio SMS Notification addon');
        sharedServerSupport = false;
    end
end

function CreateClient(uri)
	local client = types["System.Net.WebClient"]();
	
	local authCredential = types["System.Net.NetworkCredential"](Settings.AccountSID, Settings.AuthToken);		
	local credentials = types["System.Net.CredentialCache"]();	
	credentials:Add(uri, "Basic", authCredential);
	
	client.Encoding = types["System.Text.Encoding"].UTF8;		
    client.Headers:Clear();
    client.Headers:Add("Accept", "text/xml");    
    client.Headers:Add("User-Agent", "ILLiad Twilio SMS Addon");
	client.Credentials = credentials;
	
	return client;
end

function LoadXmlDocFromString(text)
	local responseDocument = types["System.Xml.XmlDocument"]();
	
	local documentLoaded = pcall(function ()
			responseDocument:LoadXml(text);
		end);
	
	if (documentLoaded == false) then
		return false;
	else
		return responseDocument;
	end	
end

function Trim(s)
	local n = s:find"%S"
	return n and s:match(".*%S", n) or ""
end

function GetXMLChildValue(xmlElement, xPath, namespaceManager)
	LogDebug("[GetXMLChildValue] "..xPath);
    if (xmlElement == nil or xPath == nil) then
        LogDebug("Invalid Element/Path to retrieve value.");        
        return nil;
    end
    
    local datafieldNode = nil;
    
    if (namespaceManager ~= nil) then        
        datafieldNode = xmlElement:SelectNodes(xPath, namespaceManager);
    else           
        datafieldNode = xmlElement:SelectNodes(xPath);
    end
						
    LogDebug("Found "..datafieldNode.Count.." node elements matching "..xPath);
    local fieldValue = "";
    for d = 0, (datafieldNode.Count - 1) do
        LogDebug("datafieldnode value is: " .. datafieldNode:Item(d).InnerText);
        fieldValue = fieldValue .. " " .. datafieldNode:Item(d).InnerText;                  
    end
    
    fieldValue = Trim(fieldValue);
	LogDebug("GetChildValue Result: " .. fieldValue);
	
	return fieldValue;
end    

function URLEncode(s)
	if (s) then
		s = string.gsub(s, "\n", "\r\n")
		s = string.gsub(s, "([^%w %-%_%.%~])",
			function (c)
				return string.format("%%%02X", string.byte(c))
			end);
		s = string.gsub(s, " ", "+")
	end
	return s
end

function HandleTwilioError(error)
	--Twilio return a response error in XML

	if ((error) and (IsType(error, "LuaInterface.LuaScriptException")) and (error.InnerException ~= nil) and (IsType(error.InnerException, "System.Net.WebException"))) then
		LogDebug('HTTP Error: ' .. error.InnerException.Message);
		
		LogDebug('Handling error encountered when receving API response');		
		
		local webError = error.InnerException;		
		
		local documentLoaded, message = pcall(function ()
			local responseStream = webError.Response:GetResponseStream();
			local reader = types["System.IO.StreamReader"](responseStream);
			local responseText = reader:ReadToEnd();
			reader:Close();

			LogDebug('Error Response: ' .. responseText);
			local responseDocument = LoadXmlDocFromString(responseText);
			if (responseDocument ~= false) then
				LogDebug('Attempting to read twilio error code and message');
				local namespaceManager = CreateDefaultNamespaceManager(responseDocument);
				local twilioErrorCode = GetXMLChildValue(responseDocument, "//Code", namespaceManager);		
				local twilioErrorMessage = GetXMLChildValue(responseDocument, "//Message", namespaceManager);		
				return twilioErrorCode .. ': ' .. twilioErrorMessage;
			else
				return webError.Message;
			end
		end);
			
		if documentLoaded then
			return nil, message;
		else
			LogDebug('XML document was not successfully loaded. Unable to obtain Twilio error');
			return nil, webError.Message;
		end				
	end
	
	if (IsType(error, "System.Exception")) then
		return nil, 'Unable to handle error. ' .. error.Message;
	else
		return nil, 'Unable to handle error.';
	end
	
end

function SendRequest(request, data, handler)
    local uri = types["System.Uri"](request);	
	
	local client = CreateClient(uri);
	
    local messageSent = false;
	local response;
	
	--Wrap the HTTP post in a pcall to trap errors
    messageSent, response = pcall(function ()
			return client:UploadValues(uri, data);			
		end);
		
	client:Dispose();
	
	if (messageSent == false) then
		LogDebug('The notification was not sent.');			
		return HandleTwilioError(response);		
	else
		if (response and IsType(response, "System.Byte[]")) then			
			local responseDocument = types["System.Xml.XmlDocument"]();
			
			local documentLoaded = pcall(function ()
				responseDocument:Load(types["System.IO.MemoryStream"](response));
			end);

			if (documentLoaded) then
				return responseDocument, nil;
			else
				LogDebug("Unable to read response content");
				return nil, "Unable to parse response";
			end
		else
			LogDebug('response string not set');
			return nil, "Unable to retrieve response";
		end
	end
end

function CheckRequest(request, handler)
    local uri = types["System.Uri"](request);	
	
	local client = CreateClient(uri);
	
    LogDebug("Checking SMS notification (" .. request .. ")");    
    
	local messageSent = false;
	local responseString;
	
	--Wrap the HTTP post in a pcall to trap errors
    messageChecked, responseString = pcall(function ()
			return client:DownloadString(uri);			
		end);
		
	client:Dispose();
	
	if (messageChecked == false) then
		LogDebug('The notification was not checked.');		
		return HandleTwilioError(responseString);				
	else
		if (responseString and #responseString > 0) then						
			local responseDocument = LoadXmlDocFromString(responseString);
			
			if (responseDocument ~= false) then
				return responseDocument, nil;
			else				
				return nil, "Unable to parse response";
			end
		else			
			return nil, "Unable to retrieve response";
		end
	end
end

function Init()
	InitializeSharedServerSupport();
	RegisterSystemEventHandler("PendingSMSNotification", "SendNotification");
	RegisterSystemEventHandler("CheckSMSSending", "CheckNotification");
end

function CheckMessagResponse(response, error)
	if (response ~= nil and IsType(response, "System.Xml.XmlDocument")) then
		local namespaceManager = CreateDefaultNamespaceManager(response);
        
		local messageStatus = GetXMLChildValue(response, "//TwilioResponse/Message/Status", namespaceManager);		
		local messageId = GetXMLChildValue(response, "//TwilioResponse/Message/Sid", namespaceManager);
		
		LogDebug("Message Status: " .. messageStatus);

		if ((messageStatus:lower() == 'failed') or (messageStatus:lower() == 'undelivered')) then
			local errorCode = GetXMLChildValue(response, "//TwilioResponse/Message/ErrorCode", namespaceManager);
			LogDebug("Error Code: " .. errorCode);
			
			local errorMessage = GetXMLChildValue(response, "//TwilioResponse/Message/ErrorMessage", namespaceManager);
			LogDebug("Error Message: " .. errorMessage);

			local error = '';
			if Trim(errorCode ~= '') then
				error = errorCode .. ": " .. errorMessage;
			end
			
			return "Failed", error;
		else			
			if ((messageStatus:lower() == 'sent') or (messageStatus:lower() == 'delivered')) then
				return "Sent", messageId;
			else
				return "Sending", messageId;
			end
		end
	else
		return "Failed", error;
	end
end

function SendUsingExternalApi(phone, message)          
	local requestUrl = TWILIO_API .. '/Accounts/' .. Settings.AccountSID .. '/Messages.xml';
		
	local data = types["System.Collections.Specialized.NameValueCollection"]();
	data:Add("From", Settings.FromNumber);
	data:Add("To", phone);
	data:Add("Body", message);

	local response, error = SendRequest(requestUrl, data, nil); 

	return CheckMessagResponse(response, error);
end

function CheckUsingExternalApi(twilioMessageId)
	local requestUrl = TWILIO_API .. '/Accounts/' .. Settings.AccountSID .. '/Messages/' .. twilioMessageId .. '.xml';
	
	local response, error = CheckRequest(requestUrl, nil); 

	return CheckMessagResponse(response, error);
end

function ShouldProcessNotification(notificationNVTGC)
	local processNotification = false;
	
	if (sharedServerSupport) then
		LogDebug('Shared Server Instance. Checking if Twilio addon should process notification for '..notificationNVTGC);
		--Check if the addon has been enabled for the NVTGC
		for i = 1, #Settings.ActiveNVTGC do    		
			if (Settings.ActiveNVTGC[i]:lower() == notificationNVTGC:lower()) then
				processNotification = true;
				break;
			end
		end		
	else
		LogDebug('Single server. ActiveNVTGC is ignored');
		processNotification = true;
	end
	
	return processNotification;
end

function CheckForRetry(status, note)
	--Certain Twilio Errors indicate we should retry
	--21611: This 'From' number has exceeded the maximum number of queued messages
	--30001: Message Delivery - Queue overflow
	--14107: Message rate limit exceeded
	
	if (status == 'Failed' and note and #note > 0 and 
		(note:find('21611:') ~= nil) or
		(note:find('30001:') ~= nil) or
		(note:find('14107:') ~= nil)
		) then
		LogDebug('Will allow retry for notification '..smsNotificationEventArgs.ID);
		return true;
	end
	return false;
end

function SendNotification(smsNotificationEventArgs)        
	local sentInExternalSystem;
	local errorMessage;

	if (smsNotificationEventArgs.Handled) then
	   LogDebug("This notification was previously handled by another notification addon. Skipping processing for notification " .. smsNotificationEventArgs.ID);
	   return;
	end
	
	if (Settings.FromNumber == '') then
           LogDebug("FromNumber is required to send SMS notifications using the Twilio addon. Skipping processing for notification " .. smsNotificationEventArgs.ID);
           return;
	end;
	
	if ((Settings.AccountSID == '') or (Settings.AuthToken == '')) then
           LogDebug("AccountSID and AuthToken are required to send SMS notifications using the Twilio addon. Skipping processing for notification " .. smsNotificationEventArgs.ID);
           return;
	end;
   			
	if (ShouldProcessNotification(smsNotificationEventArgs.NVTGC)) then

		LogDebug("Twilio SMS Notification Addon processing notification " .. smsNotificationEventArgs.ID);	
    	
		local externalStatus = '';
		local note = nil;
	
		externalStatus, note = SendUsingExternalApi(smsNotificationEventArgs.MobilePhone, smsNotificationEventArgs.Message);
				
		smsNotificationEventArgs.Handled = true;
		smsNotificationEventArgs.Status = externalStatus;		
		smsNotificationEventArgs.Note = note;		
		smsNotificationEventArgs.AllowRetry = CheckForRetry(externalStatus, note);
		
		LogDebug('Notification '.. smsNotificationEventArgs.ID ..' was updated to a status of ' .. externalStatus);
		if (note ~= nil and #note > 0) then
			LogDebug('Notification '.. smsNotificationEventArgs.ID ..' was updated with a note: ' .. note);		
		end
		
	else
		LogDebug('The Twilio SMS Notification addon is not configured to process SMS messages for NVTGC ' .. smsNotificationEventArgs.NVTGC);
	end          
end

function CheckNotification(smsNotificationEventArgs)        
	local sentInExternalSystem;
	local errorMessage;

	if (smsNotificationEventArgs.Handled) then
	   LogDebug("This notification was previously handled by another notification addon. Skipping processing for notification " .. smsNotificationEventArgs.ID);
	   return;
	end
	
	if ((Settings.AccountSID == '') or (Settings.AuthToken == '')) then
           LogDebug("AccountSID and AuthToken are required to check SMS notifications using the Twilio addon. Skipping processing for notification " .. smsNotificationEventArgs.ID);
           return;
	end;

	LogDebug("Twilio SMS Notification Addon checking notification " .. smsNotificationEventArgs.ID);

	if (ShouldProcessNotification(smsNotificationEventArgs.NVTGC)) then
		if (smsNotificationEventArgs.Note ~= nil and Trim(smsNotificationEventArgs.Note) ~= '') then
			local externalStatus = '';
			local note = nil;
			
			externalStatus, note = CheckUsingExternalApi(smsNotificationEventArgs.Note);
					
			smsNotificationEventArgs.Handled = true;
			smsNotificationEventArgs.Status = externalStatus;		
			smsNotificationEventArgs.Note = note;
			smsNotificationEventArgs.AllowRetry = CheckForRetry(externalStatus, note);
					
			LogDebug('Notification '.. smsNotificationEventArgs.ID ..' was updated to a status of ' .. externalStatus);
			if (note ~= nil and #note > 0) then
				LogDebug('Notification '.. smsNotificationEventArgs.ID ..' was updated with a note: ' .. note);		
			end
		else
			LogDebug('Notification '.. smsNotificationEventArgs.ID ..' did not have a Twilio Message ID in the note field.');				
			smsNotificationEventArgs.Handled = true;
			smsNotificationEventArgs.Status = 'Failed';
			smsNotificationEventArgs.Note = 'Invalid Twilio Message ID';
		end
	else	
		LogDebug('The Twilio SMS Notification addon is not configured to process SMS messages for NVTGC ' .. smsNotificationEventArgs.NVTGC);
	end          
end
	
function OnError(scriptErrorEventArgs)	
	LogDebug("An error occurred in the " .. scriptErrorEventArgs.ScriptName .. " addon in the " .. scriptErrorEventArgs.ScriptMethod .. " function: " .. scriptErrorEventArgs.Message);
	ExecuteCommand("WriteSystemLog", "Twilio SMS Notification error. " .. scriptErrorEventArgs.Message);
end