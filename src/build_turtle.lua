-- Toast Control: Mobfarm-Bau (vor allem fuer Creeper / Schwarzpulver), Himmels-Farm.
-- Die Turtle steht an der spaeteren Sammelstelle und baut ueber sich:
--   * einen 2x2-Fallschacht, build.height (Standard 128) Bloecke hoch: oben in
--     der Luft spawnt im Umkreis nichts anderes, und die Mobs sterben unten
--     durch den Aufprall (Creeper explodieren dabei nicht).
--   * unten 4 Trichter -> Kiste UNTER der Turtle sammelt die Drops.
--   * build.floors dunkle Spawn-Etagen (innen 18x18, nur 3 Lagen hoch):
--       Laufflaeche | Fuesse | Kopf  - die Laufflaeche ist zugleich die Decke
--       der Etage darunter, es gibt keine extra Bodenlage.
--     Ein 2 breiter Kanal durch die Mitte ist 2 tief unter die Laufflaeche
--     eingelassen: Wasser fliesst von beiden Enden 8 Bloecke bis zum 2x2-Loch
--     in der Mitte. Die Etagen sind abwechselnd um 90 Grad gedreht, damit der
--     Kanal oben quer im Raum darunter liegt (dort, wo ohnehin Stufen waeren).
--   * Mob-KI ("Falltuer-Trick"): Mobs meiden Wasser und Abgruende, halten
--     Falltueren aber IMMER fuer festen Boden. Ueber dem Kanal liegen deshalb
--     OFFENE Falltueren (Klappe in der Kanalmitte, also nicht im Weg). Offen
--     werden sie, weil daneben ein Redstoneblock liegt. Der muss liegen bleiben.
--   * Stufenreihen: keine Spinnen (brauchen 3x3 frei), 2 breite Gaenge zum Kanal.
--   * build.creeperOnly: Falltueren oben an der Decke -> nur 1,81 Bloecke frei:
--     Creeper (1,7) passen, Zombies/Skelette/Hexen/Endermen nicht.
--   * Dach aus Stufen: darauf spawnt nichts.
--   * build.afk: Leiter am Schacht hoch zu einem AFK-Platz 30 Bloecke unter der
--     Farm (Mobs spawnen nur bis 128 Bloecke um den Spieler, und weiter als
--     128 entfernte Mobs verschwinden sofort - auch beim Fallen).
-- Kisten: UNTER der Turtle = Drops, HINTER der Turtle = Material (Bruchstein,
-- Stufen, Wassereimer, Falltueren, Redstonebloecke, Leitern, Fackeln, 4 Trichter,
-- Kohle). Am Ende steht die Turtle 2 Bloecke rechts neben dem Schacht.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.build
local W=dofile("/toast/toast_worker.lua")
local F=C.floors
local HGT=C.height or 128
local CREEPER=C.creeperOnly~=false
local AFK=C.afk~=false
-- Im Berg/Gelaende: alle Luftfelder freiraeumen. Sonst (im Freien) wie ein
-- 3D-Drucker: Schicht fuer Schicht nur die Bahnen, wo ein Block hinkommt.
local TERRAIN=C.inTerrain==true
local R=8                      -- Laenge der Wasserkanaele (Wasser fliesst 8 Bloecke)
local OUT=R+1                  -- Aussenwand
local B0=HGT                   -- Kanalboden der untersten Etage
local H=3                      -- Lagen je Etage: Laufflaeche, Fuesse, Kopf
local function SURF(g) return B0+2+H*g end    -- Laufflaeche von Etage g (0 = unterste)
local TOP=SURF(F-1)+H          -- Dach
local AY=B0-30                 -- Boden des AFK-Platzes
local VX,VZ=11,4               -- Aussen-Fahrsaeule (neben der Farm, fuer Dach -> Boden)

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
local function isLadder(n) return n=="minecraft:ladder" end
local function isTorch(n) return n=="minecraft:torch" end
local function isHopper(n) return n=="minecraft:hopper" end
local function isLiquid(n) return n=="minecraft:water" or n=="minecraft:lava" or n:find("flowing_",1,true)~=nil end
local function isTool(n) return n:find("_pickaxe",1,true)~=nil end
local function isContainer(n) return n:find("chest",1,true)~=nil or n:find("barrel",1,true)~=nil or n:find("shulker",1,true)~=nil or n:find("hopper",1,true)~=nil end
local function isTurtle(n) return n:find("computercraft:turtle",1,true)~=nil end

-- ===== Bauplan =====
-- Koordinaten: Turtle (Sammelstelle) = 0,0,0, y nach oben. Der Schacht steht
-- direkt ueber der Turtle (x,z = 0..1); alles ist um x=z=0,5 symmetrisch.
-- A(c) = Abstand zur Mitte (0 fuer 0 und 1, 1 fuer -1 und 2, ...).
local function A(c) if c>=1 then return c-1 end return -c end
local function cf(s,a) if s>0 then return a+1 end return -a end   -- Seite s, Abstand a -> Koordinate
local SOLID,AIR,SRC,SLAB,RED,TRAP="s","a","w","p","r","t"
-- Kanalfelder mit offener Falltuer: ueberall, wo ein Gang endet (nicht vor den Stufenreihen)
local function trapZ(az) return az>=1 and az<=R and az%3~=0 end
-- Jede Etage hat eigene Koordinaten (u,v): Kanal laengs v bei u=0..1, Gaenge laengs u.
-- Die Etagen sind abwechselnd um 90 Grad gedreht. So liegt der 2 tiefe Kanal der
-- oberen Etage quer im Raum der unteren (dort, wo ohnehin eine Stufenreihe waere)
-- und die Laufflaeche oben ist gleich die Decke unten: keine extra Bodenlage.
local function rot(g) return g%2==1 end
local function loc(g,x,z) if rot(g) then return z,x end return x,z end
local function wor(g,u,v) if rot(g) then return v,u end return u,v end
-- Kanal (Boden "bed" 2 unter der Laufflaeche, Wasser "water" 1 darunter) von Etage g
local function canalPart(g,role,x,z)
    local u,v=loc(g,x,z)
    local au,av=A(u),A(v)
    if au==0 and av==0 then return AIR end            -- Fallloch 2x2
    -- unterste Etage haengt frei: Fallloch seitlich dicht (sonst kommt Licht rein)
    if g==0 and au==1 and av==0 then return SOLID end
    if role=="bed" then
        if au==0 and av<=R then return SOLID end
        return nil
    end
    if au==0 then
        if av<=R then return av==R and SRC or AIR end
        return SOLID                                   -- Stirnwand hinter der Quelle
    end
    if au==1 and av>=1 and av<=R then return SOLID end -- Kanalwaende
    return nil
end
-- Raum von Etage g: k 0 Laufflaeche, 1 Fuesse, 2 Kopf
local function room(g,k,x,z)
    local u,v=loc(g,x,z)
    local au,av=A(u),A(v)
    if au==0 and av==0 then return AIR end
    local ring=au==OUT or av==OUT
    if k==0 then
        if ring then return au==0 and SOLID or nil end -- Aussenwand-Fuss nur am Kanalende noetig
        if au==0 then return trapZ(av) and TRAP or AIR end
        if au==1 and trapZ(av) then return RED end
        return SOLID
    end
    if ring then
        if au==OUT and av==OUT then return nil end     -- Ecken: dicht ist es auch ohne
        return SOLID
    end
    if k==1 and au~=0 and av%3==0 then return SLAB end
    return AIR
end
-- Etage + Lage zu einer Hoehe (nil unterhalb der untersten Laufflaeche)
local function floorAt(y)
    local rel=y-SURF(0)
    if rel<0 then return nil,rel end
    return math.floor(rel/H),rel%H
end
local function target(x,y,z)
    local ax,az=A(x),A(z)
    if y>=1 and y<B0 then
        if ax==0 and az==0 then return AIR end
        if ax+az==1 then return SOLID end
        return nil
    end
    if y<B0 or y>TOP or ax>OUT or az>OUT then return nil end
    if y==TOP then if ax==OUT and az==OUT then return nil end;return SLAB end
    local g,k=floorAt(y)
    if not g then return canalPart(0,k==-2 and "bed" or "water",x,z) end
    if k>=1 and g+1<=F-1 then
        local c=canalPart(g+1,k==1 and "bed" or "water",x,z)
        if c~=nil then return c end
    end
    return room(g,k,x,z)
end
-- liegt hier Kanalwasser (beim Freiraeumen stehen lassen)?
local function canalWater(x,y,z)
    for g=0,F-1 do
        if y==SURF(g)-1 then
            local u,v=loc(g,x,z)
            if A(u)==0 and A(v)~=0 and A(v)<=R then return true end
        end
    end
    return false
end
-- Schritte: {t=Art,x,y=Hoehe der Turtle,z}. "cell" bearbeitet den Block UNTER der Turtle
-- (und raeumt Luftfelder 2 darueber gleich mit frei).
-- Sparsam fahren:
--  * Luftfelder, die schon 2 Lagen tiefer von unten freigeraeumt wurden, werden
--    nicht noch einmal angefahren (im Freien = fast alle Luftfelder).
--  * Reihenfolge je Lage: immer zum naechstgelegenen offenen Feld.
--  * Zur naechsten Lage direkt hoch (nicht ueber die Mitte).
--  * Schacht: Turtle faehrt die 4 Schachtfelder ab und setzt die Waende rundum.
local STEPS={}
local function add(t) STEPS[#STEPS+1]=t end
local VIS={}                       -- VIS[y]["x,z"] = Lage y wurde dort bearbeitet
local function k2(x,z) return x..","..z end
local last={x=0,z=0}
local function layer(y,skipCenter)
    local r=(y<B0) and 1 or OUT
    local cells={}
    for z=-r,r+1 do for x=-r,r+1 do
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
local SHAFT={{0,0},{1,0},{1,1},{0,1}}
local function shaft(y)
    VIS[y]={}                          -- Turtle steht IM Feld: 2 hoeher ist dadurch nicht frei
    for i=1,4 do
        local c=SHAFT[y%2==1 and i or 5-i]
        add({t="wall4",x=c[1],y=y,z=c[2],shaft=true})
        last={x=c[1],z=c[2]}
    end
end
local function water(g)
    -- 4 Quellen an den Kanalenden (2 Spuren), immer die naechstgelegene zuerst
    local P={}
    for _,u in ipairs({0,1}) do for _,v in ipairs({R+1,-R}) do local x,z=wor(g,u,v);P[#P+1]={x,z} end end
    while #P>0 do
        local bi,bd=1,math.huge
        for i,p in ipairs(P) do local d=math.abs(p[1]-last.x)+math.abs(p[2]-last.z);if d<bd then bi,bd=i,d end end
        local p=table.remove(P,bi)
        add({t="water",x=p[1],y=SURF(g),z=p[2]});last={x=p[1],z=p[2]}
    end
end
-- Offene Falltueren ueber dem Kanal: Turtle faehrt ueber der Laufflaeche die
-- beiden Spuren ab und setzt sie nach unten (die Redstonebloecke liegen schon).
-- Die Klappe steht auf der Seite, in die die Turtle schaut: beide Klappen in
-- die Kanalmitte, dann laufen die Mobs von beiden Seiten ungehindert drauf.
local function canalTraps(g)
    local y=SURF(g)
    local _,lv=loc(g,last.x,last.z)
    local up=lv<1                       -- auf der negativen Seite: nach +v fahren
    VIS[y]=VIS[y] or {}
    for lane=0,1 do
        local face=rot(g) and (lane==0 and 0 or 2) or (lane==0 and 1 or 3)
        local a,b,s=-R,R+1,1
        if not up then a,b,s=R+1,-R,-1 end
        for v=a,b,s do
            if trapZ(A(v)) then
                local x,z=wor(g,lane,v)
                add({t="ctrap",x=x,y=y+1,z=z,face=face});VIS[y][k2(x,z)]=true;last={x=x,z=z}
            end
        end
        up=not up
    end
end
-- Decken-Falltueren: Turtle faehrt in der Etage auf Fusshoehe (ueber den
-- Spawnstellen) und setzt sie nach oben an die Decke. Wege nur durch den Kanal
-- und die Gaenge (die Stufenreihen sind belegt).
local function traps(g)
    if not CREEPER then return end
    local y=SURF(g)+1
    for _,su in ipairs({1,-1}) do for _,sv in ipairs({1,-1}) do
        for _,pair in ipairs({{1,2},{4,5},{7,8}}) do
            for n,row in ipairs(pair) do
                local a,b,st=1,R,1
                if n==2 then a,b,st=R,1,-1 end
                for u=a,b,st do
                    local x,z=wor(g,cf(su,u),cf(sv,row))
                    if target(x,y+1,z)==AIR then add({t="trap",x=x,y=y,z=z,corr=true,rot=rot(g)}) end
                end
            end
        end
    end end
end
for y=1,B0-1 do shaft(y) end
-- unterste Etage: ihr Kanal haengt unter der Laufflaeche
last={x=0,z=0}
layer(B0);layer(B0+1);water(0)
for g=0,F-1 do
    local S=SURF(g)
    layer(S);canalTraps(g)
    if g>0 then traps(g-1) end            -- Decke unten ist jetzt da
    layer(S+1);layer(S+2)                 -- (mit Kanal der Etage darueber)
    if g+1<=F-1 then water(g+1) end
end
traps(F-1)                                -- Falltueren brauchen keinen Halt: vor dem Dach
layer(TOP,true)                           -- Dach aus Stufen, die Mitte (Fahrweg) zuletzt
add({t="cell",x=0,y=TOP+1,z=0,roof=true})
local OUTSTART=#STEPS+1                   -- ab hier ist der Schacht oben zu: aussen herum fahren
-- AFK-Platz: Leiter aussen am Schacht (Wand bei z=2), Plattform aus Stufen, Gelaender, 2 Fackeln
local PLAT,RAIL,TORCH={},{},{{-2,5},{2,5}}
if AFK then
    for y=1,AY+1 do add({t="ladder",x=0,y=y,z=4,out=true}) end
    PLAT={{0,4},{1,4},{1,5},{0,5},{-1,5},{-1,4},{-1,6},{0,6},{1,6}}
    for _,p in ipairs(PLAT) do add({t="plat",x=p[1],y=AY+1,z=p[2],out=true}) end
    RAIL={{1,3},{2,4},{2,5},{2,6},{1,7},{0,7},{-1,7},{-2,6},{-2,5},{-2,4},{-1,3}}
    for _,p in ipairs(RAIL) do add({t="rail",x=p[1],y=AY+2,z=p[2],out=true}) end
    for _,p in ipairs(TORCH) do add({t="torch",x=p[1],y=AY+3,z=p[2],out=true}) end
end
-- 4 Trichter unten im Schacht: (0,0) zeigt in die Kiste darunter, die anderen in (0,0)
local HOPS={
    {n=1,x=0,y=1,z=0,via={}},
    {n=2,x=0,y=0,z=2,dir=2,via={{0,1,1},{0,0,1}}},
    {n=3,x=2,y=0,z=1,dir=3,via={{1,0,2},{2,0,2}}},
    {n=4,x=2,y=0,z=0,dir=3,via={}}}
for _,h in ipairs(HOPS) do add({t="hop",n=h.n,x=h.x,y=h.y,z=h.z,dir=h.dir,via=h.via,hop=true}) end
local N=#STEPS
-- hoechste schon gebaute Lage VOR jedem Schritt (darueber ist alles noch frei)
local HB={}
do local hb=0
    for k=1,N do
        HB[k]=hb
        local s=STEPS[k]
        local l=s.out and 0 or s.hop and 0 or s.t=="cell" and s.y-1 or s.t=="wall4" and s.y or s.t=="water" and s.y-1 or s.t=="ctrap" and s.y-1 or s.t=="trap" and s.y+1 or 0
        if l>hb then hb=l end
    end
end
-- Material je Art ab Schritt i
local function remaining(i)
    local n={fill=0,slab=0,trap=0,water=0,red=0,ladder=0,torch=0,hopper=0}
    for k=i or 1,N do
        local s=STEPS[k]
        if s.t=="cell" then
            local tg=target(s.x,s.y-1,s.z)
            if tg==SOLID then n.fill=n.fill+1 elseif tg==SLAB then n.slab=n.slab+1 elseif tg==RED then n.red=n.red+1 end
        elseif s.t=="trap" or s.t=="ctrap" then n.trap=n.trap+1
        elseif s.t=="water" then n.water=n.water+1
        elseif s.t=="wall4" then
            for d=0,3 do if target(s.x+W.DX[d],s.y,s.z+W.DZ[d])==SOLID then n.fill=n.fill+1 end end
        elseif s.t=="ladder" then n.ladder=n.ladder+1
        elseif s.t=="plat" then n.slab=n.slab+1
        elseif s.t=="rail" then n.fill=n.fill+1
        elseif s.t=="torch" then n.torch=n.torch+1
        elseif s.t=="hop" then n.hopper=n.hopper+1 end
    end
    return n
end
local TOTAL=remaining(1)
local LAYOUT=table.concat({"mobfarm4",F,HGT,CREEPER and "c" or "n",TERRAIN and "t" or "p",AFK and "a" or "-"},":")

local w,round,idleHome,idleBase
local opts
opts={job="build",cfg=cfg,section=C,stateFile="/toast_build_state",args={...},cells=N,layout=LAYOUT,
    tools=isTool,noTool="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen",
    interval=0,readyText="START: Mobfarm bauen (macht weiter, wo sie war)",
    extra=function() local s=w and w.st or {}
        return {floors=F,height=HGT,afk=AFK,creeperOnly=CREEPER,placed=s.placed or 0,done=s.done,
            need=TOTAL.fill,needSlab=TOTAL.slab,needTrap=TOTAL.trap,needWater=TOTAL.water,needRed=TOTAL.red,
            needLadder=TOTAL.ladder,needTorch=TOTAL.torch,needHopper=TOTAL.hopper,
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
if st.done then run.scanned=N;opts.readyText="FERTIG: Mobfarm steht. Drops in der Kiste unter den Trichtern." end

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
local corrRot=false         -- ... und diese Etage ist gedreht (Kanal laengs x)
local outside=false         -- aussen herum (Dach -> AFK-Platz -> Basis): Gebautes nie abbauen
local MOPT={dig=true,attack=true,canDig=function(n)
    if isContainer(n) or isTurtle(n) then return false end
    if corridor and (isSlab(n) or isTrap(n) or isRed(n) or isFill(n)) then return false end
    if outside and (isSlab(n) or isTrap(n) or isRed(n) or isLadder(n) or isTorch(n) or n:find("torch",1,true)) then return false end
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
    for z=z0+s,z1,s do if A(z)%3==0 then return true end end   -- Stufenreihen (auch die Mitte)
    return false
end
-- waagrecht auf der aktuellen Hoehe
local function horizontal(x,z)
    if corridor then
        -- in Etagen-Koordinaten: u = Gang-Richtung, v = Kanal-Richtung
        local U,V=corrRot and "z" or "x",corrRot and "x" or "z"
        local cu,cv=corrRot and st.z or st.x,corrRot and st.x or st.z
        local tu,tv=corrRot and z or x,corrRot and x or z
        if cv~=tv and A(cu)~=0 and blockedZ(cv,tv) then
            local ok,why=line(U,0);if not ok then return false,why end
        end
        local ok,why=line(V,tv);if not ok then return false,why end
        return line(U,tu)
    end
    local ok,why=line("x",x);if not ok then return false,why end
    return line("z",z)
end
-- Hoehe wechseln immer durch die Mittelsaeule (die ist im ganzen Bau frei)
local function goTo(x,y,z,corr,climb,rotated)
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
    corridor=corr==true;corrRot=rotated==true
    local ok,why=horizontal(x,z)
    return ok,why
end
-- ===== Aussen herum (nach dem Dach) =====
-- Fahrsaeule (VX,*,VZ) neben der Farm vom Dach bis zum Boden; AFK-Bereich
-- x -2..3, z 3..7 bis AY+3; am Boden (y=0) Reihe z=VZ und x=0 zur Basis.
local function inAfk(x,y,z) return AFK and y>=AY+1 and y<=AY+3 and x>=-2 and x<=2 and z>=3 and z<=7 end
local function vline(y)
    while st.y~=y do
        local ok,why=w.move(st.y<y and "up" or "down",MOPT);if not ok then return false,why end
    end
    return true
end
local function outGo(x,y,z,s)
    outside=true;corridor=false
    local function done(ok,why) outside=false;return ok,why end
    if st.x==x and st.y==y and st.z==z then return done(true) end
    local ok,why
    -- Leiter: in der Leitersaeule direkt hoch (die Plattform liegt noch nicht)
    if s and s.t=="ladder" and st.x==0 and st.z==4 and st.y<=AY+1 then return done(vline(y)) end
    -- im AFK-Bereich bleiben: erst hoch, dann waagrecht, dann runter
    if inAfk(st.x,st.y,st.z) and inAfk(x,y,z) then
        ok,why=vline(math.max(st.y,y));if not ok then return done(ok,why) end
        ok,why=line("x",x);if ok then ok,why=line("z",z) end;if not ok then return done(ok,why) end
        return done(vline(y))
    end
    -- 1) zur Fahrsaeule
    if st.x~=VX or st.z~=VZ then
        if st.y>=TOP+1 then ok,why=line("z",VZ);if ok then ok,why=line("x",VX) end
        elseif inAfk(st.x,st.y,st.z) then
            ok,why=vline(AY+3);if ok then ok,why=line("z",VZ) end;if ok then ok,why=line("x",VX) end
        elseif st.z==VZ and st.y<=AY and st.x>=0 and st.x<=VX then ok,why=line("x",VX)
        elseif st.y==0 and st.x==0 and st.z>=0 and st.z<=VZ then ok,why=line("z",VZ);if ok then ok,why=line("x",VX) end
        else return done(false,"Position fuer Aussenweg unklar") end
        if not ok then return done(ok,why) end
    end
    -- 2) senkrecht, 3) hin
    if inAfk(x,y,z) then
        ok,why=vline(AY+3);if ok then ok,why=line("x",x) end;if ok then ok,why=line("z",z) end
        if ok then ok,why=vline(y) end
        return done(ok,why)
    end
    ok,why=vline(y);if ok then ok,why=line("x",x) end;if ok then ok,why=line("z",z) end
    return done(ok,why)
end
-- Trichter: feste Wegpunkte unten am Schacht (immer nur eine Achse je Stueck)
local function viaGo(pts)
    for _,p in ipairs(pts) do
        local ok,why=vline(p[2]);if ok then ok,why=line("x",p[1]) end;if ok then ok,why=line("z",p[3]) end
        if not ok then return false,why end
    end
    return true
end
local function homeNeed() return math.abs(st.x)+math.abs(st.y)+math.abs(st.z)+20+(st.idx>=OUTSTART and 2*VX+2*VZ or 0) end

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
    if isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    if isFill(name) or isSlab(name) or isTrap(name) or isRed(name) or isWaterBucket(name) or isLadder(name) or isTorch(name) or isHopper(name) then return 4096 end
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
    if not w.container(turtle.inspect) then w.face(0);return false,"Materialkiste fehlt","Kiste HINTER die Turtle stellen (Bruchstein, Stufen, Wassereimer, Falltueren, Redstonebloecke, Leitern, Fackeln, Trichter, Kohle)." end
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
        if t=="water" or t=="trap" or t=="ctrap" or tg==SLAB or tg==RED or t=="ladder" or t=="plat" or t=="torch" or t=="hop" then
            nextSpecial=(tg==SLAB or t=="plat") and "slab" or tg==RED and "red" or t=="ctrap" and "trap" or t=="hop" and "hopper" or t;break
        end
    end
    if nextSpecial=="water" and have(isWaterBucket)<math.min(4,need.water) then fetch(isWaterBucket,math.min(4,need.water)-have(isWaterBucket)) end
    if nextSpecial=="slab" and have(isSlab)<math.min(192,need.slab) then fetch(isSlab,math.min(192,need.slab)-have(isSlab)) end
    -- nach dem Dach: alles fuer AFK-Platz und Trichter auf einmal (spart Wege ueber die Fahrsaeule)
    local late=st.idx>=OUTSTART
    if late and need.slab>0 and have(isSlab)<need.slab then fetch(isSlab,need.slab-have(isSlab)) end
    if late and need.ladder>0 and have(isLadder)<math.min(128,need.ladder) then fetch(isLadder,math.min(128,need.ladder)-have(isLadder)) end
    if late and need.torch>0 and have(isTorch)<need.torch then fetch(isTorch,need.torch-have(isTorch)) end
    if late and need.hopper>0 and have(isHopper)<need.hopper then fetch(isHopper,need.hopper-have(isHopper)) end
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
    local ok,why
    if st.idx>=OUTSTART then ok,why=outGo(0,0,0) else ok,why=goTo(0,0,0,false) end
    if not ok then return false,"Rueckweg: "..tostring(why) end
    return w.face(0)
end
-- Nachschub holen; fehlt etwas, an der Basis warten bis es da ist
local MISSING={fill="Baumaterial fehlt",slab="Stufen fehlen",trap="Falltueren fehlen",water="Wassereimer fehlen",red="Redstonebloecke fehlen",
    ladder="Leitern fehlen",torch="Fackeln fehlen",hopper="Trichter fehlen"}
local HINT={fill="Bruchstein/Stein/Erde",slab="Bruchsteinstufen",trap="Falltueren (Holz)",water="Wassereimer",red="Redstonebloecke",
    ladder="Leitern",torch="Fackeln",hopper="Trichter"}
local MATCH={fill=isFill,slab=isSlab,trap=isTrap,water=isWaterBucket,red=isRed,ladder=isLadder,torch=isTorch,hopper=isHopper}
local function resupply(kind)
    local ok,why=goHome();if not ok then return false,why end
    while true do
        if not w.active() then return false,"stopped" end
        local okb,title,detail=base()
        local match=MATCH[kind]
        local want=kind=="hopper" and remaining(st.idx).hopper or 1
        if okb and (not kind or not match or have(match)>=want) then st.missing=nil;return true end
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
        local inChannel=canalWater(s.x,y,s.z)
        local ok,why=clearDown(tg==SRC or inChannel)
        if not ok then return false,why end
    end
    -- Luftfeld 2 weiter oben gleich mit freiraeumen (dann muss die Lage dort nicht nochmal hin)
    local ta=target(s.x,s.y+1,s.z)
    if TERRAIN and (ta==AIR or ta==SRC) then
        local ya=s.y+1
        clearUp(ta==SRC or canalWater(s.x,ya,s.z))
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
-- Schacht: Turtle steht in einem der 4 Schachtfelder und setzt die Waende daneben (Drehen kostet kein Fuel)
local function doWall4(s)
    local d0=st.dir
    for k=0,3 do
        local d=(d0+k)%4
        if target(s.x+W.DX[d],s.y,s.z+W.DZ[d])==SOLID then
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
    local okf,whyf=w.face(s.face or 1);if not okf then return false,whyf end
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
-- ===== AFK-Platz und Trichter =====
local function placeHere(placeFn,inspectFn,digFn,match,okFn,code,err)
    local e,b=inspectFn()
    if e and okFn(b) then return true end
    if e then
        if isContainer(b.name) or isTurtle(b.name) then return false,err..": belegt ("..b.name..")" end
        if not isLiquid(b.name) and not digFn() then return false,"Nicht abbaubar: "..b.name end
    end
    local slot=w.find(match);if not slot then return false,code end
    turtle.select(slot);local ok=placeFn();turtle.select(1)
    if not ok then return false,err end
    st.placed=(st.placed or 0)+1
    return true
end
local function doLadder(s)
    local ok,why=w.face(2);if not ok then return false,why end
    return placeHere(turtle.place,turtle.inspect,DIG.forward,isLadder,function(b) return isLadder(b.name) end,"ladder","Leiter nicht setzbar")
end
local function doPlat(s)
    local ok,why=placeHere(turtle.placeDown,turtle.inspectDown,DIG.down,isSlab,
        function(b) return isSlab(b.name) and (b.state or {}).type~="top" end,"slab","Stufe nicht setzbar")
    if not ok then return false,why end
    local e,b=turtle.inspectDown()
    if e and (b.state or {}).type=="top" then DIG.down();return false,"Stufe landet oben statt unten" end
    if TERRAIN then clearUp(false) end         -- Kopffreiheit fuer den Spieler
    return true
end
local function doRail(s)
    return placeHere(turtle.placeDown,turtle.inspectDown,DIG.down,isFill,function(b) return isFill(b.name) or OKSOLID[b.name] end,"material","Gelaender nicht setzbar")
end
local function doTorch(s)
    return placeHere(turtle.placeDown,turtle.inspectDown,DIG.down,isTorch,function(b) return b.name:find("torch",1,true)~=nil end,"torch","Fackel nicht setzbar")
end
local function doHop(s)
    if s.n==1 then
        return placeHere(turtle.placeDown,turtle.inspectDown,DIG.down,isHopper,function(b) return isHopper(b.name) end,"hopper","Trichter nicht setzbar")
    end
    local ok,why=w.face(s.dir);if not ok then return false,why end
    return placeHere(turtle.place,turtle.inspect,DIG.forward,isHopper,function(b) return isHopper(b.name) end,"hopper","Trichter nicht setzbar")
end
local function hopGo(s)
    if s.n==1 and not (st.x==0 and st.y==1 and st.z==0) and not w.isHome() then
        local ok,why=outGo(0,0,0);if not ok then return false,why end
    end
    outside=true
    local ok,why=viaGo(s.via)
    if ok then ok,why=viaGo({{s.x,s.y,s.z}}) end
    outside=false
    return ok,why
end
-- fertig: hier ist ab jetzt die Basis (Trichter liegen, wo vorher die Basis war)
local function park()
    local ok,why=w.face(0);if not ok then return false,why end
    st.x,st.y,st.z,st.dir=0,0,0,0;st.trail=nil
    w.save()
    return true
end
local DO={cell=doCell,water=doWater,trap=doTrap,ctrap=doCtrap,wall4=doWall4,
    ladder=doLadder,plat=doPlat,rail=doRail,torch=doTorch,hop=doHop}
local PHASE=function(s)
    if s.t=="wall4" then return "Schacht" end
    if s.t=="water" then return "Wasser" end
    if s.t=="trap" then return "Falltueren" end
    if s.t=="ctrap" then return "Kanal-Falltueren" end
    if s.t=="ladder" then return "Leiter" end
    if s.t=="plat" or s.t=="rail" or s.t=="torch" then return "AFK-Platz" end
    if s.t=="hop" then return "Trichter" end
    if s.y-1>=TOP then return "Dach" end
    local g=floorAt(s.y-1)
    return "Etage "..(math.min(F,(g or 0)+1)).."/"..F
end
local NEEDCODE={material="fill",slab="slab",trap="trap",water="water",red="red",ladder="ladder",torch="torch",hopper="hopper"}
local FERTIG="FERTIG: Mobfarm steht. Drops in der Kiste unter den Trichtern."
round=function()
    if st.done then
        -- Farm steht schon: nicht nochmal durch die fertigen Etagen fahren
        w.status("Fertig","Mobfarm steht schon. Neu bauen: an der Turtle N (neuer Auftrag).")
        w.finish()
        return true
    end
    opts.readyText="START: Mobfarm bauen (macht weiter, wo sie war)"
    if w.isHome() and not STEPS[st.idx].hop then
        local ok=resupply(nil);if not ok then return false end
    end
    while st.idx<=N do
        if not w.active() then w.save();return false end
        local s=STEPS[st.idx]
        run.scanned=st.idx-1
        st.phase=PHASE(s)
        if s.hop then
            -- unten am Schacht: zurueck zur Basis geht ab dem ersten Trichter nicht mehr
            if s.n==1 and not (st.x==0 and st.y==1 and st.z==0) and have(isHopper)<remaining(st.idx).hopper then
                local ok,why=resupply("hopper");if not ok then if why~="stopped" then w.fail(why) end;return false end
            end
        elseif w.freeSlots()==0 or fuel()<homeNeed()+math.abs(s.y-st.y)+40 then
            local ok,why=resupply(nil);if not ok then if why~="stopped" then w.fail(why) end;return false end
        end
        w.status("Baut",st.phase.." - Schritt "..st.idx.."/"..N)
        local ok,why
        if s.hop then ok,why=hopGo(s)
        elseif s.out then ok,why=outGo(s.x,s.y,s.z,s)
        else ok,why=goTo(s.x,s.y,s.z,s.corr,s.shaft or st.y>HB[st.idx],s.rot) end
        if ok then ok,why=DO[s.t](s) end
        if ok then
            st.idx=st.idx+1;w.saveSoon()
        elseif why=="stopped" then w.save();return false
        elseif NEEDCODE[why] and not s.hop then
            local okr,whyr=resupply(NEEDCODE[why])
            if not okr then if whyr~="stopped" then w.fail(whyr) end;return false end
        else w.fail(NEEDCODE[why] and MISSING[NEEDCODE[why]] or why);return false end
    end
    run.scanned=N
    local okp,whyp=park();if not okp then w.fail(whyp);return false end
    st.done=true;st.phase="Fertig";w.save()
    opts.readyText=FERTIG
    w.status("Fertig",FERTIG)
    w.finish()
    return true
end
idleHome=function()
    if st.done then return true end
    if w.isHome() and st.dir==0 then return true end
    return goHome()
end
idleBase=function()
    if st.done then return true end
    return w.unload(keep)
end
pcall(w.equipTool,isTool)
w.start("TOAST MOBFARM-BAU",F.." Etage(n), "..HGT.." hoch"..(CREEPER and ", nur Creeper" or "")..(AFK and ", AFK-Platz" or ""))
