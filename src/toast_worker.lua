-- Toast Control: gemeinsames Grundgeruest fuer Holzfarm- und Mob-Turtles.
-- Enthaelt alles, was jede Turtle braucht: Zustand auf der Disk, Bewegung mit
-- Wiederherstellung nach Absturz (ueber den Fuelstand), Funk mit der Zentrale
-- (START/STOP/1x/RESET), Statusmeldungen, Abladen/Tanken an der Basis und
-- automatische neue Versuche nach Fehlern.
--
-- Koordinaten: Basis = 0,0,0, Blick nach vorne = dir 0 (+z).
-- dir 1 = rechts (+x), 2 = zurueck, 3 = links. y = Hoehe (oben positiv).
-- mirror=true spiegelt rechts/links (Arbeitsbereich liegt links).
local common=dofile("/toast/toast_common.lua")
local W={}
local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
W.DX,W.DZ=DX,DZ
local CONTAINERS={["minecraft:chest"]=true,["minecraft:trapped_chest"]=true,["minecraft:barrel"]=true}
W.FUELS={["minecraft:coal"]=80,["minecraft:charcoal"]=80,["minecraft:coal_block"]=800}

function W.new(o)
    local cfg=o.cfg
    local C=o.section
    local R=common.recovery(cfg.recovery)
    local PROTOCOL=common.workerProtocols[o.job]
    local FILE=o.stateFile
    local MIRROR=o.mirror==true
    local w={cfg=cfg,C=C,R=R}

    -- ===== Zustand =====
    local function readTable(path)
        if not fs.exists(path) then return nil end
        local f=fs.open(path,"r");if not f then return nil end
        local ok,s=pcall(textutils.unserialize,f.readAll());f.close()
        if ok and type(s)=="table" and type(s.x)=="number" and type(s.z)=="number" and type(s.dir)=="number" then return s end
    end
    local st=readTable(FILE..".tmp") or readTable(FILE)
    if not st then
        if fs.exists(FILE) or fs.exists(FILE..".tmp") then
            error("Zustand beschaedigt. Turtle an Basis setzen: toast.lua --dock",0)
        end
        st={x=0,y=0,z=0,dir=0,total=0,harvested=0,rounds=0}
    end
    st.y=st.y or 0
    w.st=st
    local lastSave=0
    function w.save()
        local f=assert(fs.open(FILE..".tmp","w"),"Zustand nicht schreibbar.")
        f.write(textutils.serialize(st));f.close()
        if fs.exists(FILE) then fs.delete(FILE) end
        fs.move(FILE..".tmp",FILE)
    end
    -- Zaehler (Ertrag usw.) nicht bei jedem Schlag schreiben: hoechstens alle 5 s.
    function w.saveSoon() if os.clock()-lastSave>=5 then lastSave=os.clock();w.save() end end
    local function clearPending() st.pending,st.after,st.pendingFuel=nil,nil,nil end
    local function resolvePending()
        if not st.pending then return true end
        local fuel=turtle.getFuelLevel()
        if st.pending~="turn" and type(fuel)=="number" and type(st.pendingFuel)=="number" and type(st.after)=="table" then
            if fuel==st.pendingFuel then clearPending();w.save();return true end
            if fuel==st.pendingFuel-1 then
                st.x,st.y,st.z,st.dir=st.after.x,st.after.y,st.after.z,st.after.dir
                clearPending();w.save();return true
            end
        end
        if st.pending~="turn" and fuel=="unlimited" then return false end
        return false
    end
    local resolvedAtStart=st.pending~=nil and resolvePending()
    for _,a in ipairs(o.args or {}) do
        if a=="--dock" then
            print("Turtle muss an der Basis stehen und nach vorne schauen.")
            write("Zum Bestaetigen DOCK eingeben: ")
            assert(read()=="DOCK","Positionsreset abgebrochen.")
            st.x,st.y,st.z,st.dir=0,0,0,0;clearPending();st.lastMode=nil
        else error("Start: toast.lua [--dock]",0) end
    end
    st.controller=cfg.controllerId
    -- Neue Masse nur an der Basis uebernehmen
    if o.layout then
        assert(not st.layout or st.layout==o.layout or (st.x==0 and st.y==0 and st.z==0 and not st.pending),
            "Masse nur an der Basis aendern. Bei versetzter Turtle: toast.lua --dock")
        st.layout=o.layout
    end
    w.save()
    common.modem()

    -- ===== Laufzustand =====
    local run={mode="off",status="Bereit",detail="START an der Zentrale druecken.",scanned=0,cells=o.cells or 0,
        lastContact=os.clock(),fault=nil,recovery=st.pending~=nil,lastMode=nil,retries=0,retryAt=nil,waitUntil=0}
    w.run=run
    if run.recovery then run.status,run.detail="Position unklar","An Basis setzen; toast.lua --dock starten."
    elseif resolvedAtStart then run.detail="Position nach Neustart wiederhergestellt." end
    if not run.recovery and (st.lastMode=="auto" or st.lastMode=="once") then
        run.mode,run.lastMode=st.lastMode,st.lastMode
        run.status,run.detail="Fortsetzen","Auftrag nach Neustart fortgesetzt."
    end
    function w.status(t,d) run.status,run.detail=t,d or "" end
    function w.fail(why) run.mode,run.fault,run.retryAt="off",why,nil end
    function w.finish()
        run.mode,run.lastMode="off",nil
        if st.lastMode then st.lastMode=nil;w.save() end
    end
    local radioTimeout=C.radioTimeout or 60
    function w.active()
        if run.mode~="off" and radioTimeout>0 and os.clock()-run.lastContact>radioTimeout then w.fail("Funkverbindung verloren") end
        return run.mode~="off" and not run.recovery
    end
    function w.isHome() return st.x==0 and st.y==0 and st.z==0 end

    -- ===== Inventar =====
    function w.freeSlots() local n=0;for i=1,16 do if turtle.getItemCount(i)==0 then n=n+1 end end;return n end
    function w.count(match)
        local n=0
        for i=1,16 do local it=turtle.getItemDetail(i);if it and match(it.name) then n=n+it.count end end
        return n
    end
    function w.find(match)
        for i=1,16 do local it=turtle.getItemDetail(i);if it and match(it.name) then return i,it end end
    end
    function w.items() local n=0;for i=1,16 do n=n+turtle.getItemCount(i) end;return n end
    -- Werkzeug aus dem Inventar anlegen (Seite ohne Modem)
    function w.equipTool(tools)
        for i=1,16 do
            local it=turtle.getItemDetail(i)
            if it and tools(it.name) then
                turtle.select(i)
                for _,side in ipairs({"left","right"}) do
                    if peripheral.getType(side)~="modem" then
                        local fn=side=="left" and turtle.equipLeft or turtle.equipRight
                        if fn() then turtle.select(1);return true end
                    end
                end
            end
        end
        turtle.select(1)
        return false
    end

    -- ===== Bewegung =====
    local function action(kind,fn,update)
        local x,y,z,dir=st.x,st.y,st.z,st.dir
        update();st.after={x=st.x,y=st.y,z=st.z,dir=st.dir}
        st.x,st.y,st.z,st.dir=x,y,z,dir
        st.pending,st.pendingFuel=kind,turtle.getFuelLevel();w.save()
        local ok,why=fn();if ok then update() end
        clearPending();w.save();return ok,why
    end
    function w.face(dir)
        while st.dir~=dir do
            local left=(st.dir-dir)%4==1
            local ok,why=action("turn",(left~=MIRROR) and turtle.turnLeft or turtle.turnRight,
                function() st.dir=(st.dir+(left and 3 or 1))%4 end)
            if not ok then return false,"Drehen fehlgeschlagen: "..tostring(why) end
        end
        return true
    end
    -- opts.dig: Bloecke wegraeumen (nur erlaubte, opts.canDig(name))
    -- opts.attack: Mob im Weg angreifen; sonst nur warten
    local MOVES={
        forward={turtle.forward,turtle.detect,turtle.inspect,turtle.dig,turtle.attack,function() st.x,st.z=st.x+DX[st.dir],st.z+DZ[st.dir] end},
        up={turtle.up,turtle.detectUp,turtle.inspectUp,turtle.digUp,turtle.attackUp,function() st.y=st.y+1 end},
        down={turtle.down,turtle.detectDown,turtle.inspectDown,turtle.digDown,turtle.attackDown,function() st.y=st.y-1 end},
    }
    function w.move(kind,opts)
        opts=opts or {}
        local m=MOVES[kind]
        local last
        for attempt=1,math.max(R.moveRetries,opts.dig and 24 or 0) do
            local ok,why=action("move",m[1],m[6])
            if ok then return true end
            last=why
            if tostring(why):lower():find("fuel",1,true) then return false,"Kein Fuel mehr" end
            if m[2]() then
                local _,b=m[3]()
                local name=b and b.name or "?"
                if opts.dig and (not opts.canDig or opts.canDig(name)) then
                    local dug,dwhy=m[4]()
                    if not dug and tostring(dwhy):find("No tool",1,true) then
                        if o.tools and w.equipTool(o.tools) then dug=m[4]() end
                        if not dug then return false,o.noTool or "Kein Werkzeug" end
                    end
                    if not dug then sleep(0.3) end
                else
                    return false,"Weg blockiert: "..name
                end
            else
                -- Kein Block: Mob/Spieler im Weg
                if opts.attack and attempt>=2 then pcall(m[5]) end
                sleep(opts.attack and 0.3 or 0.6)
            end
        end
        return false,"Weg blockiert: "..tostring(last)
    end
    -- Zu Position fahren: erst Hoehe 0, dann z, dann x (sichere Fahrspur bei x=0)
    function w.home(opts)
        opts=opts or {}
        while st.y>0 do local ok,why=w.move("down",opts);if not ok then return false,why end end
        while st.y<0 do local ok,why=w.move("up",opts);if not ok then return false,why end end
        if st.x~=0 then
            local ok,why=w.face(st.x>0 and 3 or 1);if not ok then return false,why end
            while st.x~=0 do ok,why=w.move("forward",opts);if not ok then return false,why end end
        end
        if st.z~=0 then
            local ok,why=w.face(st.z>0 and 2 or 0);if not ok then return false,why end
            while st.z~=0 do ok,why=w.move("forward",opts);if not ok then return false,why end end
        end
        return w.face(0)
    end

    -- ===== Basis: Abladen (Kiste unten) und Tanken (Kiste oben) =====
    local function container(fn) local ok,b=fn();return ok and CONTAINERS[b.name]==true end
    w.container=container
    -- keep(name,count) -> wie viele davon behalten
    function w.unload(keep)
        if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt","Kiste oder Fass UNTER die Basis setzen." end
        local kept={}
        for i=1,16 do
            local it=turtle.getItemDetail(i)
            if it then
                local want=keep and keep(it.name) or 0
                local k=math.min(it.count,math.max(0,want-(kept[it.name] or 0)))
                kept[it.name]=(kept[it.name] or 0)+k
                local drop=it.count-k
                if drop>0 then
                    turtle.select(i)
                    turtle.dropDown(drop)
                    if turtle.getItemCount(i)>k then turtle.select(1);return false,"Lager voll","Ausgabekiste leeren oder vergroessern." end
                end
            end
        end
        turtle.select(1)
        return true
    end
    -- Bis target tanken; Kohle aus der Kiste oben, sonst extra(name) aus dem Inventar
    function w.refuel(target,extra)
        local lvl=turtle.getFuelLevel()
        if lvl=="unlimited" or lvl>=target then return true end
        -- zuerst Brennstoff aus dem Inventar
        for i=1,16 do
            local it=turtle.getItemDetail(i)
            if it and (W.FUELS[it.name] or (extra and extra(it.name))) then
                turtle.select(i)
                while turtle.getItemCount(i)>0 and turtle.getFuelLevel()<target do if not turtle.refuel(1) then break end end
            end
            if turtle.getFuelLevel()>=target then turtle.select(1);return true end
        end
        if container(turtle.inspectUp) then
            local slot;for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
            while slot and turtle.getFuelLevel()<target do
                turtle.select(slot)
                if not turtle.suckUp(math.max(1,math.min(64,math.ceil((target-turtle.getFuelLevel())/80)))) then break end
                local it=turtle.getItemDetail(slot)
                if not it or not W.FUELS[it.name] then turtle.dropUp();break end
                while turtle.getItemCount(slot)>0 and turtle.getFuelLevel()<target do if not turtle.refuel(1) then break end end
                if turtle.getItemCount(slot)>0 then turtle.dropUp() end
            end
        end
        turtle.select(1)
        if turtle.getFuelLevel()>=target then return true end
        return false,"Treibstoff fehlt","Kohle / Holzkohle in die Kiste UEBER der Basis legen."
    end

    -- ===== Funk =====
    local sendStatus
    local function snapshot()
        local s={kind="status",version=2,id=os.getComputerID(),status=run.status,detail=run.detail,
            mode=run.mode,recovery=run.recovery,ack=st.commandSerial or 0,fault=run.fault,retries=run.retries,
            contactAge=math.max(0,math.floor(os.clock()-run.lastContact)),radioTimeout=radioTimeout,
            fuel=turtle.getFuelLevel(),freeSlots=w.freeSlots(),x=st.x,y=st.y,z=st.z,
            total=st.total or 0,harvested=st.harvested or 0,rounds=st.rounds or 0,
            scanned=run.scanned,cells=run.cells,wait=math.max(0,math.ceil(run.waitUntil-os.clock()))}
        if o.extra then for k,v in pairs(o.extra()) do s[k]=v end end
        s.label,s.job,s.controllerId,s.toast=cfg.label,o.job,cfg.controllerId,common.version
        return s
    end
    sendStatus=function() pcall(rednet.send,st.controller,snapshot(),PROTOCOL) end
    w.sendStatus=sendStatus
    local function reset()
        run.mode,run.fault,run.lastMode,run.retries,run.retryAt,run.waitUntil="off",nil,nil,0,nil,0
        st.lastMode=nil
        if run.recovery and resolvePending() then run.recovery=false end
        if run.recovery then w.status("Position unklar","RESET reicht nicht: an Basis setzen, toast.lua --dock")
        else w.status("Reset","Fehler geloescht; Turtle geht zur Basis.") end
    end
    local function listener()
        while true do
            local e,a,b,c=os.pullEvent()
            if (e=="char" and (a=="q" or a=="Q")) then w.finish();run.fault=nil
            elseif e=="peripheral" or e=="peripheral_detach" then common.refreshModems();sendStatus()
            elseif e=="rednet_message" and a==st.controller and c==PROTOCOL and type(b)=="table" then
                if b.kind=="poll" then run.lastContact=os.clock();sendStatus()
                elseif b.kind=="command" and common.serial(b.serial) and common.actions[b.action] then
                    run.lastContact=os.clock()
                    if b.serial>(st.commandSerial or 0) then
                        st.commandSerial=b.serial
                        if b.action=="stop" then w.finish();run.fault,run.retries,run.retryAt=nil,0,nil
                        elseif b.action=="reset" then reset()
                        elseif not run.recovery then
                            run.mode=b.action=="once" and "once" or "auto"
                            run.lastMode,st.lastMode=run.mode,run.mode
                            run.fault,run.waitUntil,run.retries,run.retryAt=nil,0,0,nil
                        end
                        w.save()
                    end
                    sendStatus()
                end
            end
        end
    end
    local function heartbeat() while true do common.refreshModems();sendStatus();sleep(2) end end

    -- ===== Ablauf =====
    -- Warten, solange aktiv (fuer Pausen zwischen Runden)
    function w.wait(seconds,title,detail)
        run.waitUntil=os.clock()+seconds
        while w.active() and run.waitUntil>os.clock() do
            w.status(title or "Warten",detail or "Naechste Runde startet automatisch.")
            sleep(0.5)
        end
        run.waitUntil=0
    end
    local function idle()
        if o.idleHome then
            local ok,why=o.idleHome()
            if not ok then w.status("Rueckweg blockiert",why);return end
        end
        if o.idleBase then
            local ok,title,detail=o.idleBase()
            if not ok then w.status(title,detail);return end
        end
        if run.fault then
            local now=os.clock()
            if run.lastMode and common.retryable(run.fault) and run.retries<R.autoRetry then
                run.retryAt=run.retryAt or now+R.retryDelay
                local contact=radioTimeout==0 or now-run.lastContact<radioTimeout
                if now>=run.retryAt and contact then
                    run.retries,run.retryAt,run.fault,run.mode=run.retries+1,nil,nil,run.lastMode
                    w.status("Neuer Versuch","Automatisch "..run.retries.."/"..R.autoRetry)
                else
                    w.status(run.fault,contact and ("Neuer Versuch in "..math.max(0,math.ceil(run.retryAt-now))
                        .."s ("..(run.retries+1).."/"..R.autoRetry..") | RESET: abbrechen")
                        or "Warte auf Funkkontakt fuer neuen Versuch")
                end
            else
                w.status(run.fault,"Problem beheben; RESET loescht Fehler, START startet neu.")
            end
        else
            w.status("Bereit",o.readyText or "START: Dauerbetrieb | 1x: eine Runde.")
        end
    end
    local function worker()
        while true do
            if run.recovery then sleep(0.5)
            elseif w.active() then
                local complete=o.round()
                if complete then
                    st.rounds=(st.rounds or 0)+1;run.retries=0;w.save()
                    if run.mode=="once" then w.finish() end
                    if w.active() and (o.interval or 0)>0 then w.wait(o.interval) end
                end
            else
                idle();sleep(0.5)
            end
        end
    end
    function w.start(title,info)
        term.clear();term.setCursorPos(1,1)
        print(title.." - Turtle #"..os.getComputerID())
        print("Zentrale #"..st.controller..(info and (" | "..info) or ""))
        print("Q: Stopp + zur Basis. Ctrl+T: Programmabbruch.")
        if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
        local ok,why=pcall(function() parallel.waitForAll(worker,listener,heartbeat) end)
        if not ok then
            run.mode="off"
            run.recovery=st.pending~=nil and not resolvePending()
            w.status(run.recovery and "Position unklar" or "Programm beendet",tostring(why))
            sendStatus()
            if why~="Terminated" then error(why,0) end
            printError("Abgebrochen.")
        end
    end
    return w
end
return W
