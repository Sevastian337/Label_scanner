from fastapi import FastAPI, File, UploadFile
from paddleocr import PaddleOCR
import cv2
import numpy as np

app = FastAPI()

# Инициализируем PaddleOCR (ваша рабочая связка)
ocr = PaddleOCR(
    lang='ru',
    use_textline_orientation=True,
    enable_mkldnn=False  # Отключаем баг с процессором
)

@app.post("/recognize")
async def recognize_image(file: UploadFile = File(...)):
    # 1. Читаем картинку, которую прислал эмулятор
    contents = await file.read()
    nparr = np.frombuffer(contents, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    # 2. Распознаем текст
    result = ocr.predict(img)
    
    # 3. Собираем текст в одну строку
    text_lines = []
    for res in result:
        for text in res.get('rec_texts', []):
            text_lines.append(text)
            
    full_text = "\n".join(text_lines)
    
    # Возвращаем JSON с текстом
    return {"text": full_text}

if __name__ == "__main__":
    import uvicorn
    # Запускаем сервер на порту 8000
    uvicorn.run(app, host="0.0.0.0", port=8080)
