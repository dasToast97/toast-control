package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local S=Sim.new({config="return {}"})
local G=Sim.env(S)
local common=G.dofile("/toast/toast_common.lua")
-- Echte Welt: Basis bei (500,70,-300), Turtle schaut nach Westen (vor = -X, rechts = -Z)
local BX,BY,BZ=500,70,-300
local function truth(rel) return BX-rel.fwd,BY+rel.up,BZ-rel.right end
local cur={fwd=0,right=0,up=0}
local calls=0
G.gps={locate=function() calls=calls+1;local x,y,z=truth(cur);return x,y,z end}
local c={mine={side="right"},base={set=false,dimension="auto"}}
local function status(f,r,u) cur={fwd=f,right=r,up=u};S.T=S.T+1
    local m={x=r,y=-u,z=f};common.addPosition(m,c,"mining");return m end
local m=status(0,0,0)
check("an der Basis: GPS-Messung",m.gps and m.gps.x==500 and m.gps.y==70 and m.gps.z==-300,m.gps and (m.gps.x..","..m.gps.y..","..m.gps.z))
-- in 3 s laufen (noch keine neue Messung erlaubt), dann Messung
m=status(1,0,0);check("ohne Kalibrierung und bewegt: keine alte Position",m.gps==nil)
S.T=S.T+3;m=status(4,2,1)
check("zweite Messung -> kalibriert",common.gpsCalibration()~=nil and common.gpsCalibration().facing=="west",common.gpsCalibration() and common.gpsCalibration().facing)
local before=calls
local okAll=true
for i=1,8 do m=status(4+i,2,1);local x,y,z=truth(cur);if not (m.gps and m.gps.x==x and m.gps.y==y and m.gps.z==z and m.gps.live) then okAll=false end end
check("danach jede Sekunde richtig, ohne Funk",okAll)
check("GPS nur noch alle 10 s gefragt",calls-before<=1,calls-before)
-- Turtle wurde von Hand versetzt -> naechste Messung passt nicht -> neu kalibrieren
BX=600;S.T=S.T+11;m=status(12,2,1)
check("Versatz erkannt (Kalibrierung verworfen)",common.gpsCalibration()==nil)
print("D Dimension erkennen")
check("Netherrack",common.dimensionOf("minecraft:netherrack")=="nether")
check("Endstein",common.dimensionOf("minecraft:end_stone")=="end")
check("Deepslate",common.dimensionOf("minecraft:deepslate")=="overworld")
check("Bedrock zaehlt nicht",common.dimensionOf("minecraft:bedrock")==nil)
check("Nether-Quarzerz",common.dimensionOf("minecraft:nether_quartz_ore")=="nether")
print(pass.." bestanden, "..failc.." fehlgeschlagen")
