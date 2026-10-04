package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function cfg(dig)
    return [[return {role="turtle",job="dig",controllerId=4,name="Aushub Test",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},dig=]]..dig..[[}]]
end
local function state(S)local s=S.files["/toast_dig_state"];return s and load("return "..s)() or {} end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
-- echtes CC: Bloecke lassen sich in Wasser/Lava setzen (ersetzt die Fluessigkeit)
local function liquidPlace(S)
    local T=S.turtle
    local function placer(dy,fwd)
        return function()
            local p=S.p;local x,y,z=p.x,p.y+dy,p.z
            if fwd then local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0};x,z=x+DX[p.dir],z+DZ[p.dir] end
            local b=S.block(x,y,z)
            if b and not b:find("water",1,true) and not b:find("lava",1,true) then return false end
            local it=S.inv[S.sel];if not it then return false end
            it.count=it.count-1;if it.count==0 then S.inv[S.sel]=nil end
            S.world[S.key(x,y,z)]=it.name;S.placed=(S.placed or 0)+1;return true
        end
    end
    T.place=placer(0,true);T.placeUp=placer(-1,false);T.placeDown=placer(1,false)
end
local function new(dig,extra)
    local S=Sim.new({config=cfg(dig),actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},fuel=4000})
    S.protocol="toast.dig.v1";liquidPlace(S)
    if extra then extra(S) end
    return S
end
-- Dug-Set: Zellen (sim-Koordinaten) die am Ende Luft sind
local function airCells(S)
    local n,list=0,{}
    for k,v in pairs(S.world) do if v==false and k~=S.key(0,0,0) then n=n+1;list[k]=true end end
    return n,list
end

print("D1 Quader 3x4x3 nach unten (Schacht/Raum)")
local S=new('{shape="room",direction="down",width=3,length=4,height=3,side="right",seal="off",drain=false,keepOres="",useCoal=true,fuelTarget=500,freeSlots=2,radioTimeout=0,protectedBlocks={}}')
Sim.run(S,3000)
local st=state(S)
local n,air=airCells(S)
check("fertig",st.done==true,tail(S))
check("36 Bloecke ausgehoben",n==36,n)
local okShape=true
for x=0,2 do for z=1,4 do for y=0,2 do if not air[S.key(x,y,z)] then okShape=false end end end end
check("genau der Quader (rechts, nach unten)",okShape)
check("wieder an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0 and st.x==0 and st.y==0,S.p.x..","..S.p.y..","..S.p.z)
check("abgeladen",S.chestBelow>0,S.chestBelow)

print("D2 Kugel D5 nach oben, links")
S=new('{shape="sphere",direction="up",width=5,length=1,height=1,side="left",seal="off",drain=false,keepOres="",useCoal=true,fuelTarget=800,freeSlots=2,radioTimeout=0,protectedBlocks={}}')
Sim.run(S,6000)
st=state(S)
local exp=0
for x=0,4 do for z=1,5 do for i=0,4 do
    local dx,dy,dz=x-2,i-2,z-3
    if dx*dx+dy*dy+dz*dz<=6.25 then exp=exp+1
        if not airCells and true then end
    end
end end end
n,air=airCells(S)
local inside,outside=0,0
for k in pairs(air) do
    local x,y,z=k:match("(-?%d+),(-?%d+),(-?%d+)");x,y,z=-tonumber(x),-tonumber(y),tonumber(z)
    local dx,dy,dz=x-2,y-2,z-3
    if x>=0 and dx*dx+dy*dy+dz*dz<=6.25 then inside=inside+1 else outside=outside+1 end
end
check("fertig",st.done==true,tail(S))
check("ganze Kugel ("..exp..")",inside==exp,inside)
check("nur kurzer Zugang ausserhalb",outside<=4,outside)
check("links + oben",air[S.key(-2,-2,3)]==true and air[S.key(2,-2,3)]==nil)
check("zurueck an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0)

print("D3 Erze schonen: Diamant bleibt stehen, Eisen wird abgebaut")
S=new('{shape="room",direction="down",width=3,length=4,height=3,side="right",seal="off",drain=false,keepOres="diamond",useCoal=true,fuelTarget=500,freeSlots=2,radioTimeout=0,protectedBlocks={}}',
    function(S)
        S.world[S.key(1,1,2)]="minecraft:diamond_ore"
        S.world[S.key(0,0,3)]="minecraft:deepslate_diamond_ore"
        S.world[S.key(2,2,4)]="minecraft:iron_ore"
    end)
Sim.run(S,3000)
st=state(S)
n,air=airCells(S)
check("fertig",st.done==true,tail(S))
check("2 Diamanterze stehen noch",S.world[S.key(1,1,2)]=="minecraft:diamond_ore" and S.world[S.key(0,0,3)]=="minecraft:deepslate_diamond_ore")
check("Eisenerz abgebaut",air[S.key(2,2,4)]==true)
check("Rest drumherum ausgehoben (34)",n==34,n)
check("2 Erze gezaehlt",st.kept==2,st.kept)

print("D4 Unter Wasser: Waende zubauen + Raum trockenlegen")
S=new('{shape="room",direction="down",width=3,length=3,height=2,side="right",seal="liquids",drain=true,keepOres="",useCoal=true,fuelTarget=500,freeSlots=2,radioTimeout=0,protectedBlocks={}}',
    function(S)
        for z=0,5 do for y=-1,3 do S.world[S.key(3,y,z)]="minecraft:water" end end   -- See rechts daneben
        S.world[S.key(1,1,2)]="minecraft:water"                                      -- Wasser im Raum
        S.world[S.key(1,-1,2)]="minecraft:lava"                                     -- Lava ueber der Decke
        S.inv[3]={name="minecraft:cobblestone",count=32}
    end)
Sim.run(S,3000)
st=state(S)
local wetWall=0;for z=1,3 do for y=0,1 do if S.world[S.key(3,y,z)]=="minecraft:water" then wetWall=wetWall+1 end end end
local liquidsInside=0
for x=0,2 do for z=1,3 do for y=0,1 do local b=S.world[S.key(x,y,z)];if b and (b:find("water") or b:find("lava")) then liquidsInside=liquidsInside+1 end end end end
check("fertig",st.done==true,tail(S))
check("Wasser an der Wand zugebaut",wetWall==0,wetWall)
check("Lava ueber der Decke zugebaut",S.world[S.key(1,-1,2)]=="minecraft:cobblestone",S.world[S.key(1,-1,2)])
check("Raum trocken",liquidsInside==0,liquidsInside)
check("Zaehler",(st.sealed or 0)>=7 and (st.drained or 0)>=1,tostring(st.sealed).."/"..tostring(st.drained))

print("D5 Absturz mittendrin -> macht weiter, keine Luecke")
S=new('{shape="cylinder",direction="down",width=5,length=1,height=3,side="right",seal="off",drain=false,keepOres="",useCoal=true,fuelTarget=800,freeSlots=2,radioTimeout=0,protectedBlocks={}}')
S.crashAtMove=40
Sim.run(S,6000)
st=state(S)
n,air=airCells(S)
local cyl=0;for x=0,4 do for z=1,5 do local dx,dz=x-2,z-3;if dx*dx+dz*dz<=6.25 then cyl=cyl+1 end end end
local missing=0
for x=0,4 do for z=1,5 do local dx,dz=x-2,z-3;if dx*dx+dz*dz<=6.25 then for y=0,2 do if not air[S.key(x,y,z)] then missing=missing+1 end end end end end
check("Absturz passiert",S.crashAtMove==nil)
check("fertig nach Neustart",st.done==true,tail(S))
check("Zylinder komplett ("..(cyl*3)..")",missing==0,missing)
check("an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0)

print("D6 Schale D5 nach unten, alles dicht (Hoehle daneben), volles Inventar")
S=new('{shape="dome",direction="down",width=5,length=1,height=1,side="right",seal="all",drain=false,keepOres="all",useCoal=true,fuelTarget=800,freeSlots=2,radioTimeout=0,protectedBlocks={}}',
    function(S)
        S.world[S.key(5,0,3)]=false;S.world[S.key(5,1,3)]=false                     -- Hoehle neben der Wand
        S.world[S.key(2,1,3)]="minecraft:gold_ore"
        for i=4,16 do S.inv[i]={name="minecraft:dirt",count=64} end
    end)
Sim.run(S,8000)
st=state(S)
check("fertig",st.done==true,tail(S))
check("Hoehle an der Wand zugebaut",S.world[S.key(5,0,3)]~=false and S.world[S.key(5,1,3)]~=false)
check("Golderz steht",S.world[S.key(2,1,3)]=="minecraft:gold_ore")
check("unterwegs abgeladen (Inventar war voll)",S.chestBelow>=13*64-200,S.chestBelow)
check("an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0)

print("D7 Waende, Boden und Decke aus Steinziegeln (aus der Kiste oben)")
local function bricks(S)
    local n=0;for x=-1,3 do for y=-1,2 do for z=0,4 do if S.world[S.key(x,y,z)]=="minecraft:stone_bricks" then n=n+1 end end end end
    return n
end
S=new('{shape="room",direction="down",width=3,length=3,height=2,side="right",seal="off",drain=false,keepOres="",wallBlock="minecraft:stone_bricks",lineWalls=true,lineFloor=true,lineCeiling=true,wallStock=256,useCoal=true,fuelTarget=500,freeSlots=2,radioTimeout=0,protectedBlocks={}}',
    function(S) S.top={{name="minecraft:coal",count=16},{name="minecraft:stone_bricks",count=64}};S.topN=2 end)
Sim.run(S,4000)
st=state(S)
check("fertig",st.done==true,tail(S))
check("40 Flaechen verkleidet",bricks(S)==40 and st.lined==40,bricks(S).." / "..tostring(st.lined))
check("Ausgabekiste unter der Basis nicht abgebaut",S.world[S.key(0,1,0)]=="minecraft:chest")
check("Kohlekiste oben unberuehrt",S.world[S.key(0,-1,0)]=="minecraft:chest")
local inside=0;for x=0,2 do for z=1,3 do for y=0,1 do if S.world[S.key(x,y,z)]~=false then inside=inside+1 end end end end
check("Raum innen frei",inside==0,inside)
local coalBack=0;for i=1,(S.topN or 0) do local t=S.top[i];if t and t.name=="minecraft:coal" then coalBack=coalBack+t.count end end
check("Kohle zurueck in die Kiste",coalBack==16,coalBack)
check("an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0)

print("D8 Wandblock geht aus -> holt Nachschub, sonst klare Meldung")
S=new('{shape="room",direction="down",width=3,length=3,height=2,side="right",seal="off",drain=false,keepOres="",wallBlock="minecraft:stone_bricks",lineWalls=true,lineFloor=false,lineCeiling=false,wallStock=64,useCoal=true,fuelTarget=500,freeSlots=2,radioTimeout=0,protectedBlocks={}}',
    function(S) S.top={{name="minecraft:stone_bricks",count=10},{name="minecraft:dirt",count=5},{name="minecraft:stone_bricks",count=6}};S.topN=3 end)
Sim.run(S,4000)
st=state(S)
check("16 verbaut, dann Meldung",st.lined==16 and S.last and tostring(S.last.fault):find("Wandblock fehlt",1,true),tostring(st.lined).." "..tostring(S.last and S.last.fault))
check("wartet an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0)
check("Erde zurueck in die Kiste",(function() for i=1,S.topN do local t=S.top[i];if t and t.name=="minecraft:dirt" and t.count==5 then return true end end end)())

print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
