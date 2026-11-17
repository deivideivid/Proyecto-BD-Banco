"""Banco Andino | B3 | Genera las 4 páginas del informe de Power BI en formato PBIR.

Lo usamos así: guardamos el informe como proyecto de Power BI (.pbip), cerramos Power BI,
corrimos este script, copiamos la carpeta `paginas_generadas/pages` que crea dentro de
`BancoAndino.Report/definition/` y volvimos a abrir el .pbip. Cada objeto visual queda con su
posición en computador (visual.json) y en celular (mobile.json).
"""
import json, os, hashlib, shutil
OUT='paginas_generadas'
VS="https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.4.0/schema.json"
PS="https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json"
FT='bi fact_transaccion'; FS='bi fact_saldo_cuenta'; FC='bi fact_control'; CP='bi calidad_prueba'
DF='bi dim_fecha'; DP='bi dim_producto'; DO='bi dim_oficina'; DT='bi dim_tipo_transaccion'; DC='bi dim_cliente'
def lit(v): return {"expr":{"Literal":{"Value":v}}}
def M(t,p): return {"Measure":{"Expression":{"SourceRef":{"Entity":t}},"Property":p}}
def C(t,p): return {"Column":{"Expression":{"SourceRef":{"Entity":t}},"Property":p}}
def proj(f):
    k='Measure' if 'Measure' in f else 'Column'
    t=f[k]['Expression']['SourceRef']['Entity']; p=f[k]['Property']
    return {"field":f,"queryRef":f"{t}.{p}","nativeQueryRef":p}
def nid(*a): return hashlib.md5('|'.join(map(str,a)).encode()).hexdigest()[:20]
def title(text): return {"title":[{"properties":{"show":lit("true"),"text":lit("'"+text.replace("'","''")+"'")}}]}
def vis(page,i,vtype,pos,roles,ttl=None,objects=None,sort=None):
    q={"queryState":{r:{"projections":[proj(f) for f in fs]} for r,fs in roles.items()}}
    if sort: q["sortDefinition"]={"sort":[{"field":sort[0],"direction":sort[1]}],"isDefaultSort":True}
    v={"visualType":vtype,"query":q}
    if objects: v["objects"]=objects
    vco={}
    if ttl: vco.update(title(ttl))
    if vco: v["visualContainerObjects"]=vco
    x,y,w,h=pos
    return {"$schema":VS,"name":nid(page,i),"position":{"x":x,"y":y,"z":i*1000,"width":w,"height":h,"tabOrder":i*1000},"visual":v}
def textbox(page,i,pos,text,size="20pt"):
    x,y,w,h=pos
    return {"$schema":VS,"name":nid(page,i),"position":{"x":x,"y":y,"z":i*1000,"width":w,"height":h,"tabOrder":i*1000},
            "visual":{"visualType":"textbox","objects":{"general":[{"properties":{"paragraphs":[{"textRuns":[{"value":text,"textStyle":{"fontWeight":"bold","fontSize":size}}]}]}}]}}}
def slicer(page,i,pos,f,ttl):
    return vis(page,i,"slicer",pos,{"Values":[f]},ttl,objects={"data":[{"properties":{"mode":lit("'Dropdown'")}}]})
def card(page,i,pos,f): return vis(page,i,"card",pos,{"Values":[f]})
W,H=1280,720
def header(pg,name):
    out=[textbox(pg,0,(24,12,520,48),"Banco Andino · "+name),
         slicer(pg,1,(600,10,210,58),C(DF,'anio_mes'),'Mes'),
         slicer(pg,2,(825,10,210,58),C(DP,'producto'),'Producto'),
         slicer(pg,3,(1050,10,210,58),C(DO,'departamento'),'Departamento (oficina)')]
    return out
def cards_row(pg,start,ms,y=84,h=96):
    n=len(ms); gap=12; w=(W-48-gap*(n-1))/n
    return [card(pg,start+k,(24+k*(w+gap),y,w,h),m) for k,m in enumerate(ms)]
pages=[]
# 1 Resumen
pg='resumen'; v=header(pg,'Resumen')
v+=cards_row(pg,10,[M(FT,'K01 Transacciones contabilizadas'),M(FT,'K02 Monto movido COP'),M(FT,'K07 Clientes con movimientos'),M(FS,'K08 Cuentas activas'),M(FS,'K09 Saldo total COP'),M(FT,'K05 Tasa de rechazo %')])
v.append(vis(pg,20,"lineChart",(24,196,760,500),{"Category":[C(DF,'anio_mes')],"Y":[M(FT,'K02 Monto movido COP')]},"Monto movido COP por mes",sort=(C(DF,'anio_mes'),"Ascending")))
v.append(vis(pg,21,"barChart",(800,196,456,500),{"Category":[C(DT,'tipo')],"Y":[M(FT,'K01 Transacciones contabilizadas')]},"Transacciones por tipo",sort=(M(FT,'K01 Transacciones contabilizadas'),"Descending")))
pages.append((pg,'Resumen',v))
# 2 Transacciones
pg='transacciones'; v=header(pg,'Transacciones')
v+=cards_row(pg,10,[M(FT,'K01 Transacciones contabilizadas'),M(FT,'K04 Ticket promedio COP'),M(FT,'K03 Monto movido USD'),M(FT,'K05 Tasa de rechazo %'),M(FT,'Transacciones rechazadas'),M(FT,'K06 Reversos')])
v.append(vis(pg,20,"clusteredColumnChart",(24,196,610,250),{"Category":[C(FT,'hora')],"Y":[M(FT,'K01 Transacciones contabilizadas')]},"Transacciones por hora del día",sort=(C(FT,'hora'),"Ascending")))
v.append(vis(pg,21,"clusteredColumnChart",(646,196,610,250),{"Category":[C(DF,'nombre_dia')],"Y":[M(FT,'K01 Transacciones contabilizadas')]},"Transacciones por día de la semana"))
v.append(vis(pg,22,"barChart",(24,458,610,240),{"Category":[C(FT,'motivo_rechazo')],"Y":[M(FT,'Transacciones rechazadas')]},"Rechazos por motivo",sort=(M(FT,'Transacciones rechazadas'),"Descending")))
v.append(vis(pg,23,"barChart",(646,458,610,240),{"Category":[C(DT,'tipo')],"Y":[M(FT,'K02 Monto movido COP')]},"Monto movido COP por tipo",sort=(M(FT,'K02 Monto movido COP'),"Descending")))
pages.append((pg,'Transacciones',v))
# 3 Clientes y cuentas
pg='clientes'; v=header(pg,'Clientes y cuentas')
v+=cards_row(pg,10,[M(FS,'Cuentas al corte'),M(FS,'K08 Cuentas activas'),M(FS,'K11 Cuentas en sobregiro'),M(FS,'K09 Saldo total COP'),M(FS,'K10 Saldo total USD'),M(FT,'K07 Clientes con movimientos')])
v.append(vis(pg,20,"donutChart",(24,196,400,250),{"Category":[C(FS,'estado_cuenta')],"Y":[M(FS,'Cuentas al corte')]},"Cuentas por estado (al corte)"))
v.append(vis(pg,21,"clusteredColumnChart",(436,196,400,250),{"Category":[C(DP,'producto')],"Y":[M(FS,'Cuentas al corte')]},"Cuentas por producto",sort=(M(FS,'Cuentas al corte'),"Descending")))
v.append(vis(pg,22,"barChart",(848,196,408,502),{"Category":[C(DO,'departamento')],"Y":[M(FS,'K09 Saldo total COP')]},"Saldo COP por departamento de la oficina",sort=(M(FS,'K09 Saldo total COP'),"Descending")))
v.append(vis(pg,23,"tableEx",(24,458,812,240),{"Values":[C(DC,'cliente'),C(DC,'tipo_cliente'),C(DC,'departamento'),M(FS,'Cuentas al corte'),M(FS,'K09 Saldo total COP')]},"Clientes con más saldo en pesos",sort=(M(FS,'K09 Saldo total COP'),"Descending")))
pages.append((pg,'Clientes y cuentas',v))
# 4 Control y calidad
pg='control'; v=[textbox(pg,0,(24,12,700,48),"Banco Andino · Control y calidad de datos")]
v+=cards_row(pg,10,[M(CP,'K12 Puntaje del quality gate'),M(FC,'K13 Controles en PASS'),M(FT,'K01 Transacciones contabilizadas'),M(FS,'Cuentas al corte')])
v.append(vis(pg,20,"tableEx",(24,196,1232,230),{"Values":[C(FC,'control_id'),C(FC,'grupo'),C(FC,'control'),C(FC,'esperado'),C(FC,'obtenido'),C(FC,'resultado')]},"Controles de cuadre y calidad (fecha de carga)",sort=(C(FC,'control_id'),"Ascending")))
v.append(vis(pg,21,"tableEx",(24,438,1232,260),{"Values":[C(CP,'test_id'),C(CP,'dimension'),C(CP,'regla'),C(CP,'severidad'),C(CP,'resultado'),C(CP,'obtenido')]},"Pruebas del quality gate de G6",sort=(C(CP,'resultado'),"Descending")))
pages.append((pg,'Control y calidad',v))

shutil.rmtree(OUT,ignore_errors=True)
order=[]
for pg,dn,vs in pages:
    pid='4e655c4ac0eebea65e59' if pg=='resumen' else nid('page',pg); order.append(pid)
    d=f"{OUT}/pages/{pid}"; os.makedirs(d+"/visuals",exist_ok=True)
    json.dump({"$schema":PS,"name":pid,"displayName":dn,"displayOption":"FitToPage","height":H,"width":W},open(d+"/page.json","w",encoding='utf-8'),ensure_ascii=False,indent=2)
    for vv in vs:
        os.makedirs(f"{d}/visuals/{vv['name']}",exist_ok=True)
        json.dump(vv,open(f"{d}/visuals/{vv['name']}/visual.json","w",encoding='utf-8'),ensure_ascii=False,indent=2)
json.dump({"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json","pageOrder":order,"activePageName":order[0]},open(f"{OUT}/pages/pages.json","w",encoding='utf-8'),indent=2)
print(order)

# ---- Diseño para celular (mobile.json en cada objeto visual) ----
MS="https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainerMobileState/2.4.0/schema.json"
MW=320
for pg,dn,vs in pages:
    pid='4e655c4ac0eebea65e59' if pg=='resumen' else nid('page',pg)
    y=0; cards=[]
    for vv in vs:
        t=vv['visual']['visualType']
        if t=='card': cards.append(vv); continue
    def put(vv,x,y,w,h):
        json.dump({"$schema":MS,"position":{"x":x,"y":y,"z":vv['position']['z'],"width":w,"height":h,"tabOrder":vv['position']['tabOrder']}},
                  open(f"{OUT}/pages/{pid}/visuals/{vv['name']}/mobile.json","w",encoding='utf-8'),indent=2)
    others=[vv for vv in vs if vv['visual']['visualType']!='card']
    tb=[vv for vv in others if vv['visual']['visualType']=='textbox']
    sl=[vv for vv in others if vv['visual']['visualType']=='slicer']
    ch=[vv for vv in others if vv['visual']['visualType'] not in ('textbox','slicer')]
    for vv in tb: put(vv,0,y,MW,44); y+=48
    for vv in sl: put(vv,0,y,MW,56); y+=60
    for k,vv in enumerate(cards):
        put(vv,(k%2)*164,y+(k//2)*88,156,80)
    y+=((len(cards)+1)//2)*88
    for vv in ch:
        h=280 if vv['visual']['visualType']=='tableEx' else 230
        put(vv,0,y,MW,h); y+=h+8
print('mobile ok')
