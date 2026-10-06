-- Toast Control: Mobfarm-Bau (vor allem fuer Creeper / Schwarzpulver).
-- Die Turtle steht an der spaeteren Toetungsstelle und baut ueber sich:
--   * einen 1x1-Fallschacht (Hoehe build.drop, Standard 22 = Mobs ueberleben
--     mit ~1 Herz, die Mob-Turtle gibt den Rest)
--   * build.floors dunkle Spawn-Etagen (innen 17x17, 5 Lagen hoch):
--       Boden | Wasserlage | Laufflaeche | 2 Luft (Fuesse/Kopf)
--     Ein Kanal (x=0) ist 2 tief in die Laufflaeche eingelassen: Wasser fliesst
--     von beiden Enden 8 Bloecke bis zum Loch in der Mitte.
--   * Mob-KI ("Falltuer-Trick"): Mobs meiden Wasser und Abgruende, halten
--     Falltueren aber IMMER fuer festen Boden. Ueber dem Kanal liegen deshalb
--     OFFENE Falltueren - die Mobs laufen drauf und fallen ins Wasser. Offen
--     werden sie, weil daneben ein Redstoneblock liegt (Falltuer neben Strom wird
--     offen gesetzt; Turtles koennen Falltueren nicht anklicken). Der Redstone-
--     block muss liegen bleiben.
--   * Stufenreihen (z = 0, +-3, +-6): keine Spinnen (brauchen 3x3 frei) und sie
--     teilen die Flaeche in 2 breite Gaenge, die alle am Kanal enden.
--   * Aus dem 2 tiefen Kanal kommt kein Mob wieder heraus.
--   * build.creeperOnly: Falltueren oben an der Decke -> nur 1,81 Bloecke frei:
--     Creeper (1,7) passen, Zombies/Skelette/Hexen/Endermen nicht.
-- Kisten: UNTER der Turtle = Ausgabe (spaeter die Drops), HINTER der Turtle =
-- Material (Bruchstein/Stein/Erde, Wassereimer, Bruchsteinstufen, Falltueren,
-- Redstonebloecke, Kohle).
-- Fertig + Schwert im Inventar: die Turtle wird selbst zur Mob-Turtle (greift
-- nur nach oben an).
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.build
local W=dofile("/toast/toast_worker.lua")
local F,D=C.floors,C.drop
local CREEPER=C.creeperOnly~=false
-- Im Berg/Gelaende: alle Luftfelder freiraeumen. Sonst (im Freien) wie ein
-- 3D-Drucker: Schicht fuer Schicht nur die Bahnen, wo ein Block hinkommt.
local TERRAIN=C.inTerrain==true
local R=8                      -- Laenge der Wasserkanaele (Wasser fliesst 8 Bloecke)
local OUT=R+1                  -- Aussenwand
local B0=D                     -- unterste Etage (Boden)
local H=5                      -- Lagen je Etage
local TOP=B0+H*F               -- Dach

-- ===== Bloecke =====
local FILL={}
for _,n in ipairs({"cobblestone","cobbled_deepslate","stone","deepslate","dirt","netherrack","andesite","diorite",
    "granite","tuff","calcite","blackstone","basalt","smooth_basalt","end_stone","coarse_dirt","mossy_cobblestone",
    "stone_bricks","sandstone","polished_andesite","polished_diorite","polished_granite"}) do FILL["minecraft:"..n]=true end
local OKSOLID={["minecraft:grass_block"]=true,["minecraft:podzol"]=true,["minecraft:mycelium"]=true,
    ["minecraft:rooted_dirt"]=true,["minecraft:terracotta"]=true,["minecraft:obsidian"]=true}
local function isFill(n) return FILL[n]==true end
local function isSlab(n) return n:find("_slab",1,true)~=nil and not n:find("wooden",1,true) end
local function isTrap(n) return n:find("_trapdoor",1,true)~=nil end
local function isRed(n) return n=="minecraft:redstone_block" end
local function isWaterBucket(n) return n=="minecraft:water_bucket" end
local function isBucket(n) return n=="minecraft:bucket" end
local function isLiquid(n) return n=="minecraft:water" or n=="minecraft:lava" or n:find("flowing_",1,true)~=nil end
local function isTool(n) return n:find("_pickaxe",1,true)~=nil end
local function isSword(n) return n:find("_sword",1,true)~=nil end
local function isContainer(n) return n:find("chest",1,true)~=nil or n:find("barrel",1,true)~=nil or n:find("shulker",1,true)~=nil end
local function isTurtle(n) return n:find("computercraft:turtle",1,true)~=nil end

-- ===== Bauplan =====
-- Koordinaten: Turtle (Toetungsstelle) = 0,0,0, y nach oben. Der Schacht steht
-- direkt ueber der Turtle (x=0,z=0); die Etagen sind um ihn herum zentriert.
local SOLID,AIR,SRC,SLAB,RED,TRAP="s","a","w","p","r","t"
-- Kanalfelder mit offener Falltuer: ueberall, wo ein Gang endet (nicht vor den Stufenreihen)
local function trapZ(az) return az>=1 and az<=R and az%3~=0 end
local function target(x,y,z)
    local ax,az=math.abs(x),math.abs(z)
    if y>=1 and y<B0 then
        if x==0 and z==0 then return AIR end
        if ax+az==1 then return SOLID end
        return nil
    end
    if y<B0 or y>TOP or ax>OUT or az>OUT then return nil end
    if y==TOP then return SOLID end
    local k=(y-B0)%H                         -- 0 Boden, 1 Wasser, 2 Laufflaeche, 3+4 Luft
    local canal=x==0
    if k==0 then
        if x==0 and z==0 then return AIR end
        -- unterste Etage: Boden nur unter dem Kanal (darunter ist keine Etage)
        if y==B0 and not (canal and az<=R) then return nil end
        return SOLID
    end
    if k==1 then
        -- Wasserlage: nur Kanal + Kanalwaende. Der Rest darf hohl bleiben: dort ist
        -- nur 1 Block Luft, darin spawnt nichts (Spawn braucht 2 freie Bloecke).
        if canal then
            if z==0 then return AIR end
            if az<=R then return az==R and SRC or AIR end
            return SOLID                            -- Stirnwand hinter der Quelle
        end
        if ax==1 and az>=1 and az<=R then return SOLID end
        return nil
    end
    if ax==OUT or az==OUT then return SOLID end
    if x==0 and z==0 then return AIR end
    if k==2 then
        if canal then return trapZ(az) and TRAP or AIR end
        if x==1 and trapZ(az) then return RED end
        return SOLID
    end
    if k==3 and not canal and az%3==0 then return SLAB end
    return AIR
end
-- Schritte: {t=Art,x,y=Hoehe der Turtle,z}. "cell" bearbeitet den Block UNTER der Turtle
-- (und raeumt Luftfelder 2 darueber gleich mit frei).
-- Sparsam fahren:
--  * Luftfelder, die schon 2 Lagen tiefer von unten freigeraeumt wurden, werden
--    nicht noch einmal angefahren (im Freien = fast alle Luftfelder).
--  * Reihenfolge je Lage: immer zum naechstgelegenen offenen Feld (Ringe werden
--    als Runde gefahren statt quer durch den Raum).
--  * Zur naechsten Lage direkt hoch (nicht ueber die Mitte).
--  * Schacht: Turtle steht IM Schacht und setzt die 4 Waende durch Drehen.
local STEPS={}
local function add(t) STEPS[#STEPS+1]=t end
local VIS={}                       -- VIS[y]["x,z"] = Lage y wurde dort bearbeitet
local function k2(x,z) return x..","..z end
local last={x=0,z=0}
local function layer(y,skipCenter)
    local r=(y<B0) and 1 or OUT
    local cells={}
    for z=-r,r do for x=-r,r do
        local tg=target(x,y,z)
        if tg and tg~=TRAP and not (skipCenter and x==0 and z==0) and (TERRAIN or tg~=AIR) then
            local covered=tg==AIR and VIS[y-2] and VIS[y-2][k2(x,z)]
            if not covered then cells[#cells+1]={x=x,z=z} end
        end
    end end
    VIS[y]={}
    local cx,cz=last.x,last.z
    while #cells>0 do
        local bi,bd=1,math.huge
        for i,c in ipairs(cells) do
            local d=math.abs(c.x-cx)+math.abs(c.z-cz)
            if d<bd then bi,bd=i,d end
        end
        local c=table.remove(cells,bi)
        add({t="cell",x=c.x,y=y+1,z=c.z});VIS[y][k2(c.x,c.z)]=true
        cx,cz=c.x,c.z
    end
    last={x=cx,z=cz}
end
local function shaft(y)
    add({t="wall4",x=0,y=y,z=0})
    VIS[y]={[k2(0,0)]=true}
    last={x=0,z=0}
end
local function water(b)
    -- 2 Quellen an den Kanalenden, die naechstgelegene zuerst
    local s=(last.z>=0) and 1 or -1
    for _,z in ipairs({s*R,-s*R}) do
        add({t="water",x=0,y=b+2,z=z});last={x=0,z=z}
    end
end
-- Offene Falltueren ueber dem Kanal: Turtle faehrt ueber der Laufflaeche (b+3)
-- den Kanal ab und setzt sie nach unten (die Redstonebloecke liegen schon).
local function canalTraps(b)
    local s=(last.z>=0) and -1 or 1
    VIS[b+2]=VIS[b+2] or {}
    for i=-R,R do
        local z=-s*i
        if trapZ(math.abs(z)) then
            add({t="ctrap",x=0,y=b+3,z=z});VIS[b+2][k2(0,z)]=true;last={x=0,z=z}
        end
    end
end
-- Falltueren: Turtle faehrt in der Etage auf Hoehe b+2 (ueber den Spawnstellen)
-- und setzt sie nach oben an die Decke. Wege nur durch die Kanaele (x=0) und
-- die Spawnreihen (die Stufenreihen sind belegt).
local function traps(b)
    if not CREEPER then return end
    for _,sx in ipairs({1,-1}) do for _,sz in ipairs({1,-1}) do
        for _,pair in ipairs({{1,2},{4,5},{7,8}}) do
            for x=1,R do add({t="trap",x=sx*x,y=b+3,z=sz*pair[1],corr=true}) end
            for x=R,1,-1 do add({t="trap",x=sx*x,y=b+3,z=sz*pair[2],corr=true}) end
        end
    end end
end
for y=1,B0-1 do shaft(y) end
for k=0,F-1 do
    local b=B0+H*k
    layer(b)
    if k>0 then traps(b-H) end
    layer(b+1);water(b)
    layer(b+2);canalTraps(b)
    layer(b+3);layer(b+4)
end
layer(TOP,true)
traps(B0+H*(F-1))
add({t="cap",x=0,y=TOP-1,z=0})
local N=#STEPS
-- hoechste schon gebaute Lage VOR jedem Schritt (darueber ist alles noch frei)
local HB={}
do local hb=0
    for k=1,N do
        HB[k]=hb
        local s=STEPS[k]
        local l=s.t=="cell" and s.y-1 or s.t=="wall4" and s.y or s.t=="water" and s.y-1 or s.t=="ctrap" and s.y-1 or s.t=="trap" and s.y+1 or s.t=="cap" and TOP or 0
        if l>hb then hb=l end
    end
end
-- Material je Art ab Schritt i
local function remaining(i)
    local n={fill=0,slab=0,trap=0,water=0,red=0}
    for k=i or 1,N do
        local s=STEPS[k]
        if s.t=="cell" then
            local tg=target(s.x,s.y-1,s.z)
            if tg==SOLID then n.fill=n.fill+1 elseif tg==SLAB then n.slab=n.slab+1 elseif tg==RED then n.red=n.red+1 end
        elseif s.t=="trap" or s.t=="ctrap" then n.trap=n.trap+1
        elseif s.t=="water" then n.water=n.water+1
        elseif s.t=="cap" then n.fill=n.fill+1
        elseif s.t=="wall4" then n.fill=n.fill+4 end
    end
    return n
end
local TOTAL=remaining(1)
local LAYOUT=table.concat({"mobfarm2",F,D,CREEPER and "c" or "n",TERRAIN and "t" or "p"},":")

local w,round,idleHome,idleBase
local opts
opts={job="build",cfg=cfg,section=C,stateFile="/toast_build_state",args={...},cells=N,layout=LAYOUT,
    tools=isTool,noTool="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen",
    interval=0,readyText="START: Mobfarm bauen (macht weiter, wo sie war)",
    extra=function() local s=w and w.st or {}
        return {floors=F,drop=D,creeperOnly=CREEPER,placed=s.placed or 0,done=s.done,
            need=TOTAL.fill,needSlab=TOTAL.slab,needTrap=TOTAL.trap,needWater=TOTAL.water,needRed=TOTAL.red,
            fill=w and w.count(isFill) or 0,slabs=w and w.count(isSlab) or 0,traps=w and w.count(isTrap) or 0,
            reds=w and w.count(isRed) or 0,openFail=s.openFail,
            buckets=w and w.count(isWaterBucket) or 0,missing=s.missing,trapFail=s.trapFail,
            phase=s.phase} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end}
w=W.new(opts)
local st,run=w.st,w.run
if st.buildLayout~=LAYOUT then st.buildLayout=LAYOUT;st.idx=1;st.done=nil;w.save() end
st.idx=st.idx or 1
if st.done then run.scanned=N;opts.readyText="FERTIG: Mobfarm steht. Schwert ins Inventar -> wird zur Mob-Turtle" end

-- ===== Bewegung =====
local INSPECT={forward=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown}
local PLACE={forward=turtle.place,up=turtle.placeUp,down=turtle.placeDown}
local RAWDIG={forward=turtle.dig,up=turtle.digUp,down=turtle.digDown}
local DIG={}
for k,f in pairs(RAWDIG) do DIG[k]=function()
    local ok,why=f()
    if not ok and tostring(why):find("No tool",1,true) and w.equipTool(isTool) then ok,why=f() end
    return ok,why
end end
local corridor=false        -- in der Etage nur durch Kanal + Spawnreihen fahren
local MOPT={dig=true,attack=true,canDig=function(n)
    if isContainer(n) or isTurtle(n) then return false end
    if corridor and (isSlab(n) or isTrap(n)) then return false end
    return true end}
local function fuel() local f=turtle.getFuelLevel();if f=="unlimited" then return math.huge end;return f end
local function line(axis,v)
    while (axis=="x" and st.x or st.z)~=v do
        local cur=axis=="x" and st.x or st.z
        local d=axis=="x" and (v>cur and 1 or 3) or (v>cur and 0 or 2)
        local ok,why=w.face(d);if not ok then return false,why end
        ok,why=w.move("forward",MOPT);if not ok then return false,why end
    end
    return true
end
local function blockedZ(z0,z1)
    local s=z1>z0 and 1 or -1
    for z=z0+s,z1,s do if math.abs(z)%3==0 then return true end end   -- Stufenreihen (auch z=0)
    return false
end
-- waagrecht auf der aktuellen Hoehe
local function horizontal(x,z)
    if corridor and st.z~=z and st.x~=0 and blockedZ(st.z,z) then
        local ok,why=line("x",0);if not ok then return false,why end
    end
    if corridor then
        local ok,why=line("z",z);if not ok then return false,why end
        return line("x",x)
    end
    local ok,why=line("x",x);if not ok then return false,why end
    return line("z",z)
end
-- Hoehe wechseln immer durch die Mittelsaeule (die ist im ganzen Bau frei)
local function goTo(x,y,z,corr,climb)
    -- ueber allem Gebauten: direkt hier hoch (spart den Weg zur Mitte und zurueck)
    if climb and y>st.y then
        corridor=false
        while st.y<y do
            local ok,why=w.move("up",MOPT);if not ok then return false,why end
        end
    end
    if st.y~=y then
        local ok,why=horizontal(0,0);if not ok then return false,why end
        corridor=false
        while st.y~=y do
            ok,why=w.move(st.y<y and "up" or "down",MOPT);if not ok then return false,why end
        end
    end
    corridor=corr==true
    local ok,why=horizontal(x,z)
    return ok,why
end
local function homeNeed() return math.abs(st.x)+math.abs(st.y)+math.abs(st.z)+20 end

-- ===== Material =====
local function fuelGoal()
    -- bis zum naechsten Nachladen: grob Restschritte, mindestens fuelTarget
    return math.min(turtle.getFuelLimit and turtle.getFuelLimit() or 20000,math.max(C.fuelTarget,(N-st.idx)*2+TOP*2+200))
end
local function burn(target)
    for s=1,16 do
        local it=turtle.getItemDetail(s)
        if it and W.FUELS[it.name] then
            turtle.select(s)
            while fuel()<target and turtle.getItemCount(s)>0 do if not turtle.refuel(1) then break end end
        end
        if fuel()>=target then break end
    end
    turtle.select(1)
end
local function keep(name)
    if isTool(name) or isSword(name) or common.MODEM_ITEMS[name] then return 4096 end
    if isFill(name) or isSlab(name) or isTrap(name) or isRed(name) or isWaterBucket(name) then return 4096 end
    if W.FUELS[name] then return 64 end
    return 0
end
-- Materialkiste HINTER der Turtle (Turtle schaut dabei nach hinten = "front").
-- Mit der Kisten-Peripherie wird das gewuenschte Item erst nach vorne (Slot 1)
-- geschoben, dann eingesaugt - so ist die Reihenfolge in der Kiste egal.
local function chestList()
    local ok,inv=pcall(peripheral.wrap,"front")
    if not ok or type(inv)~="table" or type(inv.list)~="function" then return nil end
    return inv
end
local function fetch(match,count)
    local got=0
    for _=1,40 do
        if got>=count then break end
        local slot;for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
        if not slot then break end
        local skipSuck=false
        local inv=chestList()
        if inv then
            local okl,list=pcall(inv.list)
            if not okl or type(list)~="table" then break end
            local from
            for s,it in pairs(list) do if match(it.name) and (not from or s<from) then from=s end end
            if not from then break end
            if from~=1 then
                local parked
                if list[1] then
                    local size=inv.size and inv.size() or 27
                    local free;for s=2,size do if not list[s] then free=s;break end end
                    if free then pcall(inv.pushItems,"front",1,64,free)
                    else
                        -- Kiste randvoll: Slot 1 kurz in die Turtle nehmen, danach zuruecklegen
                        local tmp;for i=16,1,-1 do if turtle.getItemCount(i)==0 and i~=slot then tmp=i;break end end
                        if not tmp then break end
                        turtle.select(tmp);if not turtle.suck() then break end
                        parked=tmp
                    end
                end
                pcall(inv.pushItems,"front",from,64,1)
                if parked then
                    turtle.select(slot)
                    local okS=turtle.suck(math.min(64,count-got))
                    turtle.select(parked);turtle.drop()
                    turtle.select(slot)
                    local it=turtle.getItemDetail(slot)
                    if not (okS and it and match(it.name)) then break end
                    got=got+it.count;skipSuck=true
                end
            end
        end
        if not skipSuck then
            turtle.select(slot)
            if not turtle.suck(math.min(64,count-got)) then break end
            local it=turtle.getItemDetail(slot)
            if not it then break end
            if not match(it.name) then
                -- falsches Item (ohne Kisten-Peripherie): in die Ausgabekiste
                turtle.dropDown();if not inv then break end
            else got=got+it.count end
        end
    end
    turtle.select(1)
    return got
end
local function have(match) return w.count(match) end
-- An der Basis: abladen, leere Eimer zurueck, Material + Kohle holen
local function base()
    local ok,title,detail=w.unload(keep)
    if not ok then return false,title,detail end
    local need=remaining(st.idx)
    local okf,why=w.face(2);if not okf then return false,"Drehen",why end
    if not w.container(turtle.inspect) then w.face(0);return false,"Materialkiste fehlt","Kiste HINTER die Turtle stellen (Bruchstein, Wassereimer, Stufen, Falltueren, Redstonebloecke, Kohle)." end
    -- leere Eimer zurueck in die Materialkiste
    for i=1,16 do local it=turtle.getItemDetail(i);if it and isBucket(it.name) then turtle.select(i);turtle.drop() end end
    -- zu viel Bruchstein dabei (beim Graben eingesammelt): zurueck in die Materialkiste,
    -- damit Platz bleibt (sonst faehrt sie mit vollem Inventar immer wieder heim)
    for i=16,1,-1 do
        if w.freeSlots()>=(TERRAIN and 6 or 3) then break end
        local it=turtle.getItemDetail(i)
        if it and isFill(it.name) then
            turtle.select(i)
            if not turtle.drop() then turtle.dropDown() end
        end
    end
    turtle.select(1)
    -- Kohle
    if fuel()<fuelGoal() and have(function(n) return W.FUELS[n]~=nil end)<16 then
        fetch(function(n) return W.FUELS[n]~=nil end,32);burn(fuelGoal())
    end
    -- Sonderteile fuer den naechsten Abschnitt zuerst (Eimer stapeln sich nicht)
    local nextSpecial
    for k=st.idx,N do
        local t=STEPS[k].t
        local tg=t=="cell" and target(STEPS[k].x,STEPS[k].y-1,STEPS[k].z)
        if t=="water" or t=="trap" or t=="ctrap" or tg==SLAB or tg==RED then
            nextSpecial=tg==SLAB and "slab" or tg==RED and "red" or t=="ctrap" and "trap" or t;break
        end
    end
    if nextSpecial=="water" and have(isWaterBucket)<math.min(4,need.water) then fetch(isWaterBucket,math.min(4,need.water)-have(isWaterBucket)) end
    if nextSpecial=="slab" and have(isSlab)<math.min(64,need.slab) then fetch(isSlab,math.min(64,need.slab)-have(isSlab)) end
    if nextSpecial=="trap" and have(isTrap)<math.min(128,need.trap) then fetch(isTrap,math.min(128,need.trap)-have(isTrap)) end
    if (nextSpecial=="red" or nextSpecial=="trap") and need.red>0 and have(isRed)<math.min(64,need.red) then fetch(isRed,math.min(64,need.red)-have(isRed)) end
    -- Rest mit Baumaterial auffuellen, aber Platz fuer Abraum lassen (sonst muss sie
    -- im Gelaende nach wenigen Bloecken wieder heim). Hoechstens 8 Stapel dabei.
    local stacks=math.max(0,w.freeSlots()-(TERRAIN and 5 or 2))
    local want=math.min(need.fill,8*64)-have(isFill)
    if want>0 and stacks>0 then fetch(isFill,math.min(stacks*64,want)) end
    w.face(0)
    burn(fuelGoal())
    if fuel()<math.min(fuelGoal(),homeNeed()+TOP*2+100) then
        return false,"Treibstoff fehlt","Kohle in die Kiste HINTER der Turtle legen."
    end
    w.save()
    return true
end
local function goHome()
    if w.isHome() then return w.face(0) end
    w.status("Rueckkehr","Faehrt zur Basis (Nachschub).")
    local ok,why=goTo(0,0,0,false);if not ok then return false,"Rueckweg: "..tostring(why) end
    return w.face(0)
end
-- Nachschub holen; fehlt etwas, an der Basis warten bis es da ist
local MISSING={fill="Baumaterial fehlt",slab="Stufen fehlen",trap="Falltueren fehlen",water="Wassereimer fehlen",red="Redstonebloecke fehlen"}
local HINT={fill="Bruchstein/Stein/Erde",slab="Bruchsteinstufen",trap="Falltueren (Holz)",water="Wassereimer",red="Redstonebloecke"}
local function resupply(kind)
    local ok,why=goHome();if not ok then return false,why end
    while true do
        if not w.active() then return false,"stopped" end
        local okb,title,detail=base()
        local match=({fill=isFill,slab=isSlab,trap=isTrap,water=isWaterBucket,red=isRed})[kind]
        if okb and (not kind or not match or have(match)>0) then st.missing=nil;return true end
        if okb then
            local need=remaining(st.idx)
            title=MISSING[kind];detail=HINT[kind].." in die Kiste HINTER der Turtle legen (noch "..(need[kind] or "?").." gebraucht)."
        end
        st.missing=title;w.status(title,detail)
        for _=1,20 do if not w.active() then return false,"stopped" end;sleep(0.5) end
    end
end

-- ===== Bauen =====
local function placeDown(match)
    local slot=w.find(match);if not slot then return false,"material" end
    turtle.select(slot);local ok=turtle.placeDown();turtle.select(1)
    if ok then st.placed=(st.placed or 0)+1 end
    return ok
end
local function clearDown(keepWater)
    for _=1,8 do
        local e,b=turtle.inspectDown()
        if not e then return true end
        if isLiquid(b.name) then
            if keepWater and (b.name=="minecraft:water" or b.name:find("flowing_water",1,true)) then return true end
            local slot=w.find(isFill);if not slot then return false,"material" end
            turtle.select(slot);turtle.placeDown();turtle.select(1)
            DIG.down()
        elseif isContainer(b.name) or isTurtle(b.name) then return true
        else
            if not DIG.down() then return false,"Nicht abbaubar: "..b.name end
        end
    end
    local e,b=turtle.inspectDown()
    if e and isLiquid(b.name) and not keepWater then return false,"Wasser/Lava nicht wegzubekommen" end
    return true
end
local clearUp
local function doCell(s)
    local tg=target(s.x,s.y-1,s.z)
    local e,b=turtle.inspectDown()
    if tg==SOLID then
        if not (e and (isFill(b.name) or OKSOLID[b.name])) then
            if e then local ok,why=clearDown();if not ok then return false,why end end
            if not w.find(isFill) then return false,"material" end
            local ok=placeDown(isFill)
            if not ok then return false,"Block nicht setzbar" end
        end
    elseif tg==RED then
        if not (e and isRed(b.name)) then
            if e then local ok,why=clearDown();if not ok then return false,why end end
            if not w.find(isRed) then return false,"red" end
            if not placeDown(isRed) then return false,"Redstoneblock nicht setzbar" end
        end
    elseif tg==SLAB then
        if not (e and isSlab(b.name) and (b.state or {}).type~="top") then
            if e then local ok,why=clearDown();if not ok then return false,why end end
            if not w.find(isSlab) then return false,"slab" end
            if not placeDown(isSlab) then return false,"Stufe nicht setzbar" end
            local e2,b2=turtle.inspectDown()
            if e2 and (b2.state or {}).type=="top" then DIG.down();return false,"Stufe landet oben statt unten" end
        end
    else
        -- Wasser im Kanal (auch fliessendes) beim Ausbessern stehen lassen
        local y=s.y-1
        local inChannel=y>=B0 and y<TOP and (y-B0)%H==1 and s.x==0 and s.z~=0
        local ok,why=clearDown(tg==SRC or inChannel)
        if not ok then return false,why end
    end
    -- Luftfeld 2 weiter oben gleich mit freiraeumen (dann muss die Lage dort nicht nochmal hin)
    local ta=target(s.x,s.y+1,s.z)
    if TERRAIN and (ta==AIR or ta==SRC) then
        local ya=s.y+1
        clearUp(ta==SRC or (ya>=B0 and ya<TOP and (ya-B0)%H==1 and s.x==0))
    end
    return true
end
-- Feld 2 ueber der Turtle (naechste Lage) gleich mit freiraeumen
clearUp=function(keepWater)
    for _=1,8 do
        local e,b=turtle.inspectUp()
        if not e then return true end
        if isLiquid(b.name) then
            if keepWater and (b.name=="minecraft:water" or b.name:find("flowing_water",1,true)) then return true end
            local slot=w.find(isFill);if not slot then return true end
            turtle.select(slot);turtle.placeUp();turtle.select(1)
            DIG.up()
        elseif isContainer(b.name) or isTurtle(b.name) or isSlab(b.name) or isTrap(b.name) then return true
        elseif not DIG.up() then return true end
    end
    return true
end
-- Schacht: Turtle steht im Schacht und setzt die 4 Waende rundum (Drehen kostet kein Fuel)
local function doWall4(s)
    for k=0,3 do
        local d=(st.dir+k)%4
        if target(W.DX[d],s.y,W.DZ[d])==SOLID then
            local ok,why=w.face(d);if not ok then return false,why end
            local e,b=turtle.inspect()
            if not (e and (isFill(b.name) or OKSOLID[b.name])) then
                if e and not isLiquid(b.name) and not isContainer(b.name) and not isTurtle(b.name) then
                    if not DIG.forward() then return false,"Nicht abbaubar: "..b.name end
                end
                local slot=w.find(isFill);if not slot then return false,"material" end
                turtle.select(slot);local okp=turtle.place();turtle.select(1)
                if okp then st.placed=(st.placed or 0)+1 else return false,"Block nicht setzbar" end
            end
        end
    end
    return true
end
local function doWater(s)
    local e,b=turtle.inspectDown()
    if e and b.name=="minecraft:water" and tonumber((b.state or {}).level or 0)==0 then return true end
    if e and not isLiquid(b.name) then local ok,why=clearDown();if not ok then return false,why end end
    local slot=w.find(isWaterBucket);if not slot then return false,"water" end
    turtle.select(slot);local ok=turtle.placeDown();turtle.select(1)
    if not ok then return false,"Wasser nicht setzbar" end
    return true
end
local function doTrap(s)
    if st.trapFail then return true end
    local e,b=turtle.inspectUp()
    if e and isTrap(b.name) then return true end
    if e then return true end                -- unerwartet belegt: lassen
    local slot=w.find(isTrap);if not slot then return false,"trap" end
    turtle.select(slot);local ok=turtle.placeUp();turtle.select(1)
    if not ok then return false,"Falltuer nicht setzbar" end
    local e2,b2=turtle.inspectUp()
    if e2 and (b2.state or {}).half=="bottom" then
        -- haengt unten statt oben: wuerde den Creepern den Platz nehmen -> wieder weg
        DIG.up();st.trapFail=true;w.save()
        common.log("Mobfarm: Falltueren lassen sich nicht oben anbringen, ohne Falltueren weiter")
    else st.placed=(st.placed or 0)+1 end
    return true
end
-- Kanal-Falltuer: Turtle schaut quer zum Kanal (+x), dann liegt die offene
-- Klappe laengs am Kanalrand und bremst die Mobs im Wasser nicht.
local openWarned=false
local function doCtrap(s)
    local okf,whyf=w.face(1);if not okf then return false,whyf end
    local e,b=turtle.inspectDown()
    if e and isTrap(b.name) then
        if (b.state or {}).open==true then return true end
        -- zu (z.B. Redstone fehlte): abbauen und neu setzen
        DIG.down();e=false
    end
    if e then local ok,why=clearDown();if not ok then return false,why end end
    local slot=w.find(isTrap);if not slot then return false,"trap" end
    turtle.select(slot);local ok=turtle.placeDown();turtle.select(1)
    if not ok then return false,"Falltuer nicht setzbar" end
    st.placed=(st.placed or 0)+1
    local e2,b2=turtle.inspectDown()
    if e2 and isTrap(b2.name) and (b2.state or {}).open~=true then
        st.openFail=(st.openFail or 0)+1;w.save()
        if not openWarned then openWarned=true;common.log("Mobfarm: Kanal-Falltuer ist zu - von Hand oeffnen (Redstoneblock daneben?)") end
    end
    if TERRAIN and target(s.x,s.y+1,s.z)==AIR then clearUp(false) end
    return true
end
local function doCap()
    local e,b=turtle.inspectUp()
    if e and (isFill(b.name) or OKSOLID[b.name]) then return true end
    local slot=w.find(isFill);if not slot then return false,"material" end
    turtle.select(slot);local ok=turtle.placeUp();turtle.select(1)
    if ok then st.placed=(st.placed or 0)+1 end
    return ok or false,"Dach nicht setzbar"
end
local DO={cell=doCell,water=doWater,trap=doTrap,ctrap=doCtrap,cap=doCap,wall4=doWall4}
local PHASE=function(s)
    if s.y-1<B0 and s.t=="cell" then return "Schacht" end
    if s.t=="water" then return "Wasser" end
    if s.t=="trap" then return "Falltueren" end
    if s.t=="ctrap" then return "Kanal-Falltueren" end
    if s.t=="cap" or s.y-1>=TOP then return "Dach" end
    return "Etage "..(math.floor((s.y-1-B0)/H)+1).."/"..F
end
-- Mob-Turtle werden: Schwert anlegen, Aufgabe umstellen, neu starten
local function becomeMob()
    if not C.becomeMob or not st.done or not w.isHome() then return false end
    local slot=w.find(isSword);if not slot then return false end
    if not w.equipTool(isSword) then return false end
    w.unload(function(n) if isSword(n) or common.MODEM_ITEMS[n] then return 4096 end;return 0 end)
    local okc,raw=pcall(dofile,"/toast.config.lua")
    if not okc or type(raw)~="table" then return false end
    raw.job="mob";raw.mob=raw.mob or {}
    local m=common.withDefaults(raw).mob
    m.mode="farm";m.attack="up";raw.mob=m
    raw.label=nil
    local f=fs.open("/toast.config.lua","w");f.write(common.configText(raw));f.close()
    common.log("Mobfarm fertig: Turtle wird zur Mob-Turtle")
    error("TOAST_UPDATE",0)
end
round=function()
    if st.done then
        -- Farm steht schon: nicht nochmal durch die fertigen Etagen fahren
        w.status("Fertig","Mobfarm steht schon. Neu bauen: an der Turtle N (neuer Auftrag).")
        w.finish();becomeMob()
        return true
    end
    opts.readyText="START: Mobfarm bauen (macht weiter, wo sie war)"
    if w.isHome() then
        local ok=resupply(nil);if not ok then return false end
    end
    while st.idx<=N do
        if not w.active() then w.save();return false end
        local s=STEPS[st.idx]
        run.scanned=st.idx-1
        st.phase=PHASE(s)
        if w.freeSlots()==0 or fuel()<homeNeed()+math.abs(s.y-st.y)+40 then
            local ok,why=resupply(nil);if not ok then if why~="stopped" then w.fail(why) end;return false end
        end
        w.status("Baut",st.phase.." - Schritt "..st.idx.."/"..N)
        local ok,why=goTo(s.x,s.y,s.z,s.corr,st.y>HB[st.idx])
        if ok then ok,why=DO[s.t](s) end
        if ok then
            st.idx=st.idx+1;w.saveSoon()
        elseif why=="stopped" then w.save();return false
        elseif why=="material" or why=="slab" or why=="trap" or why=="water" or why=="red" then
            local okr,whyr=resupply(why=="material" and "fill" or why)
            if not okr then if whyr~="stopped" then w.fail(whyr) end;return false end
        else w.fail(why);return false end
    end
    run.scanned=N
    local okh,whyh=goHome();if not okh then w.fail(whyh);return false end
    w.unload(keep)
    st.done=true;st.phase="Fertig";w.save()
    opts.readyText="FERTIG: Mobfarm steht. Schwert ins Inventar -> wird zur Mob-Turtle"
    w.status("Fertig","Mobfarm steht. Schwert ins Inventar legen -> wird zur Mob-Turtle.")
    w.finish()
    becomeMob()
    return true
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    return goHome()
end
idleBase=function()
    if st.done then
        becomeMob()
        return true
    end
    return w.unload(keep)
end
pcall(w.equipTool,isTool)
w.start("TOAST MOBFARM-BAU",F.." Etage(n), Schacht "..D..(CREEPER and ", nur Creeper" or ""))
