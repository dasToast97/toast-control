-- Toast Control: GPS-Sender. Beantwortet GPS-Anfragen (gps locate) von Turtles,
-- Pockets und Computern mit den eigenen Koordinaten. Man braucht mindestens 4
-- GPS-Sender, die NICHT alle auf einer Hoehe/Ebene stehen.
-- Koordinaten: aus der Config (gps.x/y/z) oder - wenn schon andere GPS-Sender
-- laufen und gps.auto = true - beim Start selbst per GPS ermittelt.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load();assert(cfg.role=="gps","GPS-Sender erforderlich.")
local G=cfg.gps
local CH=gps and gps.CHANNEL_GPS or 65534
local function wireless()
    local list={}
    for _,name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name)=="modem" then
            local m=peripheral.wrap(name)
            if m and m.isWireless and m.isWireless() then m.open(CH);list[name]=m end
        end
    end
    return list
end
local modems=wireless()
assert(next(modems),"Funk- oder Endermodem fehlt (Endermodem = unbegrenzte Reichweite).")
local x,y,z,source=G.x,G.y,G.z,"Config"
if G.auto and gps and gps.locate then
    print("Suche eigene Position per GPS ...")
    local ok,ax,ay,az=pcall(gps.locate,2)
    if ok and ax then
        x,y,z,source=math.floor(ax+0.5),math.floor(ay+0.5),math.floor(az+0.5),"GPS"
        if x~=G.x or y~=G.y or z~=G.z then
            -- gefundene Position merken (falls spaeter weniger Sender laufen)
            G.x,G.y,G.z=x,y,z
            pcall(function()
                local c=common.withDefaults(dofile("/toast.config.lua"));c.gps.x,c.gps.y,c.gps.z=x,y,z
                local f=fs.open("/toast.config.lua","w");f.write(common.configText(c));f.close()
            end)
        end
    end
end
local served,last,started=0,"-",os.clock()
common.refreshModems()       -- rednet fuer Meldung an die Zentrale und Update-Befehl
local function draw()
    local w,h=term.getSize()
    term.setBackgroundColor(colors.black);term.clear()
    local function line(yy,text,col)
        if yy>h then return end
        term.setCursorPos(1,yy);if term.isColor and term.isColor() then term.setTextColor(col or colors.white) end
        term.write(tostring(text):sub(1,w))
    end
    line(1,"TOAST GPS-SENDER  #"..os.getComputerID(),colors.cyan)
    line(3,"Position  X "..x.."  Y "..y.."  Z "..z,colors.lime)
    line(4,"Quelle    "..source,colors.lightGray)
    local n=0;for _ in pairs(modems) do n=n+1 end
    line(5,"Modems    "..n,colors.lightGray)
    line(7,"Anfragen  "..served)
    line(8,"Zuletzt   "..last,colors.lightGray)
    line(10,"Mind. 4 Sender, nicht alle auf einer Ebene.",colors.lightGray)
    line(11,"Q: beenden",colors.lightGray)
end
draw()
local timer=os.startTimer(2)
while true do
    local e,a,b,c,d,dist=os.pullEvent()
    if e=="modem_message" and b==CH and d=="PING" and dist then
        local m=modems[a] or peripheral.wrap(a)
        if m then pcall(m.transmit,c,CH,{x,y,z});served=served+1;last=(textutils.formatTime and textutils.formatTime(os.time(),true) or "jetzt") end
        draw()
    elseif e=="peripheral" or e=="peripheral_detach" then modems=wireless();draw()
    elseif e=="rednet_message" and common.isUpdateFor(cfg,a,b) then
        local ok,why=common.selfUpdate()
        if not ok then common.log("Update: "..tostring(why)) end
    elseif e=="timer" and a==timer then
        cfg.gps.x,cfg.gps.y,cfg.gps.z,cfg.gps.set=x,y,z,true
        common.nodeBeacon(cfg,"gps",{gps=served})
        draw();timer=os.startTimer(10)
    elseif e=="char" and (a=="q" or a=="Q") then
        term.clear();term.setCursorPos(1,1);print("GPS-Sender beendet.");return
    end
end
