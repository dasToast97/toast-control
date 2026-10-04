-- Toast Control: Aushub. Hoehlt eine Form vor der Basis aus:
--   room      Quader / Raum / Schacht (Breite x Laenge x Hoehe)
--   cylinder  Zylinder / runder Schacht (Durchmesser = Breite, Hoehe)
--   sphere    Kugel (Durchmesser = Breite)
--   dome      Halbkugel: nach oben = Kuppel, nach unten = Schale
-- direction "down" = von der Basis-Ebene nach unten, "up" = nach oben.
-- Extras:
--   seal      "off" | "liquids" (Wasser/Lava an den Waenden zubauen) |
--             "all" (auch Loecher/Hoehlen zubauen = komplett dichter Raum)
--   drain     Wasser/Lava IM Raum entfernen (Block rein, wieder abbauen):
--             fuer Arbeiten unter Wasser oder in Lava.
--   keepOres  "" = alles abbauen, "all" = alle Erze stehen lassen,
--             "diamond,emerald" = nur diese Erze stehen lassen. Die Turtle
--             graebt drumherum, die Erze kann man spaeter von Hand abbauen.
-- Basis: Kiste UNTER der Turtle = Ausgabe, Kiste UEBER der Turtle = Kohle.
-- Die Form beginnt direkt VOR der Turtle.
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.dig
local W=dofile("/toast/toast_worker.lua")
local DOWN=C.direction~="up"
local SEAL=C.seal or "liquids"
local DRAIN=C.drain==true
-- Verkleidung: Waende/Boden/Decke aus einem bestimmten Block (liegt in der Kiste OBEN)
local WALL=(type(C.wallBlock)=="string" and C.wallBlock~="") and C.wallBlock or nil
local LINE={side=C.lineWalls~=false,down=C.lineFloor~=false,up=C.lineCeiling~=false}
local WALLSTOCK=C.wallStock or 256
local SHAPE=C.shape
-- ===== Bloecke =====
local KEEPALL,KEEP=false,{}
do
    local ko=tostring(C.keepOres or ""):lower()
    if ko=="all" or ko=="alle" then KEEPALL=true
    else for word in ko:gmatch("[^,;%s]+") do KEEP[#KEEP+1]=word end end
end
local function isOre(n) return n:find("_ore",1,true)~=nil or n=="minecraft:ancient_debris" end
local function keptOre(n)
    if not isOre(n) then return false end
    if KEEPALL then return true end
    for _,k in ipairs(KEEP) do if n:find(k,1,true) then return true end end
    return false
end
local UNBREAKABLE={["minecraft:bedrock"]=true,["minecraft:barrier"]=true,["minecraft:end_portal_frame"]=true,
    ["minecraft:end_portal"]=true,["minecraft:nether_portal"]=true,["minecraft:reinforced_deepslate"]=true}
local function isTurtle(n) return n:find("computercraft:turtle",1,true)~=nil end
local function isLiquid(n)
    return n=="minecraft:water" or n=="minecraft:lava" or n=="minecraft:bubble_column"
        or n:find("flowing_",1,true)~=nil
end
local FILL={}
for _,n in ipairs({"cobblestone","cobbled_deepslate","stone","deepslate","dirt","netherrack","andesite","diorite",
    "granite","tuff","calcite","blackstone","basalt","smooth_basalt","end_stone"}) do
    FILL["minecraft:"..n]=true
end
local function isFill(n) return FILL[n]==true end
local function isWall(n) return WALL~=nil and n==WALL end
local function isContainer(n) return n:find("chest",1,true)~=nil or n:find("barrel",1,true)~=nil or n:find("shulker",1,true)~=nil end
local function isTool(n) return n:find("_pickaxe",1,true)~=nil end
-- Bloecke, die stehen bleiben (nicht abbauen, aussen herum)
local PROTECTED={};for _,n in ipairs(C.protectedBlocks or {}) do PROTECTED[n]=true end
local function stays(n) return UNBREAKABLE[n]==true or PROTECTED[n]==true or keptOre(n) end

-- ===== Form =====
-- Ebene i = 0 .. bh-1 (0 = Basis-Ebene), y = i nach oben bzw. -i nach unten.
-- x = 0 .. bx-1 zur Seite, z = 1 .. bz nach vorne. Basis = 0,0,0.
local bx,bz,bh
if SHAPE=="room" then bx,bz,bh=C.width,C.length,C.height
elseif SHAPE=="cylinder" then bx,bz,bh=C.width,C.width,C.height
elseif SHAPE=="sphere" then bx,bz,bh=C.width,C.width,C.width
else bx,bz,bh=C.width,C.width,math.ceil(C.width/2) end
local cx,cz=(bx-1)/2,(bz+1)/2
local R2=(C.width/2)^2
local function inside(x,i,z)
    if x<0 or x>=bx or z<1 or z>bz or i<0 or i>=bh then return false end
    if SHAPE=="room" then return true end
    local dx,dz=x-cx,z-cz
    if SHAPE=="cylinder" then return dx*dx+dz*dz<=R2 end
    local dy
    if SHAPE=="sphere" then dy=i-(bh-1)/2 else dy=i+(C.width%2==0 and 0.5 or 0) end
    return dx*dx+dy*dy+dz*dz<=R2
end
local S=72
local function key(x,i,z) return (i*S+x)*S+z end
local function unkey(k) local z=k%S;local r=(k-z)/S;local x=r%S;return x,(r-x)/S,z end
local function layer(y) return DOWN and -y or y end
local function ylev(i) return DOWN and -i or i end
local BASE=key(0,0,0)
local ORDER,INDEX={},{}
local function add(x,i,z) local k=key(x,i,z);if not INDEX[k] then ORDER[#ORDER+1]=k;INDEX[k]=#ORDER end end
-- Zugang: von der Basis bis zur ersten Zelle der Form (bei runden Formen)
do
    local x,i,z=0,0,1
    local xc,zc=math.floor(cx),math.floor(cz)
    local ic=SHAPE=="sphere" and math.floor((bh-1)/2) or 0
    for _=1,400 do
        if inside(x,i,z) then break end
        add(x,i,z)
        if x~=xc then x=x+(xc>x and 1 or -1)
        elseif i~=ic then i=i+(ic>i and 1 or -1)
        elseif z~=zc then z=z+(zc>z and 1 or -1)
        else break end
    end
end
local ACCESS=#ORDER
local LAYERSTART={}
for i=0,bh-1 do
    LAYERSTART[i]=#ORDER+1
    local cells={}
    for z=1,bz do
        local xs={}
        for x=0,bx-1 do if inside(x,i,z) then xs[#xs+1]=x end end
        if z%2==0 then for a=1,math.floor(#xs/2) do xs[a],xs[#xs+1-a]=xs[#xs+1-a],xs[a] end end
        for _,x in ipairs(xs) do cells[#cells+1]={x,z} end
    end
    -- jede zweite Ebene rueckwaerts: Ende der einen = Anfang der naechsten
    if i%2==1 then for a=1,math.floor(#cells/2) do cells[a],cells[#cells+1-a]=cells[#cells+1-a],cells[a] end end
    for _,c in ipairs(cells) do add(c[1],i,c[2]) end
end
local N=#ORDER
local SHAPE_NAMES={room="Quader",cylinder="Zylinder",sphere="Kugel",dome=DOWN and "Schale" or "Kuppel"}
local LAYOUT=table.concat({SHAPE,C.width,C.length,C.height,C.side,C.direction},":")

local w,round,idleHome,idleBase
local opts
opts={job="dig",cfg=cfg,section=C,stateFile="/toast_dig_state",args={...},cells=N,
    layout=LAYOUT,mirror=C.side=="left",
    tools=isTool,noTool="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen",
    interval=0,readyText="START: Form ausheben | 1x: dasselbe (macht weiter, wo sie war)",
    extra=function() local s=w and w.st or {}
        return {shape=SHAPE,digDir=DOWN and "down" or "up",kept=s.kept or 0,sealed=s.sealed or 0,
            drained=s.drained or 0,fill=w and w.count(isFill) or 0,noFill=s.noFill,done=s.done,
            wallBlock=WALL,wall=WALL and w and w.count(isWall) or 0,lined=s.lined or 0,noWall=s.noWall} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end}
w=W.new(opts)
local st,run=w.st,w.run
if st.digLayout~=LAYOUT then st.digLayout=LAYOUT;st.idx=1;st.skip={};st.done=nil;w.save() end
st.idx=st.idx or 1;st.skip=type(st.skip)=="table" and st.skip or {}
if st.done then run.scanned=N;opts.readyText="FERTIG: Form komplett. START = nochmal pruefen, N = neuer Auftrag" end

-- ===== Inventar / Fuel =====
local function keep(name)
    if isTool(name) or common.MODEM_ITEMS[name] then return 4096 end
    if isWall(name) then return WALLSTOCK end
    if isFill(name) and (SEAL~="off" or DRAIN) then return 64 end
    if W.FUELS[name] and C.useCoal then return 64 end
    return 0
end
local function fuel() local f=turtle.getFuelLevel();if f=="unlimited" then return math.huge end;return f end
local function homeNeed() return (math.abs(st.x)+math.abs(st.y)+math.abs(st.z))*2+30 end
local function burnCoal(target)
    if not C.useCoal then return end
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
local function wallCount() return WALL and w.count(isWall) or 0 end
-- Kiste OBEN: Kohle (tanken) und Wandblock holen. Fremdes kommt am Ende zurueck.
local function supply()
    burnCoal(C.fuelTarget)
    if not w.container(turtle.inspectUp) then return end
    local want=WALL and math.min(WALLSTOCK,math.max(0,w.freeSlots()-3)*64+wallCount()) or 0
    local back={}
    for _=1,30 do
        local needFuel=fuel()<C.fuelTarget
        local needWall=WALL~=nil and wallCount()<want
        if not needFuel and not needWall then break end
        if w.freeSlots()<=1 then break end
        local slot;for i=1,16 do if turtle.getItemCount(i)==0 then slot=i;break end end
        turtle.select(slot)
        if not turtle.suckUp() then break end
        local it=turtle.getItemDetail(slot)
        if it and W.FUELS[it.name] then
            while fuel()<C.fuelTarget and turtle.getItemCount(slot)>0 do if not turtle.refuel(1) then break end end
            if turtle.getItemCount(slot)>0 then back[#back+1]=slot end
        elseif not (it and isWall(it.name) and needWall) then back[#back+1]=slot end
    end
    for _,s in ipairs(back) do turtle.select(s);turtle.dropUp() end
    turtle.select(1)
end
local function base()
    local before=w.items()
    local ok,title,detail=w.unload(keep)
    st.total=(st.total or 0)+math.max(0,before-w.items())
    if not ok then return false,title,detail end
    supply()
    if fuel()<math.min(C.fuelTarget,(bx+bz+bh)*3+60) then
        return false,"Treibstoff fehlt","Kohle / Holzkohle in die Kiste UEBER der Basis legen."
    end
    w.save()
    return true
end

-- ===== Bewegung =====
local INSPECT={forward=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown}
local PLACE={forward=turtle.place,up=turtle.placeUp,down=turtle.placeDown}
local RAWDIG={forward=turtle.dig,up=turtle.digUp,down=turtle.digDown}
-- Abbauen; mit Chunkloader liegt evtl. das Modem an -> Spitzhacke anlegen, nochmal
local DIG={}
for k,f in pairs(RAWDIG) do DIG[k]=function()
    local ok,why=f()
    if not ok and tostring(why):find("No tool",1,true) and w.equipTool(isTool) then ok,why=f() end
    return ok,why
end end
local function placeFill(kind)
    local slot=w.find(isFill)
    if not slot then st.noFill=true;return false end
    turtle.select(slot)
    local ok=PLACE[kind]()
    turtle.select(1)
    if ok then st.noFill=nil end
    return ok
end
local MOPT={dig=true,attack=true,canDig=function(n) return not stays(n) and not isTurtle(n) end}
-- Eine Zelle weiter (Nachbar von hier). false,"keep" = Block bleibt stehen.
local function stepInto(nk)
    local nx,ni,nz=unkey(nk)
    local ny=ylev(ni)
    local kind
    if ny>st.y then kind="up" elseif ny<st.y then kind="down"
    else
        local d=nx>st.x and 1 or nx<st.x and 3 or nz>st.z and 0 or 2
        local ok,why=w.face(d);if not ok then return false,why end
        kind="forward"
    end
    local e,b=INSPECT[kind]()
    local solid=false
    if e then
        if stays(b.name) then return false,"keep",b.name end
        if isLiquid(b.name) then
            -- Unterwasser/Lava: Quelle mit einem Block fuellen und wieder abbauen
            if DRAIN and placeFill(kind) then pcall(DIG[kind]);st.drained=(st.drained or 0)+1 end
        else solid=true end
    end
    local ok,why=w.move(kind,MOPT)
    if not ok then
        local e2,b2=INSPECT[kind]()
        if e2 and stays(b2.name) then return false,"keep",b2.name end
        return false,why
    end
    if solid then st.harvested=(st.harvested or 0)+1 end
    return true
end
local DIRS6={{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0},{0,-1,0}}
local function passable(k) return k==BASE or (INDEX[k]~=nil and not st.skip[k]) end
-- Kuerzester Weg durch die Form (nur Zellen der Form + Basis)
local function path(from,to)
    if from==to then return {} end
    local prev={[from]=from}
    local q,h={from},1
    while q[h] do
        local k=q[h];h=h+1
        local x,i,z=unkey(k)
        for _,d in ipairs(DIRS6) do
            local nx,ni,nz=x+d[1],i+d[2],z+d[3]
            if nx>=0 and nx<S and nz>=0 and nz<S and ni>=0 then
                local nk=key(nx,ni,nz)
                if not prev[nk] and passable(nk) then
                    prev[nk]=k
                    if nk==to then
                        local p={};local c=nk
                        while c~=from do table.insert(p,1,c);c=prev[c] end
                        return p
                    end
                    q[#q+1]=nk
                end
            end
        end
    end
end
local function here() return key(st.x,layer(st.y),st.z) end
local function travel(tk)
    for _=1,64 do
        if here()==tk then return true end
        local p=path(here(),tk)
        if not p then return false,"unreach" end
        local replan=false
        for _,nk in ipairs(p) do
            if run.mode~="off" and not w.active() then return false,"stopped" end
            local ok,why,name=stepInto(nk)
            if not ok then
                if why~="keep" then return false,why end
                if not st.skip[nk] then
                    st.skip[nk]=true
                    if name and keptOre(name) then st.kept=(st.kept or 0)+1 end
                end
                if nk==tk then return false,"keep" end
                replan=true;break
            end
        end
        if not replan then return here()==tk,"unreach" end
    end
    return false,"unreach"
end
-- Eine Aussenseite mit dem Wandblock verkleiden: fremden Block abbauen, Wandblock
-- setzen. Erze (geschont), Grundgestein, Kisten und Turtles bleiben stehen.
-- false = kein Wandblock mehr dabei.
local ATTACK={forward=turtle.attack,up=turtle.attackUp,down=turtle.attackDown}
local function lineFace(kind)
    for _=1,10 do
        local e,b=INSPECT[kind]()
        if e and b.name==WALL then return true end
        if e and not isLiquid(b.name) then
            if stays(b.name) or isTurtle(b.name) or isContainer(b.name) then return true end
            if not DIG[kind]() then return true end
            st.harvested=(st.harvested or 0)+1
        else
            local slot=w.find(isWall)
            if not slot then st.noWall=true;return false end
            turtle.select(slot)
            local ok=PLACE[kind]()
            turtle.select(1)
            if ok then st.lined=(st.lined or 0)+1;st.noWall=nil;return true end
            pcall(ATTACK[kind]);sleep(0.2)
        end
    end
    return true
end
-- Waende: Nachbarn ausserhalb der Form verkleiden bzw. zubauen.
-- false = Wandblock fehlt (Turtle holt Nachschub und macht hier weiter).
local function sealAround()
    if SEAL=="off" and not WALL then return true end
    local x,i,z=st.x,layer(st.y),st.z
    local function need(e,b)
        if not e then return SEAL=="all" end
        return SEAL~="off" and isLiquid(b.name)
    end
    local function face(kind,lineIt)
        if WALL and lineIt then return lineFace(kind) end
        local e,b=INSPECT[kind]()
        if need(e,b) and placeFill(kind) then st.sealed=(st.sealed or 0)+1 end
        return true
    end
    local function outside(nk) return nk~=BASE and (INDEX[nk]==nil or st.skip[nk]) end
    for _,v in ipairs({{"up",1},{"down",-1}}) do
        local nk=key(x,layer(st.y+v[2]),z)
        if layer(st.y+v[2])<0 then nk=-1 end
        if nk==-1 or outside(nk) then
            if not face(v[1],LINE[v[1]]) then return false end
        end
    end
    for d=0,3 do
        local nx,nz=x+W.DX[d],z+W.DZ[d]
        local nk=(nx>=0 and nz>=0) and key(nx,i,nz) or -1
        if nk==-1 or outside(nk) then
            if w.face(d) then
                if not face("forward",LINE.side) then return false end
            end
        end
    end
    return true
end
local function goHome()
    if w.isHome() then return w.face(0) end
    w.status("Rueckkehr","Faehrt zur Basis.")
    local ok,why=travel(BASE)
    if not ok then return false,"Rueckweg: "..tostring(why) end
    return w.face(0)
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    return goHome()
end
idleBase=function() return w.unload(keep) end
local function resupply()
    w.status("Rueckkehr","Abladen / Tanken an der Basis.")
    local ok,why=goHome();if not ok then return false,why end
    local ok2,title,detail=base();if not ok2 then w.status(title,detail);return false,title end
    return true
end
round=function()
    if st.done then st.done=nil;st.idx=1;st.skip={};w.save() end
    opts.readyText="START: Form ausheben | 1x: dasselbe (macht weiter, wo sie war)"
    if w.isHome() then
        local ok,title,detail=base();if not ok then w.status(title,detail);w.fail(title);return false end
    end
    while st.idx<=N do
        if not w.active() then w.save();return false end
        if w.freeSlots()<C.freeSlots then
            local ok,why=resupply();if not ok then w.fail(why);return false end
        end
        if fuel()<homeNeed()+40 then
            burnCoal(C.fuelTarget)
            if fuel()<homeNeed()+40 then
                local ok,why=resupply();if not ok then w.fail(why);return false end
            end
        end
        local k=ORDER[st.idx]
        run.scanned=st.idx-1
        if not st.skip[k] then
            local _,ki=unkey(k)
            w.status(st.noWall and "Wandblock fehlt" or st.noFill and "Kein Fuellmaterial" or "Graebt",
                st.idx<=ACCESS and "Zugang zur Form" or
                ("Ebene "..(ki+1).."/"..bh.." ("..(DOWN and "runter" or "hoch").."), Block "..st.idx.."/"..N))
            local ok,why=travel(k)
            if ok and not sealAround() then
                -- Wandblock alle: zur Basis, aus der Kiste OBEN nachladen, hier weitermachen
                local okr,whyr=resupply();if not okr then w.fail(whyr);return false end
                if wallCount()==0 then
                    w.status("Wandblock fehlt",WALL.." in die Kiste UEBER der Basis legen.")
                    w.fail("Wandblock fehlt: "..WALL);return false
                end
                st.idx=st.idx-1
            elseif ok then
            elseif why=="stopped" then w.save();return false
            elseif why=="keep" or why=="unreach" then st.skip[k]=true
            else w.fail(why);return false end
        end
        st.idx=st.idx+1;w.saveSoon()
    end
    run.scanned=N
    local okh,whyh=goHome();if not okh then w.fail(whyh);return false end
    local ok,title,detail=base();if not ok then w.status(title,detail) end
    st.done=true;w.save()
    opts.readyText="FERTIG: Form komplett. START = nochmal pruefen, N = neuer Auftrag"
    w.finish()
    return true
end
pcall(w.equipTool,isTool)
w.start("TOAST AUSHUB",SHAPE_NAMES[SHAPE].." "..(SHAPE=="room" and (C.width.."x"..C.length.."x"..C.height)
    or SHAPE=="cylinder" and ("D"..C.width.." x "..C.height) or ("D"..C.width))..(DOWN and " runter" or " hoch"))
