-- Toast Control: Mob-Turtle mit Schwert. Drei Arten (mob.mode):
--   "farm"   Mobfarm: steht an der Toetungsstelle, schlaegt zu, sammelt Drops und
--            liefert sie in die Kiste UNTER sich.
--   "guard"  Wache: steht an einer Stelle (Tor, Gang) und wehrt Mobs ab.
--   "patrol" Patrouille: laeuft eine Runde (Rechteck) ab und greift Mobs an, die
--            im Weg stehen. Baut NIE Bloecke ab. Basis: Kiste unten = Drops,
--            Kiste oben = Kohle.
-- Achtung: Eine Turtle kann Mobs und Spieler nicht unterscheiden. Sie greift an,
-- was direkt vor ihr steht (bei Patrouille erst nach kurzem Warten).
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.mob
local W=dofile("/toast/toast_worker.lua")
local PATROL=C.mode=="patrol"
local function isTool(n) return n:find("_sword",1,true)~=nil or n:find("_axe",1,true)~=nil end
local function keep(name)
    if W.FUELS[name] and PATROL then return 4096 end
    if isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    return 0
end
-- Patrouillen-Route: Rechteck length x width, startet nach vorne
local route={}
if PATROL then
    local L,B=C.length-1,C.width-1
    for _,leg in ipairs({{0,L},{1,B},{2,L},{3,B}}) do if leg[2]>0 then route[#route+1]=leg end end
end
local perimeter=PATROL and 2*(C.length-1)+2*(C.width-1) or 0
local DIRS=C.attack=="all" and {"front","up","down"} or {"front"}
local ATTACK={front=turtle.attack,up=turtle.attackUp,down=turtle.attackDown}
local SUCK={front=turtle.suck,up=turtle.suckUp,down=turtle.suckDown}
local w,round,idleHome,idleBase
local lastHit=0
w=W.new({job="mob",cfg=cfg,section=C,stateFile="/toast_mob_state",args={...},cells=perimeter,
    layout=C.mode..":"..C.length..":"..C.width..":"..C.side,mirror=PATROL and C.side=="left",
    tools=isTool,noTool="Kein Schwert: Diamant-Schwert in die Turtle legen",
    interval=PATROL and C.interval or 0,
    readyText=PATROL and "START: Dauerbetrieb | 1 RUNDE: einmal ablaufen" or "START: Dauerbetrieb | 1x: bis keine Mobs mehr da",
    extra=function() return {mobMode=C.mode,hits=w and w.st.harvested or 0,lastHit=math.floor(os.clock()-lastHit)} end,
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
-- ===== Patrouille =====
local function walk()
    run.scanned=0
    local ok,title,detail=w.unload(keep)
    if not ok then w.status(title,detail);w.fail(title);return false end
    ok,title,detail=w.refuel(math.max(C.fuelTarget,perimeter+20))
    if not ok and turtle.getFuelLevel()<perimeter+20 then
        w.status(title,detail);w.fail(title);return false
    end
    for _,leg in ipairs(route) do
        local okf,why=w.face(leg[1]);if not okf then w.fail(why);return false end
        for _=1,leg[2] do
            if not w.active() then
                -- gestoppt: Runde zu Ende laufen waere zu lang -> direkt zurueck
                return false
            end
            if strike() then lastHit=os.clock();w.status("Kampf","Mob auf der Runde abgewehrt.")
            else w.status("Patrouille","Schritt "..run.scanned.." / "..perimeter) end
            collect()
            local okm,why2=w.move("forward",{attack=true})
            if not okm then w.fail(why2);return false end
            run.scanned=run.scanned+1
        end
    end
    w.face(0)
    local before=w.items()
    ok,title,detail=w.unload(keep)
    st.total=(st.total or 0)+math.max(0,before-w.items());w.save()
    if not ok then w.status(title,detail) end
    return true
end
-- Zurueck zur Basis immer auf dem Rechteck bleiben (nur dort ist sicher frei):
-- auf der hinteren Kante (z = Ende) erst seitlich, sonst erst nach hinten.
local function line(axis)
    local cur=axis=="x" and st.x or st.z
    if cur==0 then return true end
    local dir=axis=="x" and (cur>0 and 3 or 1) or (cur>0 and 2 or 0)
    local ok,why=w.face(dir);if not ok then return false,why end
    while (axis=="x" and st.x or st.z)~=0 do
        ok,why=w.move("forward",{attack=true});if not ok then return false,why end
    end
    return true
end
idleHome=function()
    if not PATROL or (w.isHome() and st.dir==0) then return true end
    w.status("Rueckkehr","Gehe zur Basis.")
    local first,second="z","x"
    if st.z==C.length-1 then first,second="x","z" end
    local ok,why=line(first);if not ok then return false,why end
    ok,why=line(second);if not ok then return false,why end
    return w.face(0)
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
        return walk()
    end
    return stand()
end
pcall(w.equipTool,isTool)
local names={farm="Mobfarm",guard="Wache",patrol="Patrouille "..C.length.."x"..C.width}
w.start("TOAST MOBS",names[C.mode])
