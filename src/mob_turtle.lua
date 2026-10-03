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
local DIRS=C.attack=="all" and {"front","up","down"} or {"front"}
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
        targets=w and w.st.targets or 0} end,
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
            local ok=ATTACK[d]()
            if not ok then break end
            hit=true;st.harvested=(st.harvested or 0)+1
        end
    end
    return hit
end
local function collect()
    for _,d in ipairs(DIRS) do pcall(SUCK[d]) end
end
local function hasChest() return w.container(turtle.inspectDown) end
local function stash(force)
    if not hasChest() or w.items()==0 then return true end
    if force or w.freeSlots()<=2 or os.clock()-lastUnload>=30 then
        lastUnload=os.clock()
        local before=w.items()
        local ok,title,detail=w.unload(keep)
        st.total=(st.total or 0)+math.max(0,before-w.items());w.save()
        if not ok then return false,title,detail end
    end
    return true
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
            w.status("Wache",C.mode=="farm" and "Warte auf Mobs in der Farm." or "Halte Wache.")
            sleep(0.5)
        end
        local ok,title,detail=stash(false)
        if not ok then w.status(title,detail);w.fail(title);return false end
        if run.mode=="once" and os.clock()-quiet>=8 then stash(true);return true end
    end
    w.save()
    return false
end
-- ===== Waechter im Gelaende =====
-- Gebiet: x = 0 .. width-1 (zur Seite), z = 1 .. length (nach vorne), y = Hoehe
-- relativ zur Basis (+-climb). Basis selbst: x=0, z=0, y=0.
local function inArea(x,z) return x>=0 and x<C.width and z>=1 and z<=C.length end
-- Spur: alle Felder vom Basis-Ausgang bis hierher, Schleifen werden gekuerzt.
-- Der Heimweg laeuft die Spur rueckwaerts (sicher frei) und ist genau so lang
-- wie die Spur -> der Waechter weiss immer, wie viel Fuel er fuer den Heimweg braucht.
local TRAILMAX=800
st.trail=type(st.trail)=="table" and st.trail or nil
local trailIdx={}
local function key(x,y,z) return x..","..y..","..z end
local function rebuild()
    trailIdx={}
    for i,k in ipairs(st.trail or {}) do trailIdx[k]=i end
end
rebuild()
local function push()
    if not st.trail then return end
    local k=key(st.x,st.y,st.z)
    local i=trailIdx[k]
    if i then
        for j=#st.trail,i+1,-1 do trailIdx[st.trail[j]]=nil;st.trail[j]=nil end
    elseif #st.trail>=TRAILMAX then
        st.trail=nil;trailIdx={}          -- zu lang: Heimweg dann per Navigation
    else
        st.trail[#st.trail+1]=k;trailIdx[k]=#st.trail
    end
end
local function mv(kind)
    local ok,why=w.move(kind,{attack=true})
    if ok then push() end
    return ok,why
end
local function fuelLeft()
    local f=turtle.getFuelLevel();if f=="unlimited" then return math.huge end;return f
end
-- Fuel fuer den Heimweg mit Reserve (Umwege, Klettern)
local function homeCost()
    if st.trail then return #st.trail+CLIMB+20 end
    return (math.abs(st.x)+math.abs(st.z))*3+math.abs(st.y)+CLIMB*3+40
end
local function fight()
    if strike() then lastHit=os.clock();w.status("Kampf","Mob abgewehrt.");collect();w.saveSoon();return true end
    collect();return false
end
-- Am Boden bleiben: runter, solange darunter Luft ist (Senken, Abhaenge)
local function hug()
    local n=0
    while not turtle.detectDown() and st.y>-CLIMB and n<CLIMB do
        if not mv("down") then break end
        n=n+1
    end
end
-- Ein Schritt nach vorne; Block im Weg -> hochklettern (nie abbauen)
local function stepForward()
    fight()
    local ok,why=mv("forward")
    if ok then return true end
    if not tostring(why):find("blockiert",1,true) then return false,why end
    while turtle.detect() and st.y<CLIMB do
        if turtle.detectUp() then break end
        if not mv("up") then break end
    end
    if turtle.detect() then return false,"zu hoch" end
    return mv("forward")
end
local DIRV={[0]={0,1},{1,0},{0,-1},{-1,0}}
-- Gedaechtnis: zu hohe Hindernisse (Spalten) und unerreichbare Ziele merken,
-- damit er nicht immer wieder dagegen faehrt (spart Fuel).
local wall,unreach={},{}
local function ckey(x,z) return x..":"..z end
local function blocked(why) return why=="zu hoch" or tostring(why):find("blockiert",1,true)~=nil end
-- Zu (tx,tz) laufen. ground=true: dem Boden folgen, sonst Hoehe halten.
-- Weicht Hindernissen seitlich aus. watchFuel: abbrechen, wenn Fuel knapp wird.
local function nav(tx,tz,ground,watchFuel)
    local limit=(math.abs(tx-st.x)+math.abs(tz-st.z))*3+24
    local steps=0
    while st.x~=tx or st.z~=tz do
        if run.mode~="off" and not w.active() then return false,"stopped" end
        if watchFuel and fuelLeft()<homeCost() then return false,"lowFuel" end
        steps=steps+1
        if steps>limit then return false,"kein Weg" end
        local dx,dz=tx-st.x,tz-st.z
        local cands={}
        local xd=dx>0 and 1 or 3;local zd=dz>0 and 0 or 2
        if math.abs(dx)>=math.abs(dz) then
            if dx~=0 then cands[#cands+1]=xd end;if dz~=0 then cands[#cands+1]=zd end
        else
            if dz~=0 then cands[#cands+1]=zd end;if dx~=0 then cands[#cands+1]=xd end
        end
        local side={(cands[1]+1)%4,(cands[1]+3)%4}
        if math.random(2)==1 then side[1],side[2]=side[2],side[1] end
        cands[#cands+1]=side[1];cands[#cands+1]=side[2]
        local moved=false
        for _,d in ipairs(cands) do
            local nx,nz=st.x+DIRV[d][1],st.z+DIRV[d][2]
            if (inArea(nx,nz) or (nx==tx and nz==tz)) and not wall[ckey(nx,nz)] then
                local ok,why=w.face(d);if not ok then return false,why end
                local okm,whym=stepForward()
                if okm then moved=true;break end
                if not blocked(whym) then return false,whym end
                if whym=="zu hoch" then wall[ckey(nx,nz)]=true end
            end
        end
        if not moved then return false,"kein Weg" end
        if ground then hug() end
    end
    return true
end
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
-- Zurueck zur Basis: am Boden zum Feld vor der Basis; klappt das nicht, hoch
-- auf Kletterhoehe und darueber hinweg. Dann auf Basishoehe und hinein.
idleHome=function()
    if not PATROL or (w.isHome() and st.dir==0) then return true end
    w.status("Rueckkehr","Faehrt zur Basis.")
    if not w.isHome() then
        -- 1. Spur rueckwaerts (sicher frei)
        if st.trail and #st.trail>0 and trailIdx[key(st.x,st.y,st.z)] then
            local i=trailIdx[key(st.x,st.y,st.z)]
            local okT=true
            for j=i-1,1,-1 do
                local x,y,z=st.trail[j]:match("(-?%d+),(-?%d+),(-?%d+)")
                x,y,z=tonumber(x),tonumber(y),tonumber(z)
                local ok,why
                if y>st.y then ok,why=w.move("up",{attack=true})
                elseif y<st.y then ok,why=w.move("down",{attack=true})
                else
                    local d=x>st.x and 1 or x<st.x and 3 or z>st.z and 0 or 2
                    ok,why=w.face(d);if ok then ok,why=w.move("forward",{attack=true}) end
                end
                if not ok then okT=false;break end
                st.trail[j+1]=nil;trailIdx={};
            end
            rebuild()
            if not okT then st.trail=nil;trailIdx={} end
        end
        local ok=st.x==0 and st.z==1 and st.y==0 or nav(0,1,true,false)
        if not ok then
            while st.y<CLIMB and not turtle.detectUp() do if not w.move("up",{attack=true}) then break end end
            local ok2,why2=nav(0,1,false,false)
            if not ok2 then return false,why2 end
        end
        while st.y>0 do local okd,whyd=w.move("down",{attack=true});if not okd then return false,"Basis-Eingang: "..tostring(whyd) end end
        while st.y<0 do local oku,whyu=w.move("up",{attack=true});if not oku then return false,"Basis-Eingang: "..tostring(whyu) end end
        local okf,whyf=w.face(2);if not okf then return false,whyf end
        local okm,whym=w.move("forward",{attack=true});if not okm then return false,"Basis-Eingang: "..tostring(whym) end
    end
    st.trail=nil;trailIdx={};w.save()
    return w.face(0)
end
-- Eine Tankfuellung lang zufaellig im Gebiet umherfahren, dann heim.
local function patrol()
    run.scanned=0
    local ok,title,detail=atBase()
    if not ok then w.status(title,detail);w.fail(title);return false end
    tankStart=fuelLeft()
    ok=w.face(0)
    st.trail={};trailIdx={}
    local okm,why=stepForward()
    if not okm then w.fail("Basis-Ausgang blockiert: "..tostring(why));return false end
    if st.x~=0 or st.z~=1 or st.y~=0 then st.trail=nil end   -- Ausgang muss frei auf Basishoehe sein
    hug()
    local misses,count=0,0
    while w.active() do
        -- Fortschritt = verbrauchter Tank bis zur Rueckkehr
        if tankStart~=math.huge then
            local usable=math.max(1,tankStart-homeCost())
            run.scanned=math.max(0,math.min(100,math.floor((tankStart-fuelLeft())/usable*100)))
        end
        if fuelLeft()<homeCost() then break end
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
