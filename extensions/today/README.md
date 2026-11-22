# Today (Notch)

Your day at a glance, in the style of a phone's daily brief.

- **Brief:** one short paragraph built on-device from your calendar, reminders and weather. No network and
  no AI needed.
- **Weather:** Open-Meteo (no key). Set a city in the tab's settings; only the city name and its coordinates
  are sent.
- **Schedule and reminders:** from Calendar and Reminders. Vehla already holds those permissions; the tab asks
  macOS only when you tap *Allow*.
- **Next meeting:** about ten minutes before an event, the closed Notch shows a countdown with a **Join**
  button when the event has a Zoom / Meet / Teams / Webex link.
- **AI brief (opt-in, off by default):** pick a provider in the tab's settings and the model rewrites the
  brief. Supported: **Anthropic**, **OpenAI**, **Google Gemini**, **DeepSeek**, and **Custom**: any
  OpenAI-compatible endpoint (OpenRouter, Groq, Together, or a local model such as Ollama at
  `http://localhost:11434/v1`, which needs no key). Each provider has its own key, added in Vehla's Store
  settings (`anthropicKey`, `openaiKey`, `geminiKey`, `deepseekKey`, `customKey`). The model is a dropdown filled from the
  provider's live model list (using your key), with a short built-in list as a fallback; a custom endpoint
  that doesn't list models falls back to a text field. Only event titles and times, reminder titles and the
  weather are sent, never notes, attendees or locations; the settings screen names the exact host that
  receives them. Custom endpoints must be `https` (plain `http` only for localhost). Gemini's key is sent
  in a header, not the URL.

Develop: `swift test` (parsers, brief, planner, request building) and `./build.sh`.
