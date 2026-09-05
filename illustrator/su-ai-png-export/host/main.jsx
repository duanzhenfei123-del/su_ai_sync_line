var VERSION = "3.7.2";
var desktop = Folder.desktop;

function padZero(n,l){var s=String(n);while(s.length<l)s="0"+s;return s}
function fmt(d){return d.getFullYear()+"-"+padZero(d.getMonth()+1,2)+"-"+padZero(d.getDate(),2)+" "+padZero(d.getHours(),2)+":"+padZero(d.getMinutes(),2)+":"+padZero(d.getSeconds(),2)}
function fmtFile(d){return d.getFullYear()+"-"+padZero(d.getMonth()+1,2)+"-"+padZero(d.getDate(),2)+"_"+padZero(d.getHours(),2)+"-"+padZero(d.getMinutes(),2)+"-"+padZero(d.getSeconds(),2)}
function _jsonStringify(obj) {
    if (obj === null || obj === undefined) return "null";
    if (typeof obj === "string") return '"' + obj.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
    if (typeof obj === "number") return isFinite(obj) ? String(obj) : "null";
    if (typeof obj === "boolean") return obj ? "true" : "false";
    if (obj instanceof Array) {
        var arr = [];
        for (var i = 0; i < obj.length; i++) arr.push(_jsonStringify(obj[i]));
        return "[" + arr.join(",") + "]";
    }
    if (typeof obj === "object") {
        var props = [];
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) {
                var val = _jsonStringify(obj[key]);
                if (val !== undefined) props.push('"' + key + '":' + val);
            }
        }
        return "{" + props.join(",") + "}";
    }
    return "null";
}
function mm(p){return p/(72/25.4)}
function r4(v){return Math.round(v*10000)/10000}
function clampColor(v){return Math.max(0,Math.min(255,Math.round(v)))}
function colorToRGB(c){
    if(!c)return null;
    if(c.typename==="RGBColor")return[clampColor(c.red),clampColor(c.green),clampColor(c.blue)];
    if(c.typename==="CMYKColor"){
        var k=c.black/100,remaining=1-k;
        return[clampColor(255*(1-c.cyan/100)*remaining),clampColor(255*(1-c.magenta/100)*remaining),clampColor(255*(1-c.yellow/100)*remaining)];
    }
    if(c.typename==="GrayColor"){
        var gray=clampColor(255*c.gray/100);
        return[gray,gray,gray];
    }
    if(c.typename==="SpotColor"){
        var base=colorToRGB(c.spot.color);
        if(!base)return null;
        var tint=Math.max(0,Math.min(100,c.tint))/100;
        return[clampColor(255-(255-base[0])*tint),clampColor(255-(255-base[1])*tint),clampColor(255-(255-base[2])*tint)];
    }
    try{
        if(c.typename==="LabColor"){
            var converted=app.convertSampleColor(ImageColorSpace.LAB,[c.l,c.a,c.b],ImageColorSpace.RGB,ColorConvertPurpose.defaultpurpose);
            return[clampColor(converted[0]),clampColor(converted[1]),clampColor(converted[2])];
        }
    }catch(e){}
    return null;
}
function hex(c){var rgb=colorToRGB(c);if(!rgb)return"";var h=(rgb[0]*65536+rgb[1]*256+rgb[2]).toString(16).toUpperCase();while(h.length<6)h="0"+h;return h}
function esc(s){
    return String(s).replace(/[\\"\u0000-\u001F]/g,function(ch){
        var map={"\\":"\\\\","\"":"\\\"","\b":"\\b","\f":"\\f","\n":"\\n","\r":"\\r","\t":"\\t"};
        if(map[ch])return map[ch];
        return "\\u"+("000"+ch.charCodeAt(0).toString(16)).slice(-4);
    });
}
function ownedSyncFile(name){return /^sync_.*\.(json|tmp)$/i.test(name)||/^latest_sync\.json\.tmp$/i.test(name)}
var TOL=0.01;
var TEXT_OUTLINE_COUNTER=0;
var COMPOUND_COUNTER=0;
function itemZIndex(item,fallback){
    try{
        var siblings=item.parent&&item.parent.pageItems;
        if(siblings){for(var i=0;i<siblings.length;i++){if(siblings[i]===item)return siblings.length-i}}
    }catch(e){}
    try{if(item.zOrderPosition!==undefined)return Number(item.zOrderPosition)}catch(e){}
    return Number(fallback||0);
}
function nextCompoundKey(){return "compound_"+padZero(COMPOUND_COUNTER++,4)}
function isLine(cur,nxt){
    return Math.abs(cur.anchor[0]-cur.rightDirection[0])<TOL&&Math.abs(cur.anchor[1]-cur.rightDirection[1])<TOL&&Math.abs(nxt.anchor[0]-nxt.leftDirection[0])<TOL&&Math.abs(nxt.anchor[1]-nxt.leftDirection[1])<TOL;
}
function polygonArea(vs){var n=vs.length,a=0;for(var i=0,j=n-1;i<n;j=i++)a+=(vs[j][0]+vs[i][0])*(vs[j][1]-vs[i][1]);return Math.abs(a/2);}
function log(m){}

var CURVE_TOLERANCE_MM=0.04;
var MAX_CURVE_DEPTH=10;
var STROKE_MITER_LIMIT=4;

function pointLineDistance(p,a,b){
    var dx=b[0]-a[0],dy=b[1]-a[1],length=Math.sqrt(dx*dx+dy*dy);
    if(length<0.000001){dx=p[0]-a[0];dy=p[1]-a[1];return Math.sqrt(dx*dx+dy*dy)}
    return Math.abs(dy*p[0]-dx*p[1]+b[0]*a[1]-b[1]*a[0])/length;
}

function flattenCubic(p0,p1,p2,p3,tolerance,depth,result){
    if(depth>=MAX_CURVE_DEPTH||(pointLineDistance(p1,p0,p3)<=tolerance&&pointLineDistance(p2,p0,p3)<=tolerance)){
        result.push([r4(p3[0]),r4(p3[1])]);return;
    }
    var p01=[(p0[0]+p1[0])/2,(p0[1]+p1[1])/2];
    var p12=[(p1[0]+p2[0])/2,(p1[1]+p2[1])/2];
    var p23=[(p2[0]+p3[0])/2,(p2[1]+p3[1])/2];
    var p012=[(p01[0]+p12[0])/2,(p01[1]+p12[1])/2];
    var p123=[(p12[0]+p23[0])/2,(p12[1]+p23[1])/2];
    var mid=[(p012[0]+p123[0])/2,(p012[1]+p123[1])/2];
    flattenCubic(p0,p01,p012,mid,tolerance,depth+1,result);
    flattenCubic(mid,p123,p23,p3,tolerance,depth+1,result);
}

function subdividePath(vertices,curves,closed){
    if(!vertices||vertices.length<2)return vertices||[];
    var result=[[vertices[0][0],vertices[0][1]]];
    var segmentCount=closed?vertices.length:vertices.length-1;
    for(var i=0;i<segmentCount;i++){
        var next=(i+1)%vertices.length,curve=curves&&curves[i];
        if(curve)flattenCubic(vertices[i],[curve[0],curve[1]],[curve[2],curve[3]],vertices[next],CURVE_TOLERANCE_MM,0,result);
        else result.push([vertices[next][0],vertices[next][1]]);
    }
    if(closed&&result.length>1)result.pop();
    return result;
}

function offsetPath(vertices, distance, closed) {
    if (!closed || vertices.length < 3) return vertices;
    var n = vertices.length;
    var area = 0;
    for (var i = 0; i < n; i++) {
        var j = (i + 1) % n;
        area += vertices[i][0] * vertices[j][1] - vertices[j][0] * vertices[i][1];
    }
    var winding = area > 0 ? 1 : -1;
    var result = [];
    for (var i = 0; i < n; i++) {
        var prev = vertices[(i - 1 + n) % n];
        var curr = vertices[i];
        var next = vertices[(i + 1) % n];
        var d1x = curr[0] - prev[0];
        var d1y = curr[1] - prev[1];
        var d2x = next[0] - curr[0];
        var d2y = next[1] - curr[1];
        var len1 = Math.sqrt(d1x * d1x + d1y * d1y);
        var len2 = Math.sqrt(d2x * d2x + d2y * d2y);
        if (len1 < 0.001 || len2 < 0.001) {
            result.push([curr[0], curr[1]]);
            continue;
        }
        var n1x = winding * (-d1y / len1);
        var n1y = winding * (d1x / len1);
        var n2x = winding * (-d2y / len2);
        var n2y = winding * (d2x / len2);
        var bisectorX=n1x+n2x,bisectorY=n1y+n2y;
        var bisectorLength=Math.sqrt(bisectorX*bisectorX+bisectorY*bisectorY);
        if(bisectorLength<0.001){result.push([r4(curr[0]+n1x*distance),r4(curr[1]+n1y*distance)]);continue}
        bisectorX/=bisectorLength;bisectorY/=bisectorLength;
        var denominator=bisectorX*n1x+bisectorY*n1y;
        var miterLength=Math.abs(denominator)>0.001?distance/denominator:distance;
        var maxMiter=Math.abs(distance)*STROKE_MITER_LIMIT;
        if(Math.abs(miterLength)>maxMiter)miterLength=miterLength<0?-maxMiter:maxMiter;
        result.push([r4(curr[0]+bisectorX*miterLength),r4(curr[1]+bisectorY*miterLength)]);
    }
    return result;
}

function offsetOpenPath(vertices, distance) {
    var n = vertices.length;
    if (n < 2) return vertices;
    var result = [];
    for (var i = 0; i < n; i++) {
        var dx, dy, len;
        if (i === 0) {
            dx = vertices[1][0] - vertices[0][0];
            dy = vertices[1][1] - vertices[0][1];
        } else if (i === n - 1) {
            dx = vertices[i][0] - vertices[i-1][0];
            dy = vertices[i][1] - vertices[i-1][1];
        } else {
            dx = (vertices[i+1][0] - vertices[i-1][0]) / 2;
            dy = (vertices[i+1][1] - vertices[i-1][1]) / 2;
        }
        len = Math.sqrt(dx*dx + dy*dy);
        if (len < 0.001) { result.push([vertices[i][0], vertices[i][1]]); continue; }
        result.push([vertices[i][0] - dy/len*distance, vertices[i][1] + dx/len*distance]);
    }
    return result;
}

function expandStroke(item, scale) {
    var points = item.pathPoints;
    var count = points.length;
    var vertices = [];
    var curves = [];
    var closed = item.closed;
    for (var i = 0; i < count; i++) {
        var p = points[i];
        vertices.push([r4(mm(p.anchor[0]) * scale), r4(mm(p.anchor[1]) * scale)]);
    }
    var seg = closed ? count : count - 1;
    for (var i = 0; i < seg; i++) {
        var c = points[i];
        var nx = points[(i + 1) % count];
        if (c.rightDirection && nx.leftDirection && !isLine(c, nx)) {
            curves.push([r4(mm(c.rightDirection[0]) * scale), r4(mm(c.rightDirection[1]) * scale), r4(mm(nx.leftDirection[0]) * scale), r4(mm(nx.leftDirection[1]) * scale)]);
        } else {
            curves.push(null);
        }
    }
    var strokeWidth = mm(item.strokeWidth) * scale;
    var sfc = hex(item.strokeColor);
    if (strokeWidth < 0.001 || !closed) {
        return [{vs: vertices, cv: curves, cl: closed, fc: sfc, sc: "", sw: 0, sp: "none"}];
    }
    var geoBounds = item.geometricBounds;
    var visBounds = item.visibleBounds;
    var geoWidth = mm(geoBounds[2] - geoBounds[0]) * scale;
    var visWidth = mm(visBounds[2] - visBounds[0]) * scale;
    var offset = (visWidth - geoWidth) / 2;
    var ratio = offset / strokeWidth;
    var alignment = "center";
    if (Math.abs(ratio) < 0.25) alignment = "inside";
    else if (Math.abs(ratio) > 0.75) alignment = "outside";
    log("expandStroke: sw=" + strokeWidth + " off=" + offset + " ratio=" + ratio + " align=" + alignment);
    var hasCurves = false; for (var ci = 0; ci < curves.length; ci++) { if (curves[ci] !== null) { hasCurves = true; break; } }
    if (hasCurves) {
        var subdivided = subdividePath(vertices, curves, closed);
        if (alignment === "inside") {
            return [
                {vs: subdivided, cl: closed, fc: sfc, sc: "", sw: 0, sp: "inside"},
                {vs: offsetPath(subdivided, +strokeWidth, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "inside"}
            ];
        }
        if (alignment === "outside") {
            return [
                {vs: subdivided, cl: closed, fc: sfc, sc: "", sw: 0, sp: "outside"},
                {vs: offsetPath(subdivided, -strokeWidth, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "outside"}
            ];
        }
        return [
            {vs: offsetPath(subdivided, strokeWidth / 2, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "center"},
            {vs: offsetPath(subdivided, -strokeWidth / 2, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "center"}
        ];
    }
    if (alignment === "inside") {
        return [
            {vs: vertices, cl: closed, fc: sfc, sc: "", sw: 0, sp: "inside"},
            {vs: offsetPath(vertices, +strokeWidth, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "inside"}
        ];
    }
    if (alignment === "outside") {
        return [
            {vs: vertices, cl: closed, fc: sfc, sc: "", sw: 0, sp: "outside"},
            {vs: offsetPath(vertices, -strokeWidth, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "outside"}
        ];
    }
    return [
        {vs: offsetPath(vertices, strokeWidth / 2, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "center"},
        {vs: offsetPath(vertices, -strokeWidth / 2, closed), cl: closed, fc: sfc, sc: "", sw: 0, sp: "center"}
    ];
}

function pd(item,s){
    var pts=item.pathPoints;var n=pts.length;var vs=[];var cv=[];var cl=item.closed;
    for(var i=0;i<n;i++){var p=pts[i];vs.push([r4(mm(p.anchor[0])*s),r4(mm(p.anchor[1])*s)]);}
    var seg=cl?n:n-1;
    for(var i=0;i<seg;i++){var c=pts[i];var nx=pts[(i+1)%n];
        if(c.rightDirection&&nx.leftDirection&&!isLine(c,nx)){
            cv.push([r4(mm(c.rightDirection[0])*s),r4(mm(c.rightDirection[1])*s),r4(mm(nx.leftDirection[0])*s),r4(mm(nx.leftDirection[1])*s)]);
        }else{cv.push(null);}
    }
    return{vs:vs,cv:cv,cl:cl,fc:item.filled?hex(item.fillColor):"",sc:item.stroked?hex(item.strokeColor):"",sw:item.stroked?r4(mm(item.strokeWidth)*s):0,sp:(function(){if(!item.stroked)return"none";try{var a=item.strokeAlignment;if(a===1||a==StrokeAlignment.INSIDE)return"inside";if(a===2||a==StrokeAlignment.OUTSIDE)return"outside"}catch(e){}try{var p=item.strokePosition;if(p===1||p==StrokePosition.INSIDE)return"inside";if(p===2||p==StrokePosition.OUTSIDE)return"outside"}catch(e){}return"center"})(),"zIndex":itemZIndex(item,0)};
}

function aP(item,ps,s){
    var hasStroke = item.stroked && item.strokeWidth > 0 && item.closed;
    if (!hasStroke) {
        var d = pd(item,s);
        if (item.closed) {
            d.sw = 0.01;
            d.sp = "center";
        }
        d.id = "p_" + padZero(ps.length,3);
        d.name = item.name || ("p" + ps.length);
        ps.push(d);
        return;
    }
    try {
        var expanded = expandStroke(item, s);
        for (var k = 0; k < expanded.length; k++) {
            expanded[k].id = "p_" + padZero(ps.length,3);
            expanded[k].name = item.name || ("p" + ps.length);
            ps.push(expanded[k]);
        }
    } catch (e) {
        log("expandStroke err: " + e.message);
        var d = pd(item,s);
        d.id = "p_" + padZero(ps.length,3);
        d.name = item.name || ("p" + ps.length);
        ps.push(d);
    }
}

function aCP(item,ps,s,compoundKey){
    var key=compoundKey||nextCompoundKey();
    var zIndex=itemZIndex(item,0);
    for(var i=0;i<item.pathItems.length;i++){var d=pd(item.pathItems[i],s);d.id="p_"+padZero(ps.length,3);d.name=item.name||("p"+ps.length);d.compoundKey=key;d.zIndex=zIndex;ps.push(d);}
}

function addPathAsGroup(item, targetPaths, targetGroups, scale){
    var hasStroke = item.stroked && item.strokeWidth > 0 && item.closed;
    var hasOpenStroke = item.stroked && item.strokeWidth > 0 && !item.closed;
    if (hasOpenStroke) {
        var openPath = pd(item, scale);
        var vs = subdividePath(openPath.vs, openPath.cv, false);
        var sw = r4(mm(item.strokeWidth) * scale);
        var off1 = offsetOpenPath(vs, sw / 2);
        var off2 = offsetOpenPath(vs, -sw / 2);
        var ribbon = off1.concat(off2.reverse());
        var fillHex = item.stroked ? hex(item.strokeColor) : "";
        targetPaths.push({vs: ribbon, cv: [], cl: true, fc: fillHex, sc: "", sw: 0, sp: "none", zIndex: itemZIndex(item,0),
            id: "p_" + padZero(targetPaths.length, 3),
            name: item.name || ("p"+targetPaths.length)});
        return;
    }

    if (!hasStroke) { aP(item, targetPaths, scale); return; }
    var expanded = [];
    aP(item, expanded, scale);
    if (expanded.length > 1) {
        var groupName = item.name || ("G" + targetGroups.length);
        if (item.filled) {
            // Fill: use inner stroke boundary so fill is flush against stroke
            var a0 = polygonArea(expanded[0].vs);
            var a1 = polygonArea(expanded[1].vs);
            var innerIdx = a0 < a1 ? 0 : 1;
            var fillPath = {vs: expanded[innerIdx].vs.slice(), cv: expanded[innerIdx].cv ? expanded[innerIdx].cv.slice() : null, cl: expanded[innerIdx].cl};
            fillPath.fc = hex(item.fillColor);
            fillPath.sw = 0;
            fillPath.sc = "";
            fillPath.sp = "none";
            fillPath.id = "p_" + padZero(targetPaths.length, 3);
            var strokeGroup = {name: "stroke", paths: expanded, groups: []};
            targetGroups.push({name: groupName, paths: [fillPath], zIndex: itemZIndex(item,0), groups: [strokeGroup]});
        } else {
            targetGroups.push({name: groupName, paths: expanded, zIndex: itemZIndex(item,0), groups: []});
        }
    } else {
        for (var k = 0; k < expanded.length; k++) targetPaths.push(expanded[k]);
    }
}

function gd(item,s){
    log("gd: group " + (item.name||"unnamed"));
    var g={name:item.name||"G",paths:[],groups:[],zIndex:itemZIndex(item,0)};
    for(var i=0;i<item.pageItems.length;i++){var c=item.pageItems[i];var t=c.typename;
        if(t==="GroupItem")g.groups.push(gd(c,s));
        else if(t==="TextFrame"||t==="TextArtItem"){var o=otl(c,s);for(var j=0;j<o.length;j++)g.paths.push(o[j]);}
        else if(t==="PathItem")addPathAsGroup(c,g.paths,g.groups,s);
        else if(t==="RasterItem"||t==="PlacedItem"){if(!item.clipped&&(!c.stroked||c.strokeWidth<=0))g.paths.push(imgOutline(c));}
        else if(t==="CompoundPathItem")aCP(c,g.paths,s);
    }return g;
}

function otl(item,s){
    log("otl: outline");
    var o=[];
    var textGroupId="text_"+padZero(TEXT_OUTLINE_COUNTER++,4);
    var textZIndex=itemZIndex(item,0);
    try{
        var c=item.duplicate();var r=c.createOutline();var t=(r&&r.typename)?r:c;
        if(t.typename==="GroupItem"){
            for(var i=0;i<t.pageItems.length;i++){var ci=t.pageItems[i];
                if(ci.typename==="PathItem")aP(ci,o,s);
                else if(ci.typename==="CompoundPathItem")aCP(ci,o,s);
                else if(ci.typename==="GroupItem"){for(var j=0;j<ci.pageItems.length;j++){var cj=ci.pageItems[j];
                    if(cj.typename==="PathItem")aP(cj,o,s);
                    else if(cj.typename==="CompoundPathItem")aCP(cj,o,s);}}
            }
        }else if(t.typename==="PathItem")aP(t,o,s);
        else if(t.typename==="CompoundPathItem")aCP(t,o,s);
        try{t.remove()}catch(e){}
        for(var k=0;k<o.length;k++){
            o[k].isTextOutline=true;
            o[k].textGroupId=textGroupId;
            o[k].textGroupKey=textGroupId;
            o[k].zIndex=textZIndex;
        }
    }catch(e){log("otl error:"+e.message)}
    return o;
}

function imgOutline(item){
    var b=item.visibleBounds;
    var vs=[[r4(mm(b[0])),r4(mm(b[1]))],[r4(mm(b[2])),r4(mm(b[1]))],[r4(mm(b[2])),r4(mm(b[3]))],[r4(mm(b[0])),r4(mm(b[3]))]];
    return{id:"img_"+Math.random().toString(36).substr(2,9),name:item.name||"Image",cl:true,fc:"",sc:"000000",sw:0,sp:"center",zIndex:itemZIndex(item,0),vs:vs};
}

function wg(g,f){
    f.write('{"name":"'+esc(g.name)+'","paths":[');
    for(var i=0;i<g.paths.length;i++){var p=g.paths[i];
        f.write('{"id":"'+p.id+'","name":"'+esc(p.name)+'","isClosed":'+p.cl);
        f.write(',"fillColor":"'+p.fc+'","strokeColor":"'+p.sc+'","strokeWidthMM":'+p.sw+',"sp":"'+p.sp+'"');
          f.write(',"zIndex":'+(p.zIndex||0));
        if(p.compoundKey)f.write(',"compoundKey":"'+esc(p.compoundKey)+'"');
        if(p.isTextOutline)f.write(',"isTextOutline":true,"textGroupId":"'+esc(p.textGroupId)+'","textGroupKey":"'+esc(p.textGroupKey)+'"');
        f.write(',"verticesMM":[');
        for(var v=0;v<p.vs.length;v++){f.write("["+p.vs[v][0]+","+p.vs[v][1]+"]");if(v<p.vs.length-1)f.write(",")}
        f.write("]");
        if(p.cv&&p.cv.length>0){
            f.write(',"curves":[');
            for(var j=0;j<p.cv.length;j++){
                var cv=p.cv[j];
                if(cv){f.write('{"c1":['+cv[0]+","+cv[1]+'],"c2":['+cv[2]+","+cv[3]+']}');}
                else{f.write("null");}
                if(j<p.cv.length-1)f.write(",");
            }
            f.write("]");
        }
        f.write("}");
        if(i<g.paths.length-1)f.write(",");
    }
    f.write('],"groups":[');
    for(var i=0;i<g.groups.length;i++){wg(g.groups[i],f);if(i<g.groups.length-1)f.write(",");}
    f.write('],"zIndex":'+(g.zIndex||0)+"}")
}
function exportSelectionAsJSON(folderPath) {
    try {
        var cleanFolder = new Folder(folderPath);
        if (cleanFolder.exists) {
            var allFiles = cleanFolder.getFiles();
            for (var fc = 0; fc < allFiles.length; fc++) {
                var oldFile = allFiles[fc];
                if (oldFile instanceof File) {
                    var name = oldFile.name;
                    if (ownedSyncFile(name)) {
                        try { oldFile.remove(); } catch(ce) {}
                    }
                }
            }
        }
    } catch(ce) {}
    var result = { count: 0, total: 0, errors: [], diagnostics: [], jsonFile: "" };
    try {
        TEXT_OUTLINE_COUNTER = 0;
        COMPOUND_COUNTER = 0;
        var doc = app.activeDocument;
        var selectedItems = doc.selection;
        if (!selectedItems || selectedItems.length < 1) { result.total = 0; return _jsonStringify(result); }
        var sel = [];
        for (var si = 0; si < selectedItems.length; si++) sel.push(selectedItems[si]);
        result.total = sel.length;
        var s = 1; var paths = []; var groups = []; var images = [];
        var selectionZ = [];
        for (var zi = 0; zi < sel.length; zi++) selectionZ.push(itemZIndex(sel[zi], zi));
        for (var i = 0; i < sel.length; i++) {
            var pathStart = paths.length; var groupStart = groups.length;
            var item = sel[i]; var t = item.typename;
            var diagnostic = { index: i + 1, type: t || "Unknown", name: item.name || "", status: "exported" };
            if (t === "GroupItem") { groups.push(gd(item, s)); }
            else if (t === "TextFrame" || t === "TextArtItem") { var tp = otl(item, s); for (var j = 0; j < tp.length; j++) paths.push(tp[j]); }
            else if (t === "PathItem") { addPathAsGroup(item, paths, groups, s); }
            else if (t === "RasterItem" || t === "PlacedItem") { if (!item.stroked || item.strokeWidth <= 0) paths.push(imgOutline(item)); }
            else if (t === "CompoundPathItem") {
                diagnostic.pathCount = item.pathItems ? item.pathItems.length : 0;
                if (diagnostic.pathCount > 0) {
                    aCP(item, paths, s);
                } else {
                    diagnostic.status = "skipped";
                    diagnostic.reason = "复合路径不包含可导出的子路径";
                    result.errors.push("第 " + diagnostic.index + " 项（" + diagnostic.type + "）已跳过：" + diagnostic.reason);
                }
            } else if (t === "PluginItem") {
                var temporaryPlugin = null, temporaryItems = [], cleanupErrorMessage = "";
                diagnostic.expansionCommand = "expandStyle";
                try {
                    temporaryPlugin = item.duplicate();
                    temporaryItems.push(temporaryPlugin);
                    doc.selection = [temporaryPlugin];
                    // ponytail: expandStyle only; add a plugin-specific command only after a real object requires it.
                    app.executeMenuCommand("expandStyle");
                    temporaryItems = [];
                    for (var ti = 0; ti < doc.selection.length; ti++) temporaryItems.push(doc.selection[ti]);
                    var expanded = false;
                    for (var ei = 0; ei < temporaryItems.length; ei++) {
                        var expandedItem = temporaryItems[ei], expandedType = expandedItem.typename;
                        if (expandedType === "GroupItem") { groups.push(gd(expandedItem, s)); expanded = true; }
                        else if (expandedType === "PathItem") { addPathAsGroup(expandedItem, paths, groups, s); expanded = true; }
                        else if (expandedType === "CompoundPathItem") { aCP(expandedItem, paths, s); expanded = true; }
                    }
                    if (expanded) {
                        diagnostic.temporaryExpansion = true;
                    } else {
                        diagnostic.status = "skipped";
                        diagnostic.reason = "自动扩展未生成可导出路径";
                        result.errors.push("第 " + diagnostic.index + " 项（PluginItem）已跳过：" + diagnostic.reason);
                    }
                } catch (pluginError) {
                    diagnostic.status = "skipped";
                    diagnostic.reason = "自动扩展失败: " + pluginError.message;
                    result.errors.push("第 " + diagnostic.index + " 项（PluginItem）已跳过：" + diagnostic.reason);
                } finally {
                    if (!temporaryItems.length && temporaryPlugin) temporaryItems.push(temporaryPlugin);
                    for (var ci = temporaryItems.length - 1; ci >= 0; ci--) try { temporaryItems[ci].remove(); } catch (cleanupError) { cleanupErrorMessage = cleanupError.message; }
                    try { doc.selection = sel; } catch (restoreError) { cleanupErrorMessage = "原选区恢复失败: " + restoreError.message; }
                    if (cleanupErrorMessage) {
                        diagnostic.status = "skipped";
                        diagnostic.reason = "临时扩展对象清理失败: " + cleanupErrorMessage;
                        result.errors.push("第 " + diagnostic.index + " 项（PluginItem）已跳过：" + diagnostic.reason);
                    }
                }
            } else {
                diagnostic.status = "skipped";
                diagnostic.reason = "不支持的对象类型";
                result.errors.push("第 " + diagnostic.index + " 项（" + diagnostic.type + "）已跳过：" + diagnostic.reason);
            }
            result.diagnostics.push(diagnostic);
            for (var pi = pathStart; pi < paths.length; pi++) paths[pi].zIndex = selectionZ[i];
            for (var gi = groupStart; gi < groups.length; gi++) groups[gi].zIndex = selectionZ[i];
        }
        var jsonFileName = "latest_sync.json";
        var jsonFilePath = folderPath + "/" + jsonFileName;
        var finalFile = new File(jsonFilePath);
        var f = new File(jsonFilePath + ".tmp");
        f.encoding = "UTF-8"; f.open("w");
        f.write('{"version":"'+VERSION+'","schemaVersion":2,"units":"mm","scale":'+s);
        f.write(',"document":{"name":"'+esc(doc.name)+'","widthMM":'+mm(doc.width)+',"heightMM":'+mm(doc.height)+'}');
        f.write(',"paths":[');
        for (var i = 0; i < paths.length; i++) { var p = paths[i];
            f.write('{"id":"'+(p.id||"p_"+padZero(i,3))+'","name":"'+esc(p.name)+'","isClosed":'+p.cl);
            f.write(',"fillColor":"'+p.fc+'","strokeColor":"'+p.sc+'","strokeWidthMM":'+p.sw+',"sp":"'+(p.sp||"center")+'"');
            f.write(',"zIndex":'+(p.zIndex||0));
            if(p.compoundKey)f.write(',"compoundKey":"'+esc(p.compoundKey)+'"');
            if(p.isTextOutline)f.write(',"isTextOutline":true,"textGroupId":"'+esc(p.textGroupId)+'","textGroupKey":"'+esc(p.textGroupKey)+'"');
            f.write(',"verticesMM":[');
            for (var v = 0; v < p.vs.length; v++) { f.write("["+p.vs[v][0]+","+p.vs[v][1]+"]"); if (v < p.vs.length-1) f.write(","); }
            f.write("]");
            if (p.cv && p.cv.length > 0) {
                f.write(',"curves":[');
                for (var j = 0; j < p.cv.length; j++) { var cv = p.cv[j]; if (cv) f.write('{"c1":['+cv[0]+","+cv[1]+'],"c2":['+cv[2]+","+cv[3]+']}'); else f.write("null"); if (j < p.cv.length-1) f.write(","); }
                f.write("]");
            }
            f.write("}"); if (i < paths.length-1) f.write(",");
        }
        f.write('],"groups":[');
        for (var i = 0; i < groups.length; i++) { wg(groups[i], f); if (i < groups.length-1) f.write(","); }
        f.write('],"images":[]}');
        f.close();
        var backupFile = new File(jsonFilePath + ".previous");
        if (backupFile.exists) backupFile.remove();
        if (finalFile.exists && !finalFile.rename(jsonFileName + ".previous")) { throw new Error("Failed to preserve previous JSON file"); }
        if (!f.rename(jsonFileName)) {
            backupFile = new File(jsonFilePath + ".previous");
            if (backupFile.exists) backupFile.rename(jsonFileName);
            throw new Error("Failed to rename JSON temp file");
        }
        backupFile = new File(jsonFilePath + ".previous");
        if (backupFile.exists) backupFile.remove();
        result.count = paths.length + groups.length; result.jsonFile = jsonFileName;
    } catch(e) { result.errors.push("fatal: " + e.message); }
    return _jsonStringify(result);
}

// --- Functions required by CEP panel ---

function getSelectionInfo() {
    try { var doc = app.activeDocument; var sel = doc.selection; if (!sel) return _jsonStringify({ count: 0, docName: doc.name }); return _jsonStringify({ count: sel.length, docName: doc.name }); } catch(e) { return _jsonStringify({ count: 0, docName: "", error: e.message }); }
}

function pickExportFolder(defaultPath) {
    var dlg = new Window("dialog", "选择导出目录"); dlg.orientation = "column"; dlg.alignChildren = "fill"; dlg.spacing = 8; dlg.margins = 14;
    dlg.add("statictext", undefined, "导出目录：");
    var pt = dlg.add("edittext", undefined, defaultPath); pt.preferredSize.width = 380;
    var bg = dlg.add("group"); bg.alignment = "left";
    var bb = bg.add("button", undefined, "浏览...");
    bb.onClick = function() { var f = Folder.selectDialog("选择导出文件夹"); if (f) pt.text = f.fsName; };
    var db = dlg.add("group"); db.alignment = "right";
    db.add("button", undefined, "导出").onClick = function() { dlg.close(1); };
    db.add("button", undefined, "取消").onClick = function() { dlg.close(0); };
    if (dlg.show() != 0) return pt.text; return null;
}

function readExportConfig() {
    var cp = desktop.fsName + "/ai-export/.ai-export-config"; var f = new File(cp);
    if (!f.exists) { var def = {exportFolder: desktop.fsName + "/ai-export"}; writeExportConfig(def.exportFolder); return _jsonStringify(def); }
    f.open("r"); var raw = f.read(); f.close();
    try { var cfg = eval("(" + raw + ")"); return _jsonStringify(cfg); } catch(e) { var def = {exportFolder: desktop.fsName + "/ai-export"}; return _jsonStringify(def); }
}

function writeExportConfig(ep) {
    var d = new Folder(desktop.fsName + "/ai-export"); if (!d.exists) d.create();
    var f = new File(desktop.fsName + "/ai-export/.ai-export-config"); f.encoding = "UTF-8"; f.open("w");
    f.write('{"exportFolder":"' + String(ep).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"}'); f.close();
}

function exportSelectionAsPNG(folderPath, resolution) {
    var result = { count: 0, total: 0, errors: [] };
    try {
        var doc = app.activeDocument;
        var sel = doc.selection;
        if (!sel || sel.length < 1) { result.total = 0; return _jsonStringify(result); }
        result.total = sel.length;
        var exportDir = new Folder(folderPath);
        if (!exportDir.exists) exportDir.create();
        // Clean old PNG + log files
        var allOld = exportDir.getFiles();
        for (var oc = 0; oc < allOld.length; oc++) {
            var of = allOld[oc];
            var on = of.name;
            if (/\.png$/i.test(on)) {
                try { of.remove(); } catch(e) {}
            }
        }
        var stamp = fmtFile(new Date());
        for (var i = 0; i < sel.length; i++) {
            try {
                var item = sel[i];
                if (!item) continue;
                // Follow com.suai.sync naming: export_{stamp}_{index}.png
                var filePath = folderPath + "/export_" + stamp + "_" + padZero(i, 3) + ".png";
                var originalDoc = app.activeDocument;
                var tempDoc = app.documents.add(DocumentColorSpace.RGB);
                var dup = item.duplicate(tempDoc.layers[0], ElementPlacement.PLACEATBEGINNING);
                var b = dup.visibleBounds;
                tempDoc.artboards[0].artboardRect = [b[0], b[1], b[2], b[3]];
                var opt = new ExportOptionsPNG24();
                opt.antiAliasing = true;
                opt.transparency = true;
                opt.artBoardClipping = true;
                var exportScale = resolution / 72 * 100;
                opt.horizontalScale = exportScale;
                opt.verticalScale = exportScale;
                tempDoc.exportFile(new File(filePath), ExportType.PNG24, opt);
                tempDoc.close(SaveOptions.DONOTSAVECHANGES);
                try { originalDoc.activate(); } catch(e) {}
                result.count++;
            } catch(e) {
                result.errors.push("item " + (i+1) + ": " + e.message);
            }
        }
        return _jsonStringify(result);
    } catch(e) {
        return _jsonStringify({ count: 0, total: 0, errors: ["fatal: " + e.message] });
    }
}


// Native tool wrappers - call Illustrator's built-in functions
function openArtboardTool() {
    // Try menu commands
    try { app.executeMenuCommand("Artboard Tool"); return "ok"; } catch(e) {}
    try { app.executeMenuCommand("Edit Artboards"); return "ok"; } catch(e) {}
    try { app.executeMenuCommand("Artboards"); return "ok"; } catch(e) {}
    // Try activating tool from app.tools collection
    try {
        if (app.tools && app.tools.length > 0) {
            for (var ti = 0; ti < app.tools.length; ti++) {
                var t = app.tools[ti];
                if (t.name.indexOf("Artboard") >= 0) {
                    app.currentTool = t;
                    return "ok";
                }
            }
        }
    } catch(e) {}
    // Try internal tool name
    try { app.executeMenuCommand("artboardTool"); return "ok"; } catch(e) {}
    try { app.executeMenuCommand("??"); return "ok"; } catch(e) {}
    try { app.executeMenuCommand("????"); return "ok"; } catch(e) {}
    return "fail";
}

function openExportDialog() {
    // Try multiple menu commands to open export dialog
    try { app.executeMenuCommand("Export"); return "ok"; } catch(e) {}
    try { app.executeMenuCommand("export"); return "ok"; } catch(e) {}
    try { app.executeMenuCommand("Exportation"); return "ok"; } catch(e) {}
    try { app.executeMenuCommand("??"); return "ok"; } catch(e) {}
    return "fail: all commands failed";
}
if (typeof $.global !== "undefined") {
    $.global.exportSelectionAsJSON = exportSelectionAsJSON;
    $.global.getSelectionInfo = getSelectionInfo;
    $.global.pickExportFolder = pickExportFolder;
    $.global.readExportConfig = readExportConfig;
    $.global.writeExportConfig = writeExportConfig;
    $.global.exportSelectionAsPNG = exportSelectionAsPNG;
    $.global.openArtboardTool = openArtboardTool;
    $.global.openExportDialog = openExportDialog;
}
