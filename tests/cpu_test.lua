package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 6)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local function cfg(prog,clear)
    return [[return {role="turtle",job="cpu",controllerId=4,name="CPU",
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},cpu={program="]]..prog..[[",clear=]]..tostring(clear)..[[,fuelTarget=2000,radioTimeout=0}}]]
end
-- kleiner Testplan (Plan-Koordinaten: x nach rechts, z nach vorne, y hoch; y0 = Boden)
local PLAN=[[return {version=7,w=8,d=6,h=7,cols={"nIMM0","nIMM1"},
layers={
 [1]={[0]="3s",[2]="sdE",[4]="4.s.s"},
 [2]={[0]="3d",[2]="t",[3]="2.N"},
 [3]={[0]=".l",[4]="5.s.s"},
 [4]={},[5]={},[6]={[5]="b"},[7]={},
},
prog={ {0,0,5,4,"E"}, {0,1,7,4,"W"} },
lamps={},buttons={},stats={}}
]]
-- Sim: y positiv = unten; Turtle-x ist gespiegelt (x lokal = -x Sim)
local function simKey(S,px,py,pz) return S.key(-px,-(py-1),pz+2) end
local function setup(S,stacks)
    local K=S.key
    S.world[K(0,-1,0)]=false
    S.world[K(0,0,-1)]="minecraft:chest"
    S.supply={};for i,s in ipairs(stacks) do S.supply[i]={name=s[1],count=s[2]} end
    S.supplySize=54
    local T=S.turtle
    local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
    local function facingSupply() return S.p.x+DX[S.p.dir]==0 and S.p.z+DZ[S.p.dir]==-1 and S.p.y==0 end
    T.suck=function(n)
        if not facingSupply() or S.inv[S.sel] then return false end
        for i=1,S.supplySize do local s=S.supply[i]
            if s then local k=math.min(n or 64,s.count);S.inv[S.sel]={name=s.name,count=k};s.count=s.count-k
                if s.count==0 then S.supply[i]=nil end;return true end end
        return false
    end
    T.drop=function()
        local it=S.inv[S.sel];if not it or not facingSupply() then return false end
        for i=1,S.supplySize do if not S.supply[i] then S.supply[i]={name=it.name,count=it.count};S.inv[S.sel]=nil;return true end end
        return false
    end
    S.supplyInv={size=function() return S.supplySize end,
        list=function() local t={};for i=1,S.supplySize do local s=S.supply[i];if s then t[i]={name=s.name,count=s.count} end end;return t end,
        pushItems=function(to,from,limit,toSlot)
            local s=S.supply[from];if not s or S.supply[toSlot] then return 0 end
            S.supply[toSlot]=s;S.supply[from]=nil;return s.count end}
    S.repdir={}
    local pd=T.placeDown
    T.placeDown=function()
        local it=S.inv[S.sel]
        local x,y,z=S.p.x,S.p.y+1,S.p.z
        local b=S.block(x,y,z)
        if b and (b:find("water",1,true) or b:find("lava",1,true)) and it and it.name~="minecraft:water_bucket" then
            it.count=it.count-1;local nm=it.name;if it.count==0 then S.inv[S.sel]=nil end
            S.world[K(x,y,z)]=nm;return true
        end
        local nm=it and it.name
        local ok=pd()
        if ok and nm=="minecraft:repeater" then S.repdir[K(x,y,z)]=S.p.dir end
        if ok and nm=="minecraft:redstone" then S.world[K(x,y,z)]="minecraft:redstone_wire" end
        return ok
    end
    T.digUp=T.digUp or function() return false end
    -- echtes Spiel: Bloecke lassen sich in Wasser setzen
    local pf=T.place
    T.place=function()
        local DX,DZ={[0]=0,1,0,-1},{[0]=1,0,-1,0}
        local x,y,z=S.p.x+DX[S.p.dir],S.p.y,S.p.z+DZ[S.p.dir]
        local b=S.block(x,y,z);local it=S.inv[S.sel]
        if b and (b:find("water",1,true) or b:find("lava",1,true)) and it then
            it.count=it.count-1;local nm=it.name;if it.count==0 then S.inv[S.sel]=nil end
            S.world[K(x,y,z)]=nm;return true
        end
        return pf()
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
local NAMES={s="stone",d="minecraft:redstone_wire",t="minecraft:redstone_torch",l="minecraft:redstone_lamp",
    b="minecraft:stone_button",E="minecraft:repeater",W="minecraft:repeater",N="minecraft:repeater",S="minecraft:repeater"}
-- erwartete Sim-Richtung: Ausgang lokal +x (E) = Sim -x (dir 3)
local SIMDIR={E=3,W=1,N=2,S=0}
local function decode(s)local out={};local x=0
    for num,ch in s:gmatch("(%d*)(%D)") do local n=tonumber(num) or 1;if ch~="." then for k=0,n-1 do out[#out+1]={x+k,ch} end end;x=x+n end
    return out end
local function verify(S,plan,taps)
    local bad,why=0,{}
    for y,rows in pairs(plan.layers) do for z,row in pairs(rows) do for _,c in ipairs(decode(row)) do
        local k=simKey(S,c[1],y,z);local b=S.world[k]
        local want=NAMES[c[2]]
        local ok=b and (b==want or (c[2]=="s" and (b:find("stone",1,true) or b:find("cobble",1,true))))
        if ok and SIMDIR[c[2]] and S.repdir[k]~=SIMDIR[c[2]] then ok=false end
        if not ok then bad=bad+1;if #why<5 then why[#why+1]=c[2].."@"..c[1]..","..y..","..z.."="..tostring(b) end end
    end end end
    -- Programm-Abgriffe
    for i,p in ipairs(plan.prog) do
        local k1=simKey(S,p[3],1,p[4]);local k2=simKey(S,p[3],2,p[4])
        local tap=taps[i]
        local isTap=S.world[k2]=="minecraft:repeater" and S.repdir[k2]==SIMDIR[p[5]]
        if tap~=isTap then bad=bad+1;why[#why+1]="Abgriff "..i.." soll "..tostring(tap) end
        if tap and not (S.world[k1] and S.world[k1]~=false) then bad=bad+1;why[#why+1]="Stuetze "..i end
    end
    return bad,table.concat(why," ")
end
local function mk(prog,clear,default)
    local S=Sim.new({config=cfg(prog,clear),default=default,fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
    S.protocol="toast.cpu.v1"
    S.files["/toast/cpu_plan.lua"]=PLAN
    local stacks={{"minecraft:coal",64},{"minecraft:redstone",64},{"minecraft:redstone_torch",16},{"minecraft:repeater",16},
        {"minecraft:redstone_lamp",8},{"minecraft:stone_button",4}}
    for _=1,6 do stacks[#stacks+1]={"minecraft:cobblestone",64} end
    setup(S,stacks)
    return S
end
local plan=load(PLAN)()

print("C1 Begradigen (Huegel, Wasser, Loch im Boden) + bauen + Programm")
local S=mk("LDI 1",true,false)
-- Boden auf Sim-y 1 (lokal -1), Huegel/Wasser im Bauplatz
for x=-12,2 do for z=-2,10 do S.world[S.key(x,1,z)]="minecraft:grass_block" end end
S.world[S.key(0,1,0)]="minecraft:chest"
for y=-6,0 do S.world[S.key(-3,y,4)]="minecraft:oak_log" end
S.world[S.key(-1,0,3)]="minecraft:water"
S.world[S.key(-5,1,5)]=false          -- Loch im Boden
S.world[S.key(-2,-3,6)]="minecraft:dirt"
Sim.env=envWith
Sim.run(S,40000)
Sim.env=orig
local st=load("return "..(S.files["/toast_cpu_state"] or "{}"))()
-- Programm "LDI 1": Wort 0 IMM=1 -> nIMM0=0 (kein Abgriff), nIMM1=1 (Abgriff)
local bad,why=verify(S,plan,{false,true})
check("fertig",st.done==true,tostring(S.last and S.last.status).." "..tostring(S.last and S.last.fault).." "..tail(S))
check("Bau stimmt Block fuer Block (inkl. Repeater-Richtung)",bad==0,bad.." "..why)
local clean=true
for y=0,7 do local b=S.world[S.key(-3,-y,4)];if b=="minecraft:oak_log" then clean=false end end
check("Baum im Bauplatz weg",clean)
check("Loch im Boden gefuellt",S.world[S.key(-5,1,5)] and S.world[S.key(-5,1,5)]~=false,tostring(S.world[S.key(-5,1,5)]))
check("Wasser weg",S.world[S.key(-1,0,3)]~="minecraft:water",tostring(S.world[S.key(-1,0,3)]))
check("zurueck an der Basis",S.p.x==0 and S.p.y==0 and S.p.z==0,S.p.x..","..S.p.y..","..S.p.z)

print("C2 Neues Programm: nur Speicher umbauen")
local cfgfile=cfg("LDI 2",true)
S.files["/toast.config.lua"]=cfgfile
S.actions={{t=S.T+2,fn=function(S)Sim.cmd(S,"start",11)end}}
local placedBefore=st.placed
Sim.env=envWith
Sim.run(S,S.T+20000)
Sim.env=orig
st=load("return "..(S.files["/toast_cpu_state"] or "{}"))()
bad,why=verify(S,plan,{true,false})      -- IMM=2: nIMM0=1 (Abgriff), nIMM1=0
check("umprogrammiert",bad==0 and st.done==true,bad.." "..why.." "..tail(S))

print("C3 Ohne Begradigen")
S=mk("LDI 1",false,false)
for x=-12,2 do for z=-2,10 do S.world[S.key(x,1,z)]="minecraft:stone" end end
S.world[S.key(0,1,0)]="minecraft:chest"
Sim.env=envWith
Sim.run(S,30000)
Sim.env=orig
st=load("return "..(S.files["/toast_cpu_state"] or "{}"))()
bad,why=verify(S,plan,{false,true})
check("fertig ohne Begradigen",st.done==true and bad==0,bad.." "..why.." "..tail(S))
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
