# Convergent

Convergent is a lightweight multi-model AI chat application that lets users query multiple LMs simultaneously, compare outputs side-by-side, generate synthesized responses, search the web for real-time information, and organize conversations locally.

Unlike traditional AI chat apps that rely on a single response, Convergent helps users validate outputs across multiple models and current web sources.

Built as a **single HTML application** with no framework dependency.

---

## Why Convergent?

Most AI chat apps work like this:

- Ask one model  
- Get one response  
- Hope it's correct  

Convergent improves that workflow:

- Query multiple models simultaneously  
- Compare responses side-by-side  
- Generate synthesized answers  
- Search the web for current information  
- Save chats securely  
- Organize conversations efficiently  

---

# Key Features

### Multi-Model Comparison
Send one prompt to multiple AI models at the same time and compare responses in parallel.

---

### Response Synthesis
Generate a final answer by combining outputs from multiple model responses.

---

### Web Search Integration
Search the web for real-time information directly inside chats.

Useful for:

- Latest news  
- Current events  
- Recent documentation  
- Real-time research  
- Fact verification  

Supports configurable search providers.

---

### Slash Commands
Use built-in slash commands for faster workflows.

Examples:

- `/summarize`
- `/rewrite`
- `/explain`
- `/debug`

Users can also create custom slash commands for repetitive workflows. Type / in the prompt. See list of available slash commands or create new.

---

### Local-First Storage
All conversations remain stored on your device.

No mandatory cloud storage.

---

### Password Encryption
Protect conversations using passphrase-based encryption.

---

### Project Organization
Group chats into projects for better long-term organization.

---

### Chat Search
Search across previous chats instantly.

---

### Import / Export
Backup and restore conversations easily.

---

# Installation

1. Download the HTML file  
2. Open it in your browser  
3. Add your API keys  
4. Start chatting  

No backend setup required.  
No framework installation required.

---

# Supported AI Providers

Convergent works with any provider that exposes an API endpoint.

Examples:

- OpenAI  
- Anthropic  
- Google Gemini  
- OpenRouter  
- Groq  
- Together AI  
- Perplexity  
- DeepSeek  
- Mistral  
- Ollama  
- LM Studio  
- Self-hosted OpenAI-compatible endpoints  
- Custom API providers  

## Ollama Setup

If you're using Ollama, allow browser-based requests by setting `OLLAMA_ORIGINS`.

**Windows:**
```bash
set OLLAMA_ORIGINS=*
```

**Linux (bash) and Mac (Terminal):**
```bash
export OLLAMA_ORIGINS=*
```
---

# Supported Web Search Providers

Use your preferred search provider for real-time information retrieval.

Examples:

- Tavily  
- Brave Search  
- SerpAPI  
- Serper  
- Exa  
- Custom search APIs  

---

# Tech Stack

- HTML  
- CSS  
- JavaScript  
- LocalStorage  
- IndexedDB  
- Browser Crypto APIs  

Single-file architecture.

---

# Migrating to a New Folder

If you want to rename your existing storage folder or move your chats/configurations to a new folder:

1. Use the **Export Data** option on the home page directly or navigate to **Settings → Data**
2. Use **Export Data** to create a backup
3. Rename your existing folder **or** create a new folder
4. Use the **Import Data** option on the home page directly or navigate to **Settings → Data**
5. Select the new folder location
6. Import your exported backup
7. Enter your existing password/passphrase

Your chats, configurations, and encrypted data will be restored and accessible in the new folder.

---

# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
