# Original cover illustrations (icon-like: gold and cream on a deep colour). One SVG per category.
G = "url(#gold)"; CR = "#F6EEDC"; GL = "#E6C26E"
def wrap(bg, body, light="#ffffff"):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" width="600" height="600">
<defs>
 <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F7DE97"/><stop offset=".55" stop-color="#E2B95E"/><stop offset="1" stop-color="#B98A35"/></linearGradient>
 <radialGradient id="glow" cx=".5" cy=".42" r=".62"><stop offset="0" stop-color="{light}" stop-opacity=".22"/><stop offset="1" stop-color="{light}" stop-opacity="0"/></radialGradient>
 <radialGradient id="halo" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#FFF1C4"/><stop offset=".7" stop-color="#E9C66F"/><stop offset="1" stop-color="#C79A42"/></radialGradient>
</defs>
<rect width="600" height="600" fill="{bg}"/><rect width="600" height="600" fill="url(#glow)"/>
{body}
</svg>'''

def cross(cx, cy, s, fill=G):
    # Coptic cross: four equal arms, each ending in three small knobs
    a = s*0.095; L = s*0.40
    parts = [f'<rect x="{cx-a}" y="{cy-L}" width="{2*a}" height="{2*L}" rx="{a*0.3}" fill="{fill}"/>',
             f'<rect x="{cx-L}" y="{cy-a}" width="{2*L}" height="{2*a}" rx="{a*0.3}" fill="{fill}"/>']
    for dx, dy in [(0,-1),(0,1),(-1,0),(1,0)]:
        ex, ey = cx+dx*L, cy+dy*L
        px, py = -dy, dx
        # flared end bar
        parts.append(f'<rect x="{ex - (abs(px)*a*1.9 + abs(dx)*a*0.55)}" y="{ey - (abs(py)*a*1.9 + abs(dy)*a*0.55)}" width="{abs(px)*a*3.8 + abs(dx)*a*1.1}" height="{abs(py)*a*3.8 + abs(dy)*a*1.1}" rx="{a*0.35}" fill="{fill}"/>')
        for k in (-1, 0, 1):
            ox = ex + dx*a*1.25 + px*k*a*1.55; oy = ey + dy*a*1.25 + py*k*a*1.55
            parts.append(f'<circle cx="{ox}" cy="{oy}" r="{a*0.62}" fill="{fill}"/>')
    parts.append(f'<rect x="{cx-a*1.6}" y="{cy-a*1.6}" width="{a*3.2}" height="{a*3.2}" rx="{a*0.5}" transform="rotate(45 {cx} {cy})" fill="{fill}"/>')
    return "\n".join(parts)

def star(cx, cy, r1, r2, n=8, fill=G, rot=-90):
    import math
    pts = []
    for i in range(2*n):
        r = r1 if i % 2 == 0 else r2
        t = math.radians(rot + i*180/n)
        pts.append(f"{cx + r*math.cos(t):.1f},{cy + r*math.sin(t):.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{fill}"/>'

def rays(cx, cy, r0, r1, n, w, color=GL, op=.35, start=0, end=360):
    import math
    out = []
    for i in range(n):
        t = math.radians(start + (end-start)*i/(n if end-start == 360 else max(1, n-1)))
        out.append(f'<line x1="{cx+r0*math.cos(t):.1f}" y1="{cy+r0*math.sin(t):.1f}" x2="{cx+r1*math.cos(t):.1f}" y2="{cy+r1*math.sin(t):.1f}" stroke="{color}" stroke-width="{w}" stroke-linecap="round" opacity="{op}"/>')
    return "\n".join(out)

def palm(x, y, ang, scale=1, fill=G):
    # a palm frond: curved stem with leaflets
    import math
    leaves = []
    for i in range(11):
        t = i/10
        px = 0; py = -t*230
        ln = 70*(1-abs(t-0.45))*1.15
        for side in (-1, 1):
            leaves.append(f'<path d="M{px},{py} q{side*ln*0.55},{-ln*0.15} {side*ln},{-ln*0.55} q{-side*ln*0.45},{ln*0.05} {-side*ln},{ln*0.55}z" fill="{fill}"/>')
    stem = f'<path d="M0,40 Q-6,-100 0,-245" stroke="{fill}" stroke-width="7" fill="none" stroke-linecap="round"/>'
    return f'<g transform="translate({x},{y}) rotate({ang}) scale({scale})">{stem}{"".join(leaves)}</g>'

def chalice(cx, cy, s=1, fill=G):
    return f'''<g transform="translate({cx},{cy}) scale({s})">
<path d="M-95,-120 h190 q-6,120 -95,150 q-89,-30 -95,-150z" fill="{fill}"/>
<rect x="-13" y="28" width="26" height="70" fill="{fill}"/>
<ellipse cx="0" cy="58" rx="26" ry="11" fill="{fill}"/>
<path d="M-70,128 q70,-40 140,0 v12 h-140z" fill="{fill}"/>
<rect x="-95" y="-128" width="190" height="14" rx="7" fill="{fill}"/>
{cross(0, -50, 70, fill="#00000033")}
</g>'''

def qurban(cx, cy, r, fill=CR, ink="#C9A35A"):
    import math
    out = [f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"/>', f'<circle cx="{cx}" cy="{cy}" r="{r*0.93}" fill="none" stroke="{ink}" stroke-width="3"/>']
    for i in range(12):
        t = math.radians(i*30)
        out.append(cross(cx + r*0.72*math.cos(t), cy + r*0.72*math.sin(t), r*0.2, fill=ink))
    out.append(cross(cx, cy, r*0.62, fill=ink))
    return "\n".join(out)

def virgin(cx, cy, s=1, mantle="#2B3E7A", robe="#9E2F2F", child=True, orans=False):
    # icon-like Virgin: halo, veiled head with three stars, optionally the Child
    stars = "".join(star(x, y, 9, 3.6, 8, fill=GL) for x, y in [(0,-118), (-58,-40), (58,-40)])
    hands = ""
    if orans:
        hands = f'<path d="M-95,60 q-70,-40 -80,-150 l30,-6 q12,80 70,120z" fill="{robe}"/><path d="M95,60 q70,-40 80,-150 l-30,-6 q-12,80 -70,120z" fill="{robe}"/><ellipse cx="-162" cy="-108" rx="16" ry="22" fill="#E8C9A6"/><ellipse cx="162" cy="-108" rx="16" ry="22" fill="#E8C9A6"/>'
    kid = ""
    if child:
        kid = f'''<circle cx="0" cy="40" r="52" fill="url(#halo)"/>{cross(0, 40, 92, fill="#C08B2E")}
<circle cx="0" cy="40" r="30" fill="#E8C9A6"/><path d="M-46,150 q0,-70 46,-80 q46,10 46,80z" fill="{CR}"/><path d="M-22,96 l22,40 l22,-40" stroke="{GL}" stroke-width="5" fill="none"/>'''
    return f'''<g transform="translate({cx},{cy}) scale({s})">
<circle cx="0" cy="-95" r="105" fill="url(#halo)"/>
<path d="M-150,230 q0,-220 60,-280 q20,-70 90,-75 q70,5 90,75 q60,60 60,280z" fill="{mantle}"/>
{hands}
<path d="M-62,-80 q8,-62 62,-66 q54,4 62,66 q2,70 -62,90 q-64,-20 -62,-90z" fill="{robe}"/>
<ellipse cx="0" cy="-78" rx="40" ry="50" fill="#E8C9A6"/>
<path d="M-112,-30 q20,-150 112,-150 q92,0 112,150" stroke="{GL}" stroke-width="5" fill="none" opacity=".9"/>
{stars}
{kid}
</g>'''

def dove(cx, cy, s=1, fill=CR):
    return f'''<g transform="translate({cx},{cy}) scale({s})">
<path d="M0,0 q-60,-70 -170,-60 q70,30 90,70 q-50,-10 -80,10 q60,10 90,40z" fill="{fill}"/>
<path d="M0,0 q60,-70 170,-60 q-70,30 -90,70 q50,-10 80,10 q-60,10 -90,40z" fill="{fill}"/>
<ellipse cx="0" cy="40" rx="34" ry="62" fill="{fill}"/>
<circle cx="0" cy="-12" r="24" fill="{fill}"/>
<path d="M-8,-36 l8,-18 l8,18z" fill="{GL}"/>
<path d="M-22,96 l22,34 l22,-34z" fill="{fill}"/>
</g>'''

def flame(x, y, s=1):
    return f'<path transform="translate({x},{y}) scale({s})" d="M0,0 q-22,-30 -6,-62 q4,22 16,26 q-2,-28 14,-50 q8,46 -6,86z" fill="#F4A23A"/>'

def waves(y, color, n=3, gap=34, amp=16, op=.9, w=10):
    out = []
    for k in range(n):
        yy = y + k*gap
        d = f"M-20,{yy} " + " ".join(f"q37.5,{-amp} 75,0 t75,0" for _ in range(9))
        out.append(f'<path d="{d}" stroke="{color}" stroke-width="{w}" fill="none" opacity="{op - k*0.2:.2f}" stroke-linecap="round"/>')
    return "\n".join(out)

covers = {}
covers["nayrouz"] = wrap("#8A2F24", palm(250, 470, -18, 1.25) + palm(350, 470, 18, 1.25) + f'''
<g transform="translate(300,170)"><path d="M-110,40 l-12,-90 l55,45 l67,-85 l67,85 l55,-45 l-12,90z" fill="{G}"/><rect x="-112" y="34" width="224" height="34" rx="6" fill="{G}"/>
<circle cx="-60" cy="51" r="9" fill="#8A2F24"/><circle cx="0" cy="51" r="11" fill="#B23A3A"/><circle cx="60" cy="51" r="9" fill="#8A2F24"/><circle cx="0" cy="-92" r="10" fill="{G}"/></g>''')
covers["fete-de-la-croix"] = wrap("#5E1B29", rays(300, 300, 150, 270, 24, 6) + cross(300, 300, 330))
covers["kiahk"] = wrap("#1E3561", star(300, 92, 34, 13, 8) + virgin(300, 300, 0.95, mantle="#13254A", robe="#8E2B2B"), light="#9EC3FF")
covers["nativite"] = wrap("#7A3524", rays(300, 150, 60, 330, 15, 5, op=.4, start=40, end=140) + star(300, 150, 70, 22, 8) + f'''
<path d="M150,430 l40,90 h220 l40,-90z" fill="{G}"/><rect x="140" y="418" width="320" height="22" rx="8" fill="{G}"/>
<path d="M220,425 q80,-80 160,0z" fill="{CR}"/><circle cx="300" cy="372" r="26" fill="#E8C9A6"/><circle cx="300" cy="372" r="40" fill="none" stroke="{GL}" stroke-width="6"/>''')
covers["epiphanie"] = wrap("#1F5A63", rays(300, 120, 30, 300, 9, 6, op=.35, start=60, end=120) + dove(300, 190, 0.85) + waves(430, CR, 3, 40, 18, .9, 12))
covers["noces-de-cana"] = wrap("#6B2B4C", "".join(f'''<g transform="translate({x},{y})"><path d="M-34,-70 h68 v14 q30,30 24,100 q-6,60 -58,66 q-52,-6 -58,-66 q-6,-70 24,-100z" fill="{G}"/><rect x="-40" y="-82" width="80" height="16" rx="6" fill="{G}"/></g>''' for x, y in [(150,250),(300,250),(450,250),(150,440),(300,440),(450,440)]) + '<circle cx="300" cy="250" r="20" fill="#7A1630"/>')
covers["jonas"] = wrap("#1C4A57", f'''<path d="M110,300 q120,-170 300,-40 l60,-60 q-10,90 0,170 l-60,-50 q-180,130 -300,-20z" fill="{G}"/><circle cx="185" cy="270" r="12" fill="#1C4A57"/>
<path d="M120,320 q40,10 80,-6" stroke="#1C4A57" stroke-width="6" fill="none"/>''' + waves(440, CR, 3, 36, 16, .85, 10))
covers["grand-careme"] = wrap("#3A3A47", f'''<circle cx="150" cy="150" r="46" fill="{G}"/><circle cx="168" cy="138" r="42" fill="#3A3A47"/>
<path d="M40,520 l170,-230 l70,80 l90,-140 l190,290z" fill="#5A5768"/><path d="M40,520 l170,-230 l40,46 l-60,184z" fill="#6C687C"/>''' + cross(370, 175, 130) )
covers["rameaux"] = wrap("#24553F", palm(230, 520, -26, 1.45) + palm(370, 520, 26, 1.45) + palm(300, 540, 0, 1.55))
covers["semaine-sainte"] = wrap("#1A1A1A", cross(300, 300, 250, fill="#7E1D1D") + "".join(
    f'<path d="M{300+150*__import__("math").cos(t):.1f},{300+150*__import__("math").sin(t):.1f} l{22*__import__("math").cos(t+0.9):.1f},{22*__import__("math").sin(t+0.9):.1f}" stroke="{GL}" stroke-width="6" stroke-linecap="round"/>'
    for t in [i*0.3 for i in range(21)]) + f'<circle cx="300" cy="300" r="150" fill="none" stroke="{G}" stroke-width="14"/><circle cx="300" cy="300" r="138" fill="none" stroke="{GL}" stroke-width="5" opacity=".6"/>')
covers["resurrection"] = wrap("#A9472F", rays(300, 300, 120, 290, 28, 6, color="#FFE3A3", op=.45) + f'''
<path d="M160,480 v-170 q140,-170 280,0 v170z" fill="#5C2418"/><path d="M200,480 v-150 q100,-120 200,0 v150z" fill="#2B0F0A"/>
<circle cx="470" cy="440" r="70" fill="#7A3324"/><circle cx="470" cy="440" r="70" fill="none" stroke="{GL}" stroke-width="5"/>''' + cross(300, 175, 120))
covers["ascension"] = wrap("#28577A", rays(300, 250, 60, 300, 20, 5, color="#FFF0C8", op=.35) + cross(300, 160, 120) + f'''
<g fill="{CR}"><circle cx="210" cy="420" r="62"/><circle cx="290" cy="395" r="78"/><circle cx="380" cy="420" r="62"/><rect x="150" y="420" width="300" height="62" rx="31"/></g>''')
covers["pentecote"] = wrap("#9A3B24", dove(300, 230, 0.95) + "".join(flame(120 + i*33, 520 - 0.0*i, 0.9) for i in range(12)))
covers["entree-en-egypte"] = wrap("#8C6424", star(420, 120, 36, 12, 8, fill=CR) + f'''
<path d="M60,470 l130,-190 l130,190z" fill="{G}"/><path d="M60,470 l130,-190 l30,190z" fill="#C99A45"/>
<path d="M280,470 l95,-140 l95,140z" fill="{G}"/><path d="M280,470 l95,-140 l22,140z" fill="#C99A45"/>
<rect x="0" y="468" width="600" height="132" fill="#6E4C17"/>''' + palm(520, 470, 6, 0.8, fill=CR))
covers["jeune-des-apotres"] = wrap("#2F5236", f'''<path d="M300,120 v250" stroke="{G}" stroke-width="10"/>{cross(300, 110, 60)}
<path d="M310,150 q120,90 0,210z" fill="{CR}"/><path d="M290,170 q-90,80 0,190z" fill="{CR}" opacity=".85"/>
<path d="M130,380 h340 l-50,70 h-240z" fill="{G}"/>''' + waves(470, CR, 3, 32, 14, .8, 9))
covers["nahda"] = wrap("#28507A", virgin(300, 300, 1.0, mantle="#163152", robe="#8E2B2B", child=False, orans=True), light="#BFD8FF")
covers["messe"] = wrap("#5A2547", qurban(300, 170, 95) + chalice(300, 400, 0.9))
covers["messe-de-saint-basile"] = wrap("#6A2F22", qurban(300, 300, 200))
covers["messe-de-saint-gregoire"] = wrap("#3F2E5E", rays(300, 300, 160, 290, 24, 5, op=.35) + chalice(300, 320, 1.25))
covers["messe-de-saint-cyrille"] = wrap("#2F4A5E", f'''<path d="M300,60 v90" stroke="{GL}" stroke-width="4"/><circle cx="300" cy="56" r="10" fill="{GL}"/>
<path d="M230,180 l70,-30 l70,30" stroke="{GL}" stroke-width="4" fill="none"/><path d="M230,180 v120 M370,180 v120 M300,150 v150" stroke="{GL}" stroke-width="3"/>
<path d="M210,300 h180 q0,120 -90,130 q-90,-10 -90,-130z" fill="{G}"/><rect x="200" y="290" width="200" height="18" rx="8" fill="{G}"/>
<path d="M260,450 h80 l14,30 h-108z" fill="{G}"/>
<g stroke="{CR}" stroke-width="9" fill="none" opacity=".55" stroke-linecap="round"><path d="M270,270 q-24,-30 0,-60 q24,-30 0,-60"/><path d="M330,270 q24,-30 0,-60 q-24,-30 0,-60"/></g>''' + cross(300, 360, 60, fill="#00000030"))
covers["messe-eveque"] = wrap("#4D3A26", f'''<path d="M200,420 q-10,-180 100,-240 q110,60 100,240z" fill="{G}"/><rect x="190" y="410" width="220" height="40" rx="10" fill="{G}"/>
<path d="M240,240 q60,-30 120,0" stroke="#4D3A26" stroke-width="6" fill="none"/>''' + cross(300, 300, 90, fill="#4D3A26") + cross(300, 140, 70))
covers["tasbeha"] = wrap("#6E5226", rays(300, 300, 190, 280, 32, 4, op=.25) + f'''
<g transform="translate(220,280) rotate(-18)"><ellipse cx="0" cy="0" rx="120" ry="120" fill="{G}"/><ellipse cx="0" cy="0" rx="40" ry="40" fill="#C99A45"/><circle cx="0" cy="0" r="16" fill="#6E5226"/></g>
<g transform="translate(380,330) rotate(18)"><ellipse cx="0" cy="0" rx="120" ry="120" fill="{G}"/><ellipse cx="0" cy="0" rx="40" ry="40" fill="#C99A45"/><circle cx="0" cy="0" r="16" fill="#6E5226"/></g>
<path d="M470,110 l60,105 h-120z" stroke="{CR}" stroke-width="10" fill="none" stroke-linejoin="round"/>''')
covers["tawzih"] = wrap("#43325E", chalice(300, 330, 1.15) + star(300, 95, 30, 12, 8, fill=CR))
covers["franco"] = wrap("#24406B", f'''<path d="M120,430 q90,-40 180,0 q90,-40 180,0 v40 q-90,-40 -180,0 q-90,-40 -180,0z" fill="{CR}"/>
<path d="M120,430 v-120 q90,-40 180,0 v120 q-90,-40 -180,0z" fill="{CR}"/><path d="M300,430 v-120 q90,-40 180,0 v120 q-90,-40 -180,0z" fill="#EADFC6"/>
<rect x="282" y="140" width="36" height="150" rx="6" fill="{CR}"/><path d="M300,138 q-22,-34 0,-76 q22,42 0,76z" fill="#F4A23A"/><path d="M300,128 q-9,-18 0,-38 q9,20 0,38z" fill="#FFE08A"/>''' + rays(300, 100, 50, 120, 12, 4, color="#FFE08A", op=.35))

html = "<html><body style='margin:0;background:#888'>" + "".join(f"<div id='{k}' style='width:600px;height:600px;display:inline-block'>{v}</div>" for k, v in covers.items()) + "</body></html>"
open("covers.html", "w").write(html)
open("keys.txt", "w").write("\n".join(covers))
print(len(covers), "covers")
