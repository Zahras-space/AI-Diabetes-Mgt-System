import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

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

  // ---------------------------------------------------------------------------
  // GUIDED FLOW VARIABLES
  // ---------------------------------------------------------------------------
  bool _collectingPlan = false;
  int _planStep = 0;
  final _answers = <String, String>{};

  final List<Map<String, dynamic>> _planQuestions = [
    {'key': 'diet', 'text': 'Do you have any dietary preference?', 'options': ['Balanced', 'Low-carb', 'High-protein', 'Vegetarian']},
    {'key': 'cuisine', 'text': 'Preferred cuisine?', 'options': ['Indian', 'Pakistani', 'Mediterranean', 'American']},
    {'key': 'goal', 'text': 'Primary goal?', 'options': ['Glucose stability', 'Weight control', 'Energy boost']},
  ];

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
              "I can help with meal plans, glucose readings, or exercise tips.",
          isUser: false,
          timestamp: DateTime.now(),
        ),
        ChatMessage.quickOptions(['Create Meal Plan', 'Breakfast Ideas', 'Glucose Help']),
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

    // 2. Handle Guided Flows
    if (_collectingPlan) { _handlePlanAnswer(text); return; }
    if (text.toLowerCase().contains('meal plan')) { _startMealPlanFlow(); return; }

    // 3. Send to AI
    _sendToGroq();
  }

 Future<void> _sendToGroq() async {
  final apiKey = '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';
  
  // Check if API key exists
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
      'model': 'llama-3.1-8b-instant', // Fast Groq model (equivalent to gemini-1.5-flash)
      'messages': [
        {
          'role': 'system',
          'content': 'You are a helpful diabetes management assistant. Provide concise, accurate advice about diet, glucose monitoring, and healthy habits for diabetic patients. Keep responses brief and actionable.'
        },
        ...messages,
      ],
      'temperature': 0.7,
      'max_tokens': 500,
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
        // Handle empty response
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
      // Handle API error response
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
    // Handle network or parsing errors
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

  // ---------------------------------------------------------------------------
  // GUIDED FLOW HELPERS
  // ---------------------------------------------------------------------------

  void _startMealPlanFlow() {
    setState(() {
      _collectingPlan = true;
      _planStep = 0;
      _answers.clear();
      _messages.add(ChatMessage(text: "Let's plan! ${_planQuestions[0]['text']}", isUser: false, timestamp: DateTime.now()));
      _messages.add(ChatMessage.quickOptions(List<String>.from(_planQuestions[0]['options'])));
    });
    _scrollToBottom();
  }

  void _handlePlanAnswer(String answer) {
    _answers[_planQuestions[_planStep]['key']] = answer;
    _planStep++;

    if (_planStep < _planQuestions.length) {
      setState(() {
        _messages.add(ChatMessage(text: _planQuestions[_planStep]['text'], isUser: false, timestamp: DateTime.now()));
        _messages.add(ChatMessage.quickOptions(List<String>.from(_planQuestions[_planStep]['options'])));
      });
    } else {
      setState(() {
        _collectingPlan = false;
        _isTyping = true;
      });

      String prompt = "Act as a diabetes expert. Create a detailed meal plan based on these preferences: $_answers. Keep it safe and healthy.";

      // Add invisible user prompt to history
      setState(() {
        _messages.add(ChatMessage(text: prompt, isUser: true, timestamp: DateTime.now()));
      });

      _sendToGroq();
    }
    _scrollToBottom();
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
      appBar: AppBar(title: const Text("AI Assistant"), backgroundColor: Colors.blue),
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
    if (msg.text.contains("Act as a diabetes expert")) {
      return const SizedBox.shrink(); // Hide the internal prompt
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
      child: Align(alignment: Alignment.centerLeft, child: Text("Thinking...", style: TextStyle(color: Colors.grey))),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isQuickOptions;
  final List<String>? options;

  ChatMessage({required this.text, required this.isUser, required this.timestamp, this.isQuickOptions = false, this.options});
  ChatMessage.quickOptions(List<String> opts) : text = '', isUser = false, timestamp = DateTime.now(), isQuickOptions = true, options = opts;
}