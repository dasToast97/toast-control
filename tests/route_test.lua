package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1;print("  PASS "..n)else fail=fail+1;print("  FAIL "..n.." "..tostring(i))end end
local function cfg(H,L,T,G)return ([[return {role="auto",job="mining",controllerId=4,label="T",autoDiscover=true,autoPairPockets=true,
 devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
 mine={length=%d,height=%d,tunnels=%d,gap=%d,fuelTarget=100,radioTimeout=300,freeSlots=2,digRetries=16,protectedBlocks={}}}]]):format(L,H,T,G)end
local function run(H,L,T,G,file)
  local S=Sim.new({config=cfg(H,L,T,G),mineFile=file,fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
  S.protocol="toast.mine.v1";Sim.run(S,20000)
  local st=load("return "..S.files["/toast_mining_state"])()
  return S,st
end
print(("%-8s %10s %10s %8s"):format("Hoehe","alt Fuel","neu Fuel","Ersparnis"))
for H=1,5 do
  local L,T,G=20,4,2
  local So=run(H,L,T,G,"/home/claude/toast/build/mine_turtle_before_route.lua")
  local S,st=run(H,L,T,G)
  local done=st.next==(H<=3 and L or 2*L)*T+1
  local missing,wall=0,0
  for t=0,T-1 do local x=t*(G+1)
    for z=1,L do for y=0,-(H-1),-1 do if S.world[S.key(x,y,z)]~=false then missing=missing+1 end end end
  end
  -- Waende zwischen den Gaengen (ohne vordere/hintere Querreihe) muessen stehen bleiben
  for t=0,T-2 do for gx=1,G do for z=2,L-1 do for y=0,-(H-1),-1 do
    if S.world[S.key(t*(G+1)+gx,y,z)]==false then wall=wall+1 end end end end end
  print(("%-8s %10d %10d %7d%%"):format(H,So.moves,S.moves,math.floor(100-100*S.moves/So.moves+0.5)))
  check("H="..H.." fertig, zu Hause",done and S.p.x==0 and S.p.y==0 and S.p.z==0,st.next.." "..S.p.x..","..S.p.y..","..S.p.z)
  check("H="..H.." alle Gangbloecke abgebaut",missing==0,missing)
  check("H="..H.." Waende stehen",wall==0,wall)
  check("H="..H.." Beute abgeliefert",S.chestBelow>0 and S.coal==640)
end
-- Inventar fuellt sich unterwegs -> Heimfahrt, abladen, an gleicher Stelle weiter
print("Volles Inventar unterwegs")
local S=Sim.new({config=cfg(3,60,2,2),fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
local origDig=S.turtle.digUp
local n=0
-- jede Grabung liefert eine andere Sorte -> Inventar laeuft voll
for _,k in ipairs({"dig","digUp","digDown"})do local f=S.turtle[k];S.turtle[k]=function()local ok,w=f();if ok then n=n+1;
  for i=1,16 do local it=S.inv[i];if it and it.name=="minecraft:cobblestone" then it.name="minecraft:ore"..(n%40) end end end;return ok,w end end
Sim.run(S,20000);local st=load("return "..S.files["/toast_mining_state"])()
check("fertig trotz vollem Inventar",st.next==121 and not (S.last and S.last.fault),st.next.." "..tostring(S.last and S.last.fault))
local missing=0;for t=0,1 do for z=1,60 do for y=0,-2,-1 do if S.world[S.key(t*3,y,z)]~=false then missing=missing+1 end end end end
check("trotzdem alles abgebaut",missing==0,missing)
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
print("Mine nach LINKS")
local S=Sim.new({config=cfg(3,15,3,2):gsub("gap=2,","gap=2,side=\"left\","),fuel=20000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1";Sim.run(S,20000)
local st=load("return "..S.files["/toast_mining_state"])()
local miss,right=0,0
for t=0,2 do for z=1,15 do for y=0,-2,-1 do if S.world[S.key(-t*3,y,z)]~=false then miss=miss+1 end end end end
for x=1,9 do for z=1,15 do if S.world[S.key(x,-1,z)]==false then right=right+1 end end end
print((miss==0 and right==0 and st.next==46 and S.p.x==0 and S.p.z==0) and "  PASS links: alles abgebaut, rechts unberuehrt" or ("  FAIL links "..miss.." "..right.." "..st.next))
