-- Toast Control: Oberflaeche fuer Zentrale (Monitor) und Pocket.
-- Passt sich der Bildschirmgroesse an: Liste aller Turtles mit Farbe je Zustand,
-- Antippen zeigt Details. Farm und Mining zeigen jeweils nur ihre eigenen Werte.
local common=dofile("/toast/toast_common.lua")
local M={}
-- Zustand -> Kurztext + Farbe
local WORK={["Abbau"]="Baut ab",["Ernte"]="Erntet",["Pflanzen"]="Pflanzt",["Feld pruefen"]="Prueft",
    ["Fortsetzen"]="Startet",["Neuer Versuch"]="Startet"}
function M.state(e,link)
    local d=e and e.data
    if not link or not e or not e.online or not d then return "Offline","off" end
    if d.recovery then return "Pos. ?","fault" end
    if d.fault or d.status=="Rueckweg blockiert" then return "Fehler","fault" end
    local s=tostring(d.status or "")
    if WORK[s] then return WORK[s],"work" end
    if s=="Rueckkehr" then return "Heimweg","move" end
    if s=="Warten" then return "Wartet","wait" end
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
-- Zeichenhilfen fuer einen Bildschirm (Farbe nur, wenn der Bildschirm sie kann)
local function painter(screen)
    local w,h=screen.getSize()
    local color=screen.isColor and screen.isColor()
    local P={w=w,h=h}
    local function col(c)
        if color then return c end
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
        P.text(x+f,y,string.rep(" ",width-f),colors.white,colors.gray)
    end
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
    P.text(2,1,name,colors.white,colors.blue)
    P.right(1,(e and (e.job=="farm" and "Farm" or "Mine") or "").." #"..id.." ",colors.white,colors.blue)
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
    -- Fortschritt
    y=9
    local pc=math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells))))
    P.text(1,y,"Fortschritt",colors.lightGray);P.right(y,math.floor(pc*100+0.5).."%",colors.white)
    y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind])
    if h>=20 then y=y+1;P.bar(1,y,w,pc,kind=="off" and colors.gray or COLOR[kind]) end
    y=y+2
    -- pro Stunde fuer diese Turtle
    st.hist=st.hist or {}
    local now=os.clock();local key=e.job=="farm" and num(d.total) or num(d.harvested)
    local last=st.hist[#st.hist]
    if not last or now-last.t>=30 then st.hist[#st.hist+1]={t=now,v=key};while #st.hist>31 do table.remove(st.hist,1) end end
    local first=st.hist[1]
    local perH=(first and now-first.t>=60) and short(math.max(0,(key-first.v)/(now-first.t)*3600)) or "-"
    local rows
    if e.job=="farm" then
        rows={{"Runden",short(d.rounds)},{"Diese Runde",short(d.roundYield).." Items"},{"Geerntet",short(d.harvested).." Pflanzen"},
            {"Ertrag",short(d.total).." Items"},{"Ertrag / Stunde",perH},{"Saatgut",short(d.seeds)}}
        if num(d.wait)>0 then rows[#rows+1]={"Naechste Runde","in "..num(d.wait).." s"} end
    else
        rows={{"Gaenge fertig",short(d.rounds)..(d.tunnels and (" / "..d.tunnels) or "")},{"Abgebaut",short(d.harvested).." Bloecke"},
            {"Abgebaut / Stunde",perH},{"Abgeladen",short(d.total).." Items"},{"Freie Slots",short(d.freeSlots)}}
    end
    rows[#rows+1]={"Fuel",d.fuel=="unlimited" and "unbegrenzt" or short(d.fuel)}
    if d.chunks then rows[#rows+1]={"Chunks",d.chunks>0 and (d.chunks.."  (-"..short(d.chunkFuel).." Fuel/h)") or "aus"} end
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
    if show=="farm" or show=="mining" then
        local ids={}
        for _,id in ipairs(fleet.ids or {}) do if (entries[id] or {}).job==show then ids[#ids+1]=id end end
        fleet={ids=ids,entries=entries}
    end
    local count,act={farm=0,mining=0},{farm=0,mining=0}
    local farmTotal,farmHarv,mineHarv,mineTotal,fuel,chunk,progSum,progN=0,0,0,0,0,0,0,0
    local problems,list={},{}
    for _,id in ipairs(fleet.ids or {}) do
        local e=entries[id] or {};local d=e.data or {}
        local job=e.job=="farm" and "farm" or "mining"
        local label,kind=M.state(e,link)
        count[job]=count[job]+1
        if kind=="work" or kind=="move" or kind=="wait" then act[job]=act[job]+1 end
        if job=="farm" then farmTotal=farmTotal+num(d.total);farmHarv=farmHarv+num(d.harvested)
        else mineHarv=mineHarv+num(d.harvested);mineTotal=mineTotal+num(d.total)
            if num(d.cells)>0 then progSum=progSum+num(d.scanned)/num(d.cells);progN=progN+1 end end
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
        st.hist[#st.hist+1]={t=now,farm=farmTotal,mine=mineHarv}
        while #st.hist>31 do table.remove(st.hist,1) end
    end
    local function rate(key,cur)
        local first=st.hist[1]
        if not first or now-first.t<60 then return "-" end
        return short(math.max(0,(cur-first[key])/(now-first.t)*3600))
    end
    -- Kopf
    P.fill(1,colors.blue)
    local online=0;for _,l in ipairs(list) do if l.kind~="off" then online=online+1 end end
    local clock=""
    if textutils and textutils.formatTime and os.time then
        local ok,t=pcall(function() return textutils.formatTime(os.time(),true) end);if ok then clock=t end
    end
    local rt=link and (online.."/"..#list.." online"..(clock~="" and ("  "..clock) or "").." ") or "keine Verbindung "
    local title=show=="farm" and "Farmen" or show=="mining" and "Minen" or "Uebersicht"
    P.text(2,1,(#rt+10+#title<=w) and ("TOAST  "..title) or "TOAST",colors.white,colors.blue)
    P.right(1,rt,link and colors.white or colors.orange,colors.blue)
    -- Gruppen-Kacheln (nebeneinander, wenn Platz)
    local y=3
    local function panel(x,y0,pw,title,a,n,rows)
        if n==0 then return y0 end
        P.text(x,y0,title,colors.white)
        local s=a.."/"..n.." aktiv"
        P.text(x+pw-#s,y0,s,a>0 and colors.lime or colors.lightGray)
        local yy=y0+1
        for _,r in ipairs(rows) do
            P.text(x,yy,r[1],colors.lightGray)
            P.text(x+pw-#r[2],yy,r[2],colors.white)
            yy=yy+1
        end
        return yy
    end
    local side=w>=50 and count.farm>0 and count.mining>0
    -- Kleiner Bildschirm: nur die wichtigsten Zeilen, damit die Liste Platz hat
    local compact=not side and h<26 and count.farm>0 and count.mining>0
    local prog=(progN>0 and math.floor(progSum/progN*100+0.5) or 0).."%"
    local farmRows,mineRows
    if compact then
        farmRows={{"Ertrag",short(farmTotal).."  ("..rate("farm",farmTotal).."/h)"}}
        mineRows={{"Abgebaut",short(mineHarv).."  ("..rate("mine",mineHarv).."/h)"},{"Fortschritt",prog}}
    else
        farmRows={{"Ertrag",short(farmTotal).." Items"},{"pro Stunde",rate("farm",farmTotal)},{"Geerntet",short(farmHarv).." Pfl."}}
        mineRows={{"Abgebaut",short(mineHarv).." Bl."},{"pro Stunde",rate("mine",mineHarv)},
            {"Abgeladen",short(mineTotal).." Items"},{"Fortschritt",prog}}
    end
    if side then
        local pw=math.floor((w-3)/2)
        local y1=panel(1,y,pw,"FARM",act.farm,count.farm,farmRows)
        local y2=panel(pw+4,y,w-pw-3,"MINE",act.mining,count.mining,mineRows)
        y=math.max(y1,y2)+1
    else
        local gap=compact and 0 or 1
        local y1=panel(1,y,w,"FARM",act.farm,count.farm,farmRows)
        if count.farm>0 then y=y1+gap end
        local y2=panel(1,y,w,"MINE",act.mining,count.mining,mineRows)
        if count.mining>0 then y=y2+1 end
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
        local barW=w>=40 and math.min(20,w-34) or 0
        for i=1,avail do
            local l=list[(st.page-1)*avail+i];if not l then break end
            local d=l.e.data or {}
            local name=l.e.label~="" and l.e.label or ((l.job=="farm" and "Farm" or "Mine").." #"..l.id)
            P.text(1,y,"\7",COLOR[l.kind])
            local stx=w-8
            local val=""
            if l.kind~="off" then val=l.job=="farm" and short(d.total) or short(d.harvested) end
            if barW>0 then
                stx=w-8-barW-6
                if l.kind~="off" then P.bar(w-barW-6+1,y,barW,num(d.scanned)/math.max(1,num(d.cells)),COLOR[l.kind]) end
                P.right(y,val,colors.lightGray)
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
    local ui={filter="all",selected=nil,page=1,buttons={},ids={}}
    function ui.setScreen(s) screen=s end
    function ui.draw(fleet,link,notice)
        local w,h=screen.getSize();ui.buttons={}
        local color=screen.isColor and screen.isColor()
        -- Ohne Farbbildschirm nur Grautoene verwenden
        local function col(c)
            if color then return c end
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
        local function button(x,y,width,label,action,bg,enabled)
            if width<1 then return end
            local b=enabled and bg or colors.gray
            local l=tostring(label):sub(1,width)
            local pad=math.floor((width-#l)/2)
            text(x,y,string.rep(" ",width),colors.white,b)
            text(x+pad,y,l,enabled and colors.white or colors.lightGray,b)
            ui.buttons[#ui.buttons+1]={x=x,y=y,w=width,action=action,enabled=enabled}
        end
        screen.setBackgroundColor(colors.black);screen.setTextColor(colors.white);screen.clear()
        if w<24 or h<12 then
            text(1,1,"TOAST",colors.cyan);text(1,3,"Bildschirm zu klein",colors.orange)
            text(1,4,"mind. 24 x 12 Zeichen");text(1,5,"(Monitor groesser oder");text(1,6," Schrift kleiner)");return
        end
        local entries=fleet.entries or {}
        -- Zaehlen + Gruppenwerte
        local ids,count={},{farm=0,mining=0}
        local g={farm={on=0,act=0,total=0,harv=0},mining={on=0,act=0,total=0,harv=0}}
        local online,faults,chunkFuel=0,0,0
        for _,id in ipairs(fleet.ids or {}) do
            local e=entries[id] or {};local d=e.data or {}
            local job=e.job=="farm" and "farm" or "mining"
            count[job]=count[job]+1
            local _,kind=M.state(e,link)
            local gg=g[job]
            gg.total=gg.total+num(d.total);gg.harv=gg.harv+num(d.harvested)
            if kind~="off" then gg.on=gg.on+1 end
            if kind=="work" or kind=="move" or kind=="wait" then gg.act=gg.act+1 end
            if ui.filter=="all" or e.job==ui.filter then
                ids[#ids+1]=id
                if kind~="off" then online=online+1 end
                if kind=="fault" or kind=="warn" then faults=faults+1 end
                if kind~="off" and num(d.chunks)>0 then chunkFuel=chunkFuel+num(d.chunkFuel) end
            end
        end
        ui.ids=ids
        if ui.selected and not common.contains(ids,ui.selected) then ui.selected=nil end
        -- Kopfzeile
        fill(1,colors.blue)
        text(2,1,"TOAST",colors.white,colors.blue)
        if link then right(1,online.."/"..#ids.." online ",colors.white,colors.blue)
        else right(1,"keine Verbindung ",colors.orange,colors.blue) end
        -- Reiter
        local tabs={{"Alle "..(count.farm+count.mining),"all"},{"Farm "..count.farm,"farm"},{"Mine "..count.mining,"mining"}}
        local third=math.floor(w/3)
        for i,t in ipairs(tabs) do
            local active=ui.filter==t[2]
            button(1+(i-1)*third,2,i==3 and w-2*third or third,t[1],"filter:"..t[2],active and colors.lightBlue or colors.gray,true)
        end
        -- Fusszeile: Hinweis + 2 Tastenreihen
        local foot=h-2
        local sel=ui.selected and entries[ui.selected]
        local job=sel and sel.job or (ui.filter~="all" and ui.filter) or nil
        local once=job=="farm" and "1 Runde" or job=="mining" and "1 Gang" or "1x"
        local canStart=false
        for _,id in ipairs(ids) do
            local e=entries[id]
            if link and (not ui.selected or ui.selected==id) and e and e.online and e.data and not e.data.recovery then canStart=true end
        end
        for i,b in ipairs({{"START","start",colors.green},{"STOP","stop",colors.red},{once,"once",colors.blue}}) do
            button(1+(i-1)*third,foot+1,i==3 and w-2*third or third,b[1],b[2],b[3],b[2]=="stop" and link or canStart)
        end
        local perPage
        -- ===== Detailansicht =====
        if sel then
            local d=sel.data or {}
            local label,kind=M.state(sel,link)
            local name=(sel.label and sel.label~="" and sel.label or (sel.job=="farm" and "Farm" or "Mine")).." #"..ui.selected
            button(1,3,w,"< "..name,"group",colors.gray,true)
            fill(4,COLOR[kind])
            local why=(kind=="fault" or kind=="warn") and (d.fault or d.status) or nil
            text(2,4,label..(why and (": "..tostring(why)) or ""),colors.black,COLOR[kind])
            -- Detailtext umbrechen (max. 2 Zeilen)
            local det=kind=="off" and "Keine Daten - Turtle offline oder Chunk entladen" or tostring(d.detail or "")
            local y=5
            while #det>0 and y<=6 do text(1,y,det:sub(1,w),colors.lightGray);det=det:sub(w+1);y=y+1 end
            y=7
            -- Fortschrittsbalken
            local pc=math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells))))
            local barW=math.max(4,w-6)
            local fillW=math.floor(barW*pc+0.5)
            text(1,y,string.rep(" ",fillW),colors.white,colors.lime)
            text(1+fillW,y,string.rep(" ",barW-fillW),colors.white,colors.gray)
            right(y,math.floor(pc*100+0.5).."%",colors.white)
            y=y+2
            local rows={}
            if sel.job=="farm" then
                rows={{"Runden",short(d.rounds)},{"Geerntet",short(d.harvested).." Pflanzen"},
                    {"Ertrag",short(d.total).." Items"},{"Saatgut",short(d.seeds)}}
                if num(d.roundYield)>0 then table.insert(rows,3,{"Diese Runde",short(d.roundYield).." Items"}) end
            else
                rows={{"Gaenge",short(d.rounds).." fertig"},{"Abgebaut",short(d.harvested).." Bloecke"},
                    {"Abgeladen",short(d.total).." Items"},{"Freie Slots",short(d.freeSlots)}}
            end
            rows[#rows+1]={"Fuel",d.fuel=="unlimited" and "unbegrenzt" or short(d.fuel)}
            if d.chunks then rows[#rows+1]={"Chunks",d.chunks>0 and (d.chunks..", -"..short(d.chunkFuel).."/h") or "aus"} end
            for _,r in ipairs(rows) do
                if y>=foot-1 then break end
                text(1,y,r[1],colors.lightGray);text(13,y,r[2],colors.white);y=y+1
            end
        else
        -- ===== Uebersicht =====
            local y=3
            local function group(jobName,title,valLabel,val)
                local gg=g[jobName]
                if count[jobName]==0 then return end
                text(1,y,title,colors.white)
                text(6,y,gg.act.."/"..count[jobName]..(w>=34 and " aktiv" or ""),gg.act>0 and colors.lime or colors.lightGray)
                right(y,valLabel.." "..short(val),colors.lightGray)
                y=y+1
            end
            if ui.filter~="mining" then group("farm","Farm","Ertrag",g.farm.total) end
            if ui.filter~="farm" then group("mining","Mine","Abgebaut",g.mining.harv) end
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
            for row=1,perPage do
                local id=ids[(ui.page-1)*perPage+row];if not id then break end
                local e=entries[id] or {};local d=e.data or {}
                local label,kind=M.state(e,link)
                local yy=top+row-1
                local name=e.label and e.label~="" and e.label or ((e.job=="farm" and "Farm" or "Mine").." #"..id)
                local stW=8
                local extra=""
                if wide and kind~="off" then
                    local pc=math.floor(math.max(0,math.min(1,num(d.scanned)/math.max(1,num(d.cells))))*100+0.5)
                    extra=string.format("%4d%%   %-8s%6s",pc,e.job=="farm" and "Ertrag" or "Abgebaut",e.job=="farm" and short(d.total) or short(d.harvested))
                end
                local nameW=w-2-stW-1-(#extra>0 and #extra+2 or 0)
                text(1,yy,string.rep(" ",w),colors.white,colors.black)
                text(1,yy,"\7",COLOR[kind])
                text(3,yy,name:sub(1,nameW),kind=="off" and colors.gray or colors.white)
                if #extra>0 then text(w-stW-#extra-1,yy,extra,colors.lightGray) end
                right(yy,string.format("%-8s",label),COLOR[kind])
                ui.buttons[#ui.buttons+1]={x=1,y=yy,w=w,action="id:"..id,enabled=true}
            end
        end
        -- Hinweiszeile + untere Tastenreihe
        local info=tostring(notice or "")
        if info=="" or info:find("bestaetigt",1,true) then
            info=sel and "Ziel: diese Turtle" or ("Ziel: "..(ui.filter=="all" and "alle" or ui.filter=="farm" and "alle Farmen" or "alle Minen"))
            if not sel and #info+20<=w then info=info.."  (Tippen = Details)" end
        end
        text(1,foot,info:sub(1,w),colors.lightGray)
        local pages=ui.pages or 1
        if not sel and pages>1 then
            button(1,foot+2,third,"<","pageprev",colors.gray,ui.page>1)
            button(1+third,foot+2,third,"RESET","reset",colors.orange,link and #ids>0)
            button(1+2*third,foot+2,w-2*third,ui.page.."/"..pages.." >","pagenext",colors.gray,ui.page<pages)
        else
            button(1,foot+2,w,w>=38 and "RESET  (Fehler loeschen + heim)" or "RESET","reset",colors.orange,link and #ids>0)
        end
    end
    function ui.action(a)
        if not a then return end
        if a:match("^filter:") then ui.filter=a:sub(8);ui.selected=nil;ui.page=1
        elseif a:match("^id:") then ui.selected=tonumber(a:sub(4))
        elseif a=="group" then ui.selected=nil
        elseif a=="pageprev" then ui.page=math.max(1,ui.page-1)
        elseif a=="pagenext" then ui.page=math.min(ui.pages or 1,ui.page+1)
        elseif a=="next" or a=="prev" then
            local index=0;for i,id in ipairs(ui.ids) do if id==ui.selected then index=i end end
            index=(index+(a=="next" and 1 or -1))%(#ui.ids+1)
            ui.selected=ui.ids[index]
        else return a end
    end
    function ui.target() return ui.selected or ui.filter end
    function ui.click(x,y)
        for i=#ui.buttons,1,-1 do
            local b=ui.buttons[i]
            if b.enabled and y==b.y and x>=b.x and x<b.x+b.w then return b.action end
        end
    end
    ui.keys={["0"]="group",["1"]="start",["2"]="stop",["3"]="once",["4"]="reset",["a"]="filter:all",["f"]="filter:farm",["m"]="filter:mining"}
    return ui
end
return M
