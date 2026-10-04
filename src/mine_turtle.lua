-- Toast Mining 2.6: Strip-Mining mit parallelen Gaengen, mit eigener Basis.
-- Fahrweg 2.2: Turtle baut oben/unten beim Vorwaertsfahren mit ab (1 Fuel je Block),
-- Gaenge werden in Schlangenlinie verbunden, Heimfahrt nur wenn noetig.
-- Neu: Positions-Wiederherstellung nach Absturz, RESET, Auto-Retry, Mob-Blockaden.
local common=dofile("/mine_common.lua")
local cfg=common.load();assert(cfg.role=="turtle","Mining Turtle erforderlich.")
-- CCChunkloader: Chunkloader bleibt angebaut, Spitzhacke <-> Modem werden getauscht.
local TC=dofile("/toast_common.lua")
local CL=TC.chunkConfig(cfg.chunkload)
local GEAR
local lastRadio=os.clock()    -- letztes Funkfenster (Chunkloader)
if CL.enabled then
    local why
    GEAR,why=TC.gear(CL,{['minecraft:diamond_pickaxe']=true,['minecraft:netherite_pickaxe']=true})
    assert(GEAR,why)
    assert(GEAR.radio(),"Chunkloader: Funk-/Endermodem ins Turtle-Inventar legen.")
end
common.modem()
local R=cfg.recovery or {autoRetry=3,retryDelay=30,moveRetries=8}
local C,FILE,args=cfg.mine,"/toast_mining_state",{...}
local H,L,G=C.height,C.length,C.gap
assert(C.side==nil or C.side=="right" or C.side=="left","mine.side: right oder left.")
local MIRROR=C.side=="left"
local width=(C.tunnels-1)*(G+1)+1
-- Schichten zu je 3 Bloecken: Turtle faehrt in der Mitte und baut oben/unten mit ab.
-- Schicht p deckt Reihen 3p..3p+2 ab (Reihe r = y -r). Letzte Schicht ggf. 1-2 hoch.
local P=math.ceil(H/3)
local PASS={}
for p=0,P-1 do
    local r0=3*p;local rem=math.min(3,H-r0)
    if rem==3 then PASS[p]={y=-(r0+1),up=true,down=true}
    else PASS[p]={y=-r0,up=rem==2,down=false} end
end
local WALK=PASS[0].y                    -- Laufebene zur Basis (unterste Schicht)
local area=P*L                          -- Schritte je Gang
local cells=area*C.tunnels
local tag=H<=3 and "strip2:" or "strip3:"   -- bis Hoehe 3 identisch zu 2.2
local layout=tag..L..":"..H..":"..C.tunnels..":"..G..(MIRROR and ":L" or "")
-- Schritt i -> Position (x,y,z) und ob oben/unten mit abgebaut wird.
-- Schlangenlinie in z UND in der Hoehe: Gang 1 Schichten unten->oben,
-- Gang 2 oben->unten usw.; jede Schicht startet dort, wo die vorige endete.
-- ===== Seitlich mitabbauen (nur Abstand 0) =====
-- Fahrspuren im Plus-Muster: jede Spur raeumt pro Schritt Mitte, oben, unten,
-- links, rechts (Drehen kostet kein Fuel). Spuren bei (x+2r) mod 5 = c fuellen
-- die Flaeche lueckenlos; Luecken am Rand bekommen Zusatzspuren.
assert(C.sideDig==nil or type(C.sideDig)=="boolean","mine.sideDig: true oder false.")
local SIDE=C.sideDig==true and G==0
local W=C.tunnels
local LANES,COVERMIN
local function buildLanes()
    local bestList
    for c=0,4 do
        local lanes,cov={},{}
        local function key(x,r) return x*H+r end
        local function add(x,r)
            lanes[#lanes+1]={x=x,r=r}
            for _,d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                local ax,ar=x+d[1],r+d[2]
                if ax>=0 and ax<W and ar>=0 and ar<H then cov[key(ax,ar)]=true end
            end
        end
        for x=0,W-1 do for r=0,H-1 do if (x+2*r)%5==c then add(x,r) end end end
        for x=0,W-1 do for r=0,H-1 do
            if not cov[key(x,r)] then
                -- Zusatzspur dort, wo sie die meisten offenen Felder abdeckt
                local bx,br,bn=x,r,-1
                for _,d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                    local lx,lr=x+d[1],r+d[2]
                    if lx>=0 and lx<W and lr>=0 and lr<H then
                        local n=0
                        for _,e in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                            local ax,ar=lx+e[1],lr+e[2]
                            if ax>=0 and ax<W and ar>=0 and ar<H and not cov[key(ax,ar)] then n=n+1 end
                        end
                        if n>bn then bx,br,bn=lx,lr,n end
                    end
                end
                add(bx,br)
            end
        end end
        if not bestList or #lanes<#bestList then bestList=lanes end
    end
    -- Reihenfolge: Start an der Spur, die die Ecke an der Basis abdeckt,
    -- dann immer zur naechstgelegenen offenen Spur (kurze Wechsel am Ende).
    local left={}
    for i,l in ipairs(bestList) do left[i]=l end
    local order={}
    local cx,cr=0,0
    while #left>0 do
        local bi,bd
        for i,l in ipairs(left) do
            local d=math.abs(l.x-cx)+math.abs(l.r-cr)
            if not bd or d<bd or (d==bd and (l.r<left[bi].r or (l.r==left[bi].r and l.x<left[bi].x))) then bi,bd=i,d end
        end
        local l=table.remove(left,bi);order[#order+1]=l;cx,cr=l.x,l.r
    end
    return order
end
local sideNote
if SIDE then
    LANES=buildLanes()
    if #LANES>=W*P then
        SIDE=false
        sideNote="Seitlich mitabbauen bringt bei diesen Massen nichts - normales Verfahren."
    else
        COVERMIN={}
        for li,l in ipairs(LANES) do
            for _,d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
                local ax,ar=l.x+d[1],l.r+d[2]
                if ax>=0 and ax<W and ar>=0 and ar<H then
                    local k=ax*H+ar
                    if not COVERMIN[k] or li-1<COVERMIN[k] then COVERMIN[k]=li-1 end
                end
            end
        end
        area=L;cells=#LANES*L
        layout="block5:"..L..":"..H..":"..W..(MIRROR and ":L" or "")
        sideNote="Seitlich mitabbauen: "..#LANES.." Spuren statt "..(W*P)
    end
end
local function step(i)
    if SIDE then
        local li=math.floor((i-1)/L);local j=(i-1)%L
        local l=LANES[li+1]
        local z=li%2==0 and j+1 or L-j
        return l.x,-l.r,z,l.r+1<H,l.r-1>=0,l.x-1>=0,l.x+1<W
    end
    local t=math.floor((i-1)/area);local k=(i-1)%area;local x=t*(G+1)
    local pi=math.floor(k/L);local j=k%L
    local p=t%2==0 and pi or P-1-pi
    local g=t*P+pi
    local z=g%2==0 and j+1 or L-j
    local q=PASS[p]
    return x,q.y,z,q.up,q.down
end
local st={x=0,y=0,z=0,dir=0,next=1,total=0,harvested=0,commandSerial=0,layout=layout}
local oldLayout="strip:"..L..":"..H..":"..C.tunnels..":"..G
local oldLayout22="strip2:"..L..":"..H..":"..C.tunnels..":"..G..(MIRROR and ":L" or "")
local function readTable(path)
    if not fs.exists(path) then return nil end
    local f=fs.open(path,"r");if not f then return nil end
    local ok,s=pcall(textutils.unserialize,f.readAll());f.close()
    if ok and type(s)=="table" and type(s.x)=="number" and type(s.y)=="number" and type(s.z)=="number"
        and type(s.dir)=="number" and type(s.next)=="number" then return s end
end
-- Halb geschriebene .tmp-Datei ignorieren und die letzte gute Datei nehmen.
local saved=readTable(FILE..".tmp") or readTable(FILE)
if saved then st=saved
elseif fs.exists(FILE) or fs.exists(FILE..".tmp") then
    error("Mining-Zustand beschaedigt. Turtle an Basis setzen: toast.lua --dock --new",0)
end
local function homePosition() return st.x==0 and st.y==0 and st.z==0 end
local function save()
    local f=assert(fs.open(FILE..".tmp","w"));f.write(textutils.serialize(st));f.close()
    if fs.exists(FILE) then fs.delete(FILE) end;fs.move(FILE..".tmp",FILE)
end
local function clearPending() st.pending,st.after,st.pendingFuel,st.pendingDrain=nil,nil,nil,nil end
-- Unterbrochene Bewegung ueber den Fuelstand aufloesen:
-- Fuel unveraendert = Schritt nicht ausgefuehrt, Fuel -1 = Schritt ausgefuehrt.
local function resolvePending()
    if not st.pending then return true end
    local fuel=turtle.getFuelLevel()
    if st.pending~="turn" and type(fuel)=="number" and type(st.pendingFuel)=="number" and type(st.after)=="table" then
        if fuel==st.pendingFuel then clearPending();save();return true end
        -- Chunkloader zieht nebenbei Fuel ab: dann ist "1 weniger" nicht eindeutig.
        -- Pruefen: Vor dem Schritt war das Zielfeld frei geraeumt. Steht jetzt in
        -- Fahrtrichtung massiver Block, steht die Turtle sicher schon auf dem Zielfeld.
        if st.pendingDrain then
            if fuel<st.pendingFuel then
                local probe=({forward=turtle.inspect,up=turtle.inspectUp,down=turtle.inspectDown})[st.pending]
                local okp,b=false,nil
                if probe then okp,b=probe() end
                local solid=okp and type(b)=="table" and type(b.name)=="string"
                    and not b.name:find("water",1,true) and not b.name:find("lava",1,true)
                if solid then
                    local a=st.after;st.x,st.y,st.z,st.dir=a.x,a.y,a.z,a.dir;clearPending();save();return true
                end
            end
            return false
        end
        if fuel==st.pendingFuel-1 then
            local a=st.after;st.x,st.y,st.z,st.dir=a.x,a.y,a.z,a.dir;clearPending();save();return true
        end
    end
    return false
end
local resolvedAtStart=st.pending~=nil and resolvePending()
for _,arg in ipairs(args) do
    if arg=="--dock" then
        print("An die ORIGINALBASIS setzen und in die Mine schauen.")
        write("DOCK bestaetigen: ");assert(read()=="DOCK","Abgebrochen.")
        st.x,st.y,st.z,st.dir=0,0,0,0;clearPending();st.lastMode=nil
    elseif arg=="--new" then
        assert(homePosition() and not st.pending,"Neuer Auftrag nur an der Basis; ggf. zuerst --dock.")
        write("Neue Gaenge an dieser Basis? NEU eingeben: ");assert(read()=="NEU","Abgebrochen.")
        st.next,st.layout,st.accessHigh,st.lastMode=1,layout,nil,nil
    else error("Start: toast.lua [--dock] [--new]",0) end
end
-- Fortschritt aus der alten Version uebernehmen: angefangener Gang wird neu befahren.
if not SIDE and (st.layout==oldLayout or (st.layout==oldLayout22 and oldLayout22~=layout)) then
    local t=math.floor((st.next-1)/(st.layout==oldLayout and L or (H<=3 and L or 2*L)))
    st.next=math.min(cells+1,t*area+1);st.layout=layout;st.accessHigh=nil
end
assert(st.layout==layout,"Abbaumasse geaendert: an Basis mit --new neuen Auftrag bestaetigen.")
assert(st.x>=0 and st.x<width and st.y>=-(C.height-1) and st.y<=0 and st.z>=0 and st.z<=C.length
    and st.dir>=0 and st.dir<=3 and st.dir%1==0 and st.next>=1 and st.next<=cells+1 and st.next%1==0,
    "Mining-Koordinaten ungueltig. An Basis setzen: toast.lua --dock")
save()
local run={mode="off",status=st.next>cells and "Fertig" or "Bereit",detail="START: Auftrag | 1 GANG: aktuellen Gang",
    recovery=st.pending~=nil,lastContact=os.clock(),fault=nil,onceEnd=nil,lastMode=nil,retries=0,retryAt=nil}
if run.recovery then run.status,run.detail="Position unklar","An Originalbasis setzen; toast.lua --dock"
elseif resolvedAtStart then run.detail="Position nach Neustart wiederhergestellt." end
-- Nach Absturz/Serverneustart den laufenden Auftrag selbst fortsetzen.
if not run.recovery and (st.lastMode=="auto" or st.lastMode=="once") and st.next<=cells then
    run.mode,run.lastMode,run.onceEnd=st.lastMode,st.lastMode,st.onceEnd or cells
    run.status,run.detail="Fortsetzen","Auftrag nach Neustart fortgesetzt."
end
local protected={}
for _,name in ipairs(C.protectedBlocks) do protected[name]=true end
-- Turtles nehmen keinen Schaden und fahren durch Wasser/Lava; abgebaut wird alles.
-- Nur andere Turtles werden nie abgebaut (sonst gehen deine eigenen kaputt).
local hard={['computercraft:turtle_normal']=true,['computercraft:turtle_advanced']=true}
local unbreakable={['minecraft:bedrock']=true,['minecraft:barrier']=true,['minecraft:end_portal_frame']=true,
    ['minecraft:end_portal']=true,['minecraft:nether_portal']=true,['minecraft:reinforced_deepslate']=true}
local liquid={['minecraft:water']=true,['minecraft:flowing_water']=true,['minecraft:lava']=true,['minecraft:flowing_lava']=true}
local function status(a,b) run.status,run.detail=a,b or "" end
local function retryable(fault)
    if type(fault)~="string" then return false end
    for _,w in ipairs({"Geschuetzt","Nicht abbaubar","Fuelbedarf","Position unklar"}) do
        if fault:find(w,1,true) then return false end
    end
    return true
end
local function fail(why)
    run.mode,run.fault,run.retryAt="off",why,nil
end
-- Update-Knopf der Zentrale: nur zwischen zwei Schritten ausfuehren (sicherer Punkt)
local function maybeUpdate()
    if not run.updateReq then return end
    local want=type(run.updateReq)=="string" and run.updateReq or nil
    run.updateReq=false
    local ok,why=TC.selfUpdate(function(a,b) run.status,run.detail=a,b end,want)
    if not ok then run.status,run.detail="Update fehlgeschlagen",tostring(why);TC.log("Update: "..tostring(why)) end
end
local function active()
    maybeUpdate()
    -- radioTimeout=0: auch ohne Zentrale weiterarbeiten (z.B. Zentrale in entladenem Chunk).
    -- Mit Chunkloader ist das Modem nur kurz angelegt (Funkfenster): dann zaehlen nur
    -- Funkfenster ohne Antwort, nicht die Zeit (lange Wege ohne Fenster sind normal).
    if run.mode~="off" and C.radioTimeout>0 then
        if GEAR then
            if os.clock()-run.lastContact<3 then run.radioMiss=0 end
            if (run.radioMiss or 0)>=math.max(3,math.ceil(C.radioTimeout/math.max(1,CL.report))) then fail("Funkverbindung verloren") end
        elseif os.clock()-run.lastContact>C.radioTimeout then fail("Funkverbindung verloren") end
    end
    return run.mode~="off" and not run.recovery
end
local function action(kind,fn,update)
    local x,y,z,dir=st.x,st.y,st.z,st.dir
    update();st.after={x=st.x,y=st.y,z=st.z,dir=st.dir}
    st.x,st.y,st.z,st.dir=x,y,z,dir
    st.pending,st.pendingFuel=kind,turtle.getFuelLevel()
    st.pendingDrain=GEAR~=nil and GEAR.radius>0 or nil;save()
    local ok,why=fn();if ok then update() end
    clearPending();save();return ok,why
end
local function face(dir)
    while st.dir~=dir do
        local left=(st.dir-dir)%4==1
        -- side="left": Gaenge liegen links -> alle Drehungen gespiegelt.
        local ok,why=action("turn",(left~=MIRROR) and turtle.turnLeft or turtle.turnRight,
            function()st.dir=(st.dir+(left and 3 or 1))%4 end)
        if not ok then return false,"Drehen fehlgeschlagen: "..tostring(why) end
    end
    return true
end
-- Spitzhacke: liegt eine im Inventar, legt die Turtle sie selbst an
-- (auf der Seite OHNE Modem).
local TOOLS={['minecraft:diamond_pickaxe']=true,['minecraft:netherite_pickaxe']=true}
local function equipTool()
    if GEAR then return GEAR.tool() end
    for i=1,16 do
        local it=turtle.getItemDetail(i)
        if it and TOOLS[it.name] then
            turtle.select(i)
            for _,side in ipairs({"left","right"}) do
                if peripheral.getType(side)~="modem" then
                    local fn=side=="left" and turtle.equipLeft or turtle.equipRight
                    if fn() then return true end
                end
            end
        end
    end
    return false
end
local NO_TOOL="Keine Spitzhacke: Diamant-Spitzhacke in die Turtle legen"
local FUELS={['minecraft:coal']=80,['minecraft:charcoal']=80,['minecraft:coal_block']=800}
-- mine.useCoal: abgebaute Kohle sofort verbrennen, solange der Tank Platz hat.
-- Spart Fahrten zur Brennstoffkiste. Nur zwischen zwei Bewegungen (kein
-- offener Schritt), damit die Positions-Pruefung ueber den Fuelstand stimmt.
local function burnCoal()
    if not C.useCoal or st.pending then return end
    local limit=turtle.getFuelLimit()
    if limit=="unlimited" or turtle.getFuelLevel()=="unlimited" then return end
    local burned=0
    for i=1,16 do
        local item=turtle.getItemDetail(i)
        local value=item and FUELS[item.name]
        if value then
            turtle.select(i)
            while turtle.getItemCount(i)>0 and turtle.getFuelLevel()+value<=limit do
                if not turtle.refuel(1) then break end
                burned=burned+1
            end
        end
    end
    if burned>0 then st.coal=(st.coal or 0)+burned;save() end
    turtle.select(1)
end
local function freeSlots()
    local n=0;for i=1,16 do if turtle.getItemCount(i)==0 then n=n+1 end end;return n
end
local function blockReason(b)
    if unbreakable[b.name] then return "Nicht abbaubar: "..b.name end
    if protected[b.name] or hard[b.name] then return "Geschuetzter Block: "..b.name end
end
-- Mit Chunkloader: Modem statt Spitzhacke, sobald die Turtle nur faehrt (2 Schritte
-- ohne Abbau). Die Spitzhacke kommt beim naechsten Abbau automatisch zurueck.
local digCount,freeMoves=0,0
local function clear(inspect,dig,interruptible)
    -- Rueckweg (nicht unterbrechbar): immer freiraeumen, auch mit vollem Inventar
    -- (Block faellt dann als Item auf den Boden) und laenger auf Kies/Sand warten.
    local tries=interruptible and C.digRetries or math.max(64,C.digRetries)
    for _=1,tries do
        if interruptible and not active() then return false,"stopped" end
        local exists,b=inspect()
        if not exists or liquid[b.name] then return true end
        local reason=blockReason(b)
        if reason and hard[b.name] and not interruptible then
            sleep(2)                    -- andere Turtle im Weg: abwarten, sie faehrt weiter
        elseif reason then return false,reason
        elseif interruptible and freeSlots()==0 then return false,"resupply"
        else
            local ok,why=dig()
            if not ok and tostring(why):find("No tool",1,true) then
                if not equipTool() then return false,NO_TOOL end
                ok,why=dig()
            end
            if not ok then
                if tostring(why):find("No tool",1,true) then return false,NO_TOOL end
                return false,"Nicht abbaubar: "..b.name.." / "..tostring(why)
            end
            st.harvested=(st.harvested or 0)+1;digCount=digCount+1;save()
            if C.useCoal and b.name:find("coal_ore",1,true) then sleep(0.1);burnCoal() end
            sleep(0.1)
        end
    end
    local exists,b=inspect();if not exists or liquid[b.name] then return true end
    return false,blockReason(b) or "Zu viel nachrutschender Kies/Sand"
end
local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
-- ===== Wegplanung =====
-- Die Turtle weiss, welche Felder schon frei sind: fertige Schritte (aus st.next),
-- Querwege zwischen den Gaengen und alle selbst gefahrenen Strecken (st.segs).
-- Fuer Hin- und Rueckweg werden mehrere Wege bewertet und der beste genommen.
st.segs=type(st.segs)=="table" and st.segs or {}
local SEGMAX=48
local function tunnelX(k) return k*(G+1) end
local function firstY(k) return PASS[k%2==0 and 0 or P-1].y end
local function lastY(k) return PASS[k%2==0 and P-1 or 0].y end
local function zStart(k) return (k*P)%2==0 and 1 or L end
local function zEnd(k) return (k*P+P-1)%2==0 and L or 1 end
local function onSeg(x,y,z)
    for _,g in ipairs(st.segs) do
        if g.a=="x" then if y==g.y and z==g.z and x>=g.lo and x<=g.hi then return true end
        elseif g.a=="y" then if x==g.x and z==g.z and y>=g.lo and y<=g.hi then return true end
        elseif x==g.x and y==g.y and z>=g.lo and z<=g.hi then return true end
    end
    return false
end
local function addSeg(a,x,y,z,from,to)
    if from==to then return end
    local lo,hi=math.min(from,to),math.max(from,to)
    for i=#st.segs,1,-1 do
        local g=st.segs[i]
        local same=g.a==a and (a=="x" and g.y==y and g.z==z or a=="y" and g.x==x and g.z==z or a=="z" and g.x==x and g.y==y)
        if same and g.hi>=lo-1 and g.lo<=hi+1 then lo,hi=math.min(lo,g.lo),math.max(hi,g.hi);table.remove(st.segs,i) end
    end
    st.segs[#st.segs+1]={a=a,x=x,y=y,z=z,lo=lo,hi=hi}
    while #st.segs>SEGMAX do table.remove(st.segs,1) end
end
local function cellDug(x,y,z)
    if z==0 then return x==0 and y==0 end
    if y>0 or y<-(H-1) or z<1 or z>L or x<0 or x>=width then return onSeg(x,y,z) end
    local k=math.floor(x/(G+1))
    if x==tunnelX(k) and k<C.tunnels then
        local b=math.floor(-y/3);local pi=k%2==0 and b or P-1-b
        local g=k*P+pi;local j=g%2==0 and z-1 or L-z
        if k*area+pi*L+j+1<st.next then return true end
    elseif k+1<C.tunnels and z==zEnd(k) and y==lastY(k) and st.next>(k+1)*area+1 then
        return true                     -- Querweg von Gang k nach k+1
    end
    return onSeg(x,y,z)
end
-- Bewertung: Zuege + Gewicht * noch abzubauende Felder
local function partialTunnel() if st.next>cells then return C.tunnels end return math.floor((st.next-1)/area) end
local function score(legs,w)
    local x,y,z=st.x,st.y,st.z;local moves,digs=0,0
    local pt=partialTunnel()
    for _,lg in ipairs(legs) do
        local a,v=lg[1],lg[2]
        local cur=a=="x" and x or (a=="y" and y or z)
        local d=v>cur and 1 or -1
        -- Schnell: Strecke komplett in einem fertigen Gang (innerhalb der Gangmasse) ist frei.
        local k=math.floor(x/(G+1))
        if a~="x" and x==tunnelX(k) and k<pt and z>=1 and (a=="y" or v>=1) then
            moves=moves+math.abs(v-cur);cur=v
        end
        while cur~=v do
            cur=cur+d;moves=moves+1
            if not cellDug(a=="x" and cur or x,a=="y" and cur or y,a=="z" and cur or z) then digs=digs+1 end
        end
        if a=="x" then x=v elseif a=="y" then y=v else z=v end
    end
    return moves+w*digs,moves,digs
end
-- Wie weit ist der vordere Querweg (z=1, Laufebene) schon frei? -> Gangnummer
local function frontReach()
    local reach=0
    for x=1,width-1 do
        if not cellDug(x,WALK,1) then break end
        if x%(G+1)==0 then reach=x/(G+1) end
    end
    return reach
end
-- Nur sinnvolle Umstiegs-Gaenge pruefen: ganz durch die Gaenge, bis zum Ende des
-- freien Querwegs, oder direkt vorne (ggf. mit Freiraeumen).
local function viaList(k)
    local list,seen={},{}
    for _,j in ipairs({0,math.min(k,frontReach()),k}) do
        if not seen[j] then seen[j]=true;list[#list+1]=j end
    end
    return list
end
-- Rueckweg-Kandidaten: durch die Gaenge zurueck bis Gang j, dann vorne (z=1) am Querweg zur Basis.
local function homeCandidates()
    if st.z==0 then return {{}} end
    local k=math.max(0,math.min(C.tunnels-1,math.floor(st.x/(G+1))))
    local pre={}
    if st.x~=tunnelX(k) then pre[1]={"x",tunnelX(k)} end
    local out={}
    for _,j in ipairs(viaList(k)) do
        local legs={}
        for _,l in ipairs(pre) do legs[#legs+1]=l end
        for m=k,j+1,-1 do
            legs[#legs+1]={"y",firstY(m)};legs[#legs+1]={"z",zStart(m)};legs[#legs+1]={"x",tunnelX(m-1)}
        end
        legs[#legs+1]={"y",WALK};legs[#legs+1]={"z",1};legs[#legs+1]={"x",0}
        legs[#legs+1]={"y",0};legs[#legs+1]={"z",0}
        out[#out+1]=legs
    end
    return out
end
local function best(cands,w)
    local bl,bs,bm=nil,math.huge,0
    for _,legs in ipairs(cands) do
        local sc,m=score(legs,w)
        if sc<bs then bl,bs,bm=legs,sc,m end
    end
    return bl or {},bm
end
-- Vom Gangstart (Basis) zum Ziel: vorne am Querweg bis Gang j, dann durch die Gaenge.
local function workCandidates(x,y,z)
    local tw=math.floor(x/(G+1))
    local out={}
    for _,j in ipairs(viaList(tw)) do
        local legs={{"z",1},{"y",WALK},{"x",tunnelX(j)}}
        for m=j,tw-1 do
            legs[#legs+1]={"y",lastY(m)};legs[#legs+1]={"z",zEnd(m)};legs[#legs+1]={"x",tunnelX(m+1)}
        end
        legs[#legs+1]={"y",firstY(tw)};legs[#legs+1]={"z",z};legs[#legs+1]={"y",y}
        out[#out+1]=legs
    end
    return out
end
-- Gewicht fuers Freiraeumen: kostet kein Fuel, nur Zeit -> fast egal (0.1).
-- Mit (fast) vollem Inventar wuerde Abgebautes aber auf den Boden fallen ->
-- dann eher freie Wege nehmen (0.5).
local function digWeight() return freeSlots()<=1 and 0.5 or 0.1 end
-- ----- Wegplanung im Spurmodus: Wegsuche (Dijkstra) im Querschnitt -----
local function blockDug(x,y,z)
    if z==0 then return x==0 and y==0 end
    local r=-y
    if x<0 or x>=W or r<0 or r>=H or z<1 or z>L then return onSeg(x,y,z) end
    local li=math.floor((st.next-1)/L)
    local m=COVERMIN[x*H+r]
    if m and m<li then return true end
    local l=LANES[li+1]
    if l and math.abs(l.x-x)+math.abs(l.r-r)<=1 then
        local j=(st.next-1)%L
        if li%2==0 then if z<=j then return true end elseif z>=L-j+1 then return true end
    end
    return onSeg(x,y,z)
end
-- Kosten pro Feld: 1 Zug + Gewicht, falls dort noch abzubauen ist.
local function dijkstra(z,sx,sr,w)
    local N=W*H;local dist,prev={},{}
    local heap={}
    local function push(c,d) heap[#heap+1]={c,d};local i=#heap
        while i>1 do local p=math.floor(i/2);if heap[p][2]<=heap[i][2] then break end;heap[p],heap[i]=heap[i],heap[p];i=p end end
    local function pop() local top=heap[1];heap[1]=heap[#heap];heap[#heap]=nil;local i=1
        while true do local a,b=2*i,2*i+1;local m=i
            if heap[a] and heap[a][2]<heap[m][2] then m=a end
            if heap[b] and heap[b][2]<heap[m][2] then m=b end
            if m==i then break end;heap[m],heap[i]=heap[i],heap[m];i=m end
        return top end
    local s0=sx*H+sr;dist[s0]=0;push(s0,0)
    while #heap>0 do
        local t=pop();local c,d=t[1],t[2]
        if d<=dist[c] then
            local cx,cr=math.floor(c/H),c%H
            for _,e in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                local nx,nr=cx+e[1],cr+e[2]
                if nx>=0 and nx<W and nr>=0 and nr<H then
                    local n=nx*H+nr
                    local nd=d+1+(blockDug(nx,-nr,z) and 0 or w)
                    if not dist[n] or nd<dist[n] then dist[n]=nd;prev[n]=c;push(n,nd) end
                end
            end
        end
    end
    return dist,prev
end
-- Weg im Querschnitt als Legs (zusammengefasst je Achse)
local function crossLegs(prev,from,to,reverse)
    local cells={}
    local c=to
    while c and c~=from do cells[#cells+1]=c;c=prev[c] end
    if c~=from then return nil end
    cells[#cells+1]=from
    local seq={}
    if reverse then for i=1,#cells do seq[#seq+1]=cells[i] end      -- to -> from
    else for i=#cells,1,-1 do seq[#seq+1]=cells[i] end end          -- from -> to
    local legs={}
    for i=2,#seq do
        local ax,ar=math.floor(seq[i-1]/H),seq[i-1]%H
        local bx,br=math.floor(seq[i]/H),seq[i]%H
        local a=bx~=ax and "x" or "y";local v=a=="x" and bx or -br
        if legs[#legs] and legs[#legs][1]==a then legs[#legs][2]=v else legs[#legs+1]={a,v} end
    end
    return legs
end
local function concat(...)
    local out={}
    for _,t in ipairs({...}) do for _,l in ipairs(t) do out[#out+1]=l end end
    return out
end
-- Spalten, die ueber die ganze Laenge frei sind (fertige Spurmitten)
local function freeColumns(extra)
    local cols={}
    local li=math.floor((st.next-1)/L)
    for i=1,math.min(li,#LANES) do cols[#cols+1]=LANES[i] end
    if extra then cols[#cols+1]=extra end
    return cols
end
-- Rueckweg: im Querschnitt zu einer freien Spalte, darin nach vorne (z=1),
-- vorne im Querschnitt zur Ecke an der Basis, hinein.
local function blockHome(w)
    if st.z==0 then return {},0 end
    local sx,sr=st.x,-st.y
    local dz,pz=dijkstra(st.z,sx,sr,w)
    local d1,p1=dijkstra(1,0,0,w)
    local li=math.floor((st.next-1)/L)
    local cur=LANES[li+1]
    local cols=freeColumns()
    -- eigene Spur zaehlt mit, wenn sie vorne begonnen hat und die Turtle darauf steht
    if cur and li%2==0 and sx==cur.x and sr==cur.r then cols[#cols+1]=cur end
    local bestC,bestCost
    for _,c in ipairs(cols) do
        local k=c.x*H+c.r
        if dz[k] and d1[k] then
            local cost=dz[k]+(st.z-1)+d1[k]
            if not bestCost or cost<bestCost then bestC,bestCost=c,cost end
        end
    end
    local s0,o=sx*H+sr,0
    if not bestC then
        -- Notfall: direkt nach vorne (raeumt frei, was im Weg ist)
        local legs=concat({{"z",1}},crossLegs(p1,o,s0,true) or {{"y",0},{"x",0}},{{"z",0}})
        return legs,st.z+sx+sr
    end
    local k=bestC.x*H+bestC.r
    local legs=concat(crossLegs(pz,s0,k) or {},{{"z",1}},crossLegs(p1,o,k,true) or {},{{"z",0}})
    return legs,bestCost+1
end
-- Hinweg von der Basis zu Spur-Ziel (x,y,z)
local function blockWork(x,y,z,w)
    local tr=-y
    local d1,p1=dijkstra(1,0,0,w)
    local dt,pt=dijkstra(z,x,tr,w)
    local li=math.floor((st.next-1)/L)
    local cur=LANES[li+1]
    local cols=freeColumns()
    local bestC,bestCost
    for _,c in ipairs(cols) do
        local k=c.x*H+c.r
        if d1[k] and dt[k] then
            local cost=d1[k]+(z-1)+dt[k]
            if not bestCost or cost<bestCost then bestC,bestCost=c,cost end
        end
    end
    local o,t=0,x*H+tr
    -- Ziel liegt auf der eigenen, vorne begonnenen Spur: vorne hin, dann geradeaus
    if cur and li%2==0 and cur.x==x and cur.r==tr then
        local cost=d1[t]+(z-1)
        if not bestCost or cost<=bestCost then
            return concat({{"z",1}},crossLegs(p1,o,t) or {},{{"z",z}})
        end
    end
    if not bestC then
        return concat({{"z",1}},crossLegs(p1,o,t) or {{"x",x},{"y",y}},{{"z",z}})
    end
    local k=bestC.x*H+bestC.r
    return concat({{"z",1}},crossLegs(p1,o,k) or {},{{"z",z}},crossLegs(pt,t,k,true) or {})
end
local hc={next=-1,n=0}
local function homeDistance()
    if st.z==0 then return 0 end
    if hc.next~=st.next or hc.n>=40 then
        local m
        if SIDE then _,m=blockHome(digWeight()) else _,m=best(homeCandidates(),digWeight()) end
        hc={next=st.next,x=st.x,y=st.y,z=st.z,m=m,n=0}
    end
    hc.n=hc.n+1
    return hc.m+math.abs(st.x-hc.x)+math.abs(st.y-hc.y)+math.abs(st.z-hc.z)
end
-- Chunks nur laden, solange die Turtle unterwegs ist / arbeitet / auf neuen Versuch wartet.
local function chunkTick()
    if not GEAR then return end
    local need=run.mode~="off" or not homePosition() or (run.fault~=nil and run.retryAt~=nil) or CL.idle
    GEAR.set(need and CL.radius or 0)
end
local function reserve()
    local drain=GEAR and GEAR.perSecond() or 0
    return homeDistance()*(1+drain*0.6)+12+math.ceil(drain*90)
end
local function move(kind,interruptible)
    chunkTick()
    if interruptible and not active() then return false,"stopped" end
    local fuel=turtle.getFuelLevel()
    if interruptible and (freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<reserve())) then return false,"resupply" end
    local inspect,dig,fn,update,attack
    if kind=="up" then inspect,dig,fn,attack=turtle.inspectUp,turtle.digUp,turtle.up,turtle.attackUp;update=function()st.y=st.y-1 end
    elseif kind=="down" then inspect,dig,fn,attack=turtle.inspectDown,turtle.digDown,turtle.down,turtle.attackDown;update=function()st.y=st.y+1 end
    else inspect,dig,fn,attack=turtle.inspect,turtle.dig,turtle.forward,turtle.attack;update=function()st.x,st.z=st.x+DX[st.dir],st.z+DZ[st.dir] end end
    local last
    -- Mobs/Spieler im Weg: angreifen, kurz warten, erneut versuchen.
    for attempt=1,R.moveRetries do
        local before=digCount
        local ok,why=clear(inspect,dig,interruptible);if not ok then return false,why end
        if digCount==before then freeMoves=freeMoves+1 else freeMoves=0 end
        if GEAR and freeMoves>=2 and GEAR.radio() then lastRadio=os.clock() end
        if interruptible and not active() then return false,"stopped" end
        ok,why=action(kind,fn,update)
        if ok then return true end
        last=why
        if tostring(why):lower():find("fuel",1,true) then break end
        if attempt<R.moveRetries then pcall(attack);sleep(0.5) end
    end
    return false,"Bewegung blockiert: "..tostring(last)
end
local function lineX(x,i)
    while st.x~=x do
        local ok,why=face(st.x<x and 1 or 3);if not ok then return false,why end
        ok,why=move("forward",i);if not ok then return false,why end
    end
    return true
end
local function lineZ(z,i)
    while st.z~=z do
        local ok,why=face(st.z<z and 0 or 2);if not ok then return false,why end
        ok,why=move("forward",i);if not ok then return false,why end
    end
    return true
end
local function vertical(y,i)
    while st.y~=y do local ok,why=move(st.y<y and "down" or "up",i);if not ok then return false,why end end
    return true
end
local function chain(...)
    for _,f in ipairs({...}) do local ok,why=f();if not ok then return false,why end end
    return true
end
-- Legs ausfuehren; gefahrene Strecken merken (auch teilweise), damit spaetere
-- Wege sie als frei kennen.
local function runLegs(legs,i)
    if #legs==0 then return true end
    for _,lg in ipairs(legs) do
        local a,v=lg[1],lg[2]
        local sx,sy,sz=st.x,st.y,st.z
        local ok,why
        if a=="x" then ok,why=lineX(v,i) elseif a=="y" then ok,why=vertical(v,i) else ok,why=lineZ(v,i) end
        if a=="x" then addSeg("x",nil,sy,sz,sx,st.x) elseif a=="y" then addSeg("y",sx,nil,sz,sy,st.y)
        else addSeg("z",sx,sy,nil,sz,st.z) end
        if not ok then save();return false,why end
    end
    save();return true
end
local function routeTo(x,y,z,i)
    if SIDE then
        -- Auf der eigenen Spur hinter dem Ziel: geradeaus weiter
        if st.x==x and st.y==y and st.z>0 then return runLegs({{"z",z}},i) end
        if st.z~=0 then
            local h=blockHome(digWeight())
            local ok,why=runLegs(h,i);if not ok then return false,why end
        end
        return runLegs(blockWork(x,y,z,0.1),i)
    end
    local cands={}
    if st.z==0 then cands=workCandidates(x,y,z)
    else
        -- Schon im Zielgang: direkt ueber die erste Schicht zum Ziel.
        if st.x==tunnelX(math.floor(x/(G+1))) and x==st.x then
            cands[#cands+1]={{"y",firstY(math.floor(x/(G+1)))},{"z",z},{"y",y}}
        end
        -- Sonst (oder falls kuerzer): erst zur Basis-Einfahrt, dann wie von der Basis.
        local h=best(homeCandidates(),digWeight())
        for _,w in ipairs(workCandidates(x,y,z)) do
            local legs={}
            for n=1,#h-1 do legs[#legs+1]=h[n] end     -- ohne den letzten Schritt in die Basis
            for n=2,#w do legs[#legs+1]=w[n] end
            cands[#cands+1]=legs
        end
    end
    local legs=best(cands,0.1)
    return runLegs(legs,i)
end
-- Naechster Schritt direkt (auch Querweg am Gangende): Hoehe, dann x, dann z.
local function direct(x,y,z,i)
    return chain(function()return vertical(y,i)end,function()return lineX(x,i)end,function()return lineZ(z,i)end)
end
local function home()
    if homePosition() and st.dir==0 then return true end
    status("Rueckkehr",run.fault or "Fahre ueber freigelegte Wege zur Basis.")
    local legs
    if SIDE then legs=blockHome(digWeight()) else legs=best(homeCandidates(),digWeight()) end
    local ok,why=runLegs(legs,false)
    if ok then ok,why=face(0) end
    hc.next=-1
    return ok,why
end
local containers={['minecraft:chest']=true,['minecraft:trapped_chest']=true,['minecraft:barrel']=true}
local function container(fn)local ok,b=fn();return ok and containers[b.name] end
-- Mitgenommene Kisten (mine.placeChests) und Fackeln (mine.torches) nie abladen
local TORCHES={['minecraft:torch']=true}
local function keepItem(name)
    return TOOLS[name] or TC.MODEM_ITEMS[name] or (C.placeChests and containers[name]) or ((C.torches or 0)>0 and TORCHES[name])
end
local function countItems(set) local n=0;for i=1,16 do local it=turtle.getItemDetail(i);if it and set[it.name] then n=n+it.count end end;return n end
local function findItem(set) for i=1,16 do local it=turtle.getItemDetail(i);if it and set[it.name] then return i end end end
local function unload()
    if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
    burnCoal()      -- uebrige Kohle zuerst in den Tank (falls eingeschaltet)
    for i=1,16 do
        local item=turtle.getItemDetail(i)
        if item and not keepItem(item.name) then
            if not container(turtle.inspectDown) then return false,"Ausgabekiste fehlt" end
            turtle.select(i);local before=turtle.getItemCount(i);turtle.dropDown()
            local delivered=before-turtle.getItemCount(i)
            st.total=(st.total or 0)+delivered;save()
            if turtle.getItemCount(i)>0 then return false,"Lager voll" end
        end
    end
    return true
end
local minimum=2*(width+C.length)+4*C.height+40
local fuelTarget=math.max(C.fuelTarget,minimum)
local limit=turtle.getFuelLimit()
assert(limit=="unlimited" or fuelTarget<=limit,"Fuelbedarf groesser als Tank; Config/Feld verkleinern.")
-- Obere Kiste an der Basis = Nachschub: Kohle (Fuel) und, wenn eingeschaltet,
-- Kisten (mine.placeChests) und Fackeln (mine.torches). Die Turtle holt alles in
-- freie Slots, nimmt was sie braucht (Fuel bis fuelTarget, je 1 Stapel Kisten
-- und Fackeln) und legt den Rest zurueck.
local STOCK=64
local function refuel()
    local unlimited=turtle.getFuelLevel()=="unlimited"
    local function needFuel() return not unlimited and turtle.getFuelLevel()<fuelTarget end
    local function needChests() return C.placeChests and countItems(containers)<STOCK end
    local function needTorches() return (C.torches or 0)>0 and countItems(TORCHES)<STOCK end
    if not needFuel() and not needChests() and not needTorches() then return true end
    if not container(turtle.inspectUp) then
        if needFuel() then return false,"Brennstoffkiste fehlt" end
        return true
    end
    for _=1,4 do
        if not active() and needFuel() then return false,"stopped" end
        if not needFuel() and not needChests() and not needTorches() then break end
        -- alles Erreichbare in freie Slots holen
        local pulled={}
        for i=1,16 do
            if turtle.getItemCount(i)==0 then
                turtle.select(i)
                if not turtle.suckUp() then break end
                pulled[#pulled+1]=i
            end
        end
        if #pulled==0 then break end
        for _,i in ipairs(pulled) do
            local it=turtle.getItemDetail(i)
            if it and FUELS[it.name] and needFuel() then
                turtle.select(i)
                while turtle.getItemCount(i)>0 and needFuel() do if not turtle.refuel(1) then break end end
            end
        end
        -- Kisten/Fackeln: nur bis je 1 Stapel behalten, Rest + alles andere zurueck
        local have={chest=0,torch=0}
        for i=1,16 do
            local isPulled=false;for _,p in ipairs(pulled) do if p==i then isPulled=true end end
            local it=turtle.getItemDetail(i)
            if it and not isPulled then
                if containers[it.name] then have.chest=have.chest+it.count end
                if TORCHES[it.name] then have.torch=have.torch+it.count end
            end
        end
        for _,i in ipairs(pulled) do
            local it=turtle.getItemDetail(i)
            if it then
                local keepN=0
                if C.placeChests and containers[it.name] then keepN=math.max(0,STOCK-have.chest);have.chest=have.chest+math.min(keepN,it.count)
                elseif (C.torches or 0)>0 and TORCHES[it.name] then keepN=math.max(0,STOCK-have.torch);have.torch=have.torch+math.min(keepN,it.count) end
                local back=it.count-math.min(keepN,it.count)
                if back>0 then turtle.select(i);turtle.dropUp(back) end
            end
        end
        turtle.select(1)
    end
    turtle.select(1)
    if needFuel() then return false,"Treibstoff fehlt" end
    return true
end
local function supplies()
    local ok,why=home();if not ok then return false,why end
    while active() do
        ok,why=unload();if ok then ok,why=refuel() end
        if ok then return true end
        if why=="stopped" then return false,why end
        status(why,"Problem an Basis beheben. STOP bricht Warten ab.")
        if GEAR then GEAR.radio() end
        sleep(1)
    end
    return false,"stopped"
end
-- ===== Kiste unterwegs (mine.placeChests) =====
-- Inventar voll: statt heimzufahren eine mitgebrachte Kiste in den Boden unter
-- der untersten Reihe setzen (dort wird nie gegraben) und hineinladen.
-- Nur wenn die Spalte bis zur untersten Reihe schon frei ist.
local function dugAt(x,y,z) if SIDE then return blockDug(x,y,z) end return cellDug(x,y,z) end
local function dumpHere()
    if not C.placeChests or homePosition() or st.z<1 then return false end
    local slot=findItem(containers);if not slot then return false end
    for yy=st.y+1,0 do if not dugAt(st.x,yy,st.z) then return false end end
    burnCoal()
    local y0=st.y
    status("Kiste setzen","Inventar voll: Kiste in den Boden, kein Heimweg noetig.")
    local ok=vertical(0,false);if not ok then return false end
    local e,b=turtle.inspectDown()
    if e and (liquid[b.name] or blockReason(b)) then vertical(y0,false);return false end
    if e then
        ok=clear(turtle.inspectDown,turtle.digDown,false)
        if not ok then vertical(y0,false);return false end
    end
    slot=findItem(containers)
    if not slot then vertical(y0,false);return false end
    turtle.select(slot)
    if not turtle.placeDown() then turtle.select(1);vertical(y0,false);return false end
    for i=1,16 do
        local item=turtle.getItemDetail(i)
        if item and not keepItem(item.name) then
            turtle.select(i);local before=turtle.getItemCount(i);turtle.dropDown()
            st.total=(st.total or 0)+before-turtle.getItemCount(i)
        end
    end
    turtle.select(1)
    st.chestsPlaced=(st.chestsPlaced or 0)+1
    st.chestSpots=st.chestSpots or {}
    if #st.chestSpots<64 then st.chestSpots[#st.chestSpots+1]={x=st.x,y=st.y+1,z=st.z,n=st.chestsPlaced} end
    save()
    -- Liste der Kisten auch als Datei (an der Turtle: edit /toast_kisten.txt)
    pcall(function()
        local okc,full=pcall(TC.load)
        local f=fs.open("/toast_kisten.txt","w")
        f.writeLine("Abladekisten von Turtle #"..os.getComputerID().." (Mine)")
        for _,k in ipairs(st.chestSpots) do
            local pos,rel=nil,nil
            if okc then pos,rel=TC.worldPos(full,"mining",k.x,k.y or 1,k.z) end
            local where=rel and (rel.fwd.." vor, "..math.abs(rel.right)..(rel.right>=0 and " rechts, " or " links, ")..math.abs(rel.up).." tief") or ""
            f.writeLine("Kiste "..(k.n or "?")..": "..(pos and ("X "..pos.x.." Y "..pos.y.." Z "..pos.z.."  ") or "")..where)
        end
        f.close()
    end)
    ok=vertical(y0,false)
    return ok
end
-- ===== Fackeln (mine.torches = Abstand, 0 = aus) =====
-- Auf den Boden der untersten Reihe, waehrend die Turtle in Reihe 2 vorbeifaehrt.
local function placeTorch()
    local n=C.torches or 0
    if n<=0 or st.y~=-1 or st.z<1 or st.z%n~=0 then return end
    st.torchAt=st.torchAt or {}
    local k=st.x..":"..st.z
    if st.torchAt[k] then return end
    local e=turtle.inspectDown();if e then return end
    local slot=findItem(TORCHES);if not slot then return end
    turtle.select(slot)
    if turtle.placeDown() then st.torchAt[k]=true;st.torchesPlaced=(st.torchesPlaced or 0)+1;save() end
    turtle.select(1)
end
local function fuelOk()
    local fuel=turtle.getFuelLevel()
    return fuel=="unlimited" or fuel>=reserve()
end
local function finish()
    run.mode,run.lastMode="off",nil
    if st.lastMode then st.lastMode=nil;save() end
end
local function idle()
    local ok,why=home()
    if not ok then status("Rueckweg blockiert",why);return end
    ok,why=unload()
    if not ok then status(why,"Ausgabe an Basis pruefen.")
    elseif run.fault then
        local now=os.clock()
        if run.lastMode and retryable(run.fault) and run.retries<R.autoRetry then
            run.retryAt=run.retryAt or now+R.retryDelay
            local contact=C.radioTimeout==0 or now-run.lastContact<C.radioTimeout
            if now>=run.retryAt and contact then
                run.retries=run.retries+1;run.retryAt=nil;run.fault=nil;run.mode=run.lastMode
                status("Neuer Versuch","Automatisch "..run.retries.."/"..R.autoRetry)
            else
                status(run.fault,contact and ("Neuer Versuch in "..math.max(0,math.ceil(run.retryAt-now)).."s ("..(run.retries+1).."/"..R.autoRetry..") | RESET: abbrechen")
                    or "Warte auf Funkkontakt fuer neuen Versuch")
            end
        else
            status(run.fault,"Problem beheben; RESET loescht Fehler, START setzt fort.")
        end
    elseif st.next>cells then status("Fertig","Neuer Auftrag: an der Turtle N druecken")
    else status("Bereit","START setzt fort | 1 GANG: aktuellen Gang") end
    if GEAR then GEAR.radio() end
    chunkTick()
end
local sendStatus
lastRadio=os.clock()
-- Mit Chunkloader: alle reportEvery Sekunden kurz Modem anlegen und funken.
-- Die Spitzhacke kommt beim naechsten Abbau automatisch zurueck.
local function radioWindow()
    if not GEAR or os.clock()-lastRadio<CL.report then return end
    if GEAR.radio() then
        local t0=os.clock()
        sendStatus();sleep(1.5)
        if run.lastContact>=t0 then run.radioMiss=0 else run.radioMiss=(run.radioMiss or 0)+1 end
    end
    lastRadio=os.clock()
end
local function work()
    while true do
        chunkTick()
        if not run.recovery then
            if active() then
                radioWindow()
                if st.next>cells then finish();status("Fertig","Neuer Auftrag: an der Turtle N druecken")
                else
                    local ok,why=true
                    local fuel=turtle.getFuelLevel()
                    if homePosition() or freeSlots()<C.freeSlots or (fuel~="unlimited" and fuel<reserve()) then
                        if not (freeSlots()<C.freeSlots and fuelOk() and dumpHere() and freeSlots()>=C.freeSlots) then
                            ok,why=supplies()
                        end
                    end
                    if ok and active() then
                        status("Abbau",SIDE and ("Spur "..(math.floor((st.next-1)/L)+1).." / "..#LANES)
                            or ("Gang "..(math.floor((st.next-1)/area)+1).." / "..C.tunnels))
                        local x,y,z,up,down,left,right=step(st.next)
                        local px,py,pz
                        if st.next>1 then px,py,pz=step(st.next-1) end
                        if px and st.x==px and st.y==py and st.z==pz then ok,why=direct(x,y,z,true)
                        else ok,why=routeTo(x,y,z,true) end
                        if ok and up then ok,why=clear(turtle.inspectUp,turtle.digUp,true) end
                        if ok and down then ok,why=clear(turtle.inspectDown,turtle.digDown,true) end
                        if ok then placeTorch() end
                        -- Spurmodus: links/rechts durch Drehen mitabbauen (kostet kein Fuel).
                        -- Schon freie Seiten werden uebersprungen (spart Zeit).
                        if SIDE and ok then
                            local sides={}
                            if right and not blockDug(x+1,y,z) then sides[#sides+1]=1 end
                            if left and not blockDug(x-1,y,z) then sides[#sides+1]=3 end
                            for _,d in ipairs(sides) do
                                if ok and active() then
                                    ok,why=face(d)
                                    if ok then ok,why=clear(turtle.inspect,turtle.dig,true) end
                                end
                            end
                        end
                    end
                    if ok and active() then
                        st.next=st.next+1;save();run.retries=0
                        if run.mode=="once" and st.next>run.onceEnd then finish() end
                        if st.next>cells then finish() end
                    elseif not ok and why=="resupply" then
                        if not (freeSlots()<C.freeSlots and fuelOk() and dumpHere() and freeSlots()>=C.freeSlots) then
                            local ready,problem=supplies()
                            if not ready and problem~="stopped" then fail(problem) end
                        end
                    elseif not ok and why~="stopped" then fail(why) end
                end
            end
            if not active() then idle() end
        end
        sleep(0.2)
    end
end
local function snapshot()
    return {kind="status",version=2,id=os.getComputerID(),status=run.status,detail=run.detail,
        mode=run.mode,recovery=run.recovery,ack=st.commandSerial or 0,fault=run.fault,retries=run.retries,
        contactAge=math.max(0,math.floor(os.clock()-run.lastContact)),radioTimeout=C.radioTimeout,pollToken=run.pollToken,
        width=width,length=C.length,height=C.height,tunnels=C.tunnels,gap=C.gap,fuel=turtle.getFuelLevel(),freeSlots=freeSlots(),
        chunks=GEAR and (GEAR.radius>0 and CL.chunks or 0) or nil,chunkFuel=GEAR and math.floor(GEAR.perSecond()*3600+0.5) or nil,
        x=st.x,y=st.y,z=st.z,total=st.total or 0,harvested=st.harvested or 0,coal=st.coal or 0,useCoal=C.useCoal==true,
        placeChests=C.placeChests==true,chestsPlaced=st.chestsPlaced or 0,chestsLeft=C.placeChests and countItems(containers) or nil,
        chestSpots=st.chestSpots,
        torches=C.torches or 0,torchesPlaced=st.torchesPlaced or 0,torchesLeft=(C.torches or 0)>0 and countItems(TORCHES) or nil,
        rounds=math.floor((st.next-1)/area),scanned=st.next-1,cells=cells}
end
sendStatus=function()pcall(rednet.send,cfg.controllerId,snapshot(),common.protocol)end
local function reset()
    run.mode,run.fault,run.lastMode,run.retries,run.retryAt="off",nil,nil,0,nil
    st.lastMode=nil
    if run.recovery and resolvePending() then run.recovery=false end
    if run.recovery then status("Position unklar","RESET reicht nicht: an Basis setzen, toast.lua --dock")
    else status("Reset","Fehler geloescht; Turtle faehrt zur Basis.") end
end
local function listener()
    while true do
        local e,a,b,c=os.pullEvent()
        if e=="char" and (a=="q" or a=="Q") then finish();run.fault=nil
        elseif e=="char" and (a=="n" or a=="N") and run.mode=="off" and homePosition() then error("TOAST_NEUER_AUFTRAG",0)
        elseif e=="peripheral" or e=="peripheral_detach" then common.refreshModems();sendStatus()
        elseif e=="rednet_message" and a==cfg.controllerId and c==common.protocol and type(b)=="table" then
            if b.kind=="poll" then run.lastContact=os.clock();run.pollToken=b.token;sendStatus()
            elseif b.kind=="command" and common.serial(b.serial) and ({start=true,stop=true,once=true,reset=true,update=true})[b.action] then
                run.lastContact=os.clock()
                if b.serial>(st.commandSerial or 0) then
                    st.commandSerial=b.serial
                    if b.action=="update" then run.updateReq=type(b.target)=="string" and b.target or true;run.status,run.detail="Update","Wird gleich installiert ..."
                    elseif b.action=="stop" then finish();run.fault,run.retries,run.retryAt=nil,0,nil
                    elseif b.action=="reset" then reset()
                    elseif not run.recovery and st.next<=cells then
                        run.mode=b.action=="once" and "once" or "auto";run.fault,run.retries,run.retryAt=nil,0,nil
                        run.lastMode=run.mode
                        run.onceEnd=(math.floor((st.next-1)/area)+1)*area
                        st.lastMode,st.onceEnd=run.mode,run.onceEnd
                    end
                    save()
                end
                sendStatus()
            end
        end
    end
end
local function heartbeat()while true do common.refreshModems();sendStatus();sleep(2)end end
if not GEAR then pcall(equipTool) end
term.clear();term.setCursorPos(1,1)
print("TOAST MINING 2.6 / Turtle #"..os.getComputerID())
print(C.tunnels.." Gaenge / "..C.length.." lang / "..C.height.." hoch / Abstand "..C.gap)
if sideNote then print(sideNote) end
print("Zentrale #"..cfg.controllerId)
if GEAR then print("Chunkloader: "..CL.chunks.." Chunk(s), ca. "..TC.chunkFuelPerHour(CL.chunks).." Fuel/h beim Arbeiten") end
print("Q: Stopp/Heimfahrt. N: neuer Auftrag (gestoppt, an Basis).")
if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
local ok,why=pcall(function()parallel.waitForAll(work,listener,heartbeat)end)
if not ok then
    run.mode="off";run.recovery=st.pending~=nil and not resolvePending()
    status(run.recovery and "Position unklar" or "Programm beendet",tostring(why));sendStatus()
    if why~="Terminated" then error(why,0) end
    printError("Abgebrochen.")
end
