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
For ollama running from remote server, run below commands on admin powershell console

```powershell
[System.Environment]::SetEnvironmentVariable("OLLAMA_ORIGINS", "*,null", "Machine")
[System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", "Machine")
```

---

# Accessing CORS-restricted models
Some APIs (for example NVIDIA and IndieRouter) do not allow requests from a website in the browser. They block them with a CORS error.

To use these APIs:

1. Install Node.js, then run:
   ```bash
   node convergent-proxy.js
   ```
   Leave the terminal open. If you close it, the models will stop working.

2. In the HTML file, open Settings → Endpoints. Enter `http://localhost:3030` as the proxy URL and click “Test Proxy Connection”.

3. Add the API’s base URL and your key as usual, then fetch models or start chatting.

## How it works
The local proxy runs on your machine and forwards the requests for you. The browser talks only to the proxy (which allows CORS), and the proxy talks to the real API.

When you want to support a new CORS-restricted API, do two things:

- In the HTML file, add the API’s hostname to the `isNvidiaEndpoint(ep)` function so requests are sent through the proxy.
- In `convergent-proxy.js`, add the same hostname to the `ALLOWED_HOSTS` list so the proxy is allowed to forward to it.

> This is only needed for APIs that block browser CORS requests. Most other providers work without the proxy.

# Supported Web Search Providers

Use your preferred search provider for real-time information retrieval.

Examples:

- Tavily
- SearXNG
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
