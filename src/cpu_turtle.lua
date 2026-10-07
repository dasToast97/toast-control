-- Toast Control: Redstone-CPU-Bau.
-- Baut nach dem Bauplan /toast/cpu_plan.lua eine Mini-CPU aus reinem Vanilla-Redstone:
--   4 Bit, Akkumulator, 8 Befehle Programmspeicher, Eingaben X/Y per Knopf (+1),
--   7-Segment-Anzeige 0..15, Knoepfe Takt/Reset, Hebel Lauf.
-- Ablauf: 1) Flaeche begradigen (Boden fest, darueber 8 Bloecke frei)
--         2) Lage fuer Lage bauen (Turtle setzt von oben)
--         3) Programm in den Speicher (Repeater da = 1)
--         Spaeter neues Programm: nur der Speicher wird umgebaut.
-- Turtle-Koordinaten: Basis (0,0,0), Bauflaeche beginnt 2 Bloecke vor der Turtle,
-- x laeuft nach LINKS (gespiegelt, damit die Anzeige richtig herum ist).
-- Kisten: HINTER der Turtle = Material, UNTER der Turtle = Ausgabe (Abraum).
local common=dofile("/toast/toast_common.lua")
local cfg=common.load()
local C=cfg.cpu
local W=dofile("/toast/toast_worker.lua")
local okp,PLAN=pcall(dofile,"/toast/cpu_plan.lua")
if not okp or type(PLAN)~="table" then error("Bauplan /toast/cpu_plan.lua fehlt - neu installieren.",0) end
local OZ=2                       -- Abstand Basis -> Bauflaeche
local PW,PD=PLAN.w,PLAN.d
local SAFE=9                     -- Reisehoehe ueber allem
local CLEAR=C.clear~=false

-- ===== Bloecke =====
local FILL={}
for _,n in ipairs({"cobblestone","cobbled_deepslate","stone","deepslate","dirt","netherrack","andesite","diorite",
    "granite","tuff","blackstone","smooth_basalt","end_stone","stone_bricks","sandstone","polished_andesite",
    "polished_diorite","polished_granite","mossy_cobblestone"}) do FILL["minecraft:"..n]=true end
local FLOOROK={["minecraft:grass_block"]=true,["minecraft:podzol"]=true,["minecraft:mycelium"]=true,
    ["minecraft:coarse_dirt"]=true,["minecraft:rooted_dirt"]=true,["minecraft:sand"]=true,["minecraft:gravel"]=true,
    ["minecraft:red_sand"]=true,["minecraft:clay"]=true,["minecraft:terracotta"]=true,["minecraft:obsidian"]=true,
    ["minecraft:calcite"]=true,["minecraft:basalt"]=true}
local function isFill(n) return FILL[n]==true end
local ITEM={s="fill",d="minecraft:redstone",t="minecraft:redstone_torch",l="minecraft:redstone_lamp",
    b="button",v="minecraft:lever",N="minecraft:repeater",E="minecraft:repeater",S="minecraft:repeater",W="minecraft:repeater"}
local KIND={fill="Bruchstein/Stein",["minecraft:redstone"]="Redstone",["minecraft:redstone_torch"]="Redstone-Fackeln",
    ["minecraft:redstone_lamp"]="Redstone-Lampen",button="Steinknoepfe",["minecraft:lever"]="Hebel",["minecraft:repeater"]="Repeater"}
local function matcher(item)
    if item=="fill" then return isFill end
    if item=="button" then return function(n) return n:find("_button",1,true)~=nil end end
    return function(n) return n==item end
end
-- was im Spiel an der Stelle stehen muss (Name)
local function blockOk(code,b)
    if not b then return false end
    local n=b.name
    if code=="s" then return isFill(n) or FLOOROK[n] or n=="minecraft:dirt" end
    if code=="d" then return n=="minecraft:redstone_wire" end
    if code=="t" then return n=="minecraft:redstone_torch" end
    if code=="l" then return n=="minecraft:redstone_lamp" end
    if code=="b" then return n:find("_button",1,true)~=nil end
    if code=="v" then return n=="minecraft:lever" end
    return n=="minecraft:repeater"
end
local function isContainer(n) return n:find("chest",1,true)~=nil or n:find("barrel",1,true)~=nil or n:find("shulker",1,true)~=nil end
local function isTurtle(n) return n:find("computercraft:turtle",1,true)~=nil end
local function isTool(n) return n:find("_pickaxe",1,true)~=nil end
local function isLiquid(n) return n=="minecraft:water" or n=="minecraft:lava" or n:find("flowing_",1,true)~=nil end
local BADFLOOR={"_leaves","glass","ice","snow","_slab","_stairs","fence","_wall","carpet","_door","trapdoor","bed",
    "torch","sign","flower","sapling","mushroom","grass","fern","vine","water","lava","pane","bars","web"}
local function floorGood(b)
    if not b then return false end
    local n=b.name
    if isFill(n) or FLOOROK[n] then return true end
    for _,p in ipairs(BADFLOOR) do if n:find(p,1,true) then return false end end
    return not isContainer(n)
end

-- ===== Programm (Assembler) =====
-- Befehle: LDI n, LDX, LDY, ADDI n, ADDX, ADDY, SUBI n, SUBX, SUBY, OUT, JMP n, JZ n, NOP
local function encodeOne(op,arg)
    local f={IMM=(arg or 0)%16,SELX=0,SELY=0,SELI=0,USEA=0,SUB=0,WRA=0,OUT=0,JMP=0,JZ=0}
    local src
    if op=="LDI" or op=="LDX" or op=="LDY" then f.WRA=1;src=op:sub(3,3)
    elseif op=="ADDI" or op=="ADDX" or op=="ADDY" or op=="SUBI" or op=="SUBX" or op=="SUBY" then
        f.WRA=1;f.USEA=1;f.SUB=op:sub(1,3)=="SUB" and 1 or 0;src=op:sub(4,4)
    elseif op=="OUT" then f.OUT=1
    elseif op=="JMP" then f.JMP=1
    elseif op=="JZ" then f.JMP=1;f.JZ=1
    elseif op~="NOP" then return nil,"Unbekannter Befehl: "..op end
    if src=="I" then f.SELI=1 elseif src=="X" then f.SELX=1 elseif src=="Y" then f.SELY=1 end
    return f
end
local function assemble(text)
    local prog={}
    for line in (tostring(text or "").."\n"):gmatch("([^;\n]*)[;\n]") do
        line=line:gsub("%-%-.*$",""):gsub("^%s+",""):gsub("%s+$","")
        if line~="" then
            local ops,arg=line:match("^(%a+)%s*(%-?%d*)$")
            if not ops then return nil,"Zeile unklar: "..line end
            arg=tonumber(arg)
            local f
            for part in ops:upper():gmatch("[^%+]+") do
                local g,why=encodeOne(part,arg);if not g then return nil,why end
                if not f then f=g else for k,v in pairs(g) do if k~="IMM" then f[k]=math.max(f[k],v) end end end
            end
            prog[#prog+1]=f
        end
    end
    if #prog>8 then return nil,"Hoechstens 8 Befehle (sind "..#prog..")" end
    while #prog<8 do prog[#prog+1]=encodeOne("NOP") end
    return prog
end
local function tapsFor(prog)
    -- Spalten wie im Bauplan (alle so gepolt, wie die Logik sie braucht)
    local taps={}
    for w,f in ipairs(prog) do
        local val={}
        for k=0,3 do val["nIMM"..k]=1-math.floor(f.IMM/2^k)%2 end
        val.nSELX=1-f.SELX;val.nSELY=1-f.SELY;val.nSELI=1-f.SELI;val.nUSEA=1-f.USEA
        val.SUB=f.SUB;val.nSUB=1-f.SUB;val.nWRA=1-f.WRA;val.nOUT=1-f.OUT;val.nJMP=1-f.JMP;val.nJZ=1-f.JZ
        for c,name in ipairs(PLAN.cols) do taps[(w-1)..","..(c-1)]=val[name]==1 end
    end
    return taps
end
local PROG,PROGERR=assemble(C.program)
if not PROG then error("CPU-Programm: "..tostring(PROGERR),0) end
local TAPS=tapsFor(PROG)
local PROGKEY=""
for w=0,7 do for c=0,#PLAN.cols-1 do PROGKEY=PROGKEY..(TAPS[w..","..c] and "1" or "0") end end

-- ===== Plan entpacken =====
-- CELLS[y] = Liste {x,z,code} in Schlangenreihenfolge (Reihe fuer Reihe)
local TAPAT={}                    -- "x,z" -> {r,c,f}
for _,p in ipairs(PLAN.prog) do TAPAT[p[3]..","..p[4]]={r=p[1],c=p[2],f=p[5]} end
local function decodeRow(s)
    local out={};local x=0
    for num,ch in s:gmatch("(%d*)(%D)") do
        local n=tonumber(num) or 1
        if ch~="." then for k=0,n-1 do out[#out+1]={x+k,ch} end end
        x=x+n
    end
    return out
end
local CELLS={}
local NCELLS=0
local NEED={}
for y=1,7 do
    local rows={}
    for z,s in pairs(PLAN.layers[y] or {}) do rows[#rows+1]=z end
    table.sort(rows)
    -- Programm-Abgriffe: Stuetze (y1) und Repeater (y2)
    local extra={}
    if y==1 or y==2 then
        for _,p in ipairs(PLAN.prog) do
            if TAPS[p[1]..","..p[2]] then
                extra[p[4]]=extra[p[4]] or {}
                table.insert(extra[p[4]],{p[3],y==1 and "s" or p[5]})
            end
        end
        for z in pairs(extra) do if not PLAN.layers[y][z] then rows[#rows+1]=z end end
        table.sort(rows)
    end
    local list={}
    for i,z in ipairs(rows) do
        local cells=PLAN.layers[y][z] and decodeRow(PLAN.layers[y][z]) or {}
        for _,e in ipairs(extra[z] or {}) do cells[#cells+1]=e end
        table.sort(cells,function(a,b) return a[1]<b[1] end)
        if #list%2==1 or i%2==0 then
            -- jede zweite Reihe rueckwaerts (Schlange)
        end
        local rev=(i%2==0)
        local a,b,s=1,#cells,1
        if rev then a,b,s=#cells,1,-1 end
        for k=a,b,s do
            local c=cells[k]
            list[#list+1]={c[1],z,c[2]}
            local it=ITEM[c[2]]
            NEED[it]=(NEED[it] or 0)+1
        end
    end
    CELLS[y]=list
    NCELLS=NCELLS+#list
end
local CLEARN=CLEAR and 3*PW*PD or PW*PD
local NSTEPS=CLEARN+NCELLS
local LAYOUT="cpu:"..(PLAN.version or 1)..":"..(CLEAR and "c" or "n")

-- Schritt i -> Beschreibung
local function stepAt(i)
    if i<=CLEARN then
        local k=i-1
        local per=PW*PD
        local pass=math.floor(k/per)
        local r=k%per
        local z=math.floor(r/PW)
        local x=r%PW
        if z%2==1 then x=PW-1-x end
        if pass%2==1 then z=PD-1-z end
        return {t="clear",pass=pass,x=x,z=z}
    end
    local j=i-CLEARN
    for y=1,7 do
        local n=#CELLS[y]
        if j<=n then local c=CELLS[y][j];return {t="cell",y=y,x=c[1],z=c[2],code=c[3]} end
        j=j-n
    end
end

local w,round,idleHome,idleBase
local opts
opts={job="cpu",cfg=cfg,section=C,stateFile="/toast_cpu_state",args={...},cells=NSTEPS,layout=LAYOUT,mirror=true,
    tools=isTool,noTool="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen",
    interval=0,readyText="START: Redstone-CPU bauen (macht weiter, wo sie war)",
    extra=function() local s=w and w.st or {}
        local need={}
        for it,n in pairs(NEED) do need[#need+1]=(KIND[it] or it)..": "..n end
        table.sort(need)
        return {placed=s.placed or 0,done=s.done,phase=s.phase,missing=s.missing,w=PW,d=PD,
            steps=NSTEPS,parts=NCELLS,program=C.program,progOk=s.progKey==PROGKEY,need=table.concat(need,", ")} end,
    round=function() return round() end,
    idleHome=function() return idleHome() end,
    idleBase=function() return idleBase() end}
w=W.new(opts)
local st,run=w.st,w.run
if st.cpuLayout~=LAYOUT then st.cpuLayout=LAYOUT;st.idx=1;st.done=nil;st.progKey=nil;w.save() end
st.idx=st.idx or 1
if st.done then run.scanned=NSTEPS end

-- ===== Bewegung =====
local RAWDIG={forward=turtle.dig,up=turtle.digUp,down=turtle.digDown}
local DIG={}
for k,f in pairs(RAWDIG) do DIG[k]=function()
    local ok,why=f()
    if not ok and tostring(why):find("No tool",1,true) and w.equipTool(isTool) then ok,why=f() end
    return ok,why
end end
local MOPT={dig=true,attack=true,canDig=function(n) return not (isContainer(n) or isTurtle(n)) end}
local function fuel() local f=turtle.getFuelLevel();if f=="unlimited" then return math.huge end;return f end
local clearing=false            -- beim Begradigen: Wasser/Lava vor sich zuschuetten und abbauen
local function line(axis,v)
    while (axis=="x" and st.x or st.z)~=v do
        local cur=axis=="x" and st.x or st.z
        local d=axis=="x" and (v>cur and 1 or 3) or (v>cur and 0 or 2)
        local ok,why=w.face(d);if not ok then return false,why end
        if clearing then
            local e,b=turtle.inspect()
            if e and isLiquid(b.name) then
                local slot=w.find(isFill)
                if slot then turtle.select(slot);turtle.place();turtle.select(1);DIG.forward() end
            end
        end
        ok,why=w.move("forward",MOPT);if not ok then return false,why end
    end
    return true
end
local function vert(y)
    while st.y~=y do
        local ok,why=w.move(st.y<y and "up" or "down",MOPT);if not ok then return false,why end
    end
    return true
end
-- in der Flaeche? (lokale Koordinaten)
local function inArea(x,z) return x>=0 and x<PW and z>=OZ and z<OZ+PD end
-- Zum Ziel: kurze Wege auf gleicher Hoehe direkt, sonst ueber die Reisehoehe
local function goTo(x,y,z)
    if st.x==x and st.y==y and st.z==z then return true end
    local near=st.y==y and math.abs(st.x-x)+math.abs(st.z-z)<=PW+PD
    if near and inArea(st.x,st.z) and inArea(x,z) then
        local ok,why=line("z",z);if not ok then return false,why end
        return line("x",x)
    end
    local ok,why=vert(SAFE);if not ok then return false,why end
    ok,why=line("z",z);if not ok then return false,why end
    ok,why=line("x",x);if not ok then return false,why end
    return vert(y)
end
local function homeNeed() return math.abs(st.x)+math.abs(st.z)+2*SAFE+20 end

-- ===== Material =====
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
    for it in pairs(NEED) do if it~="fill" and matcher(it)(name) then return 4096 end end
    if isFill(name) then return 256 end
    if W.FUELS[name] then return 64 end
    return 0
end
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
        if not match(it.name) then turtle.dropDown();if not inv then break end
        else got=got+it.count end
    end
    turtle.select(1)
    return got
end
local function have(match) return w.count(match) end
-- Bedarf der naechsten Schritte (fuer das Nachladen)
local function upcoming(n)
    local need={}
    local i=st.idx
    local stop=math.min(NSTEPS,i+n)
    while i<=stop do
        local s=stepAt(i)
        if s.t=="cell" then local it=ITEM[s.code];need[it]=(need[it] or 0)+1
        elseif s.t=="clear" and s.pass==0 then need.fill=(need.fill or 0)+0.2 end
        i=i+1
    end
    return need
end
local function fuelGoal()
    return math.min(turtle.getFuelLimit and turtle.getFuelLimit() or 20000,math.max(C.fuelTarget or 2000,(NSTEPS-st.idx)*2+400))
end
local function base()
    local ok,title,detail=w.unload(keep)
    if not ok then return false,title,detail end
    local okf,why=w.face(2);if not okf then return false,"Drehen",why end
    if not w.container(turtle.inspect) then w.face(0);return false,"Materialkiste fehlt","Kiste HINTER die Turtle stellen (Redstone, Repeater, Fackeln, Lampen, Bruchstein, Kohle)." end
    if fuel()<fuelGoal() and have(function(n) return W.FUELS[n]~=nil end)<16 then
        fetch(function(n) return W.FUELS[n]~=nil end,64);burn(fuelGoal())
    end
    -- Fuer die naechsten ~600 Schritte laden, Platz fuer Abraum lassen
    local need=upcoming(600)
    if st.done then need={["minecraft:repeater"]=#PLAN.prog,fill=#PLAN.prog} end
    local order={}
    for it,n in pairs(need) do order[#order+1]={it,math.ceil(n)} end
    table.sort(order,function(a,b) return a[2]>b[2] end)
    st.missing=nil
    for _,o in ipairs(order) do
        local it,n=o[1],o[2]
        local m=matcher(it)
        local want=math.min(n,64*4)-have(m)
        if want>0 and w.freeSlots()>(CLEAR and 3 or 1) then
            fetch(m,math.min(want,64*math.max(1,w.freeSlots()-(CLEAR and 3 or 1))))
        end
    end
    w.face(0)
    burn(fuelGoal())
    if fuel()<math.min(fuelGoal(),homeNeed()+PW+PD+200) then
        return false,"Treibstoff fehlt","Kohle in die Kiste HINTER der Turtle legen."
    end
    w.save()
    return true
end
local function goHome()
    if w.isHome() then return w.face(0) end
    w.status("Rueckkehr","Faehrt zur Basis (Nachschub).")
    local ok,why=vert(SAFE);if not ok then return false,"Rueckweg: "..tostring(why) end
    ok,why=line("x",0);if ok then ok,why=line("z",0) end
    if ok then ok,why=vert(0) end
    if not ok then return false,"Rueckweg: "..tostring(why) end
    return w.face(0)
end
local function resupply(item)
    local ok,why=goHome();if not ok then return false,why end
    while true do
        if not w.active() then return false,"stopped" end
        local okb,title,detail=base()
        if okb and (not item or have(matcher(item))>0) then st.missing=nil;return true end
        if okb then
            local n=0
            for i=st.idx,NSTEPS do local s=stepAt(i);if s.t=="cell" and ITEM[s.code]==item then n=n+1 end;if i-st.idx>20000 then break end end
            title=(KIND[item] or item).." fehlen";detail=(KIND[item] or item).." in die Kiste HINTER der Turtle legen (noch ca. "..n.." gebraucht)."
        end
        st.missing=title;w.status(title,detail)
        for _=1,20 do if not w.active() then return false,"stopped" end;sleep(0.5) end
    end
end

-- ===== Arbeit =====
local function clearDown()
    for _=1,8 do
        local e,b=turtle.inspectDown()
        if not e then return true end
        if isContainer(b.name) or isTurtle(b.name) then return true end
        if isLiquid(b.name) then
            local slot=w.find(isFill);if not slot then return false,"fill" end
            turtle.select(slot);turtle.placeDown();turtle.select(1)
        end
        DIG.down()
    end
    return not turtle.detectDown()
end
local function clearUp()
    for _=1,8 do
        local e,b=turtle.inspectUp()
        if not e then return true end
        if isContainer(b.name) or isTurtle(b.name) then return true end
        if isLiquid(b.name) then
            local slot=w.find(isFill);if not slot then return true end
            turtle.select(slot);turtle.placeUp();turtle.select(1)
        end
        if not DIG.up() then return true end
    end
    return true
end
local function placeFillDown()
    local slot=w.find(isFill);if not slot then return false,"item","fill" end
    turtle.select(slot);local ok=turtle.placeDown();turtle.select(1)
    if not ok then return false,"Boden nicht setzbar" end
    return true
end
local function doClear(s)
    -- Turtle steht auf Hoehe h: raeumt h+1 (und h-1); bei h=0 wird der Boden (h-1) geprueft
    clearUp()
    if s.pass==0 then
        local e,b=turtle.inspectDown()
        if e and floorGood(b) then return true end
        if e and not isLiquid(b.name) then
            if isContainer(b.name) or isTurtle(b.name) then return false,"Kiste/Turtle im Bauplatz" end
            DIG.down()
        end
        return placeFillDown()
    end
    local ok,why=clearDown();if not ok then return false,why end
    return true
end
local FACEDIR={S=0,E=1,N=2,W=3}
local function doCell(s)
    local e,b=turtle.inspectDown()
    if e and blockOk(s.code,b) then return true end
    if e then
        if isContainer(b.name) or isTurtle(b.name) then return false,"Kiste/Turtle im Bauplatz" end
        local ok,why=clearDown();if not ok then return false,why end
    end
    if FACEDIR[s.code] then
        -- Repeater: Ausgang zeigt dorthin, wohin die Turtle beim Setzen schaut
        local ok,why=w.face(FACEDIR[s.code]);if not ok then return false,why end
    end
    local it=ITEM[s.code]
    local slot=w.find(matcher(it))
    if not slot then return false,"item",it end
    turtle.select(slot);local ok,why=turtle.placeDown();turtle.select(1)
    if not ok then return false,"Setzen fehlgeschlagen: "..tostring(why) end
    st.placed=(st.placed or 0)+1
    return true
end
local function phaseOf(s)
    if s.t=="clear" then return "Begradigen "..(s.pass+1).."/"..(CLEAR and 3 or 1) end
    return "Lage "..s.y.."/7"
end

-- Programm-ROM von oben umbauen (fertige CPU, neues Programm)
local function reprogram()
    local list={}
    for _,p in ipairs(PLAN.prog) do
        list[#list+1]={x=p[3],z=p[4]+OZ,f=p[5],tap=TAPS[p[1]..","..p[2]]}
    end
    table.sort(list,function(a,b) if a.z~=b.z then return a.z<b.z end;return a.x<b.x end)
    st.rpi=st.rpi or 1
    for i=st.rpi,#list do
        if not w.active() then w.save();return false end
        local c=list[i]
        st.rpi=i
        w.status("Programmiert","Speicher "..i.."/"..#list)
        -- Turtle ueber B (lokal y2) auf y3. Ueber dem Speicher ist y3 frei, ausserhalb nicht:
        -- in derselben Zeile direkt, sonst ueber die Reisehoehe
        local ok,why
        if st.y==3 and st.z==c.z then ok,why=line("x",c.x)
        else
            ok,why=vert(SAFE)
            if ok then ok,why=line("z",c.z) end
            if ok then ok,why=line("x",c.x) end
            if ok then ok,why=vert(3) end
        end
        if not ok then return false,why end
        DIG.down()                                   -- B weg
        ok,why=w.move("down",MOPT);if not ok then return false,why end    -- in B-Feld (y2)
        local e,b=turtle.inspectDown()
        local isTap=e and b.name=="minecraft:repeater"
        if c.tap~=(isTap==true) then
            if c.tap then
                -- Stuetze (y0) + Repeater (y1)
                ok,why=w.move("down",MOPT);if not ok then return false,why end
                local e0=turtle.detectDown()
                if not e0 then local slot=w.find(isFill);if not slot then return false,"item","fill" end;turtle.select(slot);turtle.placeDown();turtle.select(1) end
                ok,why=w.move("up",MOPT);if not ok then return false,why end
                ok,why=w.face(FACEDIR[c.f]);if not ok then return false,why end
                local slot=w.find(matcher("minecraft:repeater"));if not slot then return false,"item","minecraft:repeater" end
                turtle.select(slot);turtle.placeDown();turtle.select(1)
            else
                DIG.down()
                ok,why=w.move("down",MOPT);if not ok then return false,why end
                DIG.down()
                ok,why=w.move("up",MOPT);if not ok then return false,why end
            end
        end
        ok,why=w.move("up",MOPT);if not ok then return false,why end
        local slot=w.find(isFill);if not slot then return false,"item","fill" end
        turtle.select(slot);turtle.placeDown();turtle.select(1)
        w.saveSoon()
    end
    st.rpi=nil
    return true
end

round=function()
    if st.done then
        if st.progKey==PROGKEY then
            w.status("Fertig","Redstone-CPU steht. Neues Programm: in der Config aendern, dann START.")
            w.finish();return true
        end
        -- nur Programm neu
        if w.isHome() then local ok=resupply(nil);if not ok then return false end end
        if w.count(matcher("minecraft:repeater"))<4 or w.count(isFill)<16 then
            local ok=resupply("minecraft:repeater");if not ok then return false end
        end
        st.phase="Programmieren"
        local ok,why,it=reprogram()
        if ok==false and why then
            if why=="item" then
                local okr=goHome() and resupply(it);if not okr then return false end;return round()
            end
            if why~="stopped" then w.fail(why) end
            return false
        end
        if ok then
            st.progKey=PROGKEY;w.save()
            local okh=goHome();if not okh then w.fail("Rueckweg");return false end
            w.status("Fertig","Neues Programm ist drin.");w.finish()
            return true
        end
        return false
    end
    opts.readyText="START: Redstone-CPU bauen (macht weiter, wo sie war)"
    if w.isHome() then local ok=resupply(nil);if not ok then return false end end
    while st.idx<=NSTEPS do
        if not w.active() then w.save();return false end
        local s=stepAt(st.idx)
        run.scanned=st.idx-1
        st.phase=phaseOf(s)
        if w.freeSlots()==0 or fuel()<homeNeed()+40 then
            local ok,why=resupply(nil);if not ok then if why~="stopped" then w.fail(why) end;return false end
        end
        w.status("Baut",st.phase.." - "..st.idx.."/"..NSTEPS)
        local ok,why,it
        clearing=s.t=="clear"
        if s.t=="clear" then
            local h=s.pass*3
            if not CLEAR then h=0 end
            ok,why=goTo(s.x,h,s.z+OZ)
            if ok then ok,why=doClear(s) end
            if why=="fill" then why,it="item","fill" end
        else
            ok,why=goTo(s.x,s.y,s.z+OZ)
            if ok then ok,why,it=doCell(s) end
        end
        if ok then
            st.idx=st.idx+1;w.saveSoon()
        elseif why=="stopped" then w.save();return false
        elseif why=="item" then
            local okr,whyr=resupply(it)
            if not okr then if whyr~="stopped" then w.fail(whyr) end;return false end
        else w.fail(why);return false end
    end
    run.scanned=NSTEPS
    local okh,whyh=goHome();if not okh then w.fail(whyh);return false end
    w.unload(keep)
    st.done=true;st.progKey=PROGKEY;st.phase="Fertig";w.save()
    opts.readyText="FERTIG: Redstone-CPU steht. Programm aendern -> START baut nur den Speicher um"
    w.status("Fertig","Redstone-CPU steht. Hebel 'Lauf' an oder 'Takt' druecken.")
    w.finish()
    return true
end
idleHome=function()
    if w.isHome() and st.dir==0 then return true end
    return goHome()
end
idleBase=function() return w.unload(keep) end
pcall(w.equipTool,isTool)
w.start("TOAST REDSTONE-CPU",PW.."x"..PD.." Bloecke, "..NCELLS.." Teile")
