# Verity JE Setup

[![CurseForge](https://img.shields.io/badge/CurseForge-Verity_JE-f16436?logo=curseforge)](https://www.curseforge.com/minecraft/mc-mods/verity-je)
[![Modrinth](https://img.shields.io/badge/Modrinth-Verity_JE-1bd96a?logo=modrinth)](https://modrinth.com/mod/verity-je-official)
[![Discord](https://img.shields.io/badge/Discord-join-5865f2?logo=discord)](https://discord.gg/f6DpBDVjMq)

One-click AI backend installer for the [Verity JE](https://www.curseforge.com/minecraft/mc-mods/verity-je) Minecraft mod by [VarmiteYT](https://www.youtube.com/@varmite), official adaptation of [ThatMob](https://www.youtube.com/@ThatMob)'s Verity.

---

## Overview

Verity JE adds an AI companion to Minecraft. This tool installs and configures the three backend services the mod needs: speech-to-text, text-to-speech, and an LLM gateway. Everything runs locally on your machine.

### Architecture

```
Microphone --> Whisper (STT) --> text --> LiteLLM --> Groq / Ollama --> text --> Kokoro (TTS) --> Speakers
```

- **Cloud mode**: LiteLLM routes to Groq. Fast, no GPU needed. Requires a Groq API key.
- **Local mode**: LiteLLM routes to Ollama running a local model. Private, fully offline.

---

## Quick Start

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
.\Manager.bat
```

The installer detects your hardware, asks which services you want, and handles everything automatically.

---

## Services Installed

| Service | Purpose | Port | Model |
|---------|---------|------|-------|
| FastKoko | Text-to-Speech | `8880/v1/` | Kokoro-82M |
| LiteLLM | AI Gateway (100+ LLMs) | `4000/v1/` | Groq, Ollama, or any provider |
| WhisperServer | Speech-to-Text | `9000/v1/` | large-v3-turbo, medium, base, or tiny |
| Ollama | Local LLM runner | optional | llama3.2, mistral, gemma, etc. |

All services expose OpenAI-compatible APIs under `http://127.0.0.1:{PORT}/v1/`.

---

## Hardware Detection

The installer automatically adapts to your machine:

| Hardware | Whisper Model | Torch Backend | CUDA Index |
|----------|--------------|---------------|------------|
| NVIDIA GPU (6+ GB VRAM) | `large-v3-turbo` | CUDA | auto-detected |
| NVIDIA GPU (4-6 GB VRAM) | `medium` | CUDA | auto-detected |
| NVIDIA GPU (<4 GB VRAM) | `base` | CUDA | auto-detected |
| AMD GPU | `medium` | CPU | N/A |
| CPU only, 16+ GB RAM | `base` | CPU | N/A |
| CPU only, <16 GB RAM | `tiny` | CPU | N/A |

Additional checks:
- Python version: auto-selects 3.10-3.13 (excludes 3.14+ due to torch compatibility)
- Disk space: warns if below 15 GB
- eSpeak NG path: searched in multiple locations
- uv binary path: auto-detected

---

## Usage

### Manager (recommended)

```powershell
.\Manager.bat
```

Controls all services from one window:

```
[S] Start all    [A] Stop all    [R] Restart all
[F] FastKoko     [I] LiteLLM     [W] Whisper
[Q] Quit
```

### Individual Launchers

```powershell
.\FastKoko.bat       # TTS: http://127.0.0.1:8880/v1/
.\LiteLLM.bat        # AI:  http://127.0.0.1:4000/v1/
.\WhisperServer.bat  # STT: http://127.0.0.1:9000/v1/
```

---

## Requirements

- Windows 10 or 11
- Internet connection
- That is it. Missing dependencies (Git, uv, Python, eSpeak NG) are installed automatically via winget.

---

## Project Structure

```
VerityJE-Setup/
|
+-- setup.ps1                     One-click installer
+-- _generate_scripts.ps1         Script generator (called by setup)
+-- Manager.bat                   Master control panel
+-- Manager.ps1
+-- FastKoko.bat                  TTS launcher
+-- FastKoko.ps1
+-- LiteLLM.bat                   AI Gateway launcher
+-- LiteLLM.ps1
+-- WhisperServer.bat             STT launcher
+-- WhisperLauncher.ps1
+-- WhisperServer/
|   +-- server.py                 Whisper API server
+-- .gitignore
+-- README.md
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Service not starting | Check port not in use (`netstat -ano`) and run `.\Manager.bat` again |
| Model download failed | Installer retries automatically. For manual download, check service documentation |
| CUDA not available | Update NVIDIA drivers. Installer falls back to CPU inference if GPU is not detected |
| eSpeak NG not found | Run `winget install eSpeak-NG.eSpeak-NG` or set `PHONEMIZER_ESPEAK_LIBRARY` manually |
| Python version conflict | Installer uses `uv` with isolated virtual environments (Python 3.10-3.13) |
| Ollama not in PATH | Restart terminal after installation |

---

## Links

- [Verity JE on CurseForge](https://www.curseforge.com/minecraft/mc-mods/verity-je) - 1.8M+ downloads
- [Verity JE on Modrinth](https://modrinth.com/mod/verity-je-official)
- [Verity Mod Wiki](https://veritymod.blog/)
- [ThatMob on YouTube](https://www.youtube.com/@ThatMob) - original creator
- [VarmiteYT on YouTube](https://www.youtube.com/@varmite) - mod author
- [Discord Server](https://discord.gg/f6DpBDVjMq)
