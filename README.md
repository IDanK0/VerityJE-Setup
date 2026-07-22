# VerityTM

> **One-click AI backend for [Verity JE](https://www.curseforge.com/minecraft/mc-mods/verity-je) — the Minecraft mod by [VarmiteYT](https://www.youtube.com/@varmite), official adaptation of [ThatMob](https://www.youtube.com/@ThatMob)'s Verity.**

[![CurseForge](https://img.shields.io/badge/CurseForge-Verity_JE-f16436?logo=curseforge)](https://www.curseforge.com/minecraft/mc-mods/verity-je)
[![Modrinth](https://img.shields.io/badge/Modrinth-Verity_JE-1bd96a?logo=modrinth)](https://modrinth.com/mod/verity-je-official)
[![Discord](https://img.shields.io/badge/Discord-join-5865f2?logo=discord)](https://discord.gg/f6DpBDVjMq)

VerityTM sets up all the AI infrastructure the Verity JE mod needs: speech-to-text (so Verity can hear you), text-to-speech (so Verity can talk back), and the AI gateway (so Verity can think). Cloud or fully local with Ollama — you choose.

---

## What Gets Installed

| Service | What Verity Uses It For | Port |
|---------|------------------------|------|
| **WhisperServer** | Speech-to-Text — Verity hears your voice | `9000/v1/` |
| **FastKoko** | Text-to-Speech — Verity speaks to you (Kokoro-82M) | `8880/v1/` |
| **LiteLLM** | AI Gateway — connects Verity to Groq / Ollama / any LLM | `4000/v1/` |
| **Ollama** | Local LLM runner — fully offline AI for Verity | optional |

---

## Quick Start

```powershell
# 1. Download and run the installer.
#    It asks which services you want, detects your GPU/CPU,
#    and installs everything automatically.
powershell -ExecutionPolicy Bypass -File setup.ps1

# 2. Launch the manager — start, stop, or restart any service.
.\Manager.bat
```

That's it. Configure the Verity JE mod to point at `http://127.0.0.1:4000/v1/` (LiteLLM) and Verity is ready.

---

## How Verity JE Uses These Services

```
Player voice ──► Whisper (STT) ──► text ──► LiteLLM ──► Groq / Ollama
                                                    │
Player hears ◄── FastKoko (TTS) ◄── text ◄──────────┘
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
VerityTM/
├── setup.ps1                 # One-click installer
├── _generate_scripts.ps1     # Launcher generator
├── Manager.bat / .ps1        # Master control panel
├── FastKoko.bat / .ps1       # TTS launcher
├── LiteLLM.bat / .ps1        # AI Gateway launcher
├── WhisperServer.bat / .ps1  # STT launcher
├── WhisperServer/server.py   # Whisper API (OpenAI-compatible)
├── .gitignore
└── README.md
```

---

## Links

- **Verity JE on CurseForge** — https://www.curseforge.com/minecraft/mc-mods/verity-je
- **Verity JE on Modrinth** — https://modrinth.com/mod/verity-je-official
- **Verity Mod Wiki** — https://veritymod.blog/
- **ThatMob (creator)** — https://www.youtube.com/@ThatMob
- **VarmiteYT (mod author)** — https://www.youtube.com/@varmite
- **Discord** — https://discord.gg/f6DpBDVjMq
