package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1 else fail=fail+1;print("  FAIL "..n.."  "..tostring(i))end end
local function cfg(H,L,T,side,sd)return ([[return {role="auto",job="mining",controllerId=4,name="SD",autoDiscover=true,autoPairPockets=true,
 devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
 mine={length=%d,height=%d,tunnels=%d,gap=0,side="%s",sideDig=%s,fuelTarget=2000,radioTimeout=0,freeSlots=2,digRetries=16,protectedBlocks={}}}]]):format(L,H,T,side or "right",tostring(sd))end
local function oreify(S)
  local n=0
  for _,k in ipairs({"dig","digUp","digDown"})do local f=S.turtle[k];S.turtle[k]=function()local ok,w=f();if ok then n=n+1
    for i=1,16 do local it=S.inv[i];if it and it.name=="minecraft:cobblestone" then it.name="minecraft:ore"..(n%40) end end end;return ok,w end end
end
local function run(H,L,T,sd,opts)
  opts=opts or {}
  local S=Sim.new({config=cfg(H,L,T,opts.side,sd),fuel=500000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
  S.protocol="toast.mine.v1";if opts.full then oreify(S) end
  if opts.crash then S.crashAtMove=opts.crash end
  local acts=0
  for _,k in ipairs({"forward","up","down","turnLeft","turnRight","dig","digUp","digDown"})do local f=S.turtle[k];S.turtle[k]=function(...)acts=acts+1;return f(...)end end
  Sim.run(S,60000)
  local st=load("return "..S.files["/toast_mining_state"])()
  local sx=opts.side=="left" and -1 or 1
  local miss,outside=0,0
  for x=0,T-1 do for z=1,L do for y=0,-(H-1),-1 do if S.world[S.key(sx*x,y,z)]~=false then miss=miss+1 end end end end
  for x=-1,T do for z=0,L+1 do for y=1,-H,-1 do
    local inside=x>=0 and x<T and z>=1 and z<=L and y<=0 and y>=-(H-1)
    if not inside and not (x==0 and z==0 and y==0) and S.world[S.key(sx*x,y,z)]==false then outside=outside+1 end
  end end end
  local ok=miss==0 and outside==0 and S.p.x==0 and S.p.y==0 and S.p.z==0 and S.last and S.last.status=="Fertig"
  return ok,S,acts,miss,outside
end
print(("%-12s | %-17s | %-17s | %s"):format("Mine HxLxB","normal Fuel/Akt.","seitlich Fuel/Akt.","Fuel gespart / Aktionen"))
for _,c in ipairs({{1,20,6},{2,20,6},{3,20,5},{3,20,10},{4,15,8},{6,15,8},{9,12,10},{12,10,12},{20,8,10},{30,6,16}}) do
  local H,L,T=table.unpack(c)
  local ok1,S1,a1,m1,o1=run(H,L,T,false)
  local ok2,S2,a2,m2,o2=run(H,L,T,true)
  local name=H.."x"..L.."x"..T
  print(("%-12s | %7d / %7d | %7d / %7d | %4d%%  /  %+4d%%  %s"):format(name,S1.moves,a1,S2.moves,a2,
    math.floor(100-100*S2.moves/S1.moves+0.5),math.floor(100*a2/a1-100+0.5),ok2 and "" or ("FEHLER miss="..m2.." aussen="..o2.." "..tostring(S2.last and S2.last.detail))))
  check(name.." normal",ok1,"miss="..m1.." aussen="..o1)
  check(name.." seitlich",ok2,"miss="..m2.." aussen="..o2.." "..tostring(S2.last and S2.last.status).." "..tostring(S2.last and S2.last.detail))
end
print("seitlich + volles Inventar")
for _,c in ipairs({{3,15,7},{9,10,8},{20,6,9}}) do
  local ok,S,a,m,o=run(c[1],c[2],c[3],true,{full=true})
  check(table.concat(c,"x").." voll",ok,"miss="..m.." aussen="..o.." "..tostring(S.last and S.last.detail))
end
print("seitlich, Seite links")
local ok,S,a,m,o=run(6,12,7,true,{side="left",full=true})
check("links",ok,"miss="..m.." aussen="..o.." "..tostring(S.last and S.last.detail))
print("seitlich, Absturz mitten im Schritt")
for _,cr in ipairs({11,50,130,301}) do
  ok,S,a,m,o=run(6,10,7,true,{crash=cr,full=true})
  check("Absturz "..cr,ok,"miss="..m.." aussen="..o.." "..tostring(S.last and S.last.detail))
end
print("kleine Mine: seitlich bringt nichts -> normal")
ok,S=run(3,10,2,true)
local note=false;for _,l in ipairs(S.log)do if l:find("bringt bei diesen Massen nichts",1,true) then note=true end end
check("Hinweis + normal fertig",ok and note)
-- Anzeige im Seitenmodus: Spuren (alle Ebenen) statt Gaenge, mit Prozent
do
  local S=Sim.new({config=cfg(9,10,10,"right",true),fuel=500000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
  S.protocol="toast.mine.v1"
  local seen
  S.actions[#S.actions+1]={t=400,fn=function(S) seen=S.last end}
  Sim.run(S,400)
  local d=S.last or {}
  check("Seitenmodus meldet Spurenzahl",type(d.lanes)=="number" and d.lanes>10,tostring(d.lanes))
  check("Spuren fertig <= Spuren gesamt",(d.rounds or 0)<=(d.lanes or 0),tostring(d.rounds).."/"..tostring(d.lanes))
  -- Zeile in der Zentrale
  local S3=Sim.new({config=""})
  for _,n in ipairs({"toast_common.lua","toast_ui.lua"}) do S3.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a") end
  local G=Sim.env(S3)
  do local n=0;local c={};G.colors=setmetatable({},{__index=function(_,k)if not c[k] then n=n+1;c[k]=2^n end;return c[k] end}) end
  G.textutils.formatTime=function()return "1:00" end;G.os.time=function()return 1 end
  local UI=G.dofile("/toast/toast_ui.lua")
  local rows=UI.jobRows and UI.jobRows("mining",{rounds=10,lanes=36,tunnels=10,scanned=100,cells=360})
  if rows then
    check("Zeile: Spuren 10 / 36 fertig (27%)",rows[1][1]=="Spuren" and rows[1][2]=="10 / 36 fertig (27%)",rows[1][1].." "..rows[1][2])
    local r2=UI.jobRows("mining",{rounds=2,tunnels=5,scanned=40,cells=100})
    check("Normal: Gaenge 2 / 5 fertig (40%)",r2[1][1]=="Gaenge" and r2[1][2]=="2 / 5 fertig (40%)",r2[1][2])
  else check("UI.jobRows vorhanden",false) end
end
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
if fail>0 then os.exit(1) end
