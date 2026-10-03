-- Toast Wireless Repeater | CC:Tweaked Rednet | Farm + Strip Mining
-- Start: repeater.lua. Q oder Ctrl+T beendet und schliesst eigene Kanaele.
local gpsHost
local CHANNEL_REPEAT, CHANNEL_BROADCAST, MAX_ID = 65533, 65535, 65500
local CACHE_SECONDS, CACHE_LIMIT = 30, 4096
local modems, seen, cacheCount = {}, {}, 0
local repeated, duplicates, dropped = 0, 0, 0
local function integer(n,lo,hi)
    return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi
end
local function scan()
    local current={}
    for _,name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name)=="modem" then
            local m=peripheral.wrap(name)
            if m and m.isWireless() then
                local owned=modems[name] and modems[name].owned or not m.isOpen(CHANNEL_REPEAT)
                m.open(CHANNEL_REPEAT);current[name]={device=m,owned=owned}
            end
        end
    end
    modems=current
end
-- Toast-Netz: nebenbei GPS-Sender und Meldung an die Zentrale (falls Toast installiert)
local common,toastCfg
pcall(function()
    common=dofile("/toast/toast_common.lua")
    toastCfg=common.load()
    common.refreshModems()
    gpsHost=common.gpsHost(toastCfg,true)
end)
local beaconAt=-1e9
local function beacon()
    if not common or os.clock()-beaconAt<10 then return end
    beaconAt=os.clock()
    common.nodeBeacon(toastCfg,"repeater",{repeated=repeated,gps=gpsHost and gpsHost.served or nil})
end
local function draw()
    local w,h=term.getSize()
    term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear()
    local function line(y,text)
        if y<=h then term.setCursorPos(1,y);term.write(tostring(text):sub(1,w)) end
    end
    local count=0;for _ in pairs(modems) do count=count+1 end
    local label=os.getComputerLabel and os.getComputerLabel()
    line(1,"TOAST / WIRELESS REPEATER"..(label and (" / "..label) or ""))
    line(3,"Computer-ID: "..os.getComputerID())
    line(4,"Funkmodems: "..count..(count==0 and " - BITTE ANBRINGEN" or " / AKTIV"))
    line(6,"Weitergeleitet: "..repeated)
    line(7,"Doppelte ignoriert: "..duplicates)
    line(8,"Cache voll: "..dropped)
    line(10,"Rednet: Farm, Mining, Pocket")
    line(12,"Endermodem: Reichweite unbegrenzt")
    line(11,"IDs bleiben unveraendert.")
    line(13,gpsHost and ("GPS-Sender: "..gpsHost.served.." Anfragen") or "GPS-Sender: aus")
    line(13,gpsHost and ("GPS-Sender: "..gpsHost.x.." "..gpsHost.y.." "..gpsHost.z.."  ("..gpsHost.served..")") or "")
    line(14,"Q / Ctrl+T: beenden")
end
local function cleanup()
    for _,m in pairs(modems) do if m.owned then pcall(m.device.close,CHANNEL_REPEAT) end end
end
local function loop()
    scan();draw();local timer=os.startTimer(1)
    while true do
        local e,name,channel,reply,message,dist=os.pullEventRaw()
        if gpsHost and gpsHost.event(e,name,channel,reply,message,dist) then
            -- GPS-Anfrage beantwortet
        elseif e=="rednet_message" and common and toastCfg and common.isUpdateFor(toastCfg,name,channel) then
            -- Update-Befehl der Zentrale (name=Absender, channel=Nachricht)
            cleanup()
            local ok,why=common.selfUpdate(nil,type(channel)=="table" and channel.target or nil)
            if not ok then common.log("Update: "..tostring(why)) end
            scan()
        elseif e=="terminate" or (e=="char" and (name=="q" or name=="Q")) then return
        elseif e=="peripheral" or e=="peripheral_detach" then scan();draw()
        elseif e=="term_resize" then draw()
        elseif e=="timer" and name==timer then
            local now=os.clock()
            for id,expires in pairs(seen) do if expires<=now then seen[id]=nil;cacheCount=cacheCount-1 end end
            beacon();draw();timer=os.startTimer(1)
        elseif e=="modem_message" and modems[name] and channel==CHANNEL_REPEAT
            and integer(reply,0,65535) and type(message)=="table"
            and integer(message.nMessageID,0,9007199254740991)
            and integer(message.nRecipient,0,9007199254740991) then
            local id=message.nMessageID
            if seen[id] and seen[id]>os.clock() then duplicates=duplicates+1
            elseif cacheCount>=CACHE_LIMIT then dropped=dropped+1
            else
                if not seen[id] then cacheCount=cacheCount+1 end
                seen[id]=os.clock()+CACHE_SECONDS
                local recipient=message.nRecipient==CHANNEL_BROADCAST and CHANNEL_BROADCAST or message.nRecipient%MAX_ID
                for _,m in pairs(modems) do
                    pcall(m.device.transmit,recipient,reply,message)
                    pcall(m.device.transmit,CHANNEL_REPEAT,reply,message)
                end
                repeated=repeated+1
            end
        end
    end
end
local ok,why=pcall(loop);cleanup()
term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
if not ok and tostring(why):find("TOAST_UPDATE",1,true) then error(why,0) end
if not ok then printError(tostring(why)) else print("Repeater beendet.") end
