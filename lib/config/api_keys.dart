// Central place to access runtime API keys loaded via .env (do NOT commit secrets).
// Create a .env file at project root with:
// GEMINI_API_KEY=your_gemini_key
// USDA_API_KEY=your_usda_key
// (Never commit .env)  Add to .gitignore:  .env


class ApiKeysWeb {
  static const gemini = "AIzaSyASl8VzVCz-zYoUoMaN-si4cvR4pKmuw98";
  static const usda = "Tlj8JWi0vK9poZUWSqEw8TLhZaVEAmxckE2hhiDe";
  static const groq = "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"; // ADD THIS
}
