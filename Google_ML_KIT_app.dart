import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Сканер этикеток',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  File? _image;
  bool _isLoading = false;
  Map<String, dynamic>? _analysisResult;

  // ==========================================
  // ЛОГИКА АНАЛИЗА (Fuzzy Search + Калории)
  // ==========================================
  
  // База запрещенных ингредиентов (в будущем можно вынести в настройки)
  final Map<String, List<String>> _forbiddenDb = {
    'Молоко': ['молоко', 'молочный', 'сыворотка', 'лактоза', 'казеин', 'сливки'],
    'Глютен': ['глютен', 'пшеница', 'мука', 'рожь', 'ячмень', 'овес'],
    'Соя': ['соя', 'соевый', 'лецитин'],
    'Орехи': ['орех', 'арахис', 'миндаль', 'фундук', 'кешью'],
    'Сахар': ['сахар', 'сахароза', 'фруктоза', 'сироп'],
  };

  Map<String, dynamic> _analyzeText(String rawText) {
    String textLower = rawText.toLowerCase();
    // Простая нормализация (замена латинских букв на кириллицу для похожести)
    final Map<String, String> replacements = {
      'a': 'а', 'c': 'с', 'e': 'е', 'o': 'о', 'p': 'р', 'x': 'х', 'y': 'у'
    };
    replacements.forEach((k, v) => textLower = textLower.replaceAll(k, v));

    // Ищем аллергены
    Map<String, List<String>> foundIngredients = {};
    final words = textLower.split(RegExp(r'\W+')); // Разбиваем на слова

    _forbiddenDb.forEach((category, keywords) {
      List<String> matches = [];
      for (var word in words) {
        if (word.length < 4) continue;
        
        for (var keyword in keywords) {
          // Fuzzy-поиск: если совпадение > 80%
          if (ratio(word, keyword) > 60) {
            if (!matches.contains(word)) matches.add(word);
          }
        }
      }
      if (matches.isNotEmpty) {
        foundIngredients[category] = matches;
      }
    });

    // Ищем калории (ищем число рядом со словом "ккал")
    int? calories;
    final RegExp kcalRegex = RegExp(r'(\d{2,4})\s*(?:ккал|kcal)');
    final match = kcalRegex.firstMatch(textLower);
    if (match != null) {
      calories = int.tryParse(match.group(1)!);
    }

    // Ищем сайт
    String? website;
    final RegExp urlRegex = RegExp(r'(?:www\.)?([a-z0-9-]+\.[a-z]{2,})');
    final urlMatch = urlRegex.firstMatch(textLower);
    if (urlMatch != null && (urlMatch.group(1)!.contains('.ru') || urlMatch.group(1)!.contains('.com'))) {
      website = 'https://${urlMatch.group(1)}';
    }

    // Вердикт
    String verdict = 'МОЖНО';
    Color color = Colors.green;
    if (foundIngredients.isNotEmpty) {
      if (foundIngredients.containsKey('Молоко') || foundIngredients.containsKey('Глютен') || foundIngredients.containsKey('Орехи')) {
        verdict = 'НЕЛЬЗЯ';
        color = Colors.red;
      } else {
        verdict = 'ОСТОРОЖНО';
        color = Colors.orange;
      }
    }

    return {
      'verdict': verdict,
      'color': color,
      'found': foundIngredients,
      'calories': calories,
      'website': website,
      'rawText': rawText,
    };
  }

  // ==========================================
  // СКАНИРОВАНИЕ И OCR
  // ==========================================
  Future<void> _pickAndAnalyze(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() {
      _image = File(pickedFile.path);
      _isLoading = true;
      _analysisResult = null;
    });

    try {
      final inputImage = InputImage.fromFile(_image!);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      final result = _analyzeText(recognizedText.text);
      setState(() {
        _analysisResult = result;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка распознавания: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // ==========================================
  // ИНТЕРФЕЙС
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканер состава')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Кнопки выбора фото
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _pickAndAnalyze(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Камера'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _pickAndAnalyze(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Галерея'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Фото
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!, height: 250, fit: BoxFit.cover),
              ),

            // Загрузка
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),

            // Результат
            if (_analysisResult != null) ...[
              const SizedBox(height: 20),
              
              // Вердикт
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_analysisResult!['color'] as Color).withValues(alpha: 0.2),
                  border: Border.all(color: _analysisResult!['color'] as Color, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'ВЕРДИКТ: ${_analysisResult!['verdict']}',
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold,
                        color: _analysisResult!['color'] as Color
                      ),
                    ),
                    if (_analysisResult!['calories'] != null)
                      Text(
                        'Калорийность: ${_analysisResult!['calories']} ккал',
                        style: const TextStyle(fontSize: 16),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Найденные аллергены
              if ((_analysisResult!['found'] as Map).isNotEmpty) ...[
                const Text('Обнаружено:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...(_analysisResult!['found'] as Map).entries.map((e) {
                  return ListTile(
                    leading: const Icon(Icons.warning, color: Colors.red),
                    title: Text(e.key),
                    subtitle: Text('Совпадения: ${(e.value as List).join(", ")}'),
                  );
                }),
              ],

              // Ссылка на сайт
              if (_analysisResult!['website'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ElevatedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(_analysisResult!['website'])),
                    icon: const Icon(Icons.link),
                    label: const Text('Перейти на сайт производителя'),
                  ),
                ),
              
              // Распознанный текст (скрытый)
              const SizedBox(height: 20),
              ExpansionTile(
                title: const Text('Показать распознанный текст'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_analysisResult!['rawText']),
                  )
                ],
              )
            ]
          ],
        ),
      ),
    );
  }
}
