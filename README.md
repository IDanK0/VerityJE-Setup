# Verity JE Setup

> **One-click AI backend for [Verity JE](https://www.curseforge.com/minecraft/mc-mods/verity-je) â€” the Minecraft mod by [VarmiteYT](https://www.youtube.com/@varmite), official adaptation of [ThatMob](https://www.youtube.com/@ThatMob)'s Verity.**

[![CurseForge](https://img.shields.io/badge/CurseForge-Verity_JE-f16436?logo=curseforge)](https://www.curseforge.com/minecraft/mc-mods/verity-je)
[![Modrinth](https://img.shields.io/badge/Modrinth-Verity_JE-1bd96a?logo=modrinth)](https://modrinth.com/mod/verity-je-official)
[![Discord](https://img.shields.io/badge/Discord-join-5865f2?logo=discord)](https://discord.gg/f6DpBDVjMq)

VerityJE-Setup sets up all the AI infrastructure the Verity JE mod needs: speech-to-text (so Verity can hear you), text-to-speech (so Verity can talk back), and the AI gateway (so Verity can think). Cloud or fully local with Ollama â€” you choose.

---

## What Gets Installed

| Service | What Verity Uses It For | Port |
|---------|------------------------|------|
| **WhisperServer** | Speech-to-Text â€” Verity hears your voice | `9000/v1/` |
| **FastKoko** | Text-to-Speech â€” Verity speaks to you (Kokoro-82M) | `8880/v1/` |
| **LiteLLM** | AI Gateway â€” connects Verity to Groq / Ollama / any LLM | `4000/v1/` |
| **Ollama** | Local LLM runner â€” fully offline AI for Verity | optional |

---

## Quick Start

```powershell
# 1. Download and run the installer.
#    It asks which services you want, detects your GPU/CPU,
#    and installs everything automatically.
powershell -ExecutionPolicy Bypass -File setup.ps1

# 2. Launch the manager â€” start, stop, or restart any service.
.\Manager.bat
```

That's it. Configure the Verity JE mod to point at `http://127.0.0.1:4000/v1/` (LiteLLM) and Verity is ready.

---

## How Verity JE Uses These Services

```
Player voice â”€â”€â-º Whisper (STT) â”€â”€â-º text â”€â”€â-º LiteLLM â”€â”€â-º Groq / Ollama
                                                    â”‚
Player hears â-„â”€â”€ FastKoko (TTS) â-„â”€â”€ text â-„â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

- **Cloud mode**: LiteLLM routes to Groq (fast, no GPU needed, requires API key)
- **Local mode**: LiteLLM routes to Ollama running a local model like `llama3.2` (private, offline)
- Both modes use the same Whisper + Kokoro voice pipeline

---

## Hardware Detection

| Your Hardware | Whisper Model | Torch Backend |
|--------------|---------------|---------------|
| NVIDIA GPU (6+ GB) | `large-v3-turbo` | CUDA |
| NVIDIA GPU (4-6 GB) | `medium` | CUDA |
| NVIDIA GPU (<4 GB) | `base` | CUDA |
| AMD GPU / CPU only | `base` or `tiny` | CPU |

---

## Project Structure

```
VerityJE-Setup/
â”œâ”€â”€ setup.ps1                 # One-click installer
â”œâ”€â”€ _generate_scripts.ps1     # Launcher generator
â”œâ”€â”€ Manager.bat / .ps1        # Master control panel
â”œâ”€â”€ FastKoko.bat / .ps1       # TTS launcher
â”œâ”€â”€ LiteLLM.bat / .ps1        # AI Gateway launcher
â”œâ”€â”€ WhisperServer.bat / .ps1  # STT launcher
â”œâ”€â”€ WhisperServer/server.py   # Whisper API (OpenAI-compatible)
â”œâ”€â”€ .gitignore
â””â”€â”€ README.md
```

---

## Links

- **Verity JE on CurseForge** â€” https://www.curseforge.com/minecraft/mc-mods/verity-je
- **Verity JE on Modrinth** â€” https://modrinth.com/mod/verity-je-official
- **Verity Mod Wiki** â€” https://veritymod.blog/
- **ThatMob (creator)** â€” https://www.youtube.com/@ThatMob
- **VarmiteYT (mod author)** â€” https://www.youtube.com/@varmite
- **Discord** â€” https://discord.gg/f6DpBDVjMq


