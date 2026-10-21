import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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
  
  File? _image;
  bool _isLoading = false;
  Map<String, dynamic>? _analysisResult;

  // ВАЖНО: Для эмулятора Android адрес компьютера — 10.0.2.2
  // Если запускаете на реальном телефоне, впишите IP вашего ПК (например, 192.168.1.5)
  final String serverUrl = 'http://10.0.2.2:8080/recognize';
  //final String serverUrl = 'http://localhost:8080/recognize';

  // База запрещенных ингредиентов
  final Map<String, List<String>> _forbiddenDb = {
    'Молоко': ['молоко', 'молочный', 'сыворотка', 'лактоза', 'казеин', 'сливки'],
    'Глютен': ['глютен', 'пшеница', 'мука', 'рожь', 'ячмень', 'овес'],
    'Соя': ['соя', 'соевый', 'лецитин'],
    'Орехи': ['орех', 'арахис', 'миндаль', 'фундук', 'кешью'],
    'Сахар': ['сахар', 'сахароза', 'фруктоза', 'сироп'],
  };

  // Логика анализа текста (Fuzzy Search)
  Map<String, dynamic> _analyzeText(String rawText) {
    String textLower = rawText.toLowerCase();
    
    // Заменяем латинские буквы на кириллицу (на случай, если OCR что-то перепутал)
    final Map<String, String> replacements = {
      'a': 'а', 'c': 'с', 'e': 'е', 'o': 'о', 'p': 'р', 'x': 'х', 'y': 'у'
    };
    replacements.forEach((k, v) => textLower = textLower.replaceAll(k, v));

    Map<String, List<String>> foundIngredients = {};
    final words = textLower.split(RegExp(r'\W+')); // Разбиваем на слова

    _forbiddenDb.forEach((category, keywords) {
      List<String> matches = [];
      for (var word in words) {
        if (word.length < 4) continue; // Игнорируем короткие слова
        
        for (var keyword in keywords) {
          // Fuzzy-поиск: если совпадение > 75%
          if (ratio(word, keyword) > 75) {
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
      'rawText': rawText,
    };
  }

  // Отправка фото на сервер
  Future<void> _pickAndAnalyze(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() {
      _image = File(pickedFile.path);
      _isLoading = true;
      _analysisResult = null;
    });

    try {
      // 1. Готовим запрос
      var request = http.MultipartRequest('POST', Uri.parse(serverUrl));
      request.files.add(await http.MultipartFile.fromPath('file', _image!.path));

      // 2. Отправляем на Python
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // 3. Получаем русский текст
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final recognizedTextString = jsonResponse['text'] as String;
        
        // 4. Анализируем (Fuzzy)
        final result = _analyzeText(recognizedTextString);
        
        setState(() {
          _analysisResult = result;
        });
      } else {
        throw Exception('Сервер ответил ошибкой: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e. Проверьте, запущен ли Python-сервер.')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Интерфейс
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканер (через сервер)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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

            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!, height: 250, fit: BoxFit.cover),
              ),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text('Отправка на сервер и распознавание...'),
                    ],
                  ),
                ),
              ),

            if (_analysisResult != null) ...[
              const SizedBox(height: 20),
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
              
              const SizedBox(height: 20),
              ExpansionTile(
                title: const Text('Показать текст с сервера'),
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
