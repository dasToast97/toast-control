-- Toast Control: Mob-Turtle mit Schwert. Drei Arten (mob.mode):
--   "farm"   Mobfarm: steht an der Toetungsstelle, schlaegt zu, sammelt Drops und
--            liefert sie in die Kiste UNTER sich.
--   "guard"  Wache: steht an einer Stelle (Tor, Gang) und wehrt Mobs ab.
--   "patrol" Waechter: faehrt im Gebiet (Rechteck vor der Basis) zufaellig umher,
--            folgt dem Gelaende (klettert ueber Huegel, steigt in Senken ab) und
--            greift Mobs an. Erst wenn das Fuel knapp wird, faehrt er zur Basis,
--            tankt, liefert Drops ab und macht weiter. Baut NIE Bloecke ab.
--            Basis: Kiste unten = Drops, Kiste oben = Kohle.
-- Achtung: Eine Turtle kann Mobs und Spieler nicht unterscheiden. Sie greift an,
-- was direkt vor ihr steht (unterwegs erst nach kurzem Warten).
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.mob
local W=dofile("/toast/toast_worker.lua")
local PATROL=C.mode=="patrol"
local CLIMB=C.climb or 8
local function isTool(n) return n:find("_sword",1,true)~=nil or n:find("_axe",1,true)~=nil end
local function keep(name)
    if W.FUELS[name] and PATROL then return 4096 end
    if isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    return 0
end
local DIRS=C.attack=="all" and {"front","up","down"} or C.attack=="up" and {"up"} or {"front"}
local ATTACK={front=turtle.attack,up=turtle.attackUp,down=turtle.attackDown}
local SUCK={front=turtle.suck,up=turtle.suckUp,down=turtle.suckDown}
local w,round,idleHome,idleBase
local lastHit=0
-- Fortschritt beim Waechter: verbrauchter Tank (voll = 0 %, Rueckkehr = 100 %)
local tankStart=0
w=W.new({job="mob",cfg=cfg,section=C,stateFile="/toast_mob_state",args={...},cells=PATROL and 100 or 0,
    layout=C.mode..":"..C.length..":"..C.width..":"..C.side,mirror=PATROL and C.side=="left",
    tools=isTool,noTool="Kein Schwert: Diamant-Schwert in die Turtle legen",
    interval=PATROL and C.interval or 0,
    readyText=PATROL and "START: patrouilliert bis Tank leer, tankt, weiter | 1x: eine Tankfuellung"
        or "START: Dauerbetrieb | 1x: bis keine Mobs mehr da",
    extra=function() return {mobMode=C.mode,hits=w and w.st.harvested or 0,lastHit=math.floor(os.clock()-lastHit),
        targets=w and w.st.targets or 0,looted=w and w.st.looted or 0,carried=w and w.items() or 0} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end})
local st,run=w.st,w.run
local lastUnload=os.clock()
-- Einmal in alle Richtungen zuschlagen; true = etwas getroffen
local function strike()
    local hit=false
    for _,d in ipairs(DIRS) do
        for _=1,20 do
            local ok,why=ATTACK[d]()
            if not ok and tostring(why):find("No tool",1,true) and w.equipTool(isTool) then ok=ATTACK[d]() end
            if not ok then break end
            hit=true;st.harvested=(st.harvested or 0)+1
        end
    end
    return hit
end
-- Drops/Items einsammeln: vorne, oben und unten (immer alle drei, auch wenn nur
-- nach vorne angegriffen wird). Mehrmals, weil jedes Mal nur ein Stapel kommt.
local function collect()
    local got=0
    local INS={front=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown}
    for _,d in ipairs({"front","up","down"}) do
        -- nie aus Kisten saugen (Kohlekiste oben, Ausgabekiste unten)
        local box=w and w.container(INS[d])
        for _=1,box and 0 or 8 do
            if w and w.freeSlots()==0 then return got end
            local ok,r=pcall(SUCK[d])
            if not ok or not r then break end
            got=got+1
        end
    end
    if got>0 and w then w.st.looted=(w.st.looted or 0)+got end
    return got
end
local function hasChest() return w.container(turtle.inspectDown) end
local function stash(force)
    if not hasChest() then
        -- Ohne Kiste unter der Turtle: weiter verteidigen, aber Hinweis wenn voll
        if w.freeSlots()==0 then w.status("Lager voll","Kiste UNTER die Turtle stellen, dann laedt sie die Drops ab.") end
        return true
    end
    if w.items()==0 then return true end
    if force or w.freeSlots()<=2 or os.clock()-lastUnload>=30 then
        lastUnload=os.clock()
        local before=w.items()
        local ok,title,detail=w.unload(keep)
        st.total=(st.total or 0)+math.max(0,before-w.items());w.save()
        if not ok then return false,title,detail end
    end
    return true
end
-- mob.nightOnly: nur nachts aktiv (Spielzeit 18:30 - 5:30, dann spawnen Mobs)
local function isDay()
    if not C.nightOnly or not os.time then return false end
    local ok,t=pcall(os.time)
    if not ok or type(t)~="number" then return false end
    return t>=5.5 and t<18.5
end
-- ===== Mobfarm / Wache (steht still, braucht kein Fuel) =====
local function stand()
    local quiet=os.clock()
    while w.active() do
        if strike() then
            lastHit,quiet=os.clock(),os.clock()
            w.status("Kampf",C.mode=="farm" and "Mobs werden besiegt, Drops gesammelt." or "Mob wird abgewehrt.")
            collect();w.saveSoon()
            sleep(0.2)
        else
            collect()
            if w.freeSlots()==0 and not hasChest() then
                w.status("Lager voll","Kiste UNTER die Turtle stellen, dann laedt sie die Drops ab.")
            else
                w.status("Wache",C.mode=="farm" and "Warte auf Mobs in der Farm." or "Halte Wache.")
            end
            sleep(0.5)
        end
        local ok,title,detail=stash(false)
        if not ok then w.status(title,detail);w.fail(title);return false end
        if run.mode=="once" and os.clock()-quiet>=8 then stash(true);return true end
        while w.active() and isDay() do
            w.status("Tagpause","Nur nachts aktiv - wartet bis ca. 18:30 Spielzeit.");stash(true);sleep(5)
        end
    end
    w.save()
    return false
end
-- ===== Waechter im Gelaende =====
-- Gebiet: x = 0 .. width-1 (zur Seite), z = 1 .. length (nach vorne), y = Hoehe
-- relativ zur Basis (+-climb). Basis selbst: x=0, z=0, y=0.
local function inArea(x,z) return x>=0 and x<C.width and z>=1 and z<=C.length end
local function fight()
    if strike() then lastHit=os.clock();w.status("Kampf","Mob abgewehrt.");collect();w.saveSoon();return true end
    collect();return false
end
-- Gelaende-Bewegung mit Spur (gemeinsam mit dem Holzfaeller, siehe toast_worker.lua)
local T=w.terrain({climb=CLIMB,inArea=inArea,attack=true,before=fight})
local fuelLeft,homeCost=T.fuel,T.homeCost
local wall,unreach,ckey=T.wall,T.unreach,T.ckey
local nav=T.nav
local function atBase()
    local before=w.items()
    local ok,title,detail=w.unload(keep)
    st.total=(st.total or 0)+math.max(0,before-w.items());w.save()
    if not ok then return false,title,detail end
    local need=(C.length+C.width)*4+CLIMB*6+80
    ok,title,detail=w.refuel(math.max(C.fuelTarget,need))
    if not ok and fuelLeft()<need then return false,title,detail end
    return true
end
idleHome=function()
    if not PATROL or (w.isHome() and st.dir==0) then return true end
    w.status("Rueckkehr","Faehrt zur Basis.")
    return T.home()
end
-- Eine Tankfuellung lang zufaellig im Gebiet umherfahren, dann heim.
local function patrol()
    run.scanned=0
    local ok,title,detail=atBase()
    if not ok then w.status(title,detail);w.fail(title);return false end
    tankStart=fuelLeft()
    local okl,whyl=T.leave()
    if not okl then w.fail(whyl);return false end
    local misses,count=0,0
    while w.active() do
        -- Fortschritt = verbrauchter Tank bis zur Rueckkehr
        if tankStart~=math.huge then
            local usable=math.max(1,tankStart-homeCost())
            run.scanned=math.max(0,math.min(100,math.floor((tankStart-fuelLeft())/usable*100)))
        end
        if fuelLeft()<homeCost() then break end
        if isDay() then break end
        -- Inventar fast voll: Beute zur Basis bringen (danach geht es weiter)
        if w.freeSlots()<=2 then w.status("Rueckkehr","Beute zur Basis bringen.");break end
        local tx,tz
        for _=1,20 do
            tx,tz=math.random(0,C.width-1),math.random(1,C.length)
            if not wall[ckey(tx,tz)] and not unreach[ckey(tx,tz)] and (tx~=st.x or tz~=st.z) then break end
        end
        w.status("Patrouille","Faehrt im Gebiet umher.")
        local okn,whyn=nav(tx,tz,true,true)
        count=count+1
        if okn then
            misses=0;st.targets=(st.targets or 0)+1;w.saveSoon()
            -- kurz umsehen: in alle vier Richtungen zuschlagen
            for _=1,4 do if not w.active() then break end;fight();w.face((st.dir+1)%4) end
        elseif whyn=="lowFuel" then break
        elseif whyn=="stopped" then return false
        elseif whyn=="kein Weg" then
            misses=misses+1;unreach[ckey(tx,tz)]=true
            if misses>=12 then w.status("Gelaende","Viele Ziele unerreichbar - Gebiet/Kletterhoehe pruefen.") end
        else w.fail(whyn);return false end
        -- unbegrenztes Fuel: 1x = 20 Ziele, Dauerbetrieb alle 50 Ziele kurz zur Basis
        if tankStart==math.huge and count>=(run.mode=="once" and 20 or 50) then break end
    end
    if run.mode=="off" then return false end
    run.scanned=100
    local okh,whyh=idleHome()
    if not okh then w.fail("Rueckweg: "..tostring(whyh));return false end
    ok,title,detail=atBase()
    if not ok then w.status(title,detail) end
    return true
end
idleBase=function()
    if PATROL then return w.unload(keep) end
    -- Still stehende Turtle: auch ohne Auftrag Drops wegraeumen
    local ok,title,detail=stash(false)
    if not ok then return false,title,detail end
    return true
end
round=function()
    -- Tagsueber an der Basis warten (Waechter) bzw. an der Stelle (Wache/Mobfarm)
    if isDay() then
        if PATROL and not w.isHome() then local ok,why=idleHome();if not ok then w.fail(why);return false end;w.unload(keep) end
        while w.active() and isDay() do
            w.status("Tagpause","Nur nachts aktiv - wartet bis ca. 18:30 Spielzeit.");sleep(5)
        end
        if not w.active() then return false end
    end
    if PATROL then
        if not w.isHome() then local ok,why=idleHome();if not ok then w.fail(why);return false end end
        return patrol()
    end
    return stand()
end
math.randomseed(os.epoch and os.epoch("utc") or math.floor(os.clock()*1000))
pcall(w.equipTool,isTool)
local names={farm="Mobfarm",guard="Wache",patrol="Waechter "..C.length.."x"..C.width}
w.start("TOAST MOBS",names[C.mode])
