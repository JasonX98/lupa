# -*- coding: utf-8 -*-
"""Lupa 桌面图标生成：透镜记号（环+点+柄），三方案，输出 PNG 预览 + Windows ico。"""
from PIL import Image, ImageDraw
import base64, io, os

RES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'windows', 'runner', 'resources')

SS = 4          # 4x 超采样
S = 256 * SS    # 实际画布
OUT = '.'

JADE       = (14, 124, 107, 255)    # #0E7C6B
JADE_D     = (10, 82, 71, 255)      # #0A5247
JADE_L     = (19, 135, 111, 255)    # #13876F
PAPER      = (247, 246, 243, 255)   # #F7F6F3
WHITE      = (255, 255, 255, 255)
INK_SOFT   = (24, 28, 24, 26)       # B 方案底板描边

def lerp(a, b, t): return tuple(round(a[i] + (b[i]-a[i])*t) for i in range(4))

def grad_layer(c1, c2):
    """对角线性渐变整幅图。"""
    g = Image.new('RGBA', (S, S))
    px = g.load()
    for y in range(S):
        for_splice = c2
        t = (x_t := y / S)
        row = lerp(c1, c2, t)
        for x in range(S):
            px[x, y] = lerp(c1, c2, (x + y) / (2*S))
    return g

def rounded_mask():
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([16*SS, 16*SS, 240*SS, 240*SS], radius=56*SS, fill=255)
    return m

def draw_lens(d, fg):
    """透镜记号：柄 → 环 → 中心点（画布 1024 坐标）。"""
    # 柄：45°，圆头（起点圆藏在环下，终点圆必须）
    d.line([(150*SS, 150*SS), (198*SS, 198*SS)], fill=fg, width=26*SS)
    d.ellipse([150*SS-13*SS, 150*SS-13*SS, 150*SS+13*SS, 150*SS+13*SS], fill=fg)
    d.ellipse([198*SS-13*SS, 198*SS-13*SS, 198*SS+13*SS, 198*SS+13*SS], fill=fg)
    # 环：圆心 (110,110) r=62 stroke=20
    d.ellipse([(110-62-10)*SS, (110-62-10)*SS, (110+62+10)*SS, (110+62+10)*SS],
              outline=fg, width=20*SS)
    # 中心点 r=20
    d.ellipse([(110-20)*SS, (110-20)*SS, (110+20)*SS, (110+20)*SS], fill=fg)

def make_icon(variant):
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    if variant == 'A':          # 玉底白镜
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([16*SS, 16*SS, 240*SS, 240*SS], radius=56*SS, fill=JADE)
        draw_lens(d, PAPER)
    elif variant == 'B':        # 纸底玉镜
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([16*SS, 16*SS, 240*SS, 240*SS], radius=56*SS,
                            fill=PAPER, outline=INK_SOFT, width=2*SS)
        draw_lens(d, JADE)
    else:                       # 渐变玉底 + 高光
        img.paste(grad_layer(JADE_L, JADE_D), (0, 0), rounded_mask())
        d = ImageDraw.Draw(img)
        draw_lens(d, WHITE)
        # 玻璃高光：独立图层画不透明白弧再整体合成（PIL arc 半透明是像素替换，直接画会发灰）
        hl = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        dh = ImageDraw.Draw(hl)
        dh.arc([(110-62-10)*SS, (110-62-10)*SS, (110+62+10)*SS, (110+62+10)*SS],
               start=206, end=282, fill=WHITE, width=9*SS)
        img = Image.alpha_composite(img, hl)
    return img.resize((256, 256), Image.LANCZOS)

def to_b64(img, size=None):
    if size: img = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO(); img.save(buf, 'PNG')
    return base64.b64encode(buf.getvalue()).decode()

# ---- 生成三方案（A 落地 ico；B/C 仅预览用，PNG 由工作区侧脚本导出）----
icons = {v: make_icon(v) for v in 'ABC'}

# ---- A 方案 → Windows ico（多尺寸链）----
ico_path = os.path.abspath(os.path.join(RES, 'app_icon.ico'))
icons['A'].save(ico_path, format='ICO',
                sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(24,24),(16,16)])
print('ico bytes:', os.path.getsize(ico_path))

# 预览 HTML / PNG 产物由 WorkBuddy 工作区侧的同源脚本负责，入仓版只产出 ico。
