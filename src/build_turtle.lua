-- Toast Control: Mobfarm-Bau (vor allem fuer Creeper / Schwarzpulver).
-- Die Turtle steht an der spaeteren Toetungsstelle und baut ueber sich:
--   * einen 1x1-Fallschacht (Hoehe build.drop, Standard 22 = Mobs ueberleben
--     mit ~1 Herz, die Mob-Turtle gibt den Rest)
--   * build.floors dunkle Spawn-Etagen (innen 17x17, Waende + Decke dicht),
--     in jeder 4 Wasserkanaele, die die Mobs ins Loch in der Mitte schwemmen
--   * Bruchsteinstufen in jeder 3. Reihe: keine Spinnen (wuerden im 1x1-Loch
--     haengen bleiben)
--   * build.creeperOnly: Falltueren oben an der Decke -> nur 1,81 Bloecke frei:
--     Creeper (1,7) passen, Zombies/Skelette/Hexen/Endermen nicht.
-- Kisten: UNTER der Turtle = Ausgabe (spaeter die Drops), HINTER der Turtle =
-- Material (Bruchstein/Stein/Erde, Wassereimer, Bruchsteinstufen, Falltueren, Kohle).
-- Fertig + Schwert im Inventar: die Turtle wird selbst zur Mob-Turtle (greift
-- nur nach oben an).
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.build
local W=dofile("/toast/toast_worker.lua")
local F,D=C.floors,C.drop
local CREEPER=C.creeperOnly~=false
local R=8                      -- Laenge der Wasserkanaele (Wasser fliesst 8 Bloecke)
local OUT=R+1                  -- Aussenwand
local B0=D                     -- unterste Etage (Boden)
local TOP=B0+4*F               -- Dach

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
local SOLID,AIR,SRC,SLAB="s","a","w","p"
local function target(x,y,z)
    local ax,az=math.abs(x),math.abs(z)
    if y>=1 and y<B0 then
        if x==0 and z==0 then return AIR end
        if ax+az==1 then return SOLID end
        return nil
    end
    if y<B0 or y>TOP or ax>OUT or az>OUT then return nil end
    if y==TOP then return SOLID end
    local k=(y-B0)%4                         -- 0 Boden, 1 Spawnflaeche, 2+3 Luft
    if k==0 then return (x==0 and z==0) and AIR or SOLID end
    if ax==OUT or az==OUT then return SOLID end
    if x==0 and z==0 then return AIR end
    local channel=x==0 or z==0
    if k==1 then
        if channel then return math.max(ax,az)==R and SRC or AIR end
        return SOLID
    end
    if k==2 and not channel and az%3==0 then return SLAB end
    return AIR
end
-- Schritte: {t=Art,x,y=Hoehe der Turtle,z}. "cell" bearbeitet den Block UNTER der Turtle.
local STEPS={}
local function add(t) STEPS[#STEPS+1]=t end
local flip=false
local function layer(y,skipCenter)
    local r=(y<B0) and 1 or OUT
    local list={}
    for zi=-r,r do
        local z=zi
        local xs={}
        for x=-r,r do if target(x,y,z) and not (skipCenter and x==0 and z==0) then xs[#xs+1]=x end end
        if (zi+r)%2==1 then for a=1,math.floor(#xs/2) do xs[a],xs[#xs+1-a]=xs[#xs+1-a],xs[a] end end
        for _,x in ipairs(xs) do list[#list+1]={t="cell",x=x,y=y+1,z=z} end
    end
    if flip then for a=1,math.floor(#list/2) do list[a],list[#list+1-a]=list[#list+1-a],list[a] end end
    flip=not flip
    for _,s in ipairs(list) do add(s) end
end
local function water(b)
    for _,p in ipairs({{R,0},{0,R},{-R,0},{0,-R}}) do add({t="water",x=p[1],y=b+2,z=p[2]}) end
end
-- Falltueren: Turtle faehrt in der Etage auf Hoehe b+2 (ueber den Spawnstellen)
-- und setzt sie nach oben an die Decke. Wege nur durch die Kanaele (x=0) und
-- die Spawnreihen (die Stufenreihen sind belegt).
local function traps(b)
    if not CREEPER then return end
    for _,sx in ipairs({1,-1}) do for _,sz in ipairs({1,-1}) do
        for _,pair in ipairs({{1,2},{4,5},{7,8}}) do
            for x=1,R do add({t="trap",x=sx*x,y=b+2,z=sz*pair[1],corr=true}) end
            for x=R,1,-1 do add({t="trap",x=sx*x,y=b+2,z=sz*pair[2],corr=true}) end
        end
    end end
end
for y=1,B0-1 do layer(y) end
for k=0,F-1 do
    local b=B0+4*k
    layer(b)
    if k>0 then traps(b-4) end
    layer(b+1);water(b)
    layer(b+2);layer(b+3)
end
layer(TOP,true)
traps(B0+4*(F-1))
add({t="cap",x=0,y=TOP-1,z=0})
local N=#STEPS
-- Material je Art ab Schritt i
local function remaining(i)
    local n={fill=0,slab=0,trap=0,water=0}
    for k=i or 1,N do
        local s=STEPS[k]
        if s.t=="cell" then
            local tg=target(s.x,s.y-1,s.z)
            if tg==SOLID then n.fill=n.fill+1 elseif tg==SLAB then n.slab=n.slab+1 end
        elseif s.t=="trap" then n.trap=n.trap+1
        elseif s.t=="water" then n.water=n.water+1
        elseif s.t=="cap" then n.fill=n.fill+1 end
    end
    return n
end
local TOTAL=remaining(1)
local LAYOUT=table.concat({"mobfarm",F,D,CREEPER and "c" or "n"},":")

local w,round,idleHome,idleBase
local opts
opts={job="build",cfg=cfg,section=C,stateFile="/toast_build_state",args={...},cells=N,layout=LAYOUT,
    tools=isTool,noTool="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen",
    interval=0,readyText="START: Mobfarm bauen (macht weiter, wo sie war)",
    extra=function() local s=w and w.st or {}
        return {floors=F,drop=D,creeperOnly=CREEPER,placed=s.placed or 0,done=s.done,
            need=TOTAL.fill,needSlab=TOTAL.slab,needTrap=TOTAL.trap,needWater=TOTAL.water,
            fill=w and w.count(isFill) or 0,slabs=w and w.count(isSlab) or 0,traps=w and w.count(isTrap) or 0,
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
    for z=z0+s,z1,s do if z~=0 and math.abs(z)%3==0 then return true end end
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
local function goTo(x,y,z,corr)
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
    if isFill(name) or isSlab(name) or isTrap(name) or isWaterBucket(name) then return 4096 end
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
        local inv=chestList()
        if inv then
            local okl,list=pcall(inv.list)
            if not okl or type(list)~="table" then break end
            local from
            for s,it in pairs(list) do if match(it.name) and (not from or s<from) then from=s end end
            if not from then break end
            if from~=1 then
                if list[1] then
                    local size=inv.size and inv.size() or 27
                    local free;for s=2,size do if not list[s] then free=s;break end end
                    if not free then break end
                    pcall(inv.pushItems,"front",1,64,free)
                end
                pcall(inv.pushItems,"front",from,64,1)
            end
        end
        turtle.select(slot)
        if not turtle.suck(math.min(64,count-got)) then break end
        local it=turtle.getItemDetail(slot)
        if not it then break end
        if not match(it.name) then
            -- falsches Item (ohne Kisten-Peripherie): in die Ausgabekiste
            turtle.dropDown();if not inv then break end
        else got=got+it.count end
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
    if not w.container(turtle.inspect) then w.face(0);return false,"Materialkiste fehlt","Kiste HINTER die Turtle stellen (Bruchstein, Wassereimer, Stufen, Falltueren, Kohle)." end
    -- leere Eimer zurueck in die Materialkiste
    for i=1,16 do local it=turtle.getItemDetail(i);if it and isBucket(it.name) then turtle.select(i);turtle.drop() end end
    -- zu viel Bruchstein dabei (beim Graben eingesammelt): zurueck in die Materialkiste,
    -- damit Platz bleibt (sonst faehrt sie mit vollem Inventar immer wieder heim)
    for i=16,1,-1 do
        if w.freeSlots()>=4 then break end
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
    for k=st.idx,N do local t=STEPS[k].t;if t=="water" or t=="trap" or (t=="cell" and target(STEPS[k].x,STEPS[k].y-1,STEPS[k].z)==SLAB) then nextSpecial=t=="cell" and "slab" or t;break end end
    if nextSpecial=="water" and have(isWaterBucket)<math.min(4,need.water) then fetch(isWaterBucket,math.min(4,need.water)-have(isWaterBucket)) end
    if nextSpecial=="slab" and have(isSlab)<math.min(64,need.slab) then fetch(isSlab,math.min(64,need.slab)-have(isSlab)) end
    if nextSpecial=="trap" and have(isTrap)<math.min(128,need.trap) then fetch(isTrap,math.min(128,need.trap)-have(isTrap)) end
    -- Rest mit Baumaterial auffuellen (1 Slot frei lassen fuer Abraum)
    local stacks=math.max(0,w.freeSlots()-1)
    if need.fill>have(isFill) and stacks>0 then fetch(isFill,math.min(stacks*64,need.fill-have(isFill))) end
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
local MISSING={fill="Baumaterial fehlt",slab="Stufen fehlen",trap="Falltueren fehlen",water="Wassereimer fehlen"}
local HINT={fill="Bruchstein/Stein/Erde",slab="Bruchsteinstufen",trap="Falltueren (Holz)",water="Wassereimer"}
local function resupply(kind)
    local ok,why=goHome();if not ok then return false,why end
    while true do
        if not w.active() then return false,"stopped" end
        local okb,title,detail=base()
        local match=({fill=isFill,slab=isSlab,trap=isTrap,water=isWaterBucket})[kind]
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
local function doCell(s)
    local tg=target(s.x,s.y-1,s.z)
    local e,b=turtle.inspectDown()
    if tg==SOLID then
        if e and (isFill(b.name) or OKSOLID[b.name]) then return true end
        if e then local ok,why=clearDown();if not ok then return false,why end end
        if not w.find(isFill) then return false,"material" end
        local ok=placeDown(isFill)
        if not ok then return false,"Block nicht setzbar" end
        return true
    elseif tg==SLAB then
        if e and isSlab(b.name) and (b.state or {}).type~="top" then return true end
        if e then local ok,why=clearDown();if not ok then return false,why end end
        if not w.find(isSlab) then return false,"slab" end
        if not placeDown(isSlab) then return false,"Stufe nicht setzbar" end
        local e2,b2=turtle.inspectDown()
        if e2 and (b2.state or {}).type=="top" then DIG.down();return false,"Stufe landet oben statt unten" end
        return true
    else
        -- Wasser im Kanal (auch fliessendes) beim Ausbessern stehen lassen
        local y=s.y-1
        local inChannel=y>=B0 and (y-B0)%4==1 and (s.x==0 or s.z==0) and not (s.x==0 and s.z==0)
        return clearDown(tg==SRC or inChannel)
    end
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
local function doCap()
    local e,b=turtle.inspectUp()
    if e and (isFill(b.name) or OKSOLID[b.name]) then return true end
    local slot=w.find(isFill);if not slot then return false,"material" end
    turtle.select(slot);local ok=turtle.placeUp();turtle.select(1)
    if ok then st.placed=(st.placed or 0)+1 end
    return ok or false,"Dach nicht setzbar"
end
local DO={cell=doCell,water=doWater,trap=doTrap,cap=doCap}
local PHASE=function(s)
    if s.y-1<B0 and s.t=="cell" then return "Schacht" end
    if s.t=="water" then return "Wasser" end
    if s.t=="trap" then return "Falltueren" end
    if s.t=="cap" or s.y-1>=TOP then return "Dach" end
    return "Etage "..(math.floor((s.y-1-B0)/4)+1).."/"..F
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
        -- nochmal: alles pruefen und ausbessern
        st.done=nil;st.idx=1;w.save()
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
        local ok,why=goTo(s.x,s.y,s.z,s.corr)
        if ok then ok,why=DO[s.t](s) end
        if ok then
            st.idx=st.idx+1;w.saveSoon()
        elseif why=="stopped" then w.save();return false
        elseif why=="material" or why=="slab" or why=="trap" or why=="water" then
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
