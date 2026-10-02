package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1 else fail=fail+1;print("  FAIL "..n.." "..tostring(i))end end
local function cfg(H,L,T,G)return ([[return {role="auto",job="mining",controllerId=4,label="T",autoDiscover=true,autoPairPockets=true,
 devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
 mine={length=%d,height=%d,tunnels=%d,gap=%d,fuelTarget=100,radioTimeout=300,freeSlots=2,digRetries=16,protectedBlocks={}}}]]):format(L,H,T,G)end
print(("%-6s %8s %8s %8s"):format("Hoehe","Bloecke","Fuel","Fuel/Blk"))
for _,H in ipairs({1,2,3,4,5,6,7,8,9,10,12,16,20,32,48,64}) do
  local L,T,G=8,3,2
  local S=Sim.new({config=cfg(H,L,T,G),fuel=200000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
  S.protocol="toast.mine.v1";Sim.run(S,200000)
  local st=load("return "..S.files["/toast_mining_state"])()
  local missing,wall,above=0,0,0
  for t=0,T-1 do local x=t*(G+1)
    for z=1,L do for y=0,-(H-1),-1 do if S.world[S.key(x,y,z)]~=false then missing=missing+1 end end
      if S.world[S.key(x,-H,z)]==false then above=above+1 end end
  end
  for t=0,T-2 do for gx=1,G do for z=2,L-1 do for y=0,-(H-1),-1 do
    if S.world[S.key(t*(G+1)+gx,y,z)]==false then wall=wall+1 end end end end end
  local blocks=T*L*H
  print(("%-6d %8d %8d %8.2f"):format(H,blocks,S.moves,S.moves/blocks))
  check("H="..H.." fertig+heim",st.next==math.ceil(H/3)*L*T+1 and S.p.x==0 and S.p.y==0 and S.p.z==0 and not (S.last and S.last.fault),
    st.next.." pos "..S.p.x..","..S.p.y..","..S.p.z.." "..tostring(S.last and S.last.fault))
  check("H="..H.." alles abgebaut",missing==0,missing)
  check("H="..H.." nichts darueber",above==0,above)
  check("H="..H.." Waende stehen",wall==0,wall)
end
print("Absturz mitten in hoher Mine (H=20)")
local S=Sim.new({config=cfg(20,8,2,2),fuel=200000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1";S.crashAtMove=57;Sim.run(S,200000)
local st=load("return "..S.files["/toast_mining_state"])()
local missing=0;for t=0,1 do for z=1,8 do for y=0,-19,-1 do if S.world[S.key(t*3,y,z)]~=false then missing=missing+1 end end end end
check("nach Absturz komplett",st.next==7*8*2+1 and missing==0 and S.p.y==0,st.next.." "..missing)
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
