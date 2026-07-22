# VerityTM

One script, three AI services. Bring your own keys, go from zero to production on any Windows PC.

## What It Does

| Service | What | Port | Model |
|---------|------|------|-------|
| **FastKoko** | Text-to-Speech (TTS) | `8880/v1/` | Kokoro-82M |
| **LiteLLM** | AI Gateway (100+ LLMs) | `4000/v1/` | Pick any provider |
| **WhisperServer** | Speech-to-Text (STT) | `9000/v1/` | large-v3-turbo or auto |

All services expose OpenAI-compatible APIs under `http://127.0.0.1:PORT/v1/`.

## Quick Start

```powershell
# 1. Run the installer. It detects your hardware, asks which services you want,
#    and installs everything automatically (git, uv, Python, dependencies, models).
powershell -ExecutionPolicy Bypass -File setup.ps1

# 2. Launch the manager. One window to start/stop/restart all services.
.\Manager.bat
```

That's it. No manual installs, no config files, no Docker.

## Prerequisites

- Windows 10 or 11
- Internet connection

Everything else (`git`, `uv`, `Python 3.10`, `eSpeak NG`, `torch + CUDA`, `Ollama`) is installed automatically via `winget` and `pip` by `setup.ps1`.

## Services

### FastKoko — Text-to-Speech

```
http://127.0.0.1:8880/v1/audio/speech
```

OpenAI-compatible speech endpoint powered by Kokoro-82M. Italian, English, Spanish, French, Japanese, Mandarin, and more.

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:8880/v1", api_key="not-needed")
client.audio.speech.create(model="kokoro", voice="im_nicola", input="Ciao mondo!")
```

### LiteLLM — AI Gateway

```
http://127.0.0.1:4000/v1/chat/completions
```

Single interface for 100+ LLM providers (OpenAI, Anthropic, Gemini, Groq, HuggingFace, local Ollama models, and more). The launcher prompts for your API key and model choice.

```powershell
.\LiteLLM.bat
# -> Choose model -> Enter API key -> Server ready
```

### WhisperServer — Speech-to-Text

```
http://127.0.0.1:9000/v1/audio/speech
```

Transcribe audio files. Automatically picks the best Whisper model for your hardware (large-v3-turbo for NVIDIA GPUs with 6+ GB VRAM, medium for weaker GPUs, base/tiny for CPU-only).

```bash
curl -X POST http://127.0.0.1:9000/v1/audio/speech -F "file=@recording.mp3"
```

## Hardware Detection

`setup.ps1` automatically detects:

- **NVIDIA GPU** — CUDA-enabled torch, large-v3-turbo for Whisper
- **AMD GPU** — CPU inference (ROCm not supported by Whisper)
- **CPU only** — lightweight models, no GPU acceleration
- **RAM** — model selection degrades gracefully on low-memory systems
- **Disk space** — warns if less than 15 GB free

## Project Structure

```
VerityTM/
├── setup.ps1                 # One-click installer
├── _generate_scripts.ps1     # Script generator (called by setup)
├── Manager.bat / Manager.ps1 # Master control panel
├── FastKoko.bat / .ps1       # TTS launcher
├── LiteLLM.bat / .ps1        # AI Gateway launcher
├── WhisperServer.bat / .ps1  # STT launcher
│
├── Kokoro-FastAPI/           # Cloned by setup.ps1
├── WhisperServer/            # Created by setup.ps1
│   └── server.py             # FastAPI Whisper server
└── .gitignore
```

## Manager Controls

```
[S] Start all    [A] Stop all    [R] Restart all
[F] FastKoko     [L] LiteLLM     [W] Whisper
[K] List Kokoro voices           [L] Change LiteLLM model
[Q] Quit
```
