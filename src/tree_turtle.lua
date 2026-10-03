-- Toast Control: Holzfarm. Die Turtle faehrt eine Fahrspur nach vorne entlang;
-- neben der Spur stehen Baeume (rechts, links oder beidseitig). Gewachsene Baeume
-- werden komplett gefaellt (Stamm), danach wird sofort ein neuer Setzling gesetzt.
-- Basis: Kiste UNTER der Turtle = Ausgabe, Kiste UEBER der Turtle = Kohle,
-- optional Kiste HINTER der Turtle = Setzlinge (nur noetig, wenn keine mehr da sind).
-- Am besten 1x1-Baeume: Birke oder Fichte. Eiche geht, Aeste bleiben aber haengen.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.tree
local W=dofile("/toast/toast_worker.lua")
local function isLog(n) return n:find("_log",1,true)~=nil or n:find("_stem",1,true)~=nil or n:find("_wood",1,true)~=nil end
local function isLeaves(n) return n:find("leaves",1,true)~=nil or n:find("wart_block",1,true)~=nil or n=="minecraft:vine" end
local function isSapling(n) return n:find("_sapling",1,true)~=nil or n:find("_propagule",1,true)~=nil
    or n=="minecraft:crimson_fungus" or n=="minecraft:warped_fungus" end
local function isTool(n) return n:find("_axe",1,true)~=nil or n:find("_pickaxe",1,true)~=nil end
local BONE="minecraft:bone_meal"
local function clearable(n) return isLog(n) or isLeaves(n) end
local SIDES=C.side=="both" and {1,3} or (C.side=="left" and {3} or {1})
local STEP=C.spacing+1
local cells=C.trees*#SIDES
local function slotZ(i) return 1+(i-1)*STEP end
local laneLen=slotZ(C.trees)
local w,round,idleHome,idleBase,w_saplings,w_bone,finishColumn
w=W.new({job="tree",cfg=cfg,section=C,stateFile="/toast_tree_state",args={...},cells=cells,
    layout=C.trees..":"..C.spacing..":"..C.side,tools=isTool,noTool="Keine Axt: Diamant-Axt in die Turtle legen",
    interval=C.interval,readyText="START: Dauerbetrieb | 1 RUNDE: einmal alle Baeume",
    extra=function() return {trees=cells,saplings=0+w_saplings(),bonemeal=w_bone(),felled=w and w.st.harvested or 0} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end})
local st,run=w.st,w.run
w_saplings=function() return w.count(isSapling) end
w_bone=function() return w.count(function(n) return n==BONE end) end
local skipped=0
local function logs() return w.count(isLog) end
local function keep(name)
    if isSapling(name) then return C.keepSaplings end
    if name==BONE or W.FUELS[name] or isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    return 0
end
-- ===== Basis =====
local function refillSaplings()
    if w_saplings()>0 then return end
    local ok=w.face(2);if not ok then return end
    if w.container(turtle.inspect) then
        for i=1,16 do
            if turtle.getItemCount(i)==0 then
                turtle.select(i)
                if turtle.suck(math.min(64,C.keepSaplings)) then
                    local it=turtle.getItemDetail(i)
                    if it and not isSapling(it.name) and it.name~=BONE then turtle.drop() end
                end
                break
            end
        end
        -- Knochenmehl ebenfalls aus der hinteren Kiste, wenn eingeschaltet
        if C.bonemeal and w_bone()==0 then
            for i=1,16 do if turtle.getItemCount(i)==0 then turtle.select(i);turtle.suck(64)
                local it=turtle.getItemDetail(i);if it and it.name~=BONE and not isSapling(it.name) then turtle.drop() end;break end end
        end
        turtle.select(1)
    end
    w.face(0)
end
local function base()
    local ok,title,detail=w.unload(keep)
    if not ok then return false,title,detail end
    ok,title,detail=w.refuel(C.fuelTarget)
    if not ok then
        -- Notfall: eigenes Holz verbrennen (15 Fuel pro Stamm), damit sie nicht stehen bleibt
        local need=laneLen*2+C.maxHeight*2+40
        if turtle.getFuelLevel()<need then
            ok=w.refuel(need,isLog)
            if not ok then return false,title,detail end
        end
    end
    refillSaplings()
    return true
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    local okc,whyc=finishColumn();if not okc then return false,whyc end
    w.status("Rueckkehr","Fahre zur Basis.")
    return w.home({dig=true,canDig=clearable})
end
idleBase=function() return base() end
-- ===== Baum faellen =====
local function plant()
    local slot=w.find(isSapling)
    if not slot then return false end
    turtle.select(slot)
    local ok=turtle.place()
    turtle.select(1)
    if not ok then skipped=skipped+1 end
    return ok
end
local function fell(dir)
    w.status("Faellt Baum","Baum "..math.ceil((run.scanned+1)/#SIDES).." / "..C.trees)
    local before=logs()
    local ok,why=w.move("forward",{dig=true,canDig=clearable});if not ok then return false,why end
    local h=0
    while h<C.maxHeight do
        local up,b=turtle.inspectUp()
        if not up or not isLog(b.name) then break end
        ok,why=w.move("up",{dig=true,canDig=clearable});if not ok then return false,why end
        h=h+1
    end
    while st.y>0 do ok,why=w.move("down",{dig=true,canDig=clearable});if not ok then return false,why end end
    -- zurueck auf die Fahrspur, dann wieder zum Baumplatz schauen
    ok,why=w.face((dir+2)%4);if not ok then return false,why end
    ok,why=w.move("forward",{dig=true,canDig=clearable});if not ok then return false,why end
    ok,why=w.face(dir);if not ok then return false,why end
    st.harvested=(st.harvested or 0)+1
    st.total=(st.total or 0)+math.max(0,logs()-before)
    w.save()
    return true
end
-- Knochenmehl direkt nach dem Pflanzen: waechst der Baum, wird er sofort gefaellt
local function boost(dir)
    if not C.bonemeal then return true end
    for _=1,8 do
        local slot=w.find(function(n) return n==BONE end)
        if not slot then return true end
        local e,b=turtle.inspect()
        if not e or not isSapling(b.name) then return true end
        turtle.select(slot);turtle.place();turtle.select(1)
        local e2,b2=turtle.inspect()
        if e2 and isLog(b2.name) then
            local ok,why=fell(dir);if not ok then return false,why end
            plant();return true
        end
    end
    return true
end
-- Nach Absturz mitten im Stamm: Stamm fertig faellen, dann zurueck auf die Spur
finishColumn=function()
    if st.x==0 then return true end
    w.status("Faellt Baum","Stamm nach Neustart fertig faellen.")
    while st.y<C.maxHeight do
        local up,b=turtle.inspectUp()
        if not up or not isLog(b.name) then break end
        local ok,why=w.move("up",{dig=true,canDig=clearable});if not ok then return false,why end
    end
    st.harvested=(st.harvested or 0)+1;w.save()
    return true
end
local function visit(dir)
    local ok,why=w.face(dir);if not ok then return false,why end
    local exists,b=turtle.inspect()
    if exists and isLog(b.name) then
        ok,why=fell(dir);if not ok then return false,why end
        pcall(turtle.suck)
        if plant() then return boost(dir) end
    elseif exists and isSapling(b.name) then
        return boost(dir)
    elseif exists and isLeaves(b.name) then
        turtle.dig();if plant() then return boost(dir) end
    elseif not exists then
        w.status("Pflanzen","Setzling wird gesetzt.")
        if plant() then return boost(dir) end
    else
        skipped=skipped+1
    end
    return true
end
-- Fuel fuer: zurueck zur Basis + ein Baum
local function fuelOk()
    local f=turtle.getFuelLevel()
    if f=="unlimited" then return true end
    return f>=st.z+math.abs(st.x)+st.y+C.maxHeight*2+12
end
local function goSlot(z)
    if st.z~=z then
        local ok,why=w.face(st.z<z and 0 or 2);if not ok then return false,why end
        while st.z~=z do
            if not w.active() then return false,"stopped" end
            pcall(turtle.suck)        -- liegende Setzlinge/Aepfel einsammeln
            ok,why=w.move("forward",{dig=true,canDig=clearable});if not ok then return false,why end
        end
    end
    return true
end
local function resupply()
    local ok,why=idleHome();if not ok then return false,why end
    local ok2,title=base()
    if not ok2 then return false,title end
    return true
end
round=function()
    run.scanned,skipped=0,0
    if not w.isHome() then local ok,why=idleHome();if not ok then w.fail(why);return false end end
    local ok,title,detail=base()
    if not ok then w.status(title,detail);w.fail(title);return false end
    for i=1,C.trees do
        for _,dir in ipairs(SIDES) do
            if not w.active() then return false end
            if not fuelOk() or w.freeSlots()<3 then
                local r,why=resupply();if not r then w.fail(why);return false end
            end
            w.status("Baeume pruefen","Baum "..i.." / "..C.trees)
            local okm,why=goSlot(slotZ(i))
            if not okm then if why~="stopped" then w.fail(why) end;return false end
            okm,why=visit(dir)
            if not okm then w.fail(why);return false end
            run.scanned=run.scanned+1
        end
    end
    w.status("Rueckkehr","Runde fertig, fahre zur Basis.")
    local okh,why=idleHome();if not okh then w.fail("Rueckweg blockiert: "..tostring(why));return false end
    ok,title,detail=base()
    if not ok then w.status(title,detail) end
    return true
end
pcall(w.equipTool,isTool)
w.start("TOAST HOLZ",C.trees.." Baeume, "..(C.side=="both" and "beidseitig" or C.side=="left" and "links" or "rechts"))
