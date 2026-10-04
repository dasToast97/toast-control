package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local function cfg(extra)
    return [[return {role="auto",job="mining",controllerId=4,label="Test",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
    mine={length=6,height=3,tunnels=1,gap=1,fuelTarget=200,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={},]]..extra..[[}}]]
end
-- echtes CC: Bloecke lassen sich in Wasser/Lava setzen
local function liquidPlace(S)
    local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
    local function placer(dy,fwd) return function()
        local p=S.p;local x,y,z=p.x,p.y+dy,p.z
        if fwd then x,z=x+DX[p.dir],z+DZ[p.dir] end
        local b=S.block(x,y,z)
        if b and not b:find("water",1,true) and not b:find("lava",1,true) then return false end
        local it=S.inv[S.sel];if not it then return false end
        it.count=it.count-1;if it.count==0 then S.inv[S.sel]=nil end
        S.world[S.key(x,y,z)]=it.name;return true end end
    S.turtle.place=placer(0,true);S.turtle.placeUp=placer(-1,false);S.turtle.placeDown=placer(1,false)
end
print("X1 Mine: Gang trockenlegen, Lava an der Wand zubauen, Diamant oben stehen lassen")
local S=Sim.new({config=cfg('drain=true,seal="liquids",keepOres="diamond"'),actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mine.v1";liquidPlace(S)
S.inv[4]={name="minecraft:cobblestone",count=16}
S.world[S.key(0,-1,2)]="minecraft:water"          -- Wasser mitten in der Fahrspur
S.world[S.key(1,-1,4)]="minecraft:lava"           -- Lava in der Seitenwand
S.world[S.key(-1,-1,4)]="minecraft:lava"
S.world[S.key(0,-2,3)]="minecraft:diamond_ore"    -- Diamant oben
S.world[S.key(0,-1,5)]="minecraft:iron_ore"       -- Eisen in der Fahrspur
Sim.run(S,600)
local st=load("return "..S.files["/toast_mining_state"])()
check("Mine fertig",st.next and st.next>6 and S.p.x==0 and S.p.z==0,tostring(st.next).." "..tail(S))
check("Wasser im Gang entfernt",S.world[S.key(0,-1,2)]==false,S.world[S.key(0,-1,2)])
check("Lava an beiden Waenden zugebaut",S.world[S.key(1,-1,4)]=="minecraft:cobblestone" and S.world[S.key(-1,-1,4)]=="minecraft:cobblestone",
    tostring(S.world[S.key(1,-1,4)]).." / "..tostring(S.world[S.key(-1,-1,4)]))
check("Diamant oben steht noch",S.world[S.key(0,-2,3)]=="minecraft:diamond_ore")
check("Eisen in der Fahrspur abgebaut",S.world[S.key(0,-1,5)]==false)
check("Zaehler",(st.drained or 0)>=1 and (st.sealed or 0)>=2 and (st.keptOres or 0)>=1,
    tostring(st.drained).."/"..tostring(st.sealed).."/"..tostring(st.keptOres))
check("Status zeigt es",S.last and S.last.keptOres and S.last.keptOres>=1)
print("X2 Ohne Optionen wie bisher (Erze werden abgebaut)")
S=Sim.new({config=cfg(''),actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mine.v1"
S.world[S.key(0,-2,3)]="minecraft:diamond_ore"
Sim.run(S,600)
check("Diamant abgebaut",S.world[S.key(0,-2,3)]==false)
print("X3 Erz mitten in der Fahrspur: stehen lassen, drumherum fahren")
S=Sim.new({config=cfg('keepOres="diamond"'),actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mine.v1"
S.world[S.key(0,-1,3)]="minecraft:diamond_ore"     -- in der Fahrspur (mittlere Reihe)
Sim.run(S,600)
st=load("return "..S.files["/toast_mining_state"])()
local missing=0
for z=1,6 do for y=0,-2,-1 do if not (z==3 and y==-1) and S.world[S.key(0,y,z)]~=false then missing=missing+1 end end end
check("Mine fertig + zu Hause",st.next and st.next>6 and S.p.x==0 and S.p.z==0 and S.p.y==0,tostring(st.next).." "..tail(S))
check("Diamant in der Fahrspur steht noch",S.world[S.key(0,-1,3)]=="minecraft:diamond_ore")
check("alles andere ausgehoben (auch ueber/unter dem Erz)",missing==0,missing)
check("kein Fehler",not (S.last and S.last.fault),S.last and S.last.fault)
print("X4 Erz am Ende des Gangs (Rand): dort darf sie es abbauen")
S=Sim.new({config=cfg('keepOres="diamond"'),actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}}})
S.protocol="toast.mine.v1"
S.world[S.key(0,-1,6)]="minecraft:diamond_ore"
Sim.run(S,600)
st=load("return "..S.files["/toast_mining_state"])()
check("Mine fertig",st.next and st.next>6 and S.p.x==0 and S.p.z==0,tostring(st.next).." "..tail(S))
check("Rand-Erz abgebaut",S.world[S.key(0,-1,6)]==false)
print("X5 Zwei Gaenge, Erz im Rueckweg-Gang: Heimweg faehrt drumherum")
S=Sim.new({config=(cfg('keepOres="all"'):gsub("tunnels=1","tunnels=2")),actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
S.world[S.key(0,-1,2)]="minecraft:emerald_ore";S.world[S.key(2,-1,4)]="minecraft:gold_ore"
Sim.run(S,900)
st=load("return "..S.files["/toast_mining_state"])()
check("fertig + zu Hause",st.next and st.next>12 and S.p.x==0 and S.p.z==0 and S.p.y==0,tostring(st.next).." "..tail(S))
check("beide Erze stehen",S.world[S.key(0,-1,2)]=="minecraft:emerald_ore" and S.world[S.key(2,-1,4)]=="minecraft:gold_ore")

print("X6 Viele Erze verstreut (3 Gaenge x 15, Hoehe 3): fertig, kaum Erz abgebaut")
S=Sim.new({config=(cfg('keepOres="all"'):gsub("tunnels=1","tunnels=3"):gsub("length=6","length=15"):gsub("gap=1","gap=2")),
    fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
local ores,n=0,0
for x=0,6,3 do for z=1,15 do for y=0,-2,-1 do n=n+1
    if (x*7+z*13+y*5)%9==0 then S.world[S.key(x,y,z)]="minecraft:iron_ore";ores=ores+1 end end end end
Sim.run(S,4000)
st=load("return "..S.files["/toast_mining_state"])()
local left=0;for x=0,6,3 do for z=1,15 do for y=0,-2,-1 do if S.world[S.key(x,y,z)]=="minecraft:iron_ore" then left=left+1 end end end end
print(("    %d Erze gesetzt, %d stehen noch, %d am Rand abgebaut"):format(ores,left,st.oresMined or 0))
check("fertig + zu Hause",st.next and st.next>3*15 and S.p.x==0 and S.p.z==0 and S.p.y==0 and not (S.last and S.last.fault),tostring(st.next).." "..tostring(S.last and S.last.fault).." "..tail(S))
check("die meisten Erze stehen",left>=ores-(st.oresMined or 0) and left>=ores*0.7,left.."/"..ores)

print("X7 Sehr viele Erze (jedes 4. Feld): faehrt trotzdem fertig und heim")
S=Sim.new({config=(cfg('keepOres="all"'):gsub("tunnels=1","tunnels=3"):gsub("length=6","length=15"):gsub("gap=1","gap=2")),
    fuel=30000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
ores=0
for x=0,6,3 do for z=1,15 do for y=0,-2,-1 do
    if (x*5+z*7+y*3)%4==0 then S.world[S.key(x,y,z)]="minecraft:copper_ore";ores=ores+1 end end end end
Sim.run(S,8000)
st=load("return "..S.files["/toast_mining_state"])()
left=0;for x=0,6,3 do for z=1,15 do for y=0,-2,-1 do if S.world[S.key(x,y,z)]=="minecraft:copper_ore" then left=left+1 end end end end
print(("    %d Erze gesetzt, %d stehen noch, %d notgedrungen abgebaut"):format(ores,left,st.oresMined or 0))
check("fertig + zu Hause",st.next and st.next>3*15 and S.p.x==0 and S.p.z==0 and S.p.y==0 and not (S.last and S.last.fault),tostring(st.next).." "..tostring(S.last and S.last.fault).." "..tail(S))
check("Zaehlung stimmt",left+(st.oresMined or 0)==ores,left.."+"..tostring(st.oresMined).." vs "..ores)

print("X8 Kohle-Adern hintereinander in der Fahrspur: alle stehen lassen, Rest komplett frei")
local VEINS={
    {"2 hintereinander",{{0,-1,4},{0,-1,5}}},
    {"3 hintereinander",{{0,-1,3},{0,-1,4},{0,-1,5}}},
    {"2 hintereinander + oben",{{0,-1,4},{0,-1,5},{0,-2,4},{0,-2,5}}},
    {"2 hintereinander + unten + Seite",{{0,-1,4},{0,-1,5},{0,0,5},{1,-1,4}}},
    {"2 Paare mit Luecke",{{0,-1,3},{0,-1,4},{0,-1,6},{0,-1,7}}},
}
for _,v in ipairs(VEINS) do
    S=Sim.new({config=(cfg('keepOres="all",useCoal=true'):gsub("length=6","length=10")),actions={{t=2,fn=function(S)Sim.cmd(S,"once",12)end}}})
    S.protocol="toast.mine.v1"
    local ore={}
    for _,p in ipairs(v[2]) do S.world[S.key(p[1],p[2],p[3])]="minecraft:coal_ore";ore[S.key(p[1],p[2],p[3])]=true end
    Sim.run(S,900)
    st=load("return "..S.files["/toast_mining_state"])()
    local left,rest=0,0
    for _,p in ipairs(v[2]) do if S.world[S.key(p[1],p[2],p[3])]=="minecraft:coal_ore" then left=left+1 end end
    for z=1,10 do for y=0,-2,-1 do if not ore[S.key(0,y,z)] and S.world[S.key(0,y,z)]~=false then rest=rest+1 end end end
    check(v[1]..": Kohle steht ("..left.."/"..#v[2]..")",left==#v[2],left)
    check(v[1]..": Gang sonst frei, fertig, zu Hause",rest==0 and st.next and st.next>10 and S.p.x==0 and S.p.y==0 and S.p.z==0,
        rest.." "..tostring(st.next).." "..tail(S))
end

print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
