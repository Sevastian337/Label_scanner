import os
import re
import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from paddleocr import PaddleOCR
from fuzzywuzzy import fuzz

app = FastAPI()

# Надежный путь к папке с HTML-шаблонами
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))

# Инициализация OCR (ваша рабочая связка)
ocr = PaddleOCR(lang='ru', use_textline_orientation=True, enable_mkldnn=False)

# База аллергенов
FORBIDDEN = {
    'Молоко': ['молоко', 'молочный', 'сыворотка', 'лактоза', 'казеин', 'сливки'],
    'Глютен': ['глютен', 'пшеница', 'мука', 'рожь', 'ячмень', 'овес'],
    'Соя': ['соя', 'соевый', 'лецитин'],
    'Орехи': ['орех', 'арахис', 'миндаль', 'фундук', 'кешью'],
}

def analyze_text(text):
    text_lower = text.lower()
    # Нормализация латиницы (частая проблема OCR)
    for lat, cyr in [('a','а'), ('c','с'), ('e','е'), ('o','о'), ('p','р'), ('x','х'), ('y','у')]:
        text_lower = text_lower.replace(lat, cyr)
    
    found = {}
    words = text_lower.split()
    
    for cat, kws in FORBIDDEN.items():
        matches = []
        for w in words:
            if len(w) < 4: continue
            for kw in kws:
                if fuzz.ratio(w, kw) > 75:
                    matches.append(w)
        if matches:
            found[cat] = list(set(matches))
    
    verdict = 'МОЖНО'
    color = 'green'
    if found:
        verdict = 'НЕЛЬЗЯ' if any(k in found for k in ['Молоко', 'Глютен', 'Орехи']) else 'ОСТОРОЖНО'
        color = 'red' if verdict == 'НЕЛЬЗЯ' else 'orange'
    
    # Поиск калорий
    cal = None
    m = re.search(r'(\d{2,4})\s*(?:ккал|kcal)', text_lower)
    if m: cal = int(m.group(1))
    
    return {'verdict': verdict, 'color': color, 'found': found, 'calories': cal}

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    # Новый синтаксис FastAPI (request идет первым аргументом)
    return templates.TemplateResponse(request, "index.html", {})

@app.post("/upload")
async def upload(file: UploadFile = File(...)):
    contents = await file.read()
    nparr = np.frombuffer(contents, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    # Распознавание текста
    result = ocr.predict(img)
    text_lines = []
    for res in result:
        for t in res.get('rec_texts', []):
            text_lines.append(t)
    full_text = "\n".join(text_lines)
    
    # Анализ
    analysis = analyze_text(full_text)
    analysis['raw_text'] = full_text
    return JSONResponse(analysis)

# --- ЗАПУСК С ПУБЛИЧНОЙ ССЫЛКОЙ ---
if __name__ == "__main__":
    from globalhost import GlobalHostApp
    import time
    
    host = GlobalHostApp()
    
    # Запускаем сервер и туннель
    if host.bg_launch(framework="fastapi", app="server:app", port=8000):
        print("\n" + "="*60)
        print(f"🔗 ВАША ПУБЛИЧНАЯ ССЫЛКА: {host.get_url()}")
        print("="*60 + "\n")
        print("Скопируйте эту ссылку и откройте на телефоне (с VPN).")
        
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            host.stop()
