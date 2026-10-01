-- Toast Mining 2.1: Strip-Mining mit parallelen Gaengen, mit eigener Basis.
-- Neu: Positions-Wiederherstellung nach Absturz, RESET, Auto-Retry, Mob-Blockaden.
local common=dofile("/mine_common.lua")
local cfg=common.load();assert(cfg.role=="turtle","Mining Turtle erforderlich.")
common.modem()
local R=cfg.recovery or {autoRetry=3,retryDelay=30,moveRetries=8}
local C,FILE,args=cfg.mine,"/toast_mining_state",{...}
local area,cells=C.length,C.length*C.tunnels
local width=(C.tunnels-1)*(C.gap+1)+1
local layout="strip:"..C.length..":"..C.height..":"..C.tunnels..":"..C.gap
local st={x=0,y=0,z=0,dir=0,next=1,total=0,harvested=0,commandSerial=0,layout=layout}
local function readTable(path)
    if not fs.exists(path) then return nil end
    local f=fs.open(path,"r");if not f then return nil end
    local ok,s=pcall(textutils.unserialize,f.readAll());f.close()
    if ok and type(s)=="table" and type(s.x)=="number" and type(s.y)=="number" and type(s.z)=="number"
        and type(s.dir)=="number" and type(s.next)=="number" then return s end
end
-- Halb geschriebene .tmp-Datei ignorieren und die letzte gute Datei nehmen.
local saved=readTable(FILE..".tmp") or readTable(FILE)
if saved then st=saved
elseif fs.exists(FILE) or fs.exists(FILE..".tmp") then
    error("Mining-Zustand beschaedigt. Turtle an Basis setzen: toast.lua --dock --new",0)
end
local function homePosition() return st.x==0 and st.y==0 and st.z==0 end
local function save()
    local f=assert(fs.open(FILE..".tmp","w"));f.write(textutils.serialize(st));f.close()
    if fs.exists(FILE) then fs.delete(FILE) end;fs.move(FILE..".tmp",FILE)
end
local function clearPending() st.pending,st.after,st.pendingFuel=nil,nil,nil end
-- Unterbrochene Bewegung ueber den Fuelstand aufloesen:
-- Fuel unveraendert = Schritt nicht ausgefuehrt, Fuel -1 = Schritt ausgefuehrt.
local function resolvePending()
    if not st.pending then return true end
    local fuel=turtle.getFuelLevel()
    if st.pending~="turn" and type(fuel)=="number" and type(st.pendingFuel)=="number" and type(st.after)=="table" then
        if fuel==st.pendingFuel then clearPending();save();return true end
        if fuel==st.pendingFuel-1 then
            local a=st.after;st.x,st.y,st.z,st.dir=a.x,a.y,a.z,a.dir;clearPending();save();return true
        end
    end
    return false
end
local resolvedAtStart=st.pending~=nil and resolvePending()
for _,arg in ipairs(args) do
    if arg=="--dock" then
        print("An die ORIGINALBASIS setzen und in die Mine schauen.")
        write("DOCK bestaetigen: ");assert(read()=="DOCK","Abgebrochen.")
        st.x,st.y,st.z,st.dir=0,0,0,0;clearPending();st.lastMode=nil
    elseif arg=="--new" then
        assert(homePosition() and not st.pending,"Neuer Auftrag nur an der Basis; ggf. zuerst --dock.")
        write("Neue Gaenge an dieser Basis? NEU eingeben: ");assert(read()=="NEU","Abgebrochen.")
        st.next,st.layout,st.accessHigh,st.lastMode=1,layout,nil,nil
    else error("Start: toast.lua [--dock] [--new]",0) end
end
assert(st.layout==layout,"Abbaumasse geaendert: an Basis mit --new neuen Auftrag bestaetigen.")
assert(st.x>=0 and st.x<width and st.y>=-(C.height-1) and st.y<=0 and st.z>=0 and st.z<=C.length
    and st.dir>=0 and st.dir<=3 and st.dir%1==0 and st.next>=1 and st.next<=cells+1 and st.next%1==0,
    "Mining-Koordinaten ungueltig. An Basis setzen: toast.lua --dock")
save()
local run={mode="off",status=st.next>cells and "Fertig" or "Bereit",detail="START: Auftrag | 1 GANG: aktuellen Gang",
    recovery=st.pending~=nil,lastContact=os.clock(),fault=nil,onceEnd=nil,lastMode=nil,retries=0,retryAt=nil}
if run.recovery then run.status,run.detail="Position unklar","An Originalbasis setzen; toast.lua --dock"
elseif resolvedAtStart then run.detail="Position nach Neustart wiederhergestellt." end
-- Nach Absturz/Serverneustart den laufenden Auftrag selbst fortsetzen.
if not run.recovery and (st.lastMode=="auto" or st.lastMode=="once") and st.next<=cells then
    run.mode,run.lastMode,run.onceEnd=st.lastMode,st.lastMode,st.onceEnd or cells
    run.status,run.detail="Fortsetzen","Auftrag nach Neustart fortgesetzt."
end
local protected={}
for _,name in ipairs(C.protectedBlocks) do protected[name]=true end
-- Turtles nehmen keinen Schaden und fahren durch Wasser/Lava; abgebaut wird alles.
-- Nur andere Turtles werden nie abgebaut (sonst gehen deine eigenen kaputt).
local hard={['computercraft:turtle_normal']=true,['computercraft:turtle_advanced']=true}
local unbreakable={['minecraft:bedrock']=true,['minecraft:barrier']=true,['minecraft:end_portal_frame']=true,
    ['minecraft:end_portal']=true,['minecraft:nether_portal']=true,['minecraft:reinforced_deepslate']=true}
local liquid={['minecraft:water']=true,['minecraft:flowing_water']=true,['minecraft:lava']=true,['minecraft:flowing_lava']=true}
local function status(a,b) run.status,run.detail=a,b or "" end
local function retryable(fault)
    if type(fault)~="string" then return false end
    for _,w in ipairs({"Geschuetzt","Nicht abbaubar","Fuelbedarf","Position unklar"}) do
        if fault:find(w,1,true) then return false end
    end
    return true
end
local function fail(why)
    run.mode,run.fault,run.retryAt="off",why,nil
end
local function active()
    if run.mode~="off" and os.clock()-run.lastContact>C.radioTimeout then fail("Funkverbindung verloren") end
    return run.mode~="off" and not run.recovery
end
local function action(kind,fn,update)
    local x,y,z,dir=st.x,st.y,st.z,st.dir
    update();st.after={x=st.x,y=st.y,z=st.z,dir=st.dir}
    st.x,st.y,st.z,st.dir=x,y,z,dir
    st.pending,st.pendingFuel=kind,turtle.getFuelLevel();save()
    local ok,why=fn();if ok then update() end
    clearPending();save();return ok,why
end
local function face(dir)
    while st.dir~=dir do
        local left=(st.dir-dir)%4==1
        local ok,why=action("turn",left and turtle.turnLeft or turtle.turnRight,
            function()st.dir=(st.dir+(left and 3 or 1))%4 end)
        if not ok then return false,"Drehen fehlgeschlagen: "..tostring(why) end
    end
    return true
end
local function freeSlots()
    local n=0;for i=1,16 do if turtle.getItemCount(i)==0 then n=n+1 end end;return n
end
local function blockReason(b)
    if unbreakable[b.name] then return "Nicht abbaubar: "..b.name end
    if protected[b.name] or hard[b.name] then return "Geschuetzter Block: "..b.name end
end
local function clear(inspect,dig,interruptible)
    for _=1,C.digRetries do
        if interruptible and not active() then return false,"stopped" end
        local exists,b=inspect()
        if not exists or liquid[b.name] then return true end
        local reason=blockReason(b);if reason then return false,reason end
        if freeSlots()==0 then return false,"Inventar voll / Rueckweg pruefen" end
        local ok,why=dig();if not ok then return false,"Nicht abbaubar: "..b.name.." / "..tostring(why) end
        st.harvested=(st.harvested or 0)+1;save();sleep(0.1)
    end
    local exists,b=inspect();if not exists or liquid[b.name] then return true end
    return false,blockReason(b) or "Zu viel nachrutschender Kies/Sand"
end
local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
local function homeDistance()return st.x+math.max(0,st.z-1)+math.abs(st.y)+(st.z>0 and 1 or 0)end
local function move(kind,interruptible)
    if interruptible and not active() then return false,"stopped" end
    local fuel=turtle.getFuelLevel()
    if interruptible and (freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<homeDistance()+12)) then return false,"resupply" end
    local inspect,dig,fn,update,attack
    if kind=="up" then inspect,dig,fn,attack=turtle.inspectUp,turtle.digUp,turtle.up,turtle.attackUp;update=function()st.y=st.y-1 end
    elseif kind=="down" then inspect,dig,fn,attack=turtle.inspectDown,turtle.digDown,turtle.down,turtle.attackDown;update=function()st.y=st.y+1 end
    else inspect,dig,fn,attack=turtle.inspect,turtle.dig,turtle.forward,turtle.attack;update=function()st.x,st.z=st.x+DX[st.dir],st.z+DZ[st.dir] end end
    local last
    -- Mobs/Spieler im Weg: angreifen, kurz warten, erneut versuchen.
    for attempt=1,R.moveRetries do
        local ok,why=clear(inspect,dig,interruptible);if not ok then return false,why end
        if interruptible and not active() then return false,"stopped" end
        ok,why=action(kind,fn,update)
        if ok then return true end
        last=why
        if tostring(why):lower():find("fuel",1,true) then break end
        if attempt<R.moveRetries then pcall(attack);sleep(0.5) end
    end
    return false,"Bewegung blockiert: "..tostring(last)
end
local clearHeight
local function horizontal(x,z,interruptible,xFirst)
    while st.x~=x or st.z~=z do
        local dir
        if st.x~=x and (xFirst or st.z==z) then dir=st.x<x and 1 or 3
        else dir=st.z<z and 0 or 2 end
        local ok,why=face(dir);if not ok then return false,why end
        ok,why=move("forward",interruptible);if not ok then return false,why end
        if interruptible and st.z==1 and st.x>(st.accessHigh or -1) then
            ok,why=clearHeight();if not ok then return false,why end
            st.accessHigh=st.x;save()
        end
    end
    return true
end
local function vertical(y,interruptible)
    while st.y~=y do local ok,why=move(st.y<y and "down" or "up",interruptible);if not ok then return false,why end end
    return true
end
local function home()
    status("Rueckkehr",run.fault or "Fahre ueber freigelegte Wege zur Basis.")
    local ok,why=true
    if st.z>0 then
        ok,why=vertical(0,false)
        if ok then ok,why=horizontal(0,1,false,false) end
        if ok then ok,why=vertical(0,false) end
        if ok then ok,why=horizontal(0,0,false,false) end
    end
    if ok then ok,why=face(0) end
    return ok,why
end
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
local function container(fn)local ok,b=fn();return ok and containers[b.name] end
local function unload()
    if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
    for i=1,16 do
        if turtle.getItemCount(i)>0 then
            if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
            turtle.select(i);local before=turtle.getItemCount(i);turtle.dropDown()
            local delivered=before-turtle.getItemCount(i)
            st.total=(st.total or 0)+delivered;save()
            if turtle.getItemCount(i)>0 then return false,"Lager voll" end
        end
    end
    return true
end
local minimum=2*(width+C.length)+4*C.height+40
local fuelTarget=math.max(C.fuelTarget,minimum)
local limit=turtle.getFuelLimit()
assert(limit=="unlimited" or fuelTarget<=limit,"Fuelbedarf groesser als Tank; Config/Feld verkleinern.")
local FUELS={['minecraft:coal']=80,['minecraft:charcoal']=80,['minecraft:coal_block']=800}
local function refuel()
    if turtle.getFuelLevel()=="unlimited" then return true end
    local value=80
    while turtle.getFuelLevel()<fuelTarget do
        if not active() then return false,"stopped" end
        if not container(turtle.inspectUp) then return false,"Brennstoffkiste fehlt" end
        local slot
        for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
        if not slot then return false,"Inventar voll" end
        turtle.select(slot)
        local want=math.max(1,math.min(64,math.ceil((fuelTarget-turtle.getFuelLevel())/value)))
        if not turtle.suckUp(want) then return false,"Treibstoff fehlt" end
        local item=turtle.getItemDetail(slot)
        if not item or not FUELS[item.name] then
            turtle.dropUp()
            return false,"Brennstoffkiste: nur Kohle/Holzkohle/Kohleblock"
        end
        value=FUELS[item.name]
        while turtle.getItemCount(slot)>0 and turtle.getFuelLevel()<fuelTarget do
            if not turtle.refuel(1) then return false,"Betanken fehlgeschlagen" end
        end
        -- Ueberschuss zurueck in die Brennstoffkiste, nicht ins Beutelager.
        if turtle.getItemCount(slot)>0 then turtle.dropUp() end
    end
    return true
end
local function supplies()
    local ok,why=home();if not ok then return false,why end
    while active() do
        ok,why=unload();if ok then ok,why=refuel() end
        if ok then return true end
        if why=="stopped" then return false,why end
        status(why,"Problem an Basis beheben. STOP bricht Warten ab.")
        sleep(1)
    end
    return false,"stopped"
end
local function target(index)
    local tunnel=math.floor((index-1)/C.length)
    return tunnel*(C.gap+1),0,(index-1)%C.length+1
end
local function resumePath()
    local x,_,z=target(st.next)
    local ok,why=horizontal(0,1,true,false);if not ok then return false,why end
    ok,why=horizontal(x,1,true,true);if not ok then return false,why end
    return horizontal(x,z,true,false)
end
clearHeight=function()
    for y=1,C.height-1 do
        local ok,why=move("up",true);if not ok then return false,why end
    end
    return vertical(0,true)
end
local function finish()
    run.mode,run.lastMode="off",nil
    if st.lastMode then st.lastMode=nil;save() end
end
local function idle()
    local ok,why=home()
    if not ok then status("Rueckweg blockiert",why);return end
    ok,why=unload()
    if not ok then status(why,"Ausgabe an Basis pruefen.")
    elseif run.fault then
        local now=os.clock()
        if run.lastMode and retryable(run.fault) and run.retries<R.autoRetry then
            run.retryAt=run.retryAt or now+R.retryDelay
            local contact=now-run.lastContact<C.radioTimeout
            if now>=run.retryAt and contact then
                run.retries=run.retries+1;run.retryAt=nil;run.fault=nil;run.mode=run.lastMode
                status("Neuer Versuch","Automatisch "..run.retries.."/"..R.autoRetry)
            else
                status(run.fault,contact and ("Neuer Versuch in "..math.max(0,math.ceil(run.retryAt-now)).."s ("..(run.retries+1).."/"..R.autoRetry..") | RESET: abbrechen")
                    or "Warte auf Funkkontakt fuer neuen Versuch")
            end
        else
            status(run.fault,"Problem beheben; RESET loescht Fehler, START setzt fort.")
        end
    elseif st.next>cells then status("Fertig","Neuer Auftrag: toast.lua --new")
    else status("Bereit","START setzt fort | 1 GANG: aktuellen Gang") end
end
local function work()
    while true do
        if not run.recovery then
            if active() then
                if st.next>cells then finish();status("Fertig","Neuer Auftrag: toast.lua --new")
                else
                    local ok,why=true
                    local fuel=turtle.getFuelLevel()
                    if homePosition() or freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<homeDistance()+12) then
                        ok,why=supplies()
                    end
                    if ok and active() then
                        status("Abbau","Gang "..(math.floor((st.next-1)/area)+1).." / "..C.tunnels)
                        if homePosition() then ok,why=resumePath()
                        else
                            local x,y,z=target(st.next)
                            if st.y~=0 then
                                ok,why=vertical(0,true)
                                if ok then ok,why=horizontal(x,z,true,false) end
                            elseif (st.next-1)%area==0 then
                                ok,why=supplies();if ok then ok,why=resumePath() end
                            else ok,why=horizontal(x,z,true,false) end
                        end
                    end
                    if ok and active() and not (st.z==1 and st.x<=(st.accessHigh or -1)) then ok,why=clearHeight() end
                    if ok and active() then
                        st.next=st.next+1;save();run.retries=0
                        if run.mode=="once" and st.next>run.onceEnd then finish() end
                        if st.next>cells then finish() end
                    elseif not ok and why=="resupply" then
                        local ready,problem=supplies()
                        if not ready and problem~="stopped" then fail(problem) end
                    elseif not ok and why~="stopped" then fail(why) end
                end
            end
            if not active() then idle() end
        end
        sleep(0.2)
    end
end
local function snapshot()
    return {kind="status",version=2,id=os.getComputerID(),status=run.status,detail=run.detail,
        mode=run.mode,recovery=run.recovery,ack=st.commandSerial or 0,fault=run.fault,retries=run.retries,
        contactAge=math.max(0,math.floor(os.clock()-run.lastContact)),radioTimeout=C.radioTimeout,pollToken=run.pollToken,
        width=width,length=C.length,height=C.height,tunnels=C.tunnels,gap=C.gap,fuel=turtle.getFuelLevel(),freeSlots=freeSlots(),
        x=st.x,y=st.y,z=st.z,total=st.total or 0,harvested=st.harvested or 0,
        rounds=math.floor((st.next-1)/area),scanned=st.next-1,cells=cells}
end
local function sendStatus()pcall(rednet.send,cfg.controllerId,snapshot(),common.protocol)end
local function reset()
    run.mode,run.fault,run.lastMode,run.retries,run.retryAt="off",nil,nil,0,nil
    st.lastMode=nil
    if run.recovery and resolvePending() then run.recovery=false end
    if run.recovery then status("Position unklar","RESET reicht nicht: an Basis setzen, toast.lua --dock")
    else status("Reset","Fehler geloescht; Turtle faehrt zur Basis.") end
end
local function listener()
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="char" and (a=="q" or a=="Q") then finish();run.fault=nil
        elseif e=="peripheral" or e=="peripheral_detach" then common.refreshModems();sendStatus()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.protocol and type(b)=="table" then
            if b.kind=="poll" then run.lastContact=os.clock();run.pollToken=b.token;sendStatus()
            elseif b.kind=="command" and common.serial(b.serial) and ({start=true,stop=true,once=true,reset=true})[b.action] then
                run.lastContact=os.clock()
                if b.serial>(st.commandSerial or 0) then
                    st.commandSerial=b.serial
                    if b.action=="stop" then finish();run.fault,run.retries,run.retryAt=nil,0,nil
                    elseif b.action=="reset" then reset()
                    elseif not run.recovery and st.next<=cells then
                        run.mode=b.action=="once" and "once" or "auto";run.fault,run.retries,run.retryAt=nil,0,nil
                        run.lastMode=run.mode
                        run.onceEnd=(math.floor((st.next-1)/area)+1)*area
                        st.lastMode,st.onceEnd=run.mode,run.onceEnd
                    end
                    save()
                end
                sendStatus()
            end
        end
    end
end
local function heartbeat()while true do common.refreshModems();sendStatus();sleep(2)end end
term.clear();term.setCursorPos(1,1)
print("TOAST MINING 2.1 / Turtle #"..os.getComputerID())
print(C.tunnels.." Gaenge / "..C.length.." lang / "..C.height.." hoch / Abstand "..C.gap)
print("Zentrale #"..cfg.controllerId)
print("Q: Stopp/Heimfahrt. Ctrl+T: Abbruch.")
if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
local ok,why=pcall(function()parallel.waitForAll(work,listener,heartbeat)end)
if not ok then
    run.mode="off";run.recovery=st.pending~=nil and not resolvePending()
    status(run.recovery and "Position unklar" or "Programm beendet",tostring(why));sendStatus()
    if why~="Terminated" then error(why,0) end
    printError("Abgebrochen.")
end
