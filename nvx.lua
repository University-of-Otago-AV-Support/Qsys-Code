--initializations
rapidjson = require("rapidjson")
json = require("json")
--table of active streams 
Streams = {}
FilteredStreams = {} 
Receivers = {} 
authHeader = {}
Controls.CurrentStream.String = ""
Controls.ManualStream.String = ""  
OSD = false 
StreamReceiveVariable = Controls.StreamReceive.String
PollingFunctionActive = false
    
debugNames = {
  [1] = "Authorise",
  [2] = "HttpGet",
  [3] = "HttpPost",
  [4] = "Polling",
  [5] = "Serial",
  [6] = "Posting",
  [7] = "Preview",
  [8] = "Osd",
  [9] = "Parsing",
  [10] = "Ping",
  [11] = "Informational",
  [12] = "-",
  [13] = "-",
  [14] = "-",
  [15] = "-",
  [16] = "-",
  [17] = "-",
  [18] = "-",
  [19] = "-",
  [20] = "-"
}

for name = 1, #Controls.DebugTypes do
  if debugNames[name] then
    Controls.DebugTypes[name].Legend = debugNames[name]
  end
end 

-- poll timer
PollTimer = Timer.New()

--variables
ip = Controls.IP.String
un = Controls.Username.String
pw = Controls.Password.String
fb = Controls.DeviceFB.String
nvxBaseUrl = 'https://'..ip..'/'

if StreamReceivedTimeout == nil then
    StreamReceivedTimeout = 0
end

-- flags
PollingListNumber = 1
GetPreviewActive = false 

-- Ping Minder
NVXPing = Ping.New(ip)

--Auth button visual feedback
function AuthFB(state)
  if state then
    debug(1, 'Auth State: '..tostring(state))
    if state == "Authorizing" then 
      Controls.Authorized.Boolean = false
      Controls.Authorized.Legend = state.."..."
      Controls.Authorized.Color = "Grey"
    elseif state == true then
      Controls.Authorized.Boolean = true
      Controls.Authorized.Legend = "Authorized"
      Controls.Authorized.Color = "Green"
    end
  elseif not state or state == false then
    Controls.Authorized.Boolean = false
    Controls.Authorized.Legend = "UnAuthorized"
    Controls.Authorized.Color = "Red"
  end
end 

--check data for HTML, or requested Data
function AuthCheck(data)
  if data:find("<!DOCTYPE html>") then 
    debug(1, "Can't acquire streams because not authenticated")  
    return false
  else 
    return true
  end
end  

--Authentication
--Authentication
function AuthHandler()
  debug(1, "INTO AUTH HANDLER")
  authHeader["Content-Type"] = "application/json"
  --authenticate
 
  function auth()
    debug(1, "Starting auth!")
    AuthFB("Authorizing")
    HttpClient.Upload({
    Url = 'https://'..ip..'/userlogin.html',
    Method = 'POST',
    Headers = {["Content-Type"] = "application/json"},
    Data = 'login='..un..'&&passwd='..pw,
    EventHandler = Response
    })
  end

  --auth response
  function Response(tbl, code, data, err, headers)
    debug(1, "Getting Auth Response")
    cookieString = ''
    if code ~= 200 then 
      debug(1,"Error with Code "..code)
      debug(1,"error = "..err)
      print(data)
      if data ~= "invalid credentials" and data ~= "Your user account is blocked" then
        Timer.CallAfter(AuthHandler, 2)
      else
        print("CHECK PASSWORD")
        Controls.Status.String = "CHECK PASSWORD"
      end
    else
      debug(1, "Authentication Success, code "..code)  
      for hName,Val in pairs(headers) do -- for loop for headers
        if hName == "Set-Cookie" then -- finding set-cookie header function
          debug(1,"Found Authentication Cookies!")
          for k,v in pairs(Val) do
            cookieString = cookieString..v 
          end
          AuthFB(true)
          authHeader["Cookie"] = cookieString
          if Controls.Authorized.Boolean then 
            debug(1, "Getting Device")
            HttpGet("Device/")
          end
          if PollTimer then
            PollTimer:Stop()
          end
          PollTimer:Start(1)
        end   
      end
      if Controls.Mode.String == "Receiver" and not Controls.InputSyncLed[3].Boolean then
        debug(1,"Receiver with no sync")
      end
      if Controls.Mode.String == "Transmitter" and not Controls.InputSyncLed[4].Boolean then
        debug(1,"Transmitter with no sync")
      end
    end
  end
  --change auth feedback
  if cookieString == "" then 
    AuthFB(false) 
  end
  auth()
end
 
 
------------------------------------------- FUNCTIONS

function debug(debugtype, printMessage) -- printing debug lines
  --print("debugtype = ", debugtype)
  if Controls.DebugTypes[debugtype].Boolean then
    if Controls.Debug.Boolean then
      print(printMessage)
    end
  end
end

function ClearAll() 
  local ClearTable = { "HostName", "Model", "Name", "CurrentInput", "Mode", "OSDMessage", "UsbMode", "UsbName", "BaudRate", "DataBits", "Parity", "SerialTransmitData", "CecCommand", "Data"}
  local FalseTable = { "HDCPState" }

  for i = 1, #ClearTable do
    Controls[ClearTable[i]].String = ""
  end

  for i = 1, 3 do
    Controls["HDCPState"][i].Value = 5
    Controls["HDCPState"][i].String = "Initialising"
    Controls["HDCPState"][i].Color = "gray"
  end

  for i = 1, #Controls.InputSyncLed do 
    Controls.InputSyncLed[i].Value = 0
  end
  Controls.OutputSyncLed.Value = 0
end

function HttpGet(UrlString, EventHandler)
  debug(2,"into get function, url is "..nvxBaseUrl..UrlString)
  if EventHandler ~= nil then 
    debug(2,"eventhandler is "..tostring(EventHandler))
  else 
    debug(2,"no event handler, using standard")
    EventHandler = "standard"
  end 
  debug(2, nvxBaseUrl)
  if EventHandler == "standard" then 
    EventHandler = function(t,c,d,e,h)
      debug(2,"standard eventhandler fired for "..UrlString)
      if Controls.Authorized.Boolean == true and not d:find("<!DOCTYPE html>") then
        debug(2,"HttpGet URL: "..UrlString)
        ParseData(d) 
      else 
        debug(2,"not authorised in httpget")
        --AuthHandler()
      end  
    end 
  else
  end
  HttpClient.Download {
    Url = nvxBaseUrl..UrlString,
    Headers = authHeader,
    Timeout = 10,
    EventHandler = EventHandler
  }
end

-- HTTP POST eg [=[{"Device": {"AvRouting": {"Routes": [{"VideoSource": "]=]..route..[=["}]}}}]=]
function HttpPost(UrlString, Command)
  debug(3, "into http post")
  debug(3,"url is : "..nvxBaseUrl..UrlString)
  debug(3, "command is : "..Command)
  HttpClient.Upload {
      Url = nvxBaseUrl..UrlString,
      Method = "POST", 
      Data = Command,
      Headers = authHeader,
      EventHandler = function(t,c,d,e,h)
        if c ~= 200 then debug('Error with code: '..c) else
          debug(3, "data = ".. d)
          ParseData(d)
        end
      end
    }
end

----------------- OTHER STUFF

function GetAll()
  local UrlString = "Device/DeviceInfo/"
  if Controls.Authorized.Boolean == false then 
    debug(4, "Authorization false")
  else
    HttpGet(UrlString)
  end
end

function ParentDevice()
  local UrlString = "Device/ParentDevice/SlotInParent"
  HttpGet(UrlString)
end 

function GetCurrentInput()
  local UrlString = "Device/DeviceSpecific/ActiveVideoSource/"
  HttpGet(UrlString)
end

function GetSyncState()
  debug(4, "Getting HDMI Sync States")
  UrlString = "Device/AudioVideoInputOutput/"
  HttpGet(UrlString)
end

function GetMode() --jsondata.Device.DeviceSpecific.DeviceMode
  debug(4, "Getting Device Mode")
  UrlString = "Device/DeviceSpecific/DeviceMode"
  HttpGet(UrlString) 
end 

function GetStreamTransmit()
  local UrlString = "Device/StreamTransmit/Streams/StreamLocation"
  HttpGet(UrlString)
end

function GetStreamReceive()
    local UrlString = "Device/StreamReceive/Streams/StreamLocation"
    HttpGet(UrlString, GetStreamReceiveHandler)
end

function GetStreamReceiveHandler(t, c, d, e, h)
  if d ~= nil then
    -- Decode data and assign to a variable
    local jsondata = rapidjson.decode(d)
    
    -- Check if jsondata is not nil
    if not jsondata then
      debug(4, "Failed to decode JSON")
    end
    
    -- Check if all necessary fields exist
    if jsondata.Device and jsondata.Device.StreamReceive and jsondata.Device.StreamReceive.Streams and jsondata.Device.StreamReceive.Streams.StreamLocation then
      -- Check if receive stream matches current receive stream, and assign if not
      if Controls.StreamReceive.String ~= StreamReceiveVariable then
        local streamLocation = jsondata.Device.StreamReceive.Streams.StreamLocation.StreamLocation
        if streamLocation and streamLocation ~= "" then
          Controls.StreamReceive.String = streamLocation
        else
          debug(4, "Stream received identical")
        end
      else
        debug(4, "Stream received identical")
      end

      -- Check if stream started for LED sync
      if jsondata.Device.StreamReceive.Streams.StreamLocation.Status ~= nil then
        local streamStatus = jsondata.Device.StreamReceive.Streams.StreamLocation.Status
        if streamStatus then
          debug(4, "Stream receive status not nil")
          
          if streamStatus == "Stream started" then
            if not Controls.InputSyncLed[3].Boolean then
              debug(4,"Stream is running, turning on InputSync[3] LED")
              Controls.InputSyncLed[3].Boolean = true
              StreamReceivedTimeout = 0
            end
          elseif streamStatus == "Stream stopped" then
            if Controls.InputSyncLed[3].Boolean then
              debug(4,"Stream is not running, turning off InputSync[3] LED")
              Controls.InputSyncLed[3].Boolean = false
              StreamReceivedTimeout = StreamReceivedTimeout + 1
              debug(4,"Stream received timeout is " .. StreamReceivedTimeout)
              
              if StreamReceivedTimeout >= 3 then
                if Controls.Mode.String == "Receiver" then
                  debug(4,"RECEIVE STREAM NOT RUNNING")
                end
              end
            end
          end
        else
          debug(4,"Status not available")
        end
      else
        debug(4,"Did not find Stream Location Status in jsondata")
      end
    else
      debug(4,"Did not find Stream Receive in jsondata")
    end
  else
    debug(4,"No JSON in retrieve stream handler!")
  end
end

function GetUsb()
    local UrlString = "Device/Usb/"
    HttpGet(UrlString)
end

function GetStreamState()
    debug(4,"getting stream states")
    local UrlString = "Device/StreamReceive/"
    HttpGet(UrlString)
end
 
-- Serial Commands

Controls.SerialTransmitData.EventHandler = function()
  local UrlString = "Device/ControlPorts/"
  local serialString = Controls.SerialTransmitData.String
  local Command = [=[{"Device":{"ControlPorts":{"Serial":{"Port1":{"TransmitData":"]=] .. serialString .. [=["}}}}}}]=]
  debug(5,"command = "..Command)
  debug(5,"urlstring = "..UrlString)
  HttpPost(UrlString, Command)
  Timer.CallAfter(GetReceivedSerial, 2)
end

Controls.TransmitDataFormat.EventHandler = function()
  if Controls.TransmitDataFormat.Boolean == true then
    local UrlString = "Device/ControlPorts/"
    local Command = '{"Device":{"ControlPorts":{"Serial":{"Port1":{"TransmitDataFormat":"Ascii"}}}}}'
    debug(5,"Serial command transmit = Ascii")
    mainCommandPostRequest(UrlString, Command)
  elseif  Controls.TransmitDataFormat.Boolean == false then
    HTTPGet = false
    local UrlString = "Device/ControlPorts/"
    Command = '{"Device":{ "ControlPorts":{"Serial":{"Port1":{"TransmitDataFormat":"Hex"}}}}}'
    debug(5,"Serial command transmit = Hex")
    mainCommandPostRequest(UrlString, Command)
  end
end

Controls.ReceivedDataFormat.EventHandler = function()
  if Controls.ReceivedDataFormat.Boolean == true then
    -- Received  is ASCII
    local UrlString = "Device/ControlPorts/"
    local Command = '{"Device":{"ControlPorts":{"Serial":{"Port1":{"ReceivedDataFormat":"Ascii"}}}}}'
    debug(5,"Serial command transmit = Ascii")
    HttpPost(UrlString, Command)
  elseif  Controls.ReceivedDataFormat.Boolean == false then
    -- Received  is Hex
    local UrlString = "Device/ControlPorts/"
    local Command = '{"Device":{"ControlPorts":{"Serial":{"Port1":{"ReceivedDataFormat":"Hex"}}}}}'
    debug(5,"Serial command transmit = Hex")
    HttpPost(UrlString, Command)
  end
end

Controls.BaudRate.EventHandler = function()
  BaudRate = Controls.BaudRate.String 
  local UrlString = "Device/ControlPorts/"
  local Command = '{"Device":{"ControlPorts":{"Serial":{"Port1":{"BaudRate":"'..BaudRate..'"}}}}}'
  debug(5,"BaudRate = "..BaudRate)
  HttpPost(UrlString, Command)
end

Controls.BlankOutput.EventHandler = function() --Device/AudioVideoInputOutput/Outputs/Ports/Hdmi/IsBlankingDisabled
  blankstatus = tostring(not Controls.BlankOutput.Boolean)
  local UrlString = "Device/AudioVideoInputOutput/"
  local Command = '{"Device":{"AudioVideoInputOutput":{"Outputs":[{"Ports":[{"Hdmi":{"IsBlankingDisabled":"'..  blankstatus..'"}}]}]}}}'
  debug(11,"blankstatus = "..blankstatus)
  HttpPost(UrlString, Command)
end

Controls.DataBits.EventHandler = function()
  DataBits = Controls.DataBits.String 
  local UrlString = "Device/ControlPorts/"
  local Command = '{"Device":{"ControlPorts":{"Serial":{"Port1":{"DataBits":"'..DataBits..'"}}}}}'
  debug(5,"BaudRate = "..BaudRate)
  HttpPost(UrlString, Command)
end

Controls.GetReceivedSerial.EventHandler = function ()
  GetReceivedSerial()
end

function GetReceivedSerial()
  debug(5,"getting received serial")
  UrlString = "Device/ControlPorts/"
  Controls.SerialTransmitData.String = ""
  Controls.ReceivedData.String = ""
  HttpGet(UrlString)
end 

--------------------------------------------- POST COMMANDS ---------------------------------------------

-- Send CEC
Controls.CecCommand.EventHandler = function()
  UrlString = "Device/AudioVideoInputOutput/"
  local CecCommand = Controls.CecCommand.String
  Command = '{"Device":{"AudioVideoInputOutput":{"Outputs":[{"Ports":[{"Hdmi":{"TransmitCecMessage":"'..CecCommand..'"}}]}]}}}'
  debug(6,"CECCommand command "..CecCommand.." sent") 
  HttpPost(UrlString, Command)
end

-- CHANGE STREAM
function receiveStreamChange()
  debug(6,'change stream')
  receiveStream = Controls.StreamReceive.String
  UrlString = "Device/StreamReceive"
  Command = '{"Device": {"StreamReceive": {"Streams": [{"StreamLocation": "'..receiveStream..'"}]}}}'
  HttpPost(UrlString, Command)
end
-- CHANGE USB MODE TO LOCAL
function ChangeUsbModeLocal()
  UrlString = "Device/Usb"
  Command = '{"Device":{"Usb":{"UsbPorts":[{"Mode":"Local"}]}}}'
    debug(3,"USB Mode Change Requested")
  HttpPost(UrlString, Command)
end
-- CHANGE USB MODE TO REMOTE
function ChangeUsbModeRemote()
  UrlString = "Device/Usb"
  Command = '{"Device":{"Usb":{"UsbPorts":[{"Mode":"Remote"}]}}}'
  debug(6,"USB Mode Change Requested")
  HttpPost(UrlString, Command)
end
-- REBOOT NVX
function Reboot()
  UrlString = "Device/DeviceOperations/"
  Command = '{"Device":{"DeviceOperations":{"Reboot": true }}}'
  print("****************************** REBOOTING DEVICE ******************************")
  HttpPost(UrlString, Command)
end

function ChangeInput(Input)
  UrlString = 'Device'
  Command = '{"Device":{"DeviceSpecific":{"VideoSource":"'.. Input .. '"}}}'
  HttpPost(UrlString, Command)
  Timer.CallAfter(GetCurrentInput, 1)
end

--preview
function GetPreview()
  debug(7,")(*(*&)^(&*^&*(&*                             GETTING PREVIEW                                        )(*(*&)^(&*^&*(&*")
  HttpClient.Download {
    Url = nvxBaseUrl.."Device/Preview/",
    Headers = authHeader,
    Timeout = 10,
    EventHandler = function(t,c,d,e,h)      
      if c ~= 200 or d:find("<!DOCTYPE html>") then
        debug(7,"Preview: Error with code: "..c)
      else
        debug(7,"GOT PREVIEW!") 
        GetPreviewActive = true
        local printUrl = "https://"..ip.."/preview/preview_135px.jpeg"
        HttpClient.Download { 
          Url = printUrl, 
          Headers = authHeader,
          Data = "", 
          Timeout = 30, 
          EventHandler = function(t,c,d,e,h)
            --print(d)
            Controls.PreviewImage.Style = rapidjson.encode({
            DrawChrome = false,
            IconData = Crypto.Base64Encode(d),
            })
            if not Controls.GetPreview.Boolean then  
              Controls.PreviewImage.Legend = "PREVIEW OFF"
            else
              Timer.CallAfter(GetPreview, 0.2)
            end
          end 
        }
      end
    end
  }
end 

---- OSD OSD OSD ---- OSD OSD OSD ---- OSD OSD OSD ---- OSD OSD OSD ---- OSD OSD OSD ---- OSD OSD OSD ---- OSD OSD OSD ---- OSD OSD OSD 

Controls.OSDMessage.EventHandler = function()
  OSDHandler()  
end

Controls.Identify.EventHandler = function()
  if Controls.Identify.Boolean == true then
    Controls.OSDMessage.String = Controls.IP.String .. " - ".. Controls.Name.String
    OSDHandler()
  else
    Controls.OSDMessage.String = ""
    OSDHandler() 
  end
end
 
function OSDHandler()
    if Controls.OSDMessage.String ~= "" then 
      if OSD then 
        debug(8,"OSD enabled, sending string")
        OSDMessage = Controls.OSDMessage.String 
        UrlString = "Device/Osd/"
        Command = '{"Device":{"Osd":{"Text":"'..OSDMessage..'"}}}'
        HttpPost(UrlString, Command)
      else 
        debug(8,"OSD is disabled, enabling OSD")
        OSDEnable()
        Timer.CallAfter(OSDHandler, 1)
      end 
    else      
      debug(8,"No Osd Message, disabling OSD") 
      OSDDisable()
  end
end 

function OSDEnable()
  Command = '{"Device":{"Osd":{"IsEnabled":true}}}'
  debug(8,"osd enabled")
  UrlString = "Device/Osd/"
  HttpPost(UrlString, Command)
  OSD = true 
end 

function OSDDisable()
  Command = '{"Device":{"Osd":{"IsEnabled":false}}}'
  debug(8,"osd disabled")
  UrlString = "Device/Osd/"
  HttpPost(UrlString, Command)
  OSD = false
end 

------------------------------ POLLING FUNCTION 
function PollingFunction()
  local PollTable =  
  {
    "Device/DeviceSpecific/DeviceMode", -- get mode
    "Device/Localization/Name", -- get name
    "Device/DeviceInfo", -- get all
    "Device/ParentDevice/", -- get card slot
    "Device/AudioVideoInputOutput/", -- getsyncstates
    "Device/AvRouting/Routes", --pollroute
    "Device/StreamTransmit/Streams/StreamLocation", -- getstreamtransmit
    "Device/StreamReceive/", --getstreamstate
    "Device/StreamReceive/Streams/StreamLocation", -- getstreamreceive
    "Device/Usb/"-- getusb
  }
  if Controls.GetPreview.Boolean then
    if not GetPreviewActive then
      GetPreview()
    else

    end
  end

  if Controls.Authorized.Boolean then
    HttpGet("Device/DeviceSpecific/ActiveVideoSource/")
    local UrlString = PollTable[PollingListNumber]
    debug(4,"Polling List URL is "..PollTable[PollingListNumber])
    HttpClient.Download {
    Url = nvxBaseUrl..UrlString,
    Headers = authHeader, 
    Timeout = 10, 
    EventHandler = function(t,c,d,e,h)
      if d ~= nil and not d:find("<!DOCTYPE html>") then
        ParseData(d)
        debug (4,"data received in polling function from "..tostring(PollTable[PollingListNumber]))        
        if PollingListNumber >= #PollTable then 
          PollingListNumber = 0 
        end 
        PollingListNumber = PollingListNumber + 1
      else
        debug (4,"no data from "..tostring(PollTable[PollingListNumber]).." !")
      end
    end 
    }
  else
    debug(4,"Not Authorized in Polling Function! Restarting AuthHandler!")
    Timer.CallAfter(AuthHandler, 2)
  end
end 

------------------------------------  PARSING -------------------------------------------------------------------
------------------------------------       PARSING -------------------------------------------------------------------
------------------------------------          PARSING -------------------------------------------------------------------
------------------------------------              PARSING -------------------------------------------------------------------

function ParseData(d)
  jsondata = rapidjson.decode(d)  
  if jsondata ~= nil then
  --debug(9, d)
    if jsondata.Device and jsondata.Device.DeviceSpecific and jsondata.Device.DeviceSpecific.ActiveVideoSource ~= nil then debug(9,"Input Decoded")
        Controls.CurrentInput.String = jsondata.Device.DeviceSpecific.ActiveVideoSource
        debug(9,"Input is "..jsondata.Device.DeviceSpecific.ActiveVideoSource)
      if Controls.CurrentInput.String == "Input1" then
        Controls.Input[1].Value = 1
        Controls.Input[2].Value = 0
        Controls.Input[3].Value = 0
        Controls.CurrentInput.String = "1"
      elseif Controls.CurrentInput.String == "Input2" then
        Controls.Input[1].Value = 0
        Controls.Input[2].Value = 1
        Controls.Input[3].Value = 0
        Controls.CurrentInput.String = "2"
      elseif Controls.CurrentInput.String == "Stream" then
        Controls.Input[1].Value = 0
        Controls.Input[2].Value = 0
        Controls.Input[3].Value = 1
        Controls.CurrentInput.String = "Stream"
      elseif Controls.CurrentInput.String == "None" then
        Controls.Input[1].Value = 0
        Controls.Input[2].Value = 0
        Controls.Input[3].Value = 0
        Controls.CurrentInput.String = "None"
      end
    else
      
    end

  -- INPUT FEEDBACK
    if jsondata and jsondata.Actions and #jsondata.Actions > 0 then
        local results = jsondata.Actions[1].Results
        if results and #results > 0 then
            local path = results[1].Path
            local statusInfo = results[1].StatusInfo
            
            if path == "Device.DeviceSpecific.ActiveVideoSource" then
                if statusInfo == "1" then
                    Controls.InputLed[1].Value = 1
                    Controls.InputLed[2].Value = 0
                    Controls.InputLed[3].Value = 0
                    Controls.CurrentInput.String = "1"
                elseif statusInfo == "2" then
                    Controls.InputLed[1].Value = 0
                    Controls.InputLed[2].Value = 1
                    Controls.InputLed[3].Value = 0
                    Controls.CurrentInput.String = "2"
                elseif statusInfo == "3" then
                    Controls.InputLed[1].Value = 0
                    Controls.InputLed[2].Value = 0
                    Controls.InputLed[3].Value = 1
                    Controls.CurrentInput.String = "Stream"
                end
            end
        end
    end

  -- DEVICE MODE
    if jsondata.Device and jsondata.Device.DeviceSpecific and jsondata.Device.DeviceSpecific.DeviceMode ~= nil then
      Controls.Mode.String = jsondata.Device.DeviceSpecific.DeviceMode 
    end

    if Controls.Mode.String ~= mode then
      if Controls.Mode.String == "Transmitter" then
        Controls.Mode.Color = "cyan"
        Controls.Name.Color = "cyan"
        Controls.Mode.Legend = "Transmitter"
        Controls.StreamTransmit.Color = "white"
        Controls.StreamReceive.Color = "#FF595959"
        Controls.StreamTransmit.IsDisabled = false 
        Controls.StreamReceive.IsDisabled = true
        elseif Controls.Mode.String == "Receiver" then
        Controls.Mode.Legend = "Receiver"
        Controls.Mode.Color = "black"
        Controls.Name.Color = "black"
        Controls.StreamReceive.Color = "white"
        Controls.StreamTransmit.Color = "#FF595959"
        Controls.StreamTransmit.IsDisabled = true 
        Controls.StreamReceive.IsDisabled = false
        mode = Controls.Mode.String
      end
    end

  ---------------------------------------------------- STREAMS -----------------------
  -- STREAM RECEIVE
    if jsondata.Device and jsondata.Device.StreamReceive and jsondata.Device.StreamReceive.Streams and jsondata.Device.StreamReceive.Streams.StreamLocation ~= nil then
      if Controls.StreamReceive.String ~= StreamReceiveVariable then
        if jsondata.Device.StreamReceive.Streams.StreamLocation.StreamLocation ~= nil or jsondata.Device.StreamReceive.Streams.StreamLocation.StreamLocation ~= "" then
          Controls.StreamReceive.String = jsondata.Device.StreamReceive.Streams.StreamLocation.StreamLocation
        end
      else
        debug(9,"Stream recieved identical")
      end
    else
      debug(9,"did not find Stream Receive in jsondata")
    end

  -- STREAM TRANSMIT
    if jsondata.Device and jsondata.Device.StreamTransmit and jsondata.Device.StreamTransmit.Streams and jsondata.Device.StreamTransmit.Streams.StreamLocation ~= nil then
      debug(9,"StreamTransmit =", jsondata.Device.StreamTransmit.Streams.StreamLocation.StreamLocation)
      Controls.StreamTransmit.String = jsondata.Device.StreamTransmit.Streams.StreamLocation.StreamLocation
    else 
      debug(9,"did not find Stream Transmit in jsondata")
    end
    
    debug(9,"function stream sync led")
    
    local streamReceiveStatus = jsondata.Device and jsondata.Device.StreamReceive and jsondata.Device.StreamReceive.Streams and jsondata.Device.StreamReceive.Streams.StreamLocation and jsondata.Device.StreamReceive.Streams.StreamLocation.Status

    if streamReceiveStatus ~= nil then
      if streamReceiveStatus == "Stream started" then
          -- Stream is running
          Controls.InputSyncLed[3].Boolean = true
          -- Reset the StreamReceivedTimeout counter
          StreamReceivedTimeout = 0
      else
          -- Stream is not running
          Controls.InputSyncLed[3].Boolean = false
          -- Increment the StreamReceivedTimeout counter
          StreamReceivedTimeout = StreamReceivedTimeout + 1
          -- Check if the counter has reached 3
  
          if StreamReceivedTimeout >= 3 then
              if Controls.Mode.String == "Receiver" then

                  debug(9,"RECEIVE STREAM NOT RUNNING RECEIVE STREAM NOT RUNNING RECEIVE STREAM NOT RUNNING RECEIVE STREAM NOT RUNNING RECEIVE STREAM NOT RUNNING RECEIVE STREAM NOT RUNNING RECEIVE STREAM NOT RUNNING")
              else               
              end
          else             
          end
      end
    end


    local streamTransmitstatus = jsondata.Device and jsondata.Device.StreamTransmit and jsondata.Device.StreamTransmit.Streams and jsondata.Device.StreamTransmit.Streams.StreamLocation and jsondata.Device.StreamTransmit.Streams.StreamLocation.Status 

    if streamTransmitstatus then 
      debug(9,"stream transmit status =  "..streamTransmitstatus) 
    else 
      debug(9,"streamTransmitstatus empty!") 
    end

    if streamTransmitstatus ~= nil then
      if streamTransmitstatus == "Stream started" then
        debug(9,"stream is running, turning on inputsync[4] LED")
        Controls.InputSyncLed[4].Boolean = true
      else
        debug(9,"stream is not running, turning off inputsync[4] LED")
        Controls.InputSyncLed[4].Boolean = false
        if Controls.Mode.String == "Transmitter" then
        end
      end
    end


    -- STREAM SYNC LED BUTTON

    if Controls.Mode.String == "Transmitter" then
      if Controls.InputSyncLed[4].Boolean then
        Controls.InputSyncLed[5].Boolean = true
      else
        Controls.InputSyncLed[5].Boolean = false
      end
    elseif Controls.Mode.String == "Receiver" then
      if Controls.InputSyncLed[3].Boolean then
        Controls.InputSyncLed[5].Boolean = true
      else
        Controls.InputSyncLed[5].Boolean = false
      end
    else
      debug(9,"NO MODE DETECTED")
    end
    
  -- HOST NAME
    if jsondata.Device and jsondata.Device.DeviceInfo and jsondata.Device.DeviceInfo.Name ~= nil then
      debug(9, "Name = " .. jsondata.Device.DeviceInfo.Name)
      Controls.HostName.String = jsondata.Device.DeviceInfo.Name
    else
      debug(9,"No Name Detected!")
      if Controls.HostName.String == "" then GetAll() end
    end

  -- DEVICE NAME
    if jsondata.Device and jsondata.Device.Localization and jsondata.Device.Localization.Name ~= nil then
      debug(9, "Device Name = " .. jsondata.Device.Localization.Name)
      Controls.Name.String = jsondata.Device.Localization.Name
    else
      debug(9,"No Name Detected!")
    end

  -- DEVICE INFO MODEL
    if jsondata.Device and jsondata.Device.DeviceInfo and jsondata.Device.DeviceInfo.Model ~= nil then
      debug(9,"model found")
      Controls.Model.String = jsondata.Device.DeviceInfo.Model
      debug(11, "model = "..Controls.Model.String)
      if Controls.Model.String ~= "DM-NVX-350" and Controls.Model.String ~= "DM-NVX-352" and Controls.Model.String ~= "DM-NVX-351" and Controls.Model.String ~= "DM-NVX-350C" then
        Controls.Input[2].IsDisabled = true
        Controls.InputSyncLed[2].IsDisabled = true
      else
        Controls.Input[2].IsDisabled = false
        Controls.InputSyncLed[2].IsDisabled = false
      end
    else
      debug(9,"No Model Detected!")
    end
  -- DEVICE LAST REBOOT REASON
    if jsondata.Device and jsondata.Device.DeviceInfo and jsondata.Device.DeviceInfo.RebootReason ~= nil then
      Controls.RebootReason.String = jsondata.Device.DeviceInfo.RebootReason
    else
      debug(9,"No Reboot Reason Detected!")
    end
   
  -- PARENT CARD SLOT 

    if jsondata.Device and jsondata.Device.ParentDevice and jsondata.Device.ParentDevice.SlotInParent ~= nil then
      if jsondata.Device.ParentDevice.SlotInParent == "" or nil then 
        Controls.CardSlot.String = "Stand Alone Box"
      else
        Controls.CardSlot.IsInvisible = false
        debug(9,"PARENT CARD SLOT  =", jsondata.Device.ParentDevice.SlotInParent)
        Controls.CardSlot.String = "Card Slot: "..jsondata.Device.ParentDevice.SlotInParent
      end
    else 
      debug(9,"Stream Receive not found")
    end
  -- USB REMOTE DEVICES
    if jsondata.Device and jsondata.Device.Usb and jsondata.Device.Usb.UsbPorts ~= nil then
      debug(9,"ChangeUsbRemoteIds =" ..jsondata.Device.Usb.UsbPorts[1].UsbPairing.Layer2.RemoteDevices.Id1)
      Controls.RemoteId[1].String = jsondata.Device.Usb.UsbPorts[1].UsbPairing.Layer2.RemoteDevices.Id1
    else
      debug(9,"USB Remote Devices Not found") 
    end
    
  -- HDCP STATUS 1
    if jsondata.Device and jsondata.Device.AudioVideoInputOutput and jsondata.Device.AudioVideoInputOutput.Inputs and jsondata.Device.AudioVideoInputOutput.Inputs[1] and jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1] and jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1].Hdmi ~= nil then
      debug(9,"HDCP HDMI 1 = "..jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1].Hdmi.HdcpState)
      Controls.HDCPState[1].String = jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1].Hdmi.HdcpState
      if Controls.HDCPState[1].String == "Non-HDCPSource" then
        Controls.HDCPState[1].Color = '#00bbff'
      else
        Controls.HDCPState[1].Color = 'red'
      end
    else
      debug(9,"no HDCP status")
    end 
  
  -- HDMI SOURCE DETECTION 1
    if jsondata.Device and jsondata.Device.AudioVideoInputOutput and jsondata.Device.AudioVideoInputOutput.Inputs and jsondata.Device.AudioVideoInputOutput.Inputs[1] and jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1] and jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1] ~= nil then
      --Device/AudioVideoInputOutput/Inputs/0/Ports/0/IsSyncDetected
      Controls.InputSyncLed[1].Boolean = jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1].IsSyncDetected
      debug(9,"sync hdmi source 1 = ", jsondata.Device.AudioVideoInputOutput.Inputs[1].Ports[1].IsSyncDetected)
    if Controls.InputSyncLed[1].String == "true" then
      Controls.InputSyncLed[1].Boolean = true
    else
      Controls.InputSyncLed[1].Boolean = false
    end
  end

  -- HDCP STATUS 2
    if jsondata.Device and jsondata.Device.AudioVideoInputOutput and jsondata.Device.AudioVideoInputOutput.Inputs and jsondata.Device.AudioVideoInputOutput.Inputs[2] and jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1] and jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1].Hdmi ~= nil then
      debug(9,"HDCP HDMI 2 = "..jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1].Hdmi.HdcpState)
      debug(9,jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1].Hdmi.HdcpState)
      Controls.HDCPState[2].String = jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1].Hdmi.HdcpState
      if Controls.HDCPState[2].String == "Non-HDCPSource" then
        Controls.HDCPState[2].Color = '#00bbff'
      else
        Controls.HDCPState[2].Color = 'red'
        
      end
    end 

  -- HDMI SOURCE DETECTION 2
      if jsondata.Device and jsondata.Device.AudioVideoInputOutput and jsondata.Device.AudioVideoInputOutput.Inputs and jsondata.Device.AudioVideoInputOutput.Inputs[2]  and jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1] and jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1] ~= nil then
        Controls.InputSyncLed[2].Boolean = jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1].IsSyncDetected
        debug(9,"sync hdmi source 2 = ", jsondata.Device.AudioVideoInputOutput.Inputs[2].Ports[1].IsSyncDetected)
      if Controls.InputSyncLed[2].String == "true" then
        Controls.InputSyncLed[2].Boolean = true
      else
        Controls.InputSyncLed[2].Boolean = false
      end
    end


  -- HDCP STATUS OUTPUT
    if jsondata.Device and jsondata.Device.AudioVideoInputOutput and jsondata.Device.AudioVideoInputOutput.Outputs and jsondata.Device.AudioVideoInputOutput.Outputs[1] and jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1] and jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1].Hdmi ~= nil then
      debug(9,"HDCP HDMI OUT = "..jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1].Hdmi.HdcpState)
      Controls.HDCPState[3].String = jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1].Hdmi.HdcpState
      if Controls.HDCPState[3].String == "HDCPnotRequired" then
        Controls.HDCPState[3].Color = '#00bbff'
      else
        Controls.HDCPState[3].Color = 'red'
      end
    end

  -- HDMI OUTPUT DETECTION
      if jsondata.Device and jsondata.Device.AudioVideoInputOutput and  jsondata.Device.AudioVideoInputOutput.Outputs and jsondata.Device.AudioVideoInputOutput.Outputs[1]  and jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1] and jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1] ~= nil then
        Controls.OutputSyncLed.Boolean = jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1].IsSinkConnected
        debug(9,"output sync is = ", jsondata.Device.AudioVideoInputOutput.Outputs[1].Ports[1].IsSinkConnected)
      if Controls.OutputSyncLed.String == "true" then
        Controls.OutputSyncLed.Boolean = true
      else
        Controls.OutputSyncLed.Boolean = false
      end
    end

  -- USB
    if jsondata.Device and jsondata.Device.Usb and jsondata.Device.Usb.UsbPorts ~= nil then
      debug(9,"GetUsb = " ..jsondata.Device.Usb.UsbPorts[1].Mode)
      Controls.UsbMode.String = jsondata.Device.Usb.UsbPorts[1].Mode 
      Controls.UsbName.String = jsondata.Device.Usb.UsbPorts[1].Name 
      Controls.UsbLocalDeviceId.String = jsondata.Device.Usb.UsbPorts[1].UsbPairing.Layer2.LocalDeviceId
      for i = 1, 7 do
          Controls.RemoteId[i].String = jsondata.Device.Usb.UsbPorts[1].UsbPairing.Layer2.RemoteDevices["Id" .. i]
      end
      for n = 1, 7 do
          Controls.RemoteIdPaired[n].Boolean = jsondata.Device.Usb.UsbPorts[1].UsbPairing.PairedStatus["Id"..n]
      end 
      Controls.MultipleUsbSupport.Boolean = jsondata.Device.Usb.UsbPorts[1].UsbPairing.IsMultipleDeviceSupportEnabled
      if Controls.MultipleUsbSupport.Boolean then
        for i = 2, 7 do
          Controls.RemoteIdPaired[i].IsDisabled = false
          Controls.RemoteId[i].IsDisabled = false
        end
      else 
        for i = 2, 7 do
          Controls.RemoteIdPaired[i].IsDisabled = true
          Controls.RemoteId[i].IsDisabled = true
        end
      end
    end

    if jsondata and jsondata.Actions and #jsondata.Actions > 0 then
      local results = jsondata.Actions[1].Results
        if results and #results > 0 then
            local path = results[1].Path
            local statusInfo = results[1].StatusInfo
              if path == "Device.ControlPorts.Serial.Port1" then
                if statusInfo == "OK" then
                  debug(9,"Serial send ok - fetching Received String")
                  GetReceivedSerial()
                else 
                  debug(9,"Serial failed!")
              end
          end
      end
    end

      -- SERIAL SETTINGS
  --
    if jsondata.Device and jsondata.Device.ControlPorts and jsondata.Device.ControlPorts.Serial and jsondata.Device.ControlPorts.Serial ~= nil then
      Controls.BaudRate.String = jsondata.Device.ControlPorts.Serial.Port1.BaudRate
      Controls.DataBits.String = jsondata.Device.ControlPorts.Serial.Port1.DataBits
      Controls.ReceivedDataFormat.Legend = jsondata.Device.ControlPorts.Serial.Port1.ReceivedDataFormat
      Controls.TransmitDataFormat.Legend = jsondata.Device.ControlPorts.Serial.Port1.TransmitDataFormat
      Controls.StopBits.String = jsondata.Device.ControlPorts.Serial.Port1.StopBits
      Controls.Parity.String = jsondata.Device.ControlPorts.Serial.Port1.Parity
    end
    



      -- SERIAL FEEDBACK 
    if jsondata.Device and jsondata.Device.ControlPorts and jsondata.Device.ControlPorts.Serial and jsondata.Device.ControlPorts.Serial.Port1 and jsondata.Device.ControlPorts.Serial.Port1.ReceivedData ~= nil then
      debug(9,"SERIAL FEEDBACK = "..jsondata.Device.ControlPorts.Serial.Port1.ReceivedData)
      local ReceivedData = jsondata.Device.ControlPorts.Serial.Port1.ReceivedData
      local ReceivedDataItems = {}
      for item in ReceivedData:gmatch("([^:]+):") do
        table.insert(ReceivedDataItems, item)
      end
      local last_item = ReceivedDataItems[#ReceivedDataItems] 
      debug(9,"last item = ", last_item)
      if last_item ~= nil then
        Controls.ReceivedData.String = last_item
      end
    end

  -- USB FEEDBACK
    if jsondata and jsondata.Actions and #jsondata.Actions > 0 then
        local results = jsondata.Actions[1].Results
        if results and #results > 0 then
            local path = results[1].Path
            local statusInfo = results[1].StatusInfo
              if path == "Device.Usb.UsbPorts.Mode" then
                if statusInfo == "1" then
                  Controls.UsbMode.String = "Remote"
                elseif statusInfo == "0" then
                  Controls.UsbMode.String = "Local"
                end
            end
        end
    end
  else
    debug(9,"no json detected in data!")
  end  
end 
 

----------------------------------------------------------------------- INIT ------------------------------------------------------------
function ResetVariables()
  ip = Controls.IP.String
  ip = Controls.IP.String
  un = Controls.Username.String
  pw = Controls.Password.String
  fb = Controls.DeviceFB.String
  nvxBaseUrl = 'https://'..ip..'/' 
  PollingListNumber = 1
  Streams = {} 
  FilteredStreams = {} 
  Receivers = {}   
  authHeader = {}
  Controls.CurrentStream.String = ""
  Controls.ManualStream.String = ""  
  StreamReceiveVariable = Controls.StreamReceive.String
  PollingFunctionActive = false
end

function Initialize()
  GetPreviewActive = false
  -- clear all data
  ClearAll()
  -- authorise stream 
  ResetVariables()
  -- stop ping if already running
  if NVXPing then 
    NVXPing:stop()
  end
  -- check if IP filled out, if so start AuthHandler
  if Controls.IP.String ~= "" then
    AuthHandler()
  else
    print("NO IP ADDRESS")
  end 
  -- start ping 
  NVXPing = Ping.New(ip)
  NVXPing:start(false) 
  NVXPing:setPingInterval(6.0)
  Controls.Mode.IsDisabled = true -- disable mode
  Controls.PreviewImage.Legend = "STARTING"
end

-------------------------------------------------------------------------
-----------------------          EVENTHANDLERS    -----------------------
-------------------------------------------------------------------------

--event handlers re-initialize code

Controls.Status.EventHandler = function()
  if Controls.Status.Value == 0.0 then 
    Controls.Status.Color = "#ff46ff00"
  end
end

Controls.Authorized.EventHandler = function() --ip = Controls.IP.String Initialize() 
end
Controls.IP.EventHandler = function() print("Ip entered, reinitializing") ClearAll() Initialize() end
Controls.Username.EventHandler = function() Initialize() end
Controls.Password.EventHandler = function() Initialize() end
Controls.StreamFilter.EventHandler = function() Initialize() end
Controls.GetAll.EventHandler = function() GetAll() end
Controls.StreamReceive.EventHandler = function() 
  if Controls.StreamReceive.String ~= StreamReceiveVariable then
    receiveStreamChange() 
    Timer.CallAfter(GetCurrentInput, 1) 
    StreamReceiveVariable = Controls.StreamReceive.String
  end
end

Controls.GetPreview.EventHandler = function() 
  if Controls.GetPreview.Boolean then 
    Controls.PreviewImage.Legend = ""
    GetPreview() 
  else
    Controls.PreviewImage.Legend = "PREVIEW OFF"
  end
end 

Controls.Input[1].EventHandler = function() Input = "Input1" ChangeInput(Input)  end
Controls.Input[2].EventHandler = function() Input = "Input2" ChangeInput(Input)  end
Controls.Input[3].EventHandler = function() Input = "Stream" ChangeInput(Input)  end
Controls.UsbSetMode[1].EventHandler = function() ChangeUsbModeRemote() end 
Controls.UsbSetMode[2].EventHandler = function() ChangeUsbModeLocal() end 
Controls.Reboot.EventHandler = function() Reboot() end

-- poll timer eventhandler

PollTimer.EventHandler = function() 
  print("timer tick") 
  print("Poll list number is ", PollingListNumber) 
  PollingFunction() 
end

-------------------------------------------------------------------------
-----------------------          PING             -----------------------
-------------------------------------------------------------------------
 
NVXPing.EventHandler = function(response)
  debug(10,"Host: "..response.HostName)
  debug(10,"Ping seconds: "..response.ElapsedTime)
  Controls.Status.Value = 0
  --if Controls.PreviewImage.Legend == "STARTING" then
  --  GetPreview() 
  --end
end
  
NVXPing.ErrorHandler = function(response)
  debug(10, response.HostName)
  debug(10, response.Error)
  Controls.Status.Value = 2
  Controls.Status.String = "NO PING"
end

-------------------------------------------------------------------------
-----------------------          START OF CODE    -----------------------
-------------------------------------------------------------------------
print("starting up nvx")
Initialize()
