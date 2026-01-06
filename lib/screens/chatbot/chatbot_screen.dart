import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../services/user_service.dart'; // Your existing UserService

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Local message list for UI
  List<ChatMessage> _messages = [];
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  void _initializeChat() {
    setState(() {
      _messages = [
        ChatMessage(
          text: "Hello! I'm your AI diabetes assistant.\n\n"
              "I can create personalized meal plans, exercise routines, and sleep schedules based on your profile and glucose readings.",
          isUser: false,
          timestamp: DateTime.now(),
        ),
        ChatMessage.quickOptions(['Generate Meal Plan', 'Generate Exercise Plan', 'Generate Sleep Plan', 'General Health Tips']),
      ];
    });
  }

  // ---------------------------------------------------------------------------
  // CORE CHAT LOGIC
  // ---------------------------------------------------------------------------

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    // 1. Update UI immediately
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, timestamp: DateTime.now()));
      _isTyping = true;
    });
    _messageController.clear();
    _scrollToBottom();

    // 2. Check for plan generation requests
    if (text.toLowerCase().contains('meal plan') || 
        text.toLowerCase().contains('diet') ||
        text.toLowerCase().contains('generate meal')) {
      _generateMealPlan();
      return;
    }
    if (text.toLowerCase().contains('exercise') || 
        text.toLowerCase().contains('workout') ||
        text.toLowerCase().contains('generate exercise')) {
      _generateExercisePlan();
      return;
    }
    if (text.toLowerCase().contains('sleep') ||
        text.toLowerCase().contains('generate sleep')) {
      _generateSleepPlan();
      return;
    }

    // 3. Send to AI for general queries
    _sendToGroq();
  }

  // ---------------------------------------------------------------------------
  // PLAN GENERATION METHODS
  // ---------------------------------------------------------------------------

  Future<void> _generateMealPlan() async {
    final userService = Provider.of<UserService>(context, listen: false);
    final profile = userService.userProfile;
    final readings = userService.sugarReadings;

    print("DEBUG: Generating meal plan...");
    print("DEBUG: Profile = $profile");
    print("DEBUG: Readings count = ${readings.length}");

    if (profile == null || profile.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: "⚠️ Unable to generate meal plan. Please complete your profile first.\n\n"
              "Go to Profile → Fill in your age, gender, weight, and health history.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
      return;
    }

    if (readings.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: "⚠️ No glucose readings found. Please add at least one glucose reading in your profile.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
      return;
    }

    // Build prompt based on user data
    String prompt = _buildMealPlanPrompt(profile, readings);
    
    print("✅ Profile data found, building prompt...");
    
    // Add the prompt to messages (hidden from UI)
    setState(() {
      _messages.add(ChatMessage(text: prompt, isUser: true, timestamp: DateTime.now()));
    });

    await _sendToGroq();
  }

  Future<void> _generateExercisePlan() async {
    final userService = Provider.of<UserService>(context, listen: false);
    final profile = userService.userProfile;
    final readings = userService.sugarReadings;

    if (profile == null || profile.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: "⚠️ Unable to generate exercise plan. Please complete your profile first.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
      return;
    }

    if (readings.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: "⚠️ No glucose readings found. Please add glucose readings in your profile.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
      return;
    }

    String prompt = _buildExercisePlanPrompt(profile, readings);
    
    setState(() {
      _messages.add(ChatMessage(text: prompt, isUser: true, timestamp: DateTime.now()));
    });

    await _sendToGroq();
  }

  Future<void> _generateSleepPlan() async {
    final userService = Provider.of<UserService>(context, listen: false);
    final profile = userService.userProfile;
    final readings = userService.sugarReadings;

    if (profile == null || profile.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: "⚠️ Unable to generate sleep plan. Please complete your profile first.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
      return;
    }

    if (readings.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: "⚠️ No glucose readings found. Please add glucose readings in your profile.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
      return;
    }

    String prompt = _buildSleepPlanPrompt(profile, readings);
    
    setState(() {
      _messages.add(ChatMessage(text: prompt, isUser: true, timestamp: DateTime.now()));
    });

    await _sendToGroq();
  }

  // ---------------------------------------------------------------------------
  // PROMPT BUILDERS BASED ON USER PROFILE DATA FROM FIRESTORE
  // ---------------------------------------------------------------------------

  String _buildMealPlanPrompt(Map<String, dynamic> profile, List<Map<String, dynamic>> readings) {
    final age = profile['age'] ?? 'unknown';
    final gender = profile['gender'] ?? 'unknown';
    final weight = profile['weight'] ?? 'unknown';
    final healthHistory = profile['healthHistory'] ?? 'No history provided';
    
    // Get last 3 readings
    final recentReadings = readings.take(3).toList();
    List<double> readingValues = recentReadings.map((r) => (r['reading'] as num).toDouble()).toList();
    double avgSugar = readingValues.isEmpty ? 0 : readingValues.reduce((a, b) => a + b) / readingValues.length;
    
    String readingsText = readingValues.isEmpty 
        ? 'No recent readings' 
        : readingValues.map((r) => '${r.toStringAsFixed(1)} mg/dL').join(', ');

    return """Act as a diabetes nutrition expert. Create a detailed, personalized meal plan for a patient with the following profile:

Age: $age years
Gender: $gender
Weight: $weight kg
Health History: $healthHistory
Average Blood Sugar (Recent): ${avgSugar.toStringAsFixed(1)} mg/dL
Recent Readings: $readingsText

Provide a complete daily meal plan with:
- Breakfast, Lunch, Dinner, and 2 snacks
- Specific portion sizes and calorie counts
- Carbohydrate content for each meal (with glycemic index info)
- Tips for blood sugar management based on their current readings
- Recommended meal timing
- Hydration recommendations
- Foods to emphasize or avoid based on glucose levels

Keep it safe, healthy, and specifically tailored for diabetes management.""";
  }

  String _buildExercisePlanPrompt(Map<String, dynamic> profile, List<Map<String, dynamic>> readings) {
    final age = profile['age'] ?? 'unknown';
    final gender = profile['gender'] ?? 'unknown';
    final weight = profile['weight'] ?? 'unknown';
    final healthHistory = profile['healthHistory'] ?? 'No history provided';
    
    final recentReadings = readings.take(3).toList();
    List<double> readingValues = recentReadings.map((r) => (r['reading'] as num).toDouble()).toList();
    double avgSugar = readingValues.isEmpty ? 0 : readingValues.reduce((a, b) => a + b) / readingValues.length;
    
    String glucoseStatus = 'moderate';
    if (avgSugar < 100) {
      glucoseStatus = 'well-controlled';
    } else if (avgSugar < 140) glucoseStatus = 'moderately controlled';
    else glucoseStatus = 'needs improvement';

    return """Act as a diabetes fitness expert. Create a personalized exercise routine for a patient with the following profile:

Age: $age years
Gender: $gender
Weight: $weight kg
Health History: $healthHistory
Average Blood Sugar: ${avgSugar.toStringAsFixed(1)} mg/dL (Status: $glucoseStatus)

Provide a complete weekly exercise plan with:
- 7-day workout schedule (specific exercises, sets, reps, duration)
- Exercises suitable for their age, weight, and health conditions
- Warm-up and cool-down routines
- Best times to exercise for glucose control
- Safety precautions for diabetics
- Tips for monitoring blood sugar before/after exercise
- Progressive difficulty increase recommendations
- How to adjust exercise based on glucose readings
- Rest day guidance

Keep it safe, progressive, and specifically tailored for diabetes management.""";
  }

  String _buildSleepPlanPrompt(Map<String, dynamic> profile, List<Map<String, dynamic>> readings) {
    final age = profile['age'] ?? 'unknown';
    final gender = profile['gender'] ?? 'unknown';
    final healthHistory = profile['healthHistory'] ?? 'No history provided';
    
    final recentReadings = readings.take(3).toList();
    List<double> readingValues = recentReadings.map((r) => (r['reading'] as num).toDouble()).toList();
    double avgSugar = readingValues.isEmpty ? 0 : readingValues.reduce((a, b) => a + b) / readingValues.length;
    
    // Analyze glucose pattern
    String glucosePattern = 'stable';
    if (readingValues.length >= 2) {
      final latest = readingValues.first;
      final previous = readingValues[1];
      if ((latest - previous).abs() > 30) {
        glucosePattern = 'fluctuating';
      }
    }

    return """Act as a diabetes sleep health expert. Create a comprehensive sleep improvement plan for a patient with the following profile:

Age: $age years
Gender: $gender
Health History: $healthHistory
Average Blood Sugar: ${avgSugar.toStringAsFixed(1)} mg/dL
Glucose Pattern: $glucosePattern

Provide a complete sleep optimization plan with:
- Recommended sleep schedule and optimal duration for their age
- Step-by-step bedtime routine
- Sleep hygiene practices
- Tips for managing blood sugar during sleep (especially important with $glucosePattern glucose levels)
- When to check glucose levels (before bed/morning)
- Foods/drinks to avoid before sleep
- What to do if glucose is high/low before bed
- Relaxation and stress management techniques
- Bedroom environment optimization
- How sleep affects blood sugar control

Keep it safe, practical, and specifically tailored for diabetes management.""";
  }

  // ---------------------------------------------------------------------------
  // GROQ API INTEGRATION
  // ---------------------------------------------------------------------------

  Future<void> _sendToGroq() async {
    final apiKey = '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';
    
    if (apiKey.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: "⚠️ Groq API key is missing. Please add it to your configuration.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
      return;
    }

    try {
      // 1. Prepare the chat history
      final recentMessages = _messages
          .where((m) => !m.isQuickOptions && m.text.isNotEmpty)
          .toList();
      
      // Take last 10 messages to avoid token limits
      final historyToSend = recentMessages.length > 10 
          ? recentMessages.sublist(recentMessages.length - 10) 
          : recentMessages;

      // Convert to Groq API format
      final messages = historyToSend.map((m) => {
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      }).toList();

      // 2. Build request body
      final body = {
        'model': 'llama-3.1-8b-instant',
        'messages': [
          {
            'role': 'system',
            'content': 'You are a helpful diabetes management assistant. Provide concise, accurate advice about diet, exercise, sleep, glucose monitoring, and healthy habits for diabetic patients. Keep responses brief and actionable. Format your responses in a clear, organized manner with bullet points and sections.'
          },
          ...messages,
        ],
        'temperature': 0.7,
        'max_tokens': 1200, // Increased for detailed plans
      };

      // 3. Make API call to Groq
      final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(body),
      );

      // 4. Handle successful response
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? result = data['choices']?[0]?['message']?['content'];
        
        if (result != null && result.isNotEmpty) {
          setState(() {
            _messages.add(ChatMessage(
              text: result,
              isUser: false,
              timestamp: DateTime.now(),
            ));
            _isTyping = false;
          });
          _scrollToBottom();
        } else {
          setState(() {
            _messages.add(ChatMessage(
              text: "I received an empty response. Please try again.",
              isUser: false,
              timestamp: DateTime.now(),
            ));
            _isTyping = false;
          });
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData['error']?['message'] ?? 'Unknown error';
        
        setState(() {
          _messages.add(ChatMessage(
            text: "Oops! Something went wrong.\n\nError: $errorMsg (Status: ${response.statusCode})",
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _isTyping = false;
        });
      }
    } catch (e) {
      print("GROQ ERROR: $e");
      setState(() {
        _messages.add(ChatMessage(
          text: "Oops! Something went wrong.\n\nError: $e",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // UI BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Assistant"), 
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) return _buildTypingIndicator();
                final msg = _messages[index];
                if (msg.isQuickOptions) return _buildQuickOptions(msg.options!);
                return _buildMessageBubble(msg);
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: "Type a message...",
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blue,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: () => _sendMessage(_messageController.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickOptions(List<String> options) {
    return Wrap(
      spacing: 8,
      children: options.map((o) => ActionChip(
        label: Text(o),
        onPressed: () => _sendMessage(o),
      )).toList(),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    // Hide internal expert prompts from display
    if (msg.text.contains("Act as a diabetes")) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: msg.isUser ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: msg.isUser
            ? Text(msg.text, style: const TextStyle(color: Colors.white))
            : MarkdownBody(data: msg.text),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Align(
        alignment: Alignment.centerLeft, 
        child: Text("Thinking...", style: TextStyle(color: Colors.grey))
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isQuickOptions;
  final List<String>? options;

  ChatMessage({
    required this.text, 
    required this.isUser, 
    required this.timestamp, 
    this.isQuickOptions = false, 
    this.options
  });
  
  ChatMessage.quickOptions(List<String> opts) 
    : text = '', 
      isUser = false, 
      timestamp = DateTime.now(), 
      isQuickOptions = true, 
      options = opts;
}