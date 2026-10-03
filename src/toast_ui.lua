-- Toast Control: Oberflaeche fuer Zentrale (Monitor) und Pocket.
-- Passt sich der Bildschirmgroesse an: Liste aller Turtles mit Farbe je Zustand,
-- Antippen zeigt Details. Farm und Mining zeigen jeweils nur ihre eigenen Werte.
local common=dofile("/toast/toast_common.lua")
local M={}
-- Zustand -> Kurztext + Farbe
local WORK={["Abbau"]="Baut ab",["Ernte"]="Erntet",["Pflanzen"]="Pflanzt",["Feld pruefen"]="Prueft",
    ["Fortsetzen"]="Startet",["Neuer Versuch"]="Startet",["Faellt Baum"]="Faellt",["Baeume pruefen"]="Prueft",
    ["Kampf"]="Kaempft",["Patrouille"]="Laeuft"}
function M.state(e,link)
    local d=e and e.data
    if not link or not e or not e.online or not d then return "Offline","off" end
    if d.recovery then return "Pos. ?","fault" end
    if d.fault or d.status=="Rueckweg blockiert" then return "Fehler","fault" end
    local s=tostring(d.status or "")
    if WORK[s] then return WORK[s],"work" end
    if s=="Rueckkehr" then return "Heimweg","move" end
    if s=="Warten" then return "Wartet","wait" end
    if s=="Wache" then return "Wacht","wait" end
    if s=="Tagpause" then return "Tagpause","wait" end
    if s=="Fertig" then return "Fertig","done" end
    if s=="Bereit" or s=="Reset" or s=="" then return "Bereit","idle" end
    return "Problem","warn"
end
local COLOR={work=colors.lime,move=colors.lightBlue,wait=colors.cyan,done=colors.green,
    idle=colors.lightGray,warn=colors.orange,fault=colors.red,off=colors.gray}
M.COLOR=COLOR
local function num(n) return common.number(n) end
local function short(n)
    n=num(n)
    if math.abs(n)>=1000000 then return string.format("%.1fM",n/1000000) end
    if math.abs(n)>=10000 then return string.format("%.1fk",n/1000) end
    return tostring(math.floor(n))
end
-- Spielzeit "11:08" (leer, wenn nicht verfuegbar)
local function clockText()
    if not (textutils and textutils.formatTime and os.time) then return "" end
    local ok,t=pcall(function() return textutils.formatTime(os.time(),true) end)
    t=ok and tostring(t) or ""
    if #t==4 then t="0"..t end
    return t
end
M.clockText=clockText
-- Rechte Kopfzeile: laengste Variante, die in "room" Zeichen passt
local function headRight(room,online,total,clock)
    local opts={online.."/"..total.." online  "..clock.." ",online.."/"..total.." online "..clock.." ",
        online.."/"..total.."  "..clock.." ",online.."/"..total.." "..clock.." ",clock.." ",online.."/"..total.." "}
    if clock=="" then opts={online.."/"..total.." online ",online.."/"..total.." "} end
    for _,o in ipairs(opts) do if #o<=room then return o end end
    return ""
end
M.headRight=headRight
-- ===== Aufgaben: Name, Hauptwert und Detailzeilen je Job =====
local MOB_MODES={farm="Mobfarm",guard="Wache",patrol="Waechter"}
local function wait(rows,d) if num(d.wait)>0 then rows[#rows+1]={"Naechste",num(d.wait).." s"} end end
local JOB={
    farm={name="Farm",plural="Farmen",metric="Ertrag",unit="Items",once="1 Runde",
        value=function(d) return num(d.total) end,aux={"Geerntet",function(d) return num(d.harvested) end," Pfl."},
        rows=function(d) local r={{"Runden",short(d.rounds)}}
            if num(d.roundYield)>0 then r[#r+1]={"Diese Runde",short(d.roundYield).." Items"} end
            r[#r+1]={"Geerntet",short(d.harvested).." Pflanzen"};r[#r+1]={"Ertrag",short(d.total).." Items"}
            r[#r+1]={"Saatgut",short(d.seeds)};wait(r,d);return r end},
    mining={name="Mine",plural="Minen",metric="Abgebaut",unit="Bl.",once="1 Gang",
        value=function(d) return num(d.harvested) end,aux={"Abgeladen",function(d) return num(d.total) end," Items"},
        rows=function(d) local r={{"Gaenge",short(d.rounds)..(d.tunnels and (" / "..d.tunnels) or "").." fertig"},
            {"Abgebaut",short(d.harvested).." Bloecke"},{"Abgeladen",short(d.total).." Items"},{"Freie Slots",short(d.freeSlots)}}
            if d.useCoal then r[#r+1]={"Kohle",short(d.coal).." verbrannt"} end
            if d.placeChests then r[#r+1]={"Kisten",short(d.chestsPlaced).." gesetzt, "..short(d.chestsLeft).." dabei"} end
            if num(d.torches)>0 then r[#r+1]={"Fackeln",short(d.torchesPlaced).." gesetzt, "..short(d.torchesLeft).." dabei"} end
            return r end},
    tree={name="Holz",plural="Holzfarmen",metric="Holz",unit="Staemme",once="1 Runde",
        value=function(d) return num(d.total) end,aux={"Gefaellt",function(d) return num(d.harvested) end," Baeume"},
        rows=function(d) local r={{"Runden",short(d.rounds)},{"Gefaellt",short(d.harvested).." Baeume"},
            {"Holz",short(d.total).." Staemme"},{"Setzlinge",short(d.saplings)},{"Freie Slots",short(d.freeSlots)}}
            wait(r,d);return r end},
    mob={name="Mobs",plural="Mob-Turtles",metric="Drops",unit="Items",once="EINMAL",
        value=function(d) return num(d.total) end,aux={"Treffer",function(d) return num(d.hits) end,""},
        rows=function(d) local r={{"Art",MOB_MODES[d.mobMode] or "-"},{"Treffer",short(d.hits)},{"Drops",short(d.total).." Items"}}
            if d.lastHit and num(d.hits)>0 then r[#r+1]={"Letzter Mob","vor "..short(d.lastHit).." s"} end
            if d.mobMode=="patrol" then r[#r+1]={"Ziele",short(d.targets).." angefahren"};r[#r+1]={"Tankrunden",short(d.rounds)};wait(r,d) end
            r[#r+1]={"Freie Slots",short(d.freeSlots)};return r end},
    dig={name="Aushub",plural="Aushub-Turtles",metric="Abgebaut",unit="Bl.",once="1 Auftrag",
        value=function(d) return num(d.harvested) end,aux={"Abgeladen",function(d) return num(d.total) end," Items"},
        rows=function(d) local r={{"Form",(common.DIG_SHAPES[d.shape] or "-")..(d.digDir=="up" and " hoch" or " runter")},
            {"Fortschritt",short(d.scanned).." / "..short(d.cells)..(d.done and " FERTIG" or "")},
            {"Abgebaut",short(d.harvested).." Bloecke"},{"Abgeladen",short(d.total).." Items"}}
            if num(d.kept)>0 then r[#r+1]={"Erze stehen",short(d.kept)} end
            if num(d.sealed)>0 then r[#r+1]={"Zugebaut",short(d.sealed).." Stellen"} end
            if num(d.drained)>0 then r[#r+1]={"Trockengelegt",short(d.drained)} end
            r[#r+1]={"Fuellmaterial",d.noFill and "FEHLT" or short(d.fill)}
            r[#r+1]={"Freie Slots",short(d.freeSlots)};return r end},
}
local ORDER={"farm","mining","tree","mob","dig"}
M.JOB=JOB
local function jobOf(e) return JOB[e and e.job] and e.job or "mining" end
local function hasProgress(d) return num(d.cells)>0 end
local function progress(d) return math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells)))) end
-- Position: "12 vor, 3 rechts, 5 hoch" ab Basis + Koordinaten (GPS oder aus Basis)
local function posText(d)
    local r=d.rel;if type(r)~="table" then return nil end
    local p={}
    local function part(v,plus,minus) v=num(v);if v~=0 then p[#p+1]=math.abs(v).." "..(v>0 and plus or minus) end end
    part(r.fwd,"vor","zur.");part(r.right,"re","li");part(r.up,"hoch","tief")
    return #p==0 and "an der Basis" or table.concat(p," ")
end
M.posText=posText
local function coordText(d)
    local c=type(d.gps)=="table" and d.gps or type(d.pos)=="table" and d.pos
    if not c then return nil end
    return "X"..num(c.x).." Y"..num(c.y).." Z"..num(c.z)..(type(d.gps)=="table" and " GPS" or "")
end
M.coordText=coordText
local function common_rows(rows,d)
    local pt=posText(d);if pt then rows[#rows+1]={"Position",pt} end
    local ct=coordText(d);if ct then rows[#rows+1]={"Koordinaten",ct} end
    if d.toast then rows[#rows+1]={"Version",tostring(d.toast)..(d.toast~=common.version and (" (Zentrale "..common.version..")") or "")} end
    if d.dim then
        local names={overworld="Oberwelt",nether="Nether",["end"]="End"}
        local t=names[d.dim] or tostring(d.dim)
        if d.dimSet and d.dimSet~=d.dim then t=t.." (Config: "..(names[d.dimSet] or d.dimSet)..")" end
        rows[#rows+1]={"Dimension",t}
    end
    rows[#rows+1]={"Fuel",d.fuel=="unlimited" and "unbegrenzt" or short(d.fuel)}
    if d.chunks then rows[#rows+1]={"Chunks",d.chunks>0 and (d.chunks..", -"..short(d.chunkFuel).." Fuel/h") or "aus"} end
    return rows
end
-- Dunkler Balken-Hintergrund: "braun" wird umdefiniert (sonst nirgends benutzt),
-- weil CC kein dunkleres Grau als colors.gray kennt.
local TRACK=colors.brown
M.TRACK=TRACK
local function setTrack(screen)
    if screen.isColor and screen.isColor() and screen.setPaletteColour then
        pcall(screen.setPaletteColour,TRACK,0x262626)
    end
end
M.setTrack=setTrack
function M.resetTrack(screen)
    if screen and screen.setPaletteColour and term.nativePaletteColour then
        pcall(function() screen.setPaletteColour(TRACK,term.nativePaletteColour(TRACK)) end)
    end
end
-- Balken in einer Listenzeile: obere 2/3 der Zeile gefuellt (Zeichen 143),
-- unten bleibt ein Spalt -> untereinander stehende Balken beruehren sich nicht.
local function thinBar(text,x,y,width,pc,fg,bg)
    local f=math.floor(width*math.max(0,math.min(1,pc))+0.5)
    text(x,y,string.rep("\143",f),fg or colors.lime,bg or colors.black)
    text(x+f,y,string.rep("\143",width-f),TRACK,bg or colors.black)
end
-- Zeichenhilfen fuer einen Bildschirm (Farbe nur, wenn der Bildschirm sie kann)
local function painter(screen)
    local w,h=screen.getSize()
    local color=screen.isColor and screen.isColor()
    local P={w=w,h=h}
    setTrack(screen)
    local function col(c)
        if color then return c end
        if c==TRACK then return colors.gray end
        if c==colors.black or c==colors.gray or c==colors.lightGray or c==colors.white then return c end
        return colors.white
    end
    function P.fill(y,bg) if y<1 or y>h then return end screen.setCursorPos(1,y);screen.setBackgroundColor(col(bg));screen.write(string.rep(" ",w)) end
    function P.text(x,y,s,fg,bg)
        if x<1 or x>w or y<1 or y>h then return end
        s=tostring(s):sub(1,w-x+1)
        screen.setCursorPos(x,y);screen.setTextColor(col(fg or colors.white));screen.setBackgroundColor(col(bg or colors.black))
        screen.write(s)
    end
    function P.right(y,s,fg,bg,margin) s=tostring(s);P.text(math.max(1,w-#s+1-(margin or 0)),y,s,fg,bg) end
    function P.bar(x,y,width,pc,fg)
        local f=math.floor(width*math.max(0,math.min(1,pc))+0.5)
        P.text(x,y,string.rep(" ",f),colors.white,fg or colors.lime)
        P.text(x+f,y,string.rep(" ",width-f),colors.white,TRACK)
    end
    function P.thin(x,y,width,pc,fg) thinBar(P.text,x,y,width,pc,fg) end
    return P
end
-- ===== Infoscreen: nur Anzeige, keine Knoepfe =====
-- st = Zustandstabelle des Infoscreens (Seite, Verlauf fuer "pro Stunde")
-- Infoscreen fuer genau eine Turtle: grosse Detailseite
local function drawTurtleInfo(screen,fleet,link,st,id)
    local P=painter(screen);local w,h=P.w,P.h
    screen.setBackgroundColor(colors.black);screen.clear()
    local e=(fleet.entries or {})[id]
    local d=e and e.data or {}
    local label,kind=M.state(e,link)
    local name=e and e.label~="" and e.label or ("Turtle #"..id)
    P.fill(1,colors.blue)
    local clock=clockText()
    local tag=(e and JOB[jobOf(e)].name or "").." #"..id
    local rt=tag.."  "..clock.." "
    if #name+#rt+2>w then rt=clock~="" and (clock.." ") or (tag.." ") end
    if #name+#rt+2>w then name=name:sub(1,math.max(1,w-#rt-2)) end
    P.text(2,1,name,colors.white,colors.blue)
    P.right(1,rt,colors.white,colors.blue)
    if not e then
        P.text(1,3,"Turtle #"..id.." ist der Zentrale",colors.orange)
        P.text(1,4,"(noch) nicht bekannt.",colors.orange)
        P.text(1,6,"ID in toast.lua config pruefen.",colors.lightGray)
        return
    end
    -- Zustand als grosses Band
    P.fill(3,COLOR[kind]);P.fill(4,COLOR[kind])
    P.text(2,3,label,colors.black,COLOR[kind])
    local why=(kind=="fault" or kind=="warn") and (d.fault or d.status) or nil
    if why then P.text(2,4,tostring(why),colors.black,COLOR[kind]) end
    local det=kind=="off" and "Keine Daten - offline oder Chunk entladen" or tostring(d.detail or "")
    local y=6
    while #det>0 and y<=7 do P.text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
    -- Fortschritt (nicht bei Mobfarm/Wache: dort gibt es keine Runde)
    y=9
    if hasProgress(d) then
        local pc=progress(d)
        P.text(1,y,"Fortschritt",colors.lightGray);P.right(y,math.floor(pc*100+0.5).."%",colors.white)
        y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind])
        if h>=20 then y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind]) end
        y=y+2
    end
    -- pro Stunde fuer diese Turtle
    local spec=JOB[jobOf(e)]
    st.hist=st.hist or {}
    local now=os.clock();local key=spec.value(d)
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then st.hist[#st.hist+1]={t=now,v=key};while #st.hist>31 do table.remove(st.hist,1) end end
    local first=st.hist[1]
    local perH=(first and now-first.t>=60) and short(math.max(0,(key-first.v)/(now-first.t)*3600)) or "-"
    local rows=spec.rows(d)
    -- "pro Stunde" direkt hinter dem Hauptwert
    local at=#rows+1
    for i,r in ipairs(rows) do if r[1]==spec.metric then at=i+1 end end
    table.insert(rows,math.min(at,#rows+1),{spec.metric.." / Stunde",perH})
    common_rows(rows,d)
    -- zweispaltig, wenn breit genug
    local cols=w>=56 and 2 or 1
    local cw=math.floor(w/cols)
    local per=math.ceil(#rows/cols)
    for i,r in ipairs(rows) do
        local c=math.floor((i-1)/per);local yy=y+(i-1)%per
        if yy<=h then
            local x=1+c*cw
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+cw-1-#r[2]-(cols>1 and c==0 and 2 or 0),yy,r[2],colors.white)
        end
    end
end
-- show: "all", "farm", "mining" oder Turtle-ID (Zahl)
function M.drawInfo(screen,fleet,link,st,show)
    if type(show)=="number" then return drawTurtleInfo(screen,fleet,link,st,show) end
    local P=painter(screen);local w,h=P.w,P.h
    screen.setBackgroundColor(colors.black);screen.clear()
    local entries=fleet.entries or {}
    if common.job(show) then
        local ids={}
        for _,id in ipairs(fleet.ids or {}) do if (entries[id] or {}).job==show then ids[#ids+1]=id end end
        fleet={ids=ids,entries=entries}
    end
    -- Summen je Aufgabe
    local G={}
    for _,j in ipairs(ORDER) do G[j]={n=0,act=0,value=0,aux=0,progSum=0,progN=0} end
    local fuel,chunk=0,0
    local problems,list={},{}
    for _,id in ipairs(fleet.ids or {}) do
        local e=entries[id] or {};local d=e.data or {}
        local job=jobOf(e);local g=G[job];local spec=JOB[job]
        local label,kind=M.state(e,link)
        g.n=g.n+1
        if kind=="work" or kind=="move" or kind=="wait" then g.act=g.act+1 end
        g.value=g.value+spec.value(d);g.aux=g.aux+spec.aux[2](d)
        if hasProgress(d) then g.progSum=g.progSum+progress(d);g.progN=g.progN+1 end
        if kind~="off" then
            if d.fuel~="unlimited" then fuel=fuel+num(d.fuel) end
            if num(d.chunks)>0 then chunk=chunk+num(d.chunkFuel) end
        end
        if kind=="fault" or kind=="warn" then problems[#problems+1]={id=id,e=e,label=label,kind=kind} end
        list[#list+1]={id=id,e=e,label=label,kind=kind,job=job}
    end
    -- Verlauf fuer "pro Stunde" (alle 30 s ein Messpunkt, 15 min behalten)
    st.hist=st.hist or {}
    local now=os.clock()
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then
        local p={t=now};for _,j in ipairs(ORDER) do p[j]=G[j].value end
        st.hist[#st.hist+1]=p
        while #st.hist>31 do table.remove(st.hist,1) end
    end
    local function rate(key,cur)
        local first=st.hist[1]
        if not first or not first[key] or now-first.t<60 then return "-" end
        return short(math.max(0,(cur-first[key])/(now-first.t)*3600))
    end
    -- Kopf
    P.fill(1,colors.blue)
    local online=0;for _,l in ipairs(list) do if l.kind~="off" then online=online+1 end end
    local clock=clockText()
    local rt=link and headRight(w-7,online,#list,clock) or "keine Verbindung "
    local title=JOB[show] and JOB[show].plural or "Uebersicht"
    P.text(2,1,(#rt+10+#title<=w) and ("TOAST  "..title) or "TOAST",colors.white,colors.blue)
    P.right(1,rt,link and colors.white or colors.orange,colors.blue)
    -- Kacheln je Aufgabe (zwei nebeneinander, wenn Platz)
    local y=3
    local function panel(x,y0,pw,title,a,n,rows)
        P.text(x,y0,title,colors.white)
        local s=a.."/"..n.." aktiv"
        P.text(x+pw-#s,y0,s,a>0 and colors.lime or colors.lightGray)
        local yy=y0+1
        for _,r in ipairs(rows) do
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+pw-#r[2],yy,r[2],colors.white)
            if r.bar then
                -- gruener Balken zwischen Bezeichnung und Prozent
                local bx=x+#r[1]+1;local bw=pw-#r[1]-#r[2]-2
                if bw>=3 then P.thin(bx,yy,bw,r.bar,colors.lime) end
            end
            yy=yy+1
        end
        return yy
    end
    local present={};for _,j in ipairs(ORDER) do if G[j].n>0 then present[#present+1]=j end end
    local side=w>=50 and #present>1
    -- Kleiner Bildschirm: nur die wichtigsten Zeilen, damit die Liste Platz hat
    local compact=(not side and h<26 and #present>1) or (h<26 and #present>2)
    local function rowsFor(j)
        local g,spec=G[j],JOB[j]
        local rows
        if compact then rows={{spec.metric,short(g.value).."  ("..rate(j,g.value).."/h)"}}
        else rows={{spec.metric,short(g.value).." "..spec.unit},{"pro Stunde",rate(j,g.value)},
            {spec.aux[1],short(g.aux)..spec.aux[3]}} end
        if g.progN>0 and (j=="mining" or not compact) then
            local pc=g.progSum/g.progN
            rows[#rows+1]={"Fortschritt",math.floor(pc*100+0.5).."%",bar=pc}
        end
        return rows
    end
    if side then
        local pw=math.floor((w-3)/2)
        for i=1,#present,2 do
            local a,b=present[i],present[i+1]
            local y1=panel(1,y,pw,JOB[a].name:upper(),G[a].act,G[a].n,rowsFor(a))
            local y2=b and panel(pw+4,y,w-pw-3,JOB[b].name:upper(),G[b].act,G[b].n,rowsFor(b)) or y1
            y=math.max(y1,y2)+(compact and 0 or 1)
        end
        if compact then y=y+1 end
    else
        for i,j in ipairs(present) do
            y=panel(1,y,w,JOB[j].name:upper(),G[j].act,G[j].n,rowsFor(j))
            if not compact or i==#present then y=y+1 end
        end
    end
    if #list==0 then
        P.text(1,y,"Noch keine Turtles gemeldet.",colors.lightGray)
        return
    end
    -- Probleme zuerst
    if #problems>0 and y<h-1 then
        local maxP=math.max(1,math.floor((h-y-2)/2))   -- Platz fuer die Liste lassen
        P.text(1,y,"PROBLEME",colors.orange);y=y+1
        for n,p in ipairs(problems) do
            if y>=h-1 or n>maxP then break end
            local d=p.e.data or {}
            local name=p.e.label~="" and p.e.label or ("#"..p.id)
            P.text(1,y,"\7",COLOR[p.kind]);P.text(3,y,name,colors.white)
            local msg=tostring(d.fault or d.status or p.label)
            P.text(math.min(w,4+#name),y,(" "..msg):sub(1,math.max(0,w-3-#name)),COLOR[p.kind])
            y=y+1
        end
        if not compact then y=y+1 end
    end
    -- Alle Turtles (blaettert automatisch)
    local footer=h
    local avail=footer-1-y
    if avail>=2 then
        P.text(1,y,"TURTLES",colors.white);y=y+1;avail=avail-1
        local pages=math.max(1,math.ceil(#list/math.max(1,avail)))
        st.page=st.page or 1
        if not st.flip then st.flip=now
        elseif now-st.flip>=6 then st.page=st.page%pages+1;st.flip=now end
        if st.page>pages then st.page=1 end
        if pages>1 then P.right(y-1,st.page.."/"..pages,colors.lightGray) end
        local barW=w>=60 and 20 or w>=40 and math.min(14,w-30) or w>=30 and 6 or 0
        for i=1,avail do
            local l=list[(st.page-1)*avail+i];if not l then break end
            local d=l.e.data or {}
            local name=l.e.label~="" and l.e.label or (JOB[l.job].name.." #"..l.id)
            P.text(1,y,"\7",COLOR[l.kind])
            local stx=w-8
            local val=""
            if l.kind~="off" then val=short(JOB[l.job].value(d)) end
            if barW>0 then
                -- [Zustand] [gruener Balken] [Prozent] [Wert]
                local valW=w>=40 and 6 or 0
                local bx=w-valW-5-barW+1
                stx=bx-9
                if l.kind~="off" and hasProgress(d) then
                    local pc=progress(d)
                    P.thin(bx,y,barW,pc,colors.lime)
                    P.text(bx+barW,y,string.format("%4d%%",math.floor(pc*100+0.5)),colors.lightGray)
                end
                if valW>0 then P.right(y,val,colors.lightGray) end
                P.text(stx,y,l.label,COLOR[l.kind])
            else
                P.text(stx,y,l.label,COLOR[l.kind])
            end
            P.text(3,y,name:sub(1,math.max(1,stx-4)),l.kind=="off" and colors.gray or colors.white)
            y=y+1
        end
    end
    -- Fusszeile
    P.text(1,footer,("Fuel "..short(fuel)..(chunk>0 and ("  Chunks -"..short(chunk).."/h") or "")):sub(1,w),colors.lightGray)
end
function M.new(screen,cfg)
    -- kbd: Tastatur-Bedienung sichtbar (Markierung + Tastenhinweise).
    -- Auf dem eigenen Bildschirm (Pocket/Computer) immer, am Monitor sobald
    -- eine Taste gedrueckt wurde.
    local ui={filter="all",selected=nil,page=1,buttons={},ids={},cursor=nil,kbd=screen==term,help=false}
    function ui.setScreen(s) screen=s;ui.kbd=ui.kbd or s==term end
    local CONFIRM=5
    local function confirming() return ui.confirm and os.clock()-ui.confirm.at<CONFIRM and ui.confirm end
    function ui.draw(fleet,link,notice)
        local w,h=screen.getSize();ui.buttons={}
        local color=screen.isColor and screen.isColor()
        setTrack(screen)
        -- Ohne Farbbildschirm nur Grautoene verwenden
        local function col(c)
            if color then return c end
            if c==TRACK then return colors.gray end
        if c==colors.black or c==colors.gray or c==colors.lightGray or c==colors.white then return c end
            return colors.white
        end
        local function fill(y,bg) screen.setCursorPos(1,y);screen.setBackgroundColor(col(bg));screen.write(string.rep(" ",w)) end
        local function text(x,y,s,fg,bg)
            if x<1 or x>w or y<1 or y>h then return end
            s=tostring(s):sub(1,w-x+1)
            screen.setCursorPos(x,y);screen.setTextColor(col(fg or colors.white));screen.setBackgroundColor(col(bg or colors.black))
            screen.write(s)
        end
        local function right(y,s,fg,bg) s=tostring(s);text(math.max(1,w-#s+1),y,s,fg,bg) end
        -- Knopf; height>1 = groesserer Knopf (leichter zu treffen am Monitor).
        -- Zwischen nebeneinanderliegenden Knoepfen bleibt 1 Spalte Luft (gap).
        local function button(x,y,width,label,action,bg,enabled,height,gap)
            if width<1 then return end
            height=height or 1
            local bw=width-(gap and width>4 and 1 or 0)
            local b=enabled and bg or colors.gray
            local l=tostring(label):sub(1,bw)
            local pad=math.floor((bw-#l)/2)
            local mid=y+math.floor((height-1)/2)
            for yy=y,y+height-1 do
                text(x,yy,string.rep(" ",bw),colors.white,b)
                ui.buttons[#ui.buttons+1]={x=x,y=yy,w=bw,action=action,enabled=enabled}
            end
            text(x+pad,mid,l,enabled and colors.white or colors.lightGray,b)
        end
        -- Schlichter, eckiger Knopf (einfarbig, Text mittig).
        local color=screen.isColor and screen.isColor()
        local function pill(x,y,width,label,action,bg,enabled,fgc)
            if width<1 then return end
            local b=enabled and bg or TRACK
            local f=fgc or (enabled and colors.white or colors.gray)
            if not enabled then f=colors.gray end
            if false then   -- runde Enden sahen im Spiel ausgefranst aus: eckig ist sauberer
                text(x,y,"\145",colors.black,b)
                text(x+1,y,string.rep(" ",width-2),f,b)
                text(x+width-1,y,"\157",b,colors.black)
                local l=tostring(label):sub(1,width-2)
                text(x+1+math.floor((width-2-#l)/2),y,l,f,b)
            else
                local l=tostring(label):sub(1,width)
                text(x,y,string.rep(" ",width),f,b)
                text(x+math.floor((width-#l)/2),y,l,f,b)
            end
            ui.buttons[#ui.buttons+1]={x=x,y=y,w=width,action=action,enabled=enabled}
        end
        screen.setBackgroundColor(colors.black);screen.setTextColor(colors.white);screen.clear()
        if not confirming() then ui.confirm=nil end
        if ui.help then
            fill(1,colors.blue);text(2,1,"TOAST - Tasten",colors.white,colors.blue)
            local L={{"\24 \25","Turtle waehlen"},{"Enter","Details oeffnen"},{"\27 Back","zurueck"},
                {"\27 \26 Tab","Reiter wechseln"},{"S","Start"},{"X","Stop"},{"E","einmal (1 Runde)"},
                {"R",w>=30 and "Reset (2x druecken)" or "Reset (2x)"},{"U","Update alle (2x)"},{"Bild\24\25","Seite blaettern"},{"H / ?","diese Hilfe"},{"Q","beenden"}}
            local kw=w>=34 and 11 or 9
            for i,l in ipairs(L) do
                if i+2>h-1 then break end
                text(2,i+2,l[1],colors.yellow);text(2+kw,i+2,l[2],colors.white)
            end
            text(1,h,("Taste druecken = weiter"):sub(1,w),colors.lightGray)
            ui.buttons={{x=1,y=1,w=w,action="help",enabled=true}}
            for y=2,h do ui.buttons[#ui.buttons+1]={x=1,y=y,w=w,action="help",enabled=true} end
            return
        end
        if w<24 or h<12 then
            text(1,1,"TOAST",colors.cyan);text(1,3,"Bildschirm zu klein",colors.orange)
            text(1,4,"mind. 24 x 12 Zeichen");text(1,5,"(Monitor groesser oder");text(1,6," Schrift kleiner)");return
        end
        local entries=fleet.entries or {}
        -- Zaehlen + Gruppenwerte
        local ids,count={},{}
        local g={}
        for _,j in ipairs(ORDER) do count[j]=0;g[j]={on=0,act=0,value=0} end
        local online,faults,chunkFuel=0,0,0
        for _,id in ipairs(fleet.ids or {}) do
            local e=entries[id] or {};local d=e.data or {}
            local job=jobOf(e)
            count[job]=count[job]+1
            local _,kind=M.state(e,link)
            local gg=g[job]
            gg.value=gg.value+JOB[job].value(d)
            if kind~="off" then gg.on=gg.on+1 end
            if kind=="work" or kind=="move" or kind=="wait" then gg.act=gg.act+1 end
            if ui.filter=="all" or job==ui.filter then
                ids[#ids+1]=id
                if kind~="off" then online=online+1 end
                if kind=="fault" or kind=="warn" then faults=faults+1 end
                if kind~="off" and num(d.chunks)>0 then chunkFuel=chunkFuel+num(d.chunkFuel) end
            end
        end
        -- Probleme zuerst, dann aktive, dann der Rest (sonst stabile Reihenfolge)
        local rank,pos={fault=1,warn=2,work=3,move=3,wait=3,done=4,idle=4,off=5},{}
        for i,id in ipairs(ids) do local _,k=M.state(entries[id] or {},link);pos[id]=(rank[k] or 4)*10000+i end
        table.sort(ids,function(a,b) return pos[a]<pos[b] end)
        if ui.filter~="net" then
            ui.ids=ids
            if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
            if ui.cursor and not common.contains(ids,ui.cursor) then ui.cursor=nil end
            if not ui.cursor then ui.cursor=ui.selected or ids[1] end
        end
        -- Kopfzeile
        fill(1,colors.blue)
        text(2,1,"TOAST",colors.white,colors.blue)
        -- Update-Knopf: alle Geraete holen sich die neue Version und machen weiter
        if ui.canUpdate~=false then
            local up=confirming() and ui.confirm.action=="update"
            local lab=up and "Sicher?" or "Update"
            local x=8
            text(x,1," "..lab.." ",up and colors.white or colors.blue,up and colors.red or colors.lightBlue)
            ui.buttons[#ui.buttons+1]={x=x,y=1,w=#lab+2,action="update",enabled=link}
        end
        -- rechts: online + Uhr (auf kleinen Pockets gekuerzt: "7/8 11:08")
        local room=w-(ui.canUpdate~=false and 16 or 7)
        local clock=clockText()
        if link and ui.filter=="net" and fleet.nodes then
            local on=0;for _,id in ipairs(fleet.nodes.ids) do if fleet.nodes.entries[id].online then on=on+1 end end
            right(1,headRight(room,on,#fleet.nodes.ids,clock),colors.white,colors.blue)
        elseif link then right(1,headRight(room,online,#ids,clock),colors.white,colors.blue)
        else right(1,(#clock>0 and room>=#clock+18) and ("keine Verbindung  "..clock.." ") or "keine Verbindung ",colors.orange,colors.blue) end
        -- Reiter
        -- Reiter: Alle + jede Aufgabe, die es gibt (Farm und Mine immer)
        local total=0;for _,j in ipairs(ORDER) do total=total+count[j] end
        local tabs={{"Alle",total,"all"}}
        for _,j in ipairs(ORDER) do
            if count[j]>0 or j=="farm" or j=="mining" or ui.filter==j then tabs[#tabs+1]={JOB[j].name,count[j],j} end
        end
        -- Netz: Repeater, GPS-Sender, Infoscreens, Pockets
        local nodes=fleet.nodes or {ids={},entries={}}
        if #nodes.ids>0 or ui.filter=="net" then tabs[#tabs+1]={"Netz",#nodes.ids,"net"} end
        ui.tabs={};for i,t in ipairs(tabs) do ui.tabs[i]=t[3] end
        local tw=math.floor(w/#tabs)
        for i,t in ipairs(tabs) do
            local active=ui.filter==t[3]
            local width=i==#tabs and w-(#tabs-1)*tw or tw
            local lab=t[1].." "..t[2]
            if #lab>width-2 then lab=t[1] end
            local x=1+(i-1)*tw
            if active then pill(x,2,width,lab,"filter:"..t[3],colors.lightBlue,true,colors.black)
            else
                local l=lab:sub(1,width)
                text(x+math.floor((width-#l)/2),2,l,colors.lightGray,colors.black)
                ui.buttons[#ui.buttons+1]={x=x,y=2,w=width,action="filter:"..t[3],enabled=true}
            end
        end
        if ui.filter=="net" then return ui.drawNet(nodes,link,text,right,fill,pill,w,h,notice) end
        local third=math.floor(w/3)
        -- Fusszeile: Hinweiszeile + grosse Tastenreihe + untere Reihe
        -- Grosse Bildschirme bekommen hoehere Knoepfe (leichter zu treffen).
        local bh=1
        local foot=h-1-bh
        local sel=ui.selected and entries[ui.selected]
        local job=sel and jobOf(sel) or (ui.filter~="all" and ui.filter) or nil
        -- Was ist bei den Zielen gerade moeglich?
        local canStart,canStop,faultsT,running=false,false,0,0
        for _,id in ipairs(ids) do
            local e=entries[id]
            if (not ui.selected or ui.selected==id) and e then
                local d=e.data or {}
                local _,k=M.state(e,link)
                local active=d.mode=="auto" or d.mode=="once" or (d.mode==nil and (k=="work" or k=="move" or k=="wait"))
                if link and e.online and e.data and not d.recovery and not active then canStart=true end
                if link and e.online and active then canStop=true;running=running+1 end
                if link and (k=="fault" or k=="warn") then canStop=true;faultsT=faultsT+1 end
            end
        end
        ui.state={canStart=canStart,canStop=canStop,faults=faultsT,running=running}
        local startL="Start"
        local stopL="Stopp"
        local onceL=JOB[job] and JOB[job].once or "Einmal"
        onceL=onceL:sub(1,1)..onceL:sub(2):lower()
        local gap=w>=30 and 2 or 1
        local bw=math.floor((w-2*gap)/3)
        for i,b in ipairs({{startL,"start",colors.green,canStart},{stopL,"stop",colors.red,canStop},{onceL,"once",colors.blue,canStart}}) do
            local x=1+(i-1)*(bw+gap)
            pill(x,foot+1,i==3 and w-x+1 or bw,b[1],b[2],b[3],b[4])
        end
        local perPage
        -- ===== Detailansicht =====
        if sel then
            local d=sel.data or {}
            local label,kind=M.state(sel,link)
            local name=(sel.label and sel.label~="" and sel.label or JOB[jobOf(sel)].name).." #"..ui.selected
            pill(1,3,math.min(w,#name+(w>=30 and 14 or 4)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"group",colors.gray,true)
            fill(4,COLOR[kind])
            local why=(kind=="fault" or kind=="warn") and (d.fault or d.status) or nil
            text(2,4,label..(why and (": "..tostring(why)) or ""),colors.black,COLOR[kind])
            -- Detailtext umbrechen (max. 2 Zeilen)
            local det=kind=="off" and "Keine Daten - Turtle offline oder Chunk entladen" or tostring(d.detail or "")
            local y=5
            while #det>0 and y<=6 do text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
            y=7
            -- Fortschrittsbalken (nur wenn es eine Runde gibt)
            if hasProgress(d) then
                local pc=progress(d)
                local barW=math.max(4,w-6)
                local fillW=math.floor(barW*pc+0.5)
                text(1,y,string.rep(" ",fillW),colors.white,colors.lime)
                text(1+fillW,y,string.rep(" ",barW-fillW),colors.white,TRACK)
                right(y,math.floor(pc*100+0.5).."%",colors.white)
                y=y+2
            end
            local rows=common_rows(JOB[jobOf(sel)].rows(d),d)
            for _,r in ipairs(rows) do
                if y>=foot-1 then break end
                text(1,y,r[1],colors.lightGray);text(13,y,r[2],colors.white);y=y+1
            end
        else
        -- ===== Uebersicht =====
            local y=3
            for _,j in ipairs(ORDER) do
                local gg=g[j]
                if count[j]>0 and (ui.filter=="all" or ui.filter==j) then
                    text(1,y,JOB[j].name,colors.white)
                    text(6,y,gg.act.."/"..count[j]..(w>=34 and " aktiv" or ""),gg.act>0 and colors.lime or colors.lightGray)
                    right(y,JOB[j].metric.." "..short(gg.value),colors.lightGray)
                    y=y+1
                end
            end
            local pl=faults>0 and ("! "..faults.." Problem"..(faults>1 and "e" or "")) or ""
            local cl=chunkFuel>0 and ("Chunks -"..short(chunkFuel).."/h") or ""
            if #pl+#cl+1>w then
                text(1,y,pl,colors.orange);y=y+1;right(y,cl,colors.lightGray);y=y+1
            elseif #pl+#cl>0 then
                text(1,y,pl,colors.orange);right(y,cl,colors.lightGray);y=y+1
            end
            if #ids==0 then
                text(1,y+1,"Keine Turtles.",colors.lightGray)
                text(1,y+2,"Turtles melden sich",colors.lightGray)
                text(1,y+3,"automatisch, sobald sie",colors.lightGray)
                text(1,y+4,"laufen.",colors.lightGray)
            end
            -- Liste
            local top=y
            local avail=math.max(1,foot-1-top)
            perPage=cfg.display.pageSize>0 and math.min(avail,cfg.display.pageSize) or avail
            local pages=math.max(1,math.ceil(#ids/perPage));ui.pages=pages;ui.page=math.min(ui.page,pages)
            local wide=w>=44
            ui.perPage=perPage
            -- Seite folgt der Tastatur-Markierung
            if ui.kbd and ui.cursor and ui.followCursor then
                for i,id in ipairs(ids) do if id==ui.cursor then ui.page=math.ceil(i/perPage) end end
                ui.followCursor=false
            end
            for row=1,perPage do
                local id=ids[(ui.page-1)*perPage+row];if not id then break end
                local e=entries[id] or {};local d=e.data or {}
                local label,kind=M.state(e,link)
                local yy=top+row-1
                local spec=JOB[jobOf(e)]
                local name=e.label and e.label~="" and e.label or (spec.name.." #"..id)
                local stW=8
                -- Rechts: [gruener Balken] [Prozent] [Wert] [Zustand]
                local barW=w>=70 and 20 or w>=44 and 10 or w>=34 and 6 or 0
                local value=wide and string.format("  %-8s%6s",spec.metric,short(spec.value(d))) or ""
                local block=barW>0 and (barW+5+#value) or 0      -- Balken + " 100%" + Wert
                local nameW=w-2-stW-1-(block>0 and block+1 or 0)
                local mark=ui.kbd and id==ui.cursor
                local bg=mark and colors.gray or colors.black
                local sc=(mark and kind=="off") and colors.lightGray or COLOR[kind]
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,mark and "\16" or "\7",mark and colors.white or sc,bg)
                text(3,yy,name:sub(1,nameW),kind=="off" and (mark and colors.lightGray or colors.gray) or colors.white,bg)
                if block>0 and kind~="off" then
                    local x0=w-stW-block
                    if hasProgress(d) then
                        local pc=progress(d)
                        thinBar(text,x0,yy,barW,pc,colors.lime,bg)
                        text(x0+barW,yy,string.format("%4d%%",math.floor(pc*100+0.5)),mark and colors.white or colors.lightGray,bg)
                    end
                    if #value>0 then text(x0+barW+5,yy,value,mark and colors.white or colors.lightGray,bg) end
                end
                right(yy,string.format("%-8s",label),sc,bg)
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        -- Hinweiszeile + untere Tastenreihe
        local info=tostring(notice or "")
        if info:find("Warte auf Geraete",1,true) then info="" end
        local infoCol=colors.lightGray
        local goal=sel and "diese Turtle" or (ui.filter=="all" and "alle" or ("alle "..(JOB[ui.filter] and JOB[ui.filter].plural or ui.filter)))
        if confirming() and ui.confirm.action=="update" then
            info=w>=40 and "Alle Geraete updaten? Update nochmal tippen" or "Update? Nochmal tippen";infoCol=colors.cyan
        elseif confirming() then
            info=#goal+24<=w and ("Reset fuer "..goal.."? Nochmal = ja") or "Reset? Nochmal = ja";infoCol=colors.orange
        elseif info=="" or info:find("bestaetigt",1,true) then
            info="Ziel: "..goal
            local tip
            if ui.kbd then
                tip=sel and (w>=40 and "\24\25 Turtle  \27 zurueck  H Hilfe" or "\27 zurueck  H Hilfe")
                    or (w>=40 and "\24\25 Wahl  Enter Details  H Hilfe" or "\24\25 Enter  H Hilfe")
            else tip=not sel and "Tippen = Details" or nil end
            if tip and #info+2+#tip<=w then info=info..string.rep(" ",w-#info-#tip)..tip
            elseif tip and #tip<=w and ui.kbd then info=tip end
        end
        text(1,foot,info:sub(1,w),infoCol)
        local pages=ui.pages or 1
        local sure=confirming() and ui.confirm.action=="reset"
        -- Reset: orange, wenn es Fehler gibt ("Fehler loeschen"), sonst unauffaellig grau
        -- Reset als dezenter Knopf: dunkelgrau, Schrift orange bei Fehlern, rot bei Nachfrage
        local function resetLabel(width)
            if sure then return width>=22 and "Sicher? Nochmal tippen" or "Sicher?" end
            if faultsT>0 then return width>=22 and "Fehler loeschen + heim" or width>=17 and "Fehler loeschen" or "Reset" end
            return width>=20 and "Reset (Stopp + heim)" or "Reset"
        end
        local rfg=sure and colors.white or (faultsT>0 and colors.orange or colors.lightGray)
        local rbg=sure and colors.red or colors.gray
        local y2=h
        if not sel and pages>1 then
            local pw=math.max(5,math.floor(w/6))
            pill(1,y2,pw,"\27","pageprev",colors.gray,ui.page>1,colors.white)
            pill(w-pw+1,y2,pw,"\26","pagenext",colors.gray,ui.page<pages,colors.white)
            local mw=w-2*pw-2*gap
            local lab=resetLabel(mw-2)
            pill(pw+gap+1,y2,mw,lab,"reset",rbg,link and #ids>0,rfg)
        else
            local lab=resetLabel(w-2)
            local rw=math.min(w,math.max(#lab+6,bw))
            pill(math.floor((w-rw)/2)+1,y2,rw,lab,"reset",rbg,link and #ids>0,rfg)
        end
        if not sel and pages>1 then right(foot,ui.page.."/"..pages,colors.gray) end
    end
    -- ===== Netz-Ansicht =====
    local NODE_NAMES={repeater="Repeater",gps="GPS-Sender",info="Infoscreen",pocket="Pocket"}
    function ui.drawNet(nodes,link,text,right,fill,pill,w,h,notice)
        local ids=nodes.ids
        ui.ids=ids
        if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
        if ui.cursor and not common.contains(ids,ui.cursor) then ui.cursor=nil end
        if not ui.cursor then ui.cursor=ui.selected or ids[1] end
        local function coords(d)
            local p=d and d.pos;if type(p)~="table" then return nil end
            return "X"..num(p.x).." Y"..num(p.y).." Z"..num(p.z)
        end
        local foot=h-1
        local sel=ui.selected and nodes.entries[ui.selected]
        if sel then
            local d=sel.data or {}
            local name=(sel.label~="" and sel.label or NODE_NAMES[sel.role] or "Geraet").." #"..ui.selected
            pill(1,3,math.min(w,#name+(w>=30 and 14 or 4)),(w>=30 and "\27 Zurueck  " or "\27 ")..name,"group",colors.gray,true)
            local kind=sel.online and "done" or "off"
            fill(4,COLOR[kind])
            text(2,4,sel.online and "Online" or "Offline - keine Meldung seit 30 s",colors.black,COLOR[kind])
            local rows={{"Typ",NODE_NAMES[sel.role] or tostring(sel.role)},
                {"Version",tostring(d.toast)..((d.toast and d.toast~=common.version) and (" (Zentrale "..common.version..")") or "")}}
            local c=coords(d)
            rows[#rows+1]={"Koordinaten",c and (c..(d.pos.src and (" "..d.pos.src) or "")) or "unbekannt"}
            local st=d.stats or {}
            if st.gps then rows[#rows+1]={"GPS-Anfragen",short(st.gps)} end
            if st.repeated then rows[#rows+1]={"Weitergeleitet",short(st.repeated).." Nachrichten"} end
            local y=6
            for _,r in ipairs(rows) do if y<foot then text(1,y,r[1],colors.lightGray);text(15,y,r[2],colors.white);y=y+1 end end
        else
            local y=3
            if #ids==0 then
                text(1,y+1,"Keine Netzgeraete gemeldet.",colors.lightGray)
                text(1,y+2,"Repeater/GPS-Sender melden sich",colors.lightGray)
                text(1,y+3,"nach dem Update auf 3.4 selbst.",colors.lightGray)
            end
            local avail=foot-y
            for row=1,avail do
                local id=ids[row];if not id then break end
                local e=nodes.entries[id];local d=e.data or {}
                local yy=y+row-1
                local mark=ui.kbd and id==ui.cursor
                local bg=mark and colors.gray or colors.black
                text(1,yy,string.rep(" ",w),colors.white,bg)
                text(1,yy,mark and "\16" or "\7",e.online and colors.lime or colors.gray,bg)
                local name=e.label~="" and e.label or ((NODE_NAMES[e.role] or "Geraet").." #"..id)
                local typ=NODE_NAMES[e.role] or e.role
                local c=coords(d)
                if w>=60 then
                    text(3,yy,name:sub(1,24),e.online and colors.white or colors.gray,bg)
                    text(29,yy,typ,colors.lightGray,bg)
                    if c then text(42,yy,c,colors.lightGray,bg) end
                    right(yy,(e.online and "" or "Offline ").."v"..tostring(d.toast),e.online and colors.lightGray or colors.gray,bg)
                else
                    text(3,yy,name:sub(1,w-13),e.online and colors.white or colors.gray,bg)
                    right(yy,e.online and typ:sub(1,10) or "Offline",e.online and colors.lightGray or colors.gray,bg)
                end
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        local info=tostring(notice or "")
        if info:find("Warte auf Geraete",1,true) or info:find("bestaetigt",1,true) then info="" end
        if info=="" then info=sel and "Update oben aktualisiert alle Geraete" or "Tippen = Details, Position, Version" end
        text(1,h,info:sub(1,w),colors.lightGray)
    end
    local function indexOf(id) for i,v in ipairs(ui.ids) do if v==id then return i end end return 0 end
    function ui.action(a)
        if not a then return end
        if a~="reset" and a~="update" then ui.confirm=nil end
        if a=="redraw" then return
        elseif a=="help" then ui.help=not ui.help
        elseif a:match("^filter:") then ui.filter=a:sub(8);ui.selected=nil;ui.page=1;ui.cursor=nil
        elseif a:match("^id:") then ui.selected=tonumber(a:sub(4));ui.cursor=ui.selected
        elseif a=="group" then ui.cursor=ui.selected or ui.cursor;ui.selected=nil;ui.followCursor=true
        elseif a=="pageprev" then ui.page=math.max(1,ui.page-1)
        elseif a=="pagenext" then ui.page=math.min(ui.pages or 1,ui.page+1)
        elseif a=="tabprev" or a=="tabnext" then
            local TABS=ui.tabs or {"all","farm","mining"}
            local i=1;for k,t in ipairs(TABS) do if t==ui.filter then i=k end end
            i=(i-1+(a=="tabnext" and 1 or -1))%#TABS+1
            return ui.action("filter:"..TABS[i])
        elseif a=="up" or a=="down" then
            if #ui.ids==0 then return end
            local i=indexOf(ui.selected or ui.cursor)
            if i==0 then i=a=="down" and 1 or #ui.ids else i=math.max(1,math.min(#ui.ids,i+(a=="down" and 1 or -1))) end
            ui.cursor=ui.ids[i];ui.followCursor=true
            if ui.selected then ui.selected=ui.cursor end
        elseif a=="first" or a=="last" then
            if #ui.ids==0 then return end
            ui.cursor=ui.ids[a=="first" and 1 or #ui.ids];ui.followCursor=true
            if ui.selected then ui.selected=ui.cursor end
        elseif a=="open" then
            if not ui.selected and ui.cursor and indexOf(ui.cursor)>0 then ui.selected=ui.cursor end
        elseif a=="next" or a=="prev" then
            local index=indexOf(ui.selected)
            index=(index+(a=="next" and 1 or -1))%(#ui.ids+1)
            ui.selected=ui.ids[index];if ui.selected then ui.cursor=ui.selected end
        elseif a=="reset" or a=="update" then
            -- Sicherheitsabfrage: zweimal innerhalb von 5 s druecken/tippen
            if confirming() and ui.confirm.action==a then ui.confirm=nil;return a end
            ui.confirm={at=os.clock(),action=a};return
        else return a end
    end
    -- Tastatur: Sondertasten (Name aus keys.getName) und Zeichen
    local KEYS={up="up",down="down",enter="open",numPadEnter="open",space="open",backspace="group",
        tab="tabnext",pageUp="pageprev",pageDown="pagenext",home="first",["end"]="last"}
    function ui.key(name)
        if not name then return end
        ui.kbd=true
        if ui.help then ui.help=false;return "redraw" end
        if name=="left" then return ui.selected and "group" or "tabprev" end
        if name=="right" then return ui.selected and nil or "tabnext" end
        local a=KEYS[name]
        if ui.selected and (a=="pageprev" or a=="pagenext") then return a=="pageprev" and "up" or "down" end
        return a
    end
    function ui.char(ch)
        if not ch then return end
        ui.kbd=true
        if ui.help then ui.help=false;return "redraw" end
        return ui.keys[ch:lower()] or ui.keys[ch]
    end
    function ui.target() return ui.selected or ui.filter end
    function ui.click(x,y)
        for i=#ui.buttons,1,-1 do
            local b=ui.buttons[i]
            if b.enabled and y==b.y and x>=b.x and x<b.x+b.w then return b.action end
        end
    end
    ui.keys={["0"]="group",["1"]="start",["2"]="stop",["3"]="once",["4"]="reset",
        s="start",x="stop",e="once",r="reset",h="help",["?"]="help",u="update",
        a="filter:all",f="filter:farm",m="filter:mining"}
    return ui
end
return M
