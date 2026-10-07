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
        local b0=S.block(x,y,z)
        if b0 and not (b0:find("water",1,true) or b0:find("lava",1,true)) then return false end
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
    -- Trichter zeigen weg von der Turtle (placeDown: nach unten); Leitern brauchen
    -- einen Block dahinter; Fackeln einen vollen Block darunter.
    local pf=T.place
    T.place=function()
        local it=S.inv[S.sel]
        local DX2,DZ2={[0]=0,1,0,-1},{[0]=1,0,-1,0}
        local x,y,z=S.p.x+DX2[S.p.dir],S.p.y,S.p.z+DZ2[S.p.dir]
        if it and it.name=="minecraft:ladder" then
            local sup=S.block(x+DX2[S.p.dir],y,z+DZ2[S.p.dir])
            if not sup or sup:find("water",1,true) or sup:find("ladder",1,true) then return false end
        end
        local ok=pf()
        if ok and it and (it.name=="minecraft:hopper" or it.name=="minecraft:ladder") then S.tstate[K(x,y,z)]={facing=S.p.dir} end
        return ok
    end
    local pd4=T.placeDown
    T.placeDown=function()
        local it=S.inv[S.sel]
        local x,y,z=S.p.x,S.p.y+1,S.p.z
        if it and it.name=="minecraft:torch" then
            local b=S.block(x,y+1,z)
            if not b or b:find("slab",1,true) or b:find("torch",1,true) then return false end
        end
        local ok=pd4()
        if ok and it and it.name=="minecraft:hopper" then S.tstate[K(x,y,z)]={facing="down"} end
        if ok and it and it.name:find("_slab",1,true) then S.tstate[K(x,y,z)]={type="bottom"} end
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
-- Sollzustand (Turtle-Koordinaten, y oben) -> Sim-Welt pruefen (eigene Nachrechnung der Spezifikation)
local function verify(S,F,HG,creeper,afk)
    local B0,R,OUT=HG,8,9
    local function SURF(g) return B0+2+3*g end
    local TOP=SURF(F-1)+3
    local AY=B0-30
    local bad,why=0,{}
    local function A(c) if c>=1 then return c-1 end return -c end
    local function get(x,y,z) return S.block(x,-y,z) or false end
    local function ts(x,y,z) return S.tstate[S.key(x,-y,z)] or {} end
    local function loc(g,x,z) if g%2==1 then return z,x end return x,z end
    local function canal(g,role,x,z)
        local u,v=loc(g,x,z);local au,av=A(u),A(v)
        if au==0 and av==0 then return "air" end
        if g==0 and au==1 and av==0 then return "solid" end
        if role=="bed" then return (au==0 and av<=R) and "solid" or nil end
        if au==0 then if av<=R then return av==R and "water" or "air" end;return "solid" end
        if au==1 and av>=1 and av<=R then return "solid" end
    end
    local function want(x,y,z)
        local ax,az=A(x),A(z)
        if y>=1 and y<B0 then if ax==0 and az==0 then return "air" end;if ax+az==1 then return "solid" end;return nil end
        if y<B0 or y>TOP or ax>OUT or az>OUT then return nil end
        if y==TOP then if ax==OUT and az==OUT then return nil end;return "slab" end
        local rel=y-SURF(0)
        if rel<0 then return canal(0,rel==-2 and "bed" or "water",x,z) end
        local g,k=rel//3,rel%3
        if k>=1 and g+1<=F-1 then local c=canal(g+1,k==1 and "bed" or "water",x,z);if c then return c end end
        local u,v=loc(g,x,z);local au,av=A(u),A(v)
        if au==0 and av==0 then return "air" end
        local ring=au==OUT or av==OUT
        local tz=av>=1 and av<=R and av%3~=0
        if k==0 then
            if ring then return au==0 and "solid" or nil end
            if au==0 then
                if not tz then return "air" end
                -- Klappe zur Kanalmitte: Spur u=0 -> +u, Spur u=1 -> -u (FACING = Gegenseite)
                local flapPlus=(u==0)
                local face
                if g%2==0 then face=flapPlus and 3 or 1 else face=flapPlus and 2 or 0 end
                return "ctrap"..face
            end
            if au==1 and tz then return "red" end
            return "solid"
        end
        if ring then if au==OUT and av==OUT then return nil end;return "solid" end
        if k==1 and au~=0 and av%3==0 then return "slab" end
        if k==2 and creeper and au~=0 and av%3~=0 then return "trap" end
        return "air"
    end
    local function isSolid(b) return b and (b:find("cobble",1,true) or b=="minecraft:stone" or b=="minecraft:dirt") and not b:find("slab",1,true) end
    local function fail(t) bad=bad+1;if #why<8 then why[#why+1]=t end end
    for y=1,TOP do for x=-OUT,OUT+1 do for z=-OUT,OUT+1 do
        local wv=want(x,y,z)
        if wv then
            local b=get(x,y,z)
            local st=ts(x,y,z)
            local ok=(wv=="air" and b==false) or (wv=="solid" and isSolid(b))
                or (wv=="water" and b=="minecraft:water") or (wv=="slab" and b and b:find("_slab",1,true) and st.type~="top")
                or (wv=="trap" and b and b:find("_trapdoor",1,true) and not st.open)
                or (wv=="red" and b=="minecraft:redstone_block")
                or (wv:sub(1,5)=="ctrap" and b and b:find("_trapdoor",1,true) and st.open==true and st.facing==tonumber(wv:sub(6)))
            if not ok then fail(wv.."@"..x..","..y..","..z.."="..tostring(b).."/"..tostring(st.facing)) end
        end
    end end end
    -- Trichter unten: (0,0) in die Kiste, die anderen in (0,0)
    local H={{0,0,"down"},{0,1,2},{1,1,3},{1,0,3}}
    for _,h in ipairs(H) do
        if get(h[1],0,h[2])~="minecraft:hopper" or ts(h[1],0,h[2]).facing~=h[3] then fail("hopper@"..h[1]..",0,"..h[2].."="..tostring(get(h[1],0,h[2])).."/"..tostring(ts(h[1],0,h[2]).facing)) end
    end
    if get(0,-1,0)~="minecraft:chest" then fail("Kiste unter Trichter fehlt") end
    if afk then
        for y=1,AY+1 do
            if get(0,y,3)~="minecraft:ladder" or ts(0,y,3).facing~=2 or not isSolid(get(0,y,2)) then fail("ladder@0,"..y..",3="..tostring(get(0,y,3))) end
        end
        for x=-1,1 do for z=4,6 do
            local b=get(x,AY,z)
            if not (b and b:find("_slab",1,true) and ts(x,AY,z).type~="top") then fail("plat@"..x..","..z.."="..tostring(b)) end
            if get(x,AY+1,z) or get(x,AY+2,z) then fail("Kopffreiheit@"..x..","..z) end
        end end
        for _,p in ipairs({{1,3},{2,4},{2,5},{2,6},{1,7},{0,7},{-1,7},{-2,6},{-2,5},{-2,4},{-1,3}}) do
            if not isSolid(get(p[1],AY+1,p[2])) then fail("rail@"..p[1]..","..p[2].."="..tostring(get(p[1],AY+1,p[2]))) end
        end
        for _,p in ipairs({{-2,5},{2,5}}) do if get(p[1],AY+2,p[2])~="minecraft:torch" then fail("torch@"..p[1]..","..p[2]) end end
    end
    return bad,table.concat(why," ")
end
local EXTRA={{"minecraft:hopper",4},{"minecraft:ladder",64},{"minecraft:ladder",64},{"minecraft:torch",4}}
local function withExtra(stacks) for _,e in ipairs(EXTRA) do stacks[#stacks+1]=e end;return stacks end
local function parked(S) return S.p.x==2 and S.p.y==0 and S.p.z==0 and S.p.dir==0 end

local function std(stacks,cobble,slabs,traps,coal)
    for _=1,traps do stacks[#stacks+1]={"minecraft:oak_trapdoor",64} end
    for _=1,slabs do stacks[#stacks+1]={"minecraft:cobblestone_slab",64} end
    for _=1,cobble do stacks[#stacks+1]={"minecraft:cobblestone",64} end
    for _=1,coal or 2 do stacks[#stacks+1]={"minecraft:coal",64} end
    return withExtra(stacks)
end
local function result(S) return load("return "..(S.files["/toast_build_state"] or "{}"))() end
local function why(S) return tostring(S.last and S.last.status).." "..tostring(S.last and S.last.fault).." "..tail(S) end

print("B1 Creeper-Mobfarm, 1 Etage, 32 hoch, im Freien, AFK-Platz; Materialkiste bunt gemischt")
local S=Sim.new({config=cfg('{floors=1,height=32,creeperOnly=true,afk=true,fuelTarget=2000,radioTimeout=0}'),default=false,
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.build.v1"
local stacks={{"minecraft:oak_trapdoor",64},{"minecraft:dirt",3},{"minecraft:redstone_block",64},{"minecraft:spruce_trapdoor",64},{"minecraft:cobblestone_slab",64}}
for _=1,4 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
stacks[#stacks+1]={"minecraft:hopper",2}
for _=1,8 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
stacks[#stacks+1]={"minecraft:hopper",2}
for _=1,8 do stacks[#stacks+1]={"minecraft:cobblestone_slab",64} end
for _=1,6 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
stacks[#stacks+1]={"minecraft:oak_trapdoor",64};stacks[#stacks+1]={"minecraft:birch_trapdoor",64};stacks[#stacks+1]={"minecraft:ladder",16};stacks[#stacks+1]={"minecraft:torch",8}
stacks[#stacks+1]={"minecraft:coal",64}
setup(S,stacks)
Sim.env=envWith
Sim.run(S,40000)
Sim.env=orig
local st=result(S)
local bad,w1=verify(S,1,32,true,true)
check("fertig",st.done==true,why(S))
check("Bau stimmt Block fuer Block (Farm, Schacht 2x2, Trichter, Leiter, AFK-Platz)",bad==0,bad.." "..w1)
check("4 Wasserquellen (2 Spuren)",(S.waterPlaced or 0)==4,S.waterPlaced)
check("Turtle parkt neben dem Schacht, schaut nach vorne",parked(S),S.p.x..","..S.p.y..","..S.p.z.." dir "..S.p.dir)
check("dort ist jetzt die Basis",st.x==0 and st.y==0 and st.z==0 and st.dir==0,tostring(st.x)..","..tostring(st.y)..","..tostring(st.z))
check("Materialkiste umsortiert (Kisten-Peripherie)",(S.pushes or 0)>0,S.pushes)
check("bleibt Bauer (keine Mob-Turtle mehr)",(load(S.files["/toast.config.lua"])()).job=="build")
print("    Zuege: "..S.moves)

print("B2 2 Etagen, 40 hoch, Gelaende-Modus, Wasser/Lava im Weg, Material knapp -> wartet, dann weiter")
S=Sim.new({config=cfg('{floors=2,height=40,creeperOnly=false,inTerrain=true,afk=true,fuelTarget=2000,radioTimeout=0}'),default=false,
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end},
        {t=4000,fn=function(S)
            for _=1,40 do for i=1,S.supplySize do if not S.supply[i] then S.supply[i]={name="minecraft:cobblestone",count=64};break end end end
            S.refilled=true end}}})
S.protocol="toast.build.v1"
stacks={{"minecraft:coal",64},{"minecraft:coal",64},{"minecraft:redstone_block",64},{"minecraft:spruce_trapdoor",64}}
for _=1,8 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
for _=1,10 do stacks[#stacks+1]={"minecraft:cobblestone_slab",64} end
withExtra(stacks)
setup(S,stacks)
S.world[S.key(3,-42,3)]="minecraft:water";S.world[S.key(-2,-45,5)]="minecraft:lava";S.world[S.key(4,-44,-3)]="minecraft:water"
local sawMissing=false
Sim.env=function(S2) local G=envWith(S2)
    local send=G.rednet.send
    G.rednet.send=function(id,msg,p) if type(msg)=="table" and tostring(msg.status):find("Baumaterial fehlt",1,true) then sawMissing=true end;return send(id,msg,p) end
    return G end
Sim.run(S,80000)
Sim.env=orig
st=result(S)
bad,w1=verify(S,2,40,false,true)
check("meldet 'Baumaterial fehlt' und wartet",sawMissing)
check("nach dem Nachfuellen fertig",st.done==true and S.refilled,why(S))
check("Bau stimmt (Gelaende freigeraeumt, Wasser/Lava weg)",bad==0,bad.." "..w1)
check("8 Wasserquellen",(S.waterPlaced or 0)==8,S.waterPlaced)
check("Turtle parkt",parked(S),S.p.x..","..S.p.y..","..S.p.z)
print("    Zuege: "..S.moves)

print("B3 Absturz mitten im Bau (in den Etagen und beim AFK-Platz): macht weiter, Ergebnis stimmt")
for _,crash in ipairs({900,2300}) do
    S=Sim.new({config=cfg('{floors=1,height=32,creeperOnly=true,afk=true,fuelTarget=2000,radioTimeout=0}'),default=false,
        fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
    S.protocol="toast.build.v1"
    setup(S,std({{"minecraft:redstone_block",64},{"minecraft:water_bucket",1},{"minecraft:water_bucket",1},{"minecraft:water_bucket",1},{"minecraft:water_bucket",1}},14,9,4))
    S.crashAtMove=crash
    Sim.env=envWith
    Sim.run(S,40000)
    Sim.env=orig
    st=result(S)
    bad,w1=verify(S,1,32,true,true)
    check("fertig trotz Absturz bei Zug "..crash,st.done==true,why(S))
    check("Bau stimmt",bad==0,bad.." "..w1)
end

print("B4 Ohne AFK-Platz, im Gelaende (alles Stein): graebt sich frei")
S=Sim.new({config=cfg('{floors=1,height=32,creeperOnly=true,inTerrain=true,afk=false,fuelTarget=2000,radioTimeout=0}'),
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.build.v1"
setup(S,std({{"minecraft:redstone_block",64},{"minecraft:water_bucket",1},{"minecraft:water_bucket",1},{"minecraft:water_bucket",1},{"minecraft:water_bucket",1}},4,9,4))
Sim.env=envWith
Sim.run(S,60000)
Sim.env=orig
st=result(S)
bad,w1=verify(S,1,32,true,false)
check("fertig",st.done==true,why(S))
check("Bau stimmt (Raeume frei gegraben)",bad==0,bad.." "..w1)
check("keine Leiter gebaut",S.block(0,-1,3)~="minecraft:ladder")
print("    Zuege: "..S.moves)

print("B5 Wie gewuenscht: 128 hoch, 2 Etagen, im Freien (3D-Drucker)")
S=Sim.new({config=cfg('{floors=2,height=128,creeperOnly=true,inTerrain=false,afk=true,fuelTarget=3000,radioTimeout=0}'),default=false,
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.build.v1"
stacks={{"minecraft:redstone_block",64}}
for _=1,8 do stacks[#stacks+1]={"minecraft:water_bucket",1} end
setup(S,std(stacks,33,10,7,4))
Sim.env=envWith
Sim.run(S,200000)
Sim.env=orig
st=result(S)
bad,w1=verify(S,2,128,true,true)
check("fertig",st.done==true,why(S))
check("Bau stimmt Block fuer Block",bad==0,bad.." "..w1)
check("Turtle parkt",parked(S),S.p.x..","..S.p.y..","..S.p.z)
print("    Zuege (= Fuel) 128 hoch, 2 Etagen + AFK-Platz: "..S.moves)
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
