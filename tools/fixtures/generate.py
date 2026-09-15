#!/usr/bin/env python3
"""Generate original synthetic PDF/HTML test inputs. NOT a PDF production renderer.

Run in the pinned development-only environment described in README.md.
No customer data, provider artwork, external assets or printer I/O.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
from reportlab.graphics.barcode import code128, qr
from reportlab.graphics.shapes import Drawing
from reportlab.graphics import renderPDF
from pypdf import PdfReader, PdfWriter, Transformation
from pypdf.generic import NameObject, NumberObject, RectangleObject

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / 'Fixtures/generated'
W,H=288,432


def draw_label(c, tag='A', variant='normal'):
    c.setFillColorRGB(1,1,1); c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColorRGB(0,0,0); c.setStrokeColorRGB(0,0,0)
    c.setLineWidth(.5); c.rect(10,10,268,412)
    c.setFont('Helvetica-Bold',15); c.drawString(19,399,'SYNTHETIC TEST LABEL')
    c.setFont('Helvetica',9); c.drawString(19,382,f'Fixture {tag}  |  NOT VALID FOR SHIPPING')
    c.line(18,369,270,369)
    c.setFont('Helvetica-Bold',20); c.drawString(19,340,f'LABEL {tag}')
    c.setFont('Helvetica',11)
    for y,text in [(320,'TEST RECIPIENT - NO REAL ADDRESS'),(302,'Test route: ALPHA / BETA / GAMMA')]:
        c.setFont('Helvetica',10 if y==320 else 9); c.drawString(19,y,text)
    c.line(18,290,270,290)
    c.setFont('Helvetica',10)
    for i,text in enumerate(['Native face: 4 x 6 inches','Do not fit to Letter here','Quiet zones are intentional','TOP / LEFT must stay correct']):
        if variant != "small-text": c.drawString(19,270-i*17,text)
    payload=f'LPD-TEST-{tag}-001'
    widget=qr.QrCodeWidget(payload)
    x0,y0,x1,y1=widget.getBounds(); size=84
    drawing=Drawing(size,size,transform=[size/(x1-x0),0,0,size/(y1-y0),-x0,-y0])
    drawing.add(widget); renderPDF.draw(drawing,c,182,151)
    c.setFont('Helvetica',8); c.drawString(19,180,'Black pixels: 1')
    c.drawString(19,166,'White pixels: 0')
    for i,pts in enumerate([.25,.5,.75,1.0]):
        c.setLineWidth(pts);c.line(19,148-i*9,153,148-i*9)
    c.setFont('Helvetica',6);c.drawString(19,106,'Six point text 0123456789: geometry before enhancement.')
    bar=code128.Code128(payload,barWidth=.85,barHeight=35,quiet=True)
    if bar.width > 250: raise RuntimeError('Barcode exceeds fixture region')
    bar.drawOn(c,(W-bar.width)/2,49)
    c.setFont('Helvetica',9);c.drawCentredString(W/2,34,payload)
    c.setFont('Helvetica',7);c.drawString(19,20,'BOTTOM LEFT');c.drawRightString(269,20,'BOTTOM RIGHT')
    if variant == 'transparency':
        c.saveState();c.setFillAlpha(.35);c.setFillColorRGB(0,0,0)
        c.rect(17,202,155,18,fill=1,stroke=0);c.restoreState()
    if variant in ('raster-low','raster-high','mixed'):
        n=24 if variant=='raster-low' else 384
        image=Image.new('L',(n,n))
        image.putdata([0 if ((x*8//n)+(y*8//n))%2 else 255 for y in range(n) for x in range(n)])
        c.drawImage(ImageReader(image),112,154,width=50,height=50,mask=None)
    if variant == 'small-text':
        c.saveState();c.setFillColorRGB(1,1,1);c.rect(18,202,157,70,fill=1,stroke=0)
        c.setFillColorRGB(0,0,0)
        for i,pts in enumerate([6,8,10,12]): c.setFont('Helvetica',pts);c.drawString(19,257-i*16,f'{pts} pt: ABC 012345')
        c.restoreState()
    return payload


def markers(c,w,h):
    c.setStrokeColorRGB(0,0,0);c.setLineWidth(.4)
    for x,y in [(4,4),(w-4,4),(4,h-4),(w-4,h-4)]:
        c.line(x-2,y,x+2,y);c.line(x,y-2,x,y+2)


def make_page(size=(W,H), placements=None, variant='normal', instruction=False,
              rotate=0, shift=(0,0), unit=1):
    placements=placements if placements is not None else [(0,0,1,'A')]
    buffer=io.BytesIO();c=canvas.Canvas(buffer,pagesize=size,invariant=1,pageCompression=1)
    c.setTitle('Original synthetic label-driver fixture')
    if instruction:
        c.setFont('Helvetica-Bold',16);c.drawString(36,size[1]-60,'INSTRUCTIONS - NOT A LABEL')
        c.setFont('Helvetica',11);c.drawString(36,size[1]-90,'This page must not be silently discarded.')
    regions=[]
    for x,y,scale,tag in placements:
        c.saveState();c.translate(x,y);c.scale(scale,scale)
        payload=draw_label(c,tag,variant);c.restoreState()
        regions.append({'tag':tag,'payload':payload,'rawRect':[x+shift[0],y+shift[1],W*scale,H*scale]})
    markers(c,*size);c.showPage();c.save()
    page=PdfReader(io.BytesIO(buffer.getvalue())).pages[0]
    if shift != (0,0):
        page.add_transformation(Transformation().translate(*shift))
        page.mediabox=RectangleObject([shift[0],shift[1],size[0]+shift[0],size[1]+shift[1]])
        page.cropbox=RectangleObject(page.mediabox)
    if rotate: page.rotate(rotate)
    if unit != 1: page[NameObject('/UserUnit')]=NumberObject(unit)
    box=[float(v) for v in page.cropbox]; bw=box[2]-box[0];bh=box[3]-box[1]
    def upright(x,y):
        x-=box[0];y-=box[1]
        return {0:(x/bw,1-y/bh),90:(y/bh,x/bw),180:(1-x/bw,y/bh),270:(1-y/bh,1-x/bw)}[rotate%360]
    for reg in regions:
        x,y,w,h=reg['rawRect'];pts=[upright(a,b) for a,b in [(x,y),(x+w,y),(x,y+h),(x+w,y+h)]]
        xs,ys=zip(*pts);reg['uprightNormalizedRect']=[min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)]
    meta={'mediaBox':[float(v) for v in page.mediabox], 'cropBox':box,
          'rotation':rotate, 'userUnit':unit,'regions':regions,
          'expectedBarcodePayloads':[r['payload'] for r in regions],
          'nonLabelPage':instruction}
    return page,meta


def write_pdf(identifier, pages, family, note='', match='explicit-profile'):
    writer=PdfWriter();writer.pdf_header=b'%PDF-1.7';metadata=[]
    for page,meta in pages: writer.add_page(page);metadata.append(meta)
    writer.add_metadata({'/Title':identifier,'/Author':'Label Printer Driver synthetic fixtures',
                         '/CreationDate':'D:20260915000000Z'})
    path=OUT/(identifier+'.pdf')
    with path.open('wb') as f: writer.write(f)
    return {'id':identifier,'family':family,'path':str(path.relative_to(REPO)),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,
            'pageCount':len(pages),'pages':metadata,'matchExpectation':match,'note':note,
            'provenance':'Original synthetic project artwork; generated by tools/fixtures/generate.py',
            'license':'MIT','physicalQualification':'not-run'}


def browser_html(name, sheet):
    # Inline SVG rect geometry, no external assets, JS, tracking or live courier site.
    bar=code128.Code128('LPD-BROWSER-001',barWidth=1,barHeight=38,quiet=True)
    bar.validate();bar.encode();pattern=bar.decompose()
    x=12;rects=[]
    for symbol in pattern:
        width=ord(symbol.lower())-ord('a')+1
        if symbol.isupper(): rects.append(f'<rect x="{x}" y="0" width="{width}" height="38"/>')
        x+=width
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {x+12} 38" aria-label="Synthetic Code 128"><g fill="black">'+''.join(rects)+'</g></svg>'
    page_css={'native':'4in 6in','letter':'letter','a4':'A4'}[sheet]
    outer={'native':'4in; height:6in','letter':'8.5in; height:11in','a4':'210mm; height:297mm'}[sheet]
    left,top=('0','0') if sheet=='native' else ('0.5in','2in')
    text=f"""<!doctype html>
<html lang="en"><meta charset="utf-8"><title>Label driver synthetic {sheet} print fixture</title>
<style>
@page {{ size: {page_css}; margin: 0; }}
* {{ box-sizing:border-box; }} html,body {{ margin:0; padding:0; font-family:Arial,sans-serif; }}
.sheet {{ position:relative; width:{outer}; background:white; }}
.label {{ position:absolute; left:{left}; top:{top}; width:4in; height:6in; border:1px solid black; padding:0.22in; }}
h1 {{ font-size:17pt; margin:0 0 0.15in; }} p {{ font-size:11pt; }}
svg {{ width:3.4in; height:0.7in; display:block; }}
.foot {{ position:absolute; bottom:0.3in; left:0.22in; right:0.22in; }}
.mark {{ position:absolute; width:4px; height:4px; background:black; }}
</style>
<div class="sheet"><i class="mark" style="left:2px;top:2px"></i><i class="mark" style="right:2px;bottom:2px"></i>
<section class="label"><h1>SYNTHETIC BROWSER LABEL</h1><p>NOT VALID FOR SHIPPING</p>
<p>Input sheet: {sheet}. Output label: 4 x 6 inches.</p><p>No private address. No external assets.</p>
<p>Verify scale, headers/footers, margins, complete-page capture and the system dialog separately.</p>
<div class="foot">{svg}<p>LPD-BROWSER-001</p><p>BOTTOM - THIS TEXT MUST REMAIN VISIBLE</p></div>
</section></div></html>
"""
    path=OUT/name;path.write_text(text)
    return {'id':name.removesuffix('.html'),'family':'browser-synthetic','path':str(path.relative_to(REPO)),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,
            'provenance':'Original synthetic HTML and Code128 rectangles; no provider layout',
            'license':'MIT','browserQualification':'not-run'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replace-generated',action='store_true',help='Explicitly allow regenerating committed synthetic inputs')
    args=parser.parse_args()
    if OUT.exists() and any(OUT.iterdir()) and not args.replace_generated:
        parser.error('Output exists; review then use --replace-generated')
    OUT.mkdir(parents=True,exist_ok=True)
    fixtures=[]
    def add(id,pages,family=None,note='',match='explicit-profile'):
        fixtures.append(write_pdf(id,pages,family or id,note,match))
    add('native-vector',[make_page()])
    add('letter-one',[make_page((612,792),[(36,180,1,'A')])])
    add('a4-one',[make_page((595.275590551,841.88976378),[(36,210,1,'A')])])
    add('sheet-two',[make_page((792,612),[(36,90,1,'A'),(432,90,1,'B')])])
    add('sheet-four',[make_page((612,792),[(72,480,.5,'A'),(360,480,.5,'B'),(72,120,.5,'C'),(360,120,.5,'D')])])
    add('rotations',[make_page(rotate=r) for r in (0,90,180,270)],note='Page /Rotate, not pre-rotated raster. Region rotation tests remain separate.')
    add('box-origins',[make_page(shift=s) for s in ((18,24),(-54,-72))])
    add('user-unit',[make_page(),make_page((144,216),[(0,0,.5,'A')],unit=2)],note='UserUnit 1 and 2 physically match; unsupported/invalid unit cases remain to implement.')
    for name in ['transparency','small-text']:
        add(name,[make_page(variant=name)])
    add('raster-high-low',[make_page(variant='raster-low'),make_page(variant='raster-high')],note='Embedded analytic checker at two resolutions; barcode stays vector.')
    add('mixed-content',[make_page(variant='mixed')])
    add('mixed-pages',[make_page(),make_page((612,792),[(36,180,1,'B')])])
    add('non-label-pages',[make_page(),make_page((612,792),[],instruction=True)],match='review-non-label-page')
    add('layout-changed',[make_page((612,792),[(90,240,1,'A')])],match='reject-original-letter-template',note='Actual region differs from letter-one; matching by paper size alone is insufficient.')
    add('ambiguous-region',[make_page((792,612),[(36,90,1,'A'),(432,90,1,'B')])],match='review-without-explicit-multilabel-profile')
    add('copy-order',[make_page(placements=[(0,0,1,tag)]) for tag in ('A','B','C')])
    for name in ('native','letter','a4'): fixtures.append(browser_html(f'browser-{name}.html',name))
    manifest={'schemaVersion':1,'generator':'tools/fixtures/generate.py','coordinateConvention':'rawRect is PDF-user-space x/y/width/height; uprightNormalizedRect uses top-left of rotated effective crop box',
              'fixtures':fixtures,'warning':'Synthetic regression inputs; not actual courier website compatibility evidence or physical validation.'}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    # Populate only families with concrete examples. Partial coverage is explicit.
    catalog_path=REPO/'Fixtures/catalog.json';catalog=json.loads(catalog_path.read_text())
    by_family={item['family']:item for item in fixtures}
    for entry in catalog['fixtures']:
        if entry['id'] in by_family:
            item=by_family[entry['id']]
            entry.update(state='available-partial',path=item['path'],sha256=item['sha256'],provenance=item['provenance'])
    catalog_path.write_text(json.dumps(catalog,indent=2)+'\n')
    print(f'Generated {sum(f["path"].endswith(".pdf") for f in fixtures)} PDFs and 3 HTML files; no device access.')
if __name__=='__main__': main()
