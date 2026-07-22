# Verity JE Setup

[![CurseForge](https://img.shields.io/badge/CurseForge-Verity_JE-f16436?logo=curseforge)](https://www.curseforge.com/minecraft/mc-mods/verity-je)
[![Modrinth](https://img.shields.io/badge/Modrinth-Verity_JE-1bd96a?logo=modrinth)](https://modrinth.com/mod/verity-je-official)
[![Discord](https://img.shields.io/badge/Discord-join-5865f2?logo=discord)](https://discord.gg/f6DpBDVjMq)

One-click AI backend for [Verity JE](https://www.curseforge.com/minecraft/mc-mods/verity-je), the Minecraft mod by [VarmiteYT](https://www.youtube.com/@varmite) based on [ThatMob](https://www.youtube.com/@ThatMob)'s Verity.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [What Gets Installed](#what-gets-installed)
- [How It Works](#how-it-works)
- [Usage](#usage)
  - [Manager Controls](#manager-controls)
  - [Individual Launchers](#individual-launchers)
- [Hardware Detection](#hardware-detection)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)
- [Links](#links)

## Prerequisites

- Windows 10 or 11
- Internet connection
- That is it. Everything else (Git, uv, Python 3.10, eSpeak NG, CUDA torch, Ollama) is installed automatically.

## Quick Start

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
.\Manager.bat
```

The installer detects your hardware, asks which services you want, and downloads everything. Then point the Verity JE mod to `http://127.0.0.1:4000/v1/`.

## What Gets Installed

| Service | Purpose | Port |
|---------|---------|------|
| WhisperServer | Speech-to-Text | `9000/v1/` |
| FastKoko | Text-to-Speech (Kokoro-82M) | `8880/v1/` |
| LiteLLM | AI Gateway (Groq / Ollama / any LLM) | `4000/v1/` |
| Ollama | Local LLM runner (optional) | `11434` |

All services expose OpenAI-compatible APIs.

## How It Works

```
Player voice --> Whisper --> text --> LiteLLM --> Groq / Ollama --> text --> FastKoko --> Player hears
```

Two modes are supported:

- **Cloud**: LiteLLM routes to Groq. Fast, no GPU needed. Requires a Groq API key.
- **Local**: LiteLLM routes to Ollama running a local model. Private, fully offline.

## Usage

### Manager Controls

```
[S] Start all    [A] Stop all    [R] Restart all
[F] FastKoko     [I] LiteLLM     [W] Whisper
[L] Change LiteLLM model         [K] List Kokoro voices
[Q] Quit
```

### Individual Launchers

Each service can also be started separately:

```powershell
.\FastKoko.bat       # http://127.0.0.1:8880/v1/
.\LiteLLM.bat        # http://127.0.0.1:4000/v1/
.\WhisperServer.bat  # http://127.0.0.1:9000/v1/
```

## Hardware Detection

`setup.ps1` scans your system and picks the right configuration automatically.

| Hardware | Whisper Model | Torch |
|----------|--------------|-------|
| NVIDIA GPU (6 GB or more) | `large-v3-turbo` | CUDA |
| NVIDIA GPU (4 to 6 GB) | `medium` | CUDA |
| NVIDIA GPU (under 4 GB) | `base` | CUDA |
| AMD GPU or CPU only | `base` or `tiny` | CPU |

Disk space and RAM are also checked. You get a warning if below 15 GB free.

## Troubleshooting

- **Port already in use**: Stop any running servers and try again.
- **Model download failed**: The installer retries automatically. For manual download, check the individual service documentation.
- **CUDA not available**: If you have an NVIDIA GPU but CUDA is not detected, update your NVIDIA drivers.
- **eSpeak NG not found**: Install it manually from `winget install eSpeak-NG.eSpeak-NG`.
- **Ollama service not running**: Start it from the Start Menu or run `ollama serve`.

## Project Structure

```
VerityJE-Setup/
|
+-- setup.ps1                     One-click installer
+-- _generate_scripts.ps1         Script generator
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

## Links

- [Verity JE on CurseForge](https://www.curseforge.com/minecraft/mc-mods/verity-je)
- [Verity JE on Modrinth](https://modrinth.com/mod/verity-je-official)
- [Verity Mod Wiki](https://veritymod.blog/)
- [ThatMob on YouTube](https://www.youtube.com/@ThatMob)
- [VarmiteYT on YouTube](https://www.youtube.com/@varmite)
- [Discord Server](https://discord.gg/f6DpBDVjMq)