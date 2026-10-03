-- Toast Control: Holzfaeller im Gelaende. Die Turtle faehrt ein Gebiet vor der
-- Basis (Laenge nach vorne x Breite zur Seite) in Bahnen ab, folgt dabei dem
-- Boden (klettert ueber Huegel, steigt in Senken ab) und sucht links und rechts
-- nach Baeumen. Gefundene Baeume (egal wo sie stehen) werden komplett gefaellt
-- (ganzer Stamm), auf Wunsch wird ein Setzling nachgepflanzt.
-- Baut ausser Holz und Blaettern NIE etwas ab.
-- Basis: Kiste UNTER der Turtle = Ausgabe, Kiste UEBER der Turtle = Kohle,
-- optional Kiste HINTER der Turtle = Setzlinge.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.tree
local W=dofile("/toast/toast_worker.lua")
local function isLog(n) return n:find("_log",1,true)~=nil or n:find("_stem",1,true)~=nil
    or (n:find("_wood",1,true)~=nil and n:find("planks",1,true)==nil) end
local function isLeaves(n) return n:find("leaves",1,true)~=nil or n:find("wart_block",1,true)~=nil
    or n=="minecraft:vine" or n=="minecraft:shroomlight" end
local function isSapling(n) return n:find("_sapling",1,true)~=nil or n:find("_propagule",1,true)~=nil
    or n=="minecraft:crimson_fungus" or n=="minecraft:warped_fungus" end
local function isTool(n) return n:find("_axe",1,true)~=nil or n:find("_pickaxe",1,true)~=nil end
local CLIMB=C.climb or 8
-- Bahnen alle 3 Bloecke: jede Bahn prueft links und rechts mit (Drehen kostet kein Fuel)
local POINTS={}
do
    local lanes={}
    if C.width<=2 then lanes={math.min(1,C.width-1)}
    else local x=1;while x<C.width do lanes[#lanes+1]=x;x=x+3 end
        if lanes[#lanes]<C.width-2 then lanes[#lanes+1]=C.width-1 end end
    for i,x in ipairs(lanes) do
        if i%2==1 then for z=1,C.length do POINTS[#POINTS+1]={x,z} end
        else for z=C.length,1,-1 do POINTS[#POINTS+1]={x,z} end end
    end
end
local w,round,idleHome,idleBase
w=W.new({job="tree",cfg=cfg,section=C,stateFile="/toast_tree_state",args={...},cells=#POINTS,
    layout="forest:"..C.length..":"..C.width..":"..C.side,mirror=C.side=="left",
    tools=isTool,noTool="Keine Axt: Diamant-Axt in die Turtle legen",
    interval=C.interval,readyText="START: Dauerbetrieb | 1 RUNDE: Gebiet einmal absuchen",
    extra=function() return {saplings=w and w.count(isSapling) or 0,felled=w and w.st.harvested or 0} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end})
local st,run=w.st,w.run
local function logs() return w.count(isLog) end
local function keep(name)
    if isSapling(name) then return C.keepSaplings end
    if W.FUELS[name] or isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    return 0
end
local function inArea(x,z) return x>=0 and x<C.width and z>=1 and z<=C.length end
local fell
local T
-- Vor jedem Schritt: steht ein Stamm vor der Nase -> faellen
local function checkFront()
    local e,b=turtle.inspect()
    if e and isLog(b.name) then return fell(st.dir) end
    return true
end
T=w.terrain({climb=CLIMB,inArea=inArea,attack=true,canDig=isLeaves,hugThrough=isLeaves,
    extraCost=C.maxHeight*2+10,before=function() pcall(turtle.suck);checkFront() end,
    facing=function() return checkFront() end})
-- ===== Basis =====
local function refillSaplings()
    if not C.replant or w.count(isSapling)>0 then return end
    if not w.face(2) then return end
    if w.container(turtle.inspect) then
        for i=1,16 do
            if turtle.getItemCount(i)==0 then
                turtle.select(i)
                if turtle.suck(math.min(64,C.keepSaplings)) then
                    local it=turtle.getItemDetail(i)
                    if it and not isSapling(it.name) then turtle.drop() end
                end
                break
            end
        end
        turtle.select(1)
    end
    w.face(0)
end
local function base()
    local before=logs()
    local ok,title,detail=w.unload(keep)
    if not ok then return false,title,detail end
    ok,title,detail=w.refuel(C.fuelTarget)
    if not ok then
        -- Notfall: eigenes Holz verbrennen (15 Fuel pro Stamm), damit sie nicht stehen bleibt
        local need=(C.length+C.width)*3+C.maxHeight*2+CLIMB*4+60
        if turtle.getFuelLevel()<need then
            ok=w.refuel(need,isLog)
            if not ok then return false,title,detail end
        end
    end
    refillSaplings()
    return true
end
-- ===== Baum faellen =====
local function plantBelow()
    if not C.replant then return false end
    local slot=w.find(isSapling)
    if not slot then return false end
    turtle.select(slot)
    local ok=turtle.placeDown()
    turtle.select(1)
    return ok
end
local function dig(fn)
    local ok,why=fn()
    if not ok and tostring(why):find("No tool",1,true) then
        if w.equipTool(isTool) then ok,why=fn() end
    end
    return ok,why
end
-- Turtle steht vor dem Stamm (Blick dir). Stamm ganz faellen (hoch und runter),
-- unten nachpflanzen, dann zurueck auf das Feld davor und wieder zum Stamm schauen.
fell=function(dir)
    w.status("Faellt Baum","Baum gefunden, wird gefaellt.")
    local before=logs()
    local y0=st.y
    local ok,why=dig(turtle.dig);if not ok then return false,"Baum nicht abbaubar: "..tostring(why) end
    st.felling=true;w.save()
    ok,why=T.mv("forward");if not ok then st.felling=nil;return false,why end
    -- hoch
    while st.y-y0<C.maxHeight do
        local e,b=turtle.inspectUp()
        if not e or not isLog(b.name) then break end
        if not dig(turtle.digUp) then break end
        if not T.mv("up") then break end
    end
    -- zurueck auf Starthoehe, dann Stamm nach unten (Baum steht tiefer)
    while st.y>y0 do if not T.mv("down") then break end end
    while true do
        local e,b=turtle.inspectDown()
        if not e or not isLog(b.name) then break end
        if not dig(turtle.digDown) then break end
        if not T.mv("down") then break end
    end
    local planted=false
    -- nachpflanzen: einen hoch, Setzling nach unten (auf den Boden unter dem Stamm)
    if C.replant and w.find(isSapling) then
        local e=turtle.detectDown()
        if e and T.mv("up") then planted=plantBelow() end
    end
    -- zurueck auf das Feld davor (auf Starthoehe oder knapp darueber)
    while st.y<y0 do if not T.mv("up") then break end end
    ok,why=w.face((dir+2)%4);if not ok then return false,why end
    ok,why=T.mv("forward")
    if not ok then
        -- Feld davor auf dieser Hoehe belegt: eine Stufe hoeher versuchen
        if T.mv("up") then ok,why=T.mv("forward") end
        if not ok then return false,"Rueckweg vom Baum: "..tostring(why) end
    end
    T.hug()
    st.felling=nil
    st.harvested=(st.harvested or 0)+1
    st.total=(st.total or 0)+math.max(0,logs()-before)
    if planted then st.planted=(st.planted or 0)+1 end
    w.save()
    pcall(turtle.suck)
    return w.face(dir)
end
-- Nach Absturz mitten im Stamm: Rest des Stamms ueber der Turtle noch faellen
local function finishColumn()
    if not st.felling then return true end
    w.status("Faellt Baum","Stamm nach Neustart fertig faellen.")
    local y0=st.y
    while st.y-y0<C.maxHeight do
        local e,b=turtle.inspectUp()
        if not e or not isLog(b.name) then break end
        if not dig(turtle.digUp) or not T.mv("up") then break end
    end
    while st.y>y0 do if not T.mv("down") then break end end
    st.felling=nil;st.harvested=(st.harvested or 0)+1;w.save()
    return true
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    finishColumn()
    w.status("Rueckkehr","Faehrt zur Basis.")
    return T.home()
end
-- Ohne Auftrag / nach Fehler: nur abladen. Nicht tanken/Setzlinge holen, sonst
-- dreht sie sich alle halbe Sekunde zur hinteren Kiste und zurueck.
idleBase=function() return w.unload(keep) end
local function resupply()
    w.status("Rueckkehr","Nachschub / Abladen an der Basis.")
    local ok,why=T.home();if not ok then return false,"Rueckweg: "..tostring(why) end
    local ok2,title=base();if not ok2 then return false,title end
    return T.leave()
end
-- Links und rechts nach Baeumen sehen
local function lookAround()
    -- Bahnen laufen in z-Richtung: Baeume stehen links/rechts (x-Richtung)
    for _,d in ipairs({1,3}) do
        local ok=w.face(d);if not ok then return false end
        local e,b=turtle.inspect()
        if e and isLog(b.name) then
            local okf,why=fell(d);if not okf then return false,why end
        end
    end
    return true
end
round=function()
    if not w.isHome() then local ok,why=idleHome();if not ok then w.fail(why);return false end end
    local ok,title,detail=base()
    if not ok then w.status(title,detail);w.fail(title);return false end
    st.sweep=st.sweep or 1
    if st.sweep>#POINTS then st.sweep=1 end
    local okl,whyl=T.leave();if not okl then w.fail(whyl);return false end
    while st.sweep<=#POINTS do
        if not w.active() then return false end
        if T.fuel()<T.homeCost()+20 or w.freeSlots()<3 then
            local r,why=resupply();if not r then w.fail(why);return false end
        end
        local p=POINTS[st.sweep]
        run.scanned=st.sweep-1
        w.status("Sucht Baeume","Bahn "..math.ceil(st.sweep/C.length).." , Feld "..st.sweep.." / "..#POINTS)
        local okn,whyn=T.nav(p[1],p[2],true,true)
        if not okn then
            if whyn=="stopped" then return false end
            if whyn=="lowFuel" then
                local r,why=resupply();if not r then w.fail(why);return false end
            elseif whyn~="kein Weg" then w.fail(whyn);return false end
            -- unerreichbar: Punkt auslassen
            if whyn=="kein Weg" then st.sweep=st.sweep+1 end
        else
            local oka,whya=lookAround();if not oka and whya then w.fail(whya);return false end
            st.sweep=st.sweep+1;w.saveSoon()
        end
    end
    st.sweep=1;run.scanned=#POINTS
    local okh,whyh=idleHome();if not okh then w.fail("Rueckweg: "..tostring(whyh));return false end
    ok,title,detail=base()
    if not ok then w.status(title,detail) end
    return true
end
math.randomseed(os.epoch and os.epoch("utc") or math.floor(os.clock()*1000))
pcall(w.equipTool,isTool)
w.start("TOAST HOLZ","Gebiet "..C.length.."x"..C.width..(C.side=="left" and " links" or " rechts"))
