package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local function cfg(b)
    return [[return {role="turtle",job="build",controllerId=4,name="Bauer",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},build=]]..b..[[}]]
end
-- Materialkiste hinter der Turtle (Sim-Koordinaten: y positiv = unten, z=-1 = hinten)
local function setup(S,stacks)
    local K=S.key
    S.world[K(0,-1,0)]=false                 -- keine Kohlekiste oben (dort ist der Schacht)
    S.world[K(0,0,-1)]="minecraft:chest"
    S.supply={};for i,s in ipairs(stacks) do S.supply[i]={name=s[1],count=s[2]} end
    S.supplySize=108
    local T=S.turtle
    local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
    local function facingSupply() return S.p.x+DX[S.p.dir]==0 and S.p.z+DZ[S.p.dir]==-1 and S.p.y==0 and S.p.x==0 and S.p.z==0 end
    T.suck=function(n)
        if not facingSupply() then return false end
        if S.inv[S.sel] then return false end
        for i=1,S.supplySize do local s=S.supply[i]
            if s then local k=math.min(n or 64,s.count);S.inv[S.sel]={name=s.name,count=k};s.count=s.count-k
                if s.count==0 then S.supply[i]=nil end;return true end end
        return false
    end
    T.drop=function(n)
        local it=S.inv[S.sel];if not it then return false end
        if not facingSupply() then return false end
        for i=1,S.supplySize do if not S.supply[i] then S.supply[i]={name=it.name,count=it.count};S.inv[S.sel]=nil;return true end end
        return false
    end
    local inv={size=function() return S.supplySize end,
        list=function() local t={};for i=1,S.supplySize do local s=S.supply[i];if s then t[i]={name=s.name,count=s.count} end end;return t end,
        pushItems=function(to,from,limit,toSlot)
            local s=S.supply[from];if not s or S.supply[toSlot] then return 0 end
            S.supply[toSlot]=s;S.supply[from]=nil;S.pushes=(S.pushes or 0)+1;return s.count end}
    S.supplyInv=inv
    -- Wasser aus Eimern, Bloecke nach oben setzen
    local pd=T.placeDown
    T.placeDown=function()
        local it=S.inv[S.sel]
        if it and it.name=="minecraft:water_bucket" then
            local x,y,z=S.p.x,S.p.y+1,S.p.z
            if S.block(x,y,z) then return false end
            S.world[K(x,y,z)]="minecraft:water";S.inv[S.sel]={name="minecraft:bucket",count=1};S.waterPlaced=(S.waterPlaced or 0)+1
            return true
        end
        return pd()
    end
    -- echtes Spiel: Bloecke lassen sich in Wasser/Lava setzen
    local pd2=T.placeDown
    T.placeDown=function()
        local x,y,z=S.p.x,S.p.y+1,S.p.z
        local b=S.block(x,y,z)
        if b and (b:find("water",1,true) or b:find("lava",1,true)) and S.inv[S.sel] and S.inv[S.sel].name~="minecraft:water_bucket" then
            local it=S.inv[S.sel];it.count=it.count-1;local nm=it.name;if it.count==0 then S.inv[S.sel]=nil end
            S.world[K(x,y,z)]=nm;return true
        end
        return pd2()
    end
    T.placeUp=function()
        local x,y,z=S.p.x,S.p.y-1,S.p.z
        if S.block(x,y,z) then return false end
        local it=S.inv[S.sel];if not it then return false end
        it.count=it.count-1;local nm=it.name;if it.count==0 then S.inv[S.sel]=nil end
        S.world[K(x,y,z)]=nm;return true
    end
    T.digUp=T.digUp or function() return false end
    -- Falltueren: offen, wenn beim Setzen ein Redstoneblock direkt daneben liegt
    -- (wie im Spiel: getStateForPlacement prueft hasNeighborSignal); Klappe laengs
    -- zur Blickrichtung der Turtle (FACING = Gegenrichtung).
    S.tstate={}
    local function redNear(x,y,z)
        for _,d in ipairs({{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}) do
            if S.block(x+d[1],y+d[2],z+d[3])=="minecraft:redstone_block" then return true end
        end
        return false
    end
    local pd3=T.placeDown
    T.placeDown=function()
        local it=S.inv[S.sel]
        if it and it.name:find("_trapdoor",1,true) then
            local x,y,z=S.p.x,S.p.y+1,S.p.z
            if S.block(x,y,z) then return false end
            it.count=it.count-1;local nm=it.name;if it.count==0 then S.inv[S.sel]=nil end
            S.world[K(x,y,z)]=nm;S.tstate[K(x,y,z)]={open=redNear(x,y,z),half="top",facing=(S.p.dir+2)%4}
            return true
        end
        return pd3()
    end
    local pu=T.placeUp
    T.placeUp=function()
        local it=S.inv[S.sel];local isT=it and it.name:find("_trapdoor",1,true)
        local ok=pu()
        if ok and isT then local x,y,z=S.p.x,S.p.y-1,S.p.z;S.tstate[K(x,y,z)]={open=redNear(x,y,z),half="top",facing=(S.p.dir+2)%4} end
        return ok
    end
    local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
    local function at(kind) local p=S.p
        if kind=="up" then return p.x,p.y-1,p.z elseif kind=="down" then return p.x,p.y+1,p.z end
        return p.x+DX[p.dir],p.y,p.z+DZ[p.dir] end
    for kind,fn in pairs({[""]="inspect",Up="inspectUp",Down="inspectDown"}) do
        local o=T[fn];local k=kind=="" and "forward" or kind:lower()
        T[fn]=function() local ok,b=o();if ok and S.tstate[K(at(k))] then b.state=S.tstate[K(at(k))] end;return ok,b end
    end
    for kind,fn in pairs({[""]="dig",Up="digUp",Down="digDown"}) do
        local o=T[fn];local k=kind=="" and "forward" or kind:lower()
        T[fn]=function() local key=K(at(k));local ok,why=o();if ok then S.tstate[key]=nil end;return ok,why end
    end
end
local orig=Sim.env
local function envWith(S2)
    local G=orig(S2)
    local wrap=G.peripheral.wrap
    G.peripheral.wrap=function(side)
        if side=="front" and S2.supplyInv then
            local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
            if S2.p.x+DX[S2.p.dir]==0 and S2.p.z+DZ[S2.p.dir]==-1 and S2.p.y==0 then return S2.supplyInv end
        end
        return wrap(side)
    end
    return G
end
-- Sollzustand (Turtle-Koordinaten, y oben) -> Sim-Welt pruefen
local function verify(S,F,Dp,creeper)
    local B0,TOP,R,OUT=Dp,Dp+5*F,8,9
    local bad,why=0,{}
    local function get(x,y,z) return S.block(x,-y,z) or false end
    local function want(x,y,z)
        local ax,az=math.abs(x),math.abs(z)
        if y>=1 and y<B0 then if x==0 and z==0 then return "air" end;if ax+az==1 then return "solid" end;return nil end
        if y<B0 or y>TOP or ax>OUT or az>OUT then return nil end
        if y==TOP then return "solid" end
        local k=(y-B0)%5
        local ch=x==0
        local tz=az%3~=0
        if k==0 then
            if x==0 and z==0 then return "air" end
            if y==B0 and not (ch and az<=R) then return nil end
            return "solid"
        end
        if k==1 then
            if ch then if z==0 then return "air" end;if az<=R then return az==R and "water" or "air" end;return "solid" end
            if ax==1 and az>=1 and az<=R then return "solid" end
            return nil
        end
        if ax==OUT or az==OUT then return "solid" end
        if x==0 and z==0 then return "air" end
        if k==2 then
            if ch then return tz and "ctrap" or "air" end
            if x==1 and tz then return "red" end
            return "solid"
        end
        if k==3 and not ch and az%3==0 then return "slab" end
        if k==4 and creeper and not ch and az%3~=0 then return "trap" end
        return "air"
    end
    for y=1,TOP do for x=-OUT,OUT do for z=-OUT,OUT do
        local wv=want(x,y,z)
        if wv then
            local b=get(x,y,z)
            local ok=(wv=="air" and b==false) or (wv=="solid" and b and (b:find("cobble",1,true) or b=="minecraft:stone" or b=="minecraft:dirt") and not b:find("slab",1,true))
                or (wv=="water" and b=="minecraft:water") or (wv=="slab" and b and b:find("_slab",1,true))
                or (wv=="trap" and b and b:find("_trapdoor",1,true) and not (S.tstate[S.key(x,-y,z)] or {}).open)
                or (wv=="red" and b=="minecraft:redstone_block")
                or (wv=="ctrap" and b and b:find("_trapdoor",1,true) and (S.tstate[S.key(x,-y,z)] or {}).open==true
                    and ((S.tstate[S.key(x,-y,z)] or {}).facing or 0)%2==1)
            if not ok then bad=bad+1;if #why<6 then why[#why+1]=wv.."@"..x..","..y..","..z.."="..tostring(b) end end
        end
    end end end
    return bad,table.concat(why," ")
end

print("B1 Creeper-Mobfarm, 1 Etage, Schacht 6, im Freien; Materialkiste bunt gemischt")
local S=Sim.new({config=cfg('{floors=1,drop=6,creeperOnly=true,becomeMob=true,fuelTarget=2000,radioTimeout=0}'),default=false,
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.build.v1"
local stacks={{"minecraft:oak_trapdoor",64},{"minecraft:dirt",3}};stacks[#stacks+1]={"minecraft:redstone_block",64};stacks[#stacks+1]={"minecraft:spruce_trapdoor",64};stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,4 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
stacks[#stacks+1]={"minecraft:oak_trapdoor",64}
for _=1,8 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,22 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
stacks[#stacks+1]={"minecraft:oak_trapdoor",64}
stacks[#stacks+1]={"minecraft:coal",64}
setup(S,stacks)
S.inv[16]={name="minecraft:diamond_sword",count=1}
Sim.env=envWith
Sim.run(S,20000)
Sim.env=orig
local st=load("return "..(S.files["/toast_build_state"] or "{}"))()
local bad,why=verify(S,1,6,true)
check("fertig",st.done==true,tostring(S.last and S.last.status).." "..tostring(S.last and S.last.fault).." "..tail(S))
check("Bau stimmt Block fuer Block",bad==0,bad.." "..why)
check("2 Wasserquellen gesetzt",(S.waterPlaced or 0)==2,S.waterPlaced)
check("Turtle zurueck an der Toetungsstelle",S.p.x==0 and S.p.y==0 and S.p.z==0,S.p.x..","..S.p.y..","..S.p.z)
check("Materialkiste umsortiert (Kisten-Peripherie)",(S.pushes or 0)>0,S.pushes)
local okc,newcfg=pcall(load(S.files["/toast.config.lua"] or "return nil"))
check("danach Mob-Turtle (Schwert gefunden): Mobfarm, Angriff nur oben",okc and newcfg and newcfg.job=="mob" and newcfg.mob.mode=="farm" and newcfg.mob.attack=="up",
    okc and newcfg and (tostring(newcfg.job).." "..tostring(newcfg.mob and newcfg.mob.attack)) or "?")

print("B2 2 Etagen, Schacht 22, Wasser/Lava im Weg, Material knapp -> wartet, dann weiter")
S=Sim.new({config=cfg('{floors=2,drop=22,creeperOnly=false,inTerrain=true,becomeMob=false,fuelTarget=2000,radioTimeout=0}'),default=false,
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
        {t=2500,fn=function(S) for i=1,S.supplySize do if not S.supply[i] then S.supply[i]={name="minecraft:cobblestone",count=64};break end end
            for _=1,40 do for i=1,S.supplySize do if not S.supply[i] then S.supply[i]={name="minecraft:cobblestone",count=64};break end end end
            S.refilled=true end}}})
S.protocol="toast.build.v1"
stacks={{"minecraft:coal",64},{"minecraft:coal",64}};stacks[#stacks+1]={"minecraft:redstone_block",64};stacks[#stacks+1]={"minecraft:spruce_trapdoor",64};stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,8 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
stacks[#stacks+1]={"minecraft:cobblestone_slab",64};stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,6 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
setup(S,stacks)
-- Gelaende: Stein ueberall (Standard), Wasserloch mitten im Bau
S.world[S.key(3,-24,3)]="minecraft:water";S.world[S.key(-2,-27,5)]="minecraft:lava"
local sawMissing=false
local sendOrig
Sim.env=function(S2) local G=envWith(S2)
    local send=G.rednet.send
    G.rednet.send=function(id,msg,p) if type(msg)=="table" and tostring(msg.status):find("Baumaterial fehlt",1,true) then sawMissing=true end;return send(id,msg,p) end
    return G end
Sim.run(S,60000)
Sim.env=orig
st=load("return "..(S.files["/toast_build_state"] or "{}"))()
bad,why=verify(S,2,22,false)
check("meldet 'Baumaterial fehlt' und wartet",sawMissing)
check("nach dem Nachfuellen fertig",st.done==true and S.refilled,tostring(S.last and S.last.status).." "..tostring(S.last and S.last.fault).." "..tail(S))
check("Bau stimmt (Wasser/Lava im Weg weggeraeumt)",bad==0,bad.." "..why)
check("4 Wasserquellen",(S.waterPlaced or 0)==4,S.waterPlaced)
print("    Zuege (= Fuel) fuer 2 Etagen + Schacht 22: "..S.moves)
check("bleibt Bauer (becomeMob aus)",(load(S.files["/toast.config.lua"])()).job=="build")

print("B4 Mitten im Gelaende (alles Stein): graebt sich frei, nutzt den Abraum als Material")
S=Sim.new({config=cfg('{floors=1,drop=10,creeperOnly=true,inTerrain=true,becomeMob=false,fuelTarget=2000,radioTimeout=0}'),
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.build.v1"
stacks={{"minecraft:coal",64},{"minecraft:coal",64}};stacks[#stacks+1]={"minecraft:redstone_block",64};stacks[#stacks+1]={"minecraft:spruce_trapdoor",64};stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,4 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
for _=1,3 do stacks[#stacks+1]={"minecraft:oak_trapdoor",64} end
stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,4 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
setup(S,stacks)
Sim.env=envWith
Sim.run(S,40000)
Sim.env=orig
st=load("return "..(S.files["/toast_build_state"] or "{}"))()
bad,why=verify(S,1,10,true)
check("fertig",st.done==true,tostring(S.last and S.last.status).." "..tostring(S.last and S.last.fault).." "..tail(S))
check("Bau stimmt (Raeume frei gegraben)",bad==0,bad.." "..why)
print("    Zuege (= Fuel): "..S.moves)

print("B3 Absturz mitten im Bau: macht weiter, Ergebnis stimmt")
S=Sim.new({config=cfg('{floors=1,drop=5,creeperOnly=true,becomeMob=false,fuelTarget=2000,radioTimeout=0}'),default=false,
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.build.v1"
stacks={{"minecraft:coal",64}};stacks[#stacks+1]={"minecraft:redstone_block",64};stacks[#stacks+1]={"minecraft:spruce_trapdoor",64};stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,4 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
for _=1,4 do stacks[#stacks+1]={"minecraft:oak_trapdoor",64} end
stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,30 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
setup(S,stacks)
S.crashAtMove=700
Sim.env=envWith
Sim.run(S,20000)
Sim.env=orig
st=load("return "..(S.files["/toast_build_state"] or "{}"))()
bad,why=verify(S,1,5,true)
check("fertig trotz Absturz",st.done==true,tostring(S.last and S.last.status).." "..tail(S))
check("Bau stimmt",bad==0,bad.." "..why)

print("B5 Im Freien wie ein 3D-Drucker (2 Etagen, Schacht 22): nur Bahnen mit Bloecken")
S=Sim.new({config=cfg('{floors=2,drop=22,creeperOnly=true,inTerrain=false,becomeMob=false,fuelTarget=2000,radioTimeout=0}'),default=false,
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.build.v1"
stacks={{"minecraft:coal",64},{"minecraft:coal",64}};stacks[#stacks+1]={"minecraft:redstone_block",64};stacks[#stacks+1]={"minecraft:spruce_trapdoor",64};stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,8 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
for _=1,6 do stacks[#stacks+1]={"minecraft:oak_trapdoor",64} end
stacks[#stacks+1]={"minecraft:cobblestone_slab",64};stacks[#stacks+1]={"minecraft:cobblestone_slab",64}
for _=1,60 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
setup(S,stacks)
Sim.env=envWith
Sim.run(S,60000)
Sim.env=orig
st=load("return "..(S.files["/toast_build_state"] or "{}"))()
bad,why=verify(S,2,22,true)
check("fertig",st.done==true,tostring(S.last and S.last.status).." "..tostring(S.last and S.last.fault).." "..tail(S))
check("Bau stimmt Block fuer Block",bad==0,bad.." "..why)
check("sparsam: unter 3600 Zuege (vorher ~4900)",S.moves<3600,S.moves)
print("    Zuege (= Fuel) 3D-Drucker, 2 Etagen + Schacht 22: "..S.moves)
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
