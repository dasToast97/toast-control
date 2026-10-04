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
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
