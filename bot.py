import asyncio
import logging
import sys
from aiogram import Bot, Dispatcher, F
from aiogram.filters import CommandStart
from aiogram.types import Message

# Импортируем вашу функцию распознавания из server.py
# (Убедитесь, что server.py лежит в той же папке, или скопируйте сюда функцию recognize_image)
# Если server.py использует FastAPI, проще вынести логику PaddleOCR в отдельную функцию.
# Для простоты, давайте использовать PaddleOCR напрямую здесь.
from paddleocr import PaddleOCR
import cv2
import numpy as np
from fuzzywuzzy import fuzz, process
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
# --- НАСТРОЙКИ БОТА ---
BOT_TOKEN = "8826844366:AAH4v8LZf0sA9DT39evipUcWCbtvu5giIrA" # Получите у @BotFather

# --- ИНИЦИАЛИЗАЦИЯ OCR (как в вашем server.py) ---
logging.basicConfig(level=logging.INFO)
ocr = PaddleOCR(lang='ru', use_textline_orientation=True, enable_mkldnn=False)

# --- БАЗА ДЛЯ АНАЛИЗА (Упрощенная версия) ---
FORBIDDEN = {
    'Молоко': ['молоко', 'молочный', 'сыворотка', 'лактоза'],
    'Глютен': ['глютен', 'пшеница', 'мука'],
    'Соя': ['соя', 'соевый', 'лецитин'],
    'Орехи': ['орех', 'арахис', 'миндаль'],
}

def analyze_text(text):
    text_lower = text.lower()
    # Замена латиницы (на всякий случай, если Paddle ошибся)
    for lat, cyr in [('a','а'), ('c','с'), ('e','е'), ('o','о'), ('p','р'), ('x','х')]:
        text_lower = text_lower.replace(lat, cyr)
    
    found = {}
    words = text_lower.split()
    
    for category, keywords in FORBIDDEN.items():
        matches = []
        for word in words:
            if len(word) < 4: continue
            for kw in keywords:
                if fuzz.ratio(word, kw) > 75:
                    matches.append(word)
        if matches:
            found[category] = list(set(matches))
    
    if not found:
        return "✅ МОЖНО\nНежелательных веществ не найдено."
    
    verdict = "🔴 НЕЛЬЗЯ\nОбнаружено:\n"
    for cat, matches in found.items():
        verdict += f"• {cat}: {', '.join(matches)}\n"
    return verdict

# --- ЛОГИКА БОТА ---
dp = Dispatcher()

@dp.message(CommandStart())
async def start(message: Message):
    await message.answer("Привет! Отправь мне фото этикетки, и я проверю состав.")

@dp.message(F.photo)
async def handle_photo(message: Message, bot: Bot):
    await message.answer("🔍 Распознаю текст, подождите...")
    
    # 1. Скачиваем фото
    photo = message.photo[-1] # Берем самое большое
    file = await bot.get_file(photo.file_id)
    file_path = f"temp_{photo.file_id}.jpg"
    await bot.download_file(file.file_path, file_path)
    
    try:
        # 2. Распознаем через PaddleOCR
        result = ocr.predict(file_path)
        text_lines = []
        for res in result:
            for t in res.get('rec_texts', []):
                text_lines.append(t)
        full_text = "\n".join(text_lines)
        
        # 3. Анализируем
        analysis = analyze_text(full_text)
        
        # 4. Отправляем ответ
        await message.answer(analysis)
        
    except Exception as e:
        await message.answer(f"Ошибка: {e}")
    finally:
        import os
        if os.path.exists(file_path):
            os.remove(file_path)

async def main():
    bot = Bot(token=BOT_TOKEN)
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
