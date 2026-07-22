# Verity JE Setup

[![CurseForge](https://img.shields.io/badge/CurseForge-Verity_JE-f16436?logo=curseforge)](https://www.curseforge.com/minecraft/mc-mods/verity-je)
[![Modrinth](https://img.shields.io/badge/Modrinth-Verity_JE-1bd96a?logo=modrinth)](https://modrinth.com/mod/verity-je-official)
[![Discord](https://img.shields.io/badge/Discord-join-5865f2?logo=discord)](https://discord.gg/f6DpBDVjMq)

One-click AI backend installer for the [Verity JE](https://www.curseforge.com/minecraft/mc-mods/verity-je) Minecraft mod by [VarmiteYT](https://www.youtube.com/@varmite), official adaptation of [ThatMob](https://www.youtube.com/@ThatMob)'s Verity.

---

## Quick Start

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
.\Manager.bat
```

The installer detects your hardware, asks which services you want, and handles everything automatically. No manual installs, no Docker, no config files.

---

## Services

| Service | Purpose | Port | Model |
|---------|---------|------|-------|
| FastKoko | Text-to-Speech | `8880/v1/` | Kokoro-82M |
| LiteLLM | AI Gateway (100+ LLMs) | `4000/v1/` | Groq / Ollama / any provider |
| WhisperServer | Speech-to-Text | `9000/v1/` | auto-selected by hardware |
| Ollama | Local LLM runner | optional | llama3.2, mistral, gemma, etc. |

All services expose OpenAI-compatible APIs under `http://127.0.0.1:{PORT}/v1/`.

---

## Architecture

```
Microphone -> Whisper (STT) -> text -> LiteLLM -> Groq / Ollama -> text -> Kokoro (TTS) -> Speakers
```

- **Cloud mode**: LiteLLM routes to Groq. Requires a Groq API key.
- **Local mode**: LiteLLM routes to Ollama running a local model. Fully offline.

---

## Hardware Detection

| Hardware | Whisper Model | Torch Backend | CUDA Index |
|----------|--------------|---------------|------------|
| NVIDIA GPU (6+ GB VRAM) | `large-v3-turbo` | CUDA | auto-detected |
| NVIDIA GPU (4-6 GB VRAM) | `medium` | CUDA | auto-detected |
| NVIDIA GPU (<4 GB VRAM) | `base` | CUDA | auto-detected |
| AMD GPU / CPU only, 16+ GB RAM | `base` | CPU | N/A |
| CPU only, <16 GB RAM | `tiny` | CPU | N/A |

All values are auto-detected at install time. Nothing is hardcoded.

---

## Usage

### Manager

```powershell
.\Manager.bat
```

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

Missing dependencies (Git, uv, Python 3.10-3.13, eSpeak NG) are installed automatically. If winget is unavailable (e.g. Windows Sandbox), the installer downloads directly from official sources.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Service not starting | Check port is free (`netstat -ano`), restart via Manager |
| Model download failed | Installer retries automatically. Re-run `setup.ps1` |
| CUDA not available | Update NVIDIA drivers. Installer falls back to CPU |
| winget not found | Installer downloads directly from official URLs |
| Git/uv not found | Installer installs them automatically |
| Python version conflict | Installer uses `uv` with isolated venvs (Python 3.10-3.13) |

---

## Project Structure

```
setup.ps1                 One-click installer
_generate_scripts.ps1     Script generator (called by setup)
Manager.bat / .ps1        Master control panel
FastKoko.bat / .ps1       TTS launcher
LiteLLM.bat / .ps1        AI Gateway launcher
WhisperServer.bat         STT launcher
WhisperLauncher.ps1
WhisperServer/server.py   Whisper API server
.gitignore
README.md
```

---

## Links

- [Verity JE on CurseForge](https://www.curseforge.com/minecraft/mc-mods/verity-je) - 1.8M+ downloads
- [Verity JE on Modrinth](https://modrinth.com/mod/verity-je-official)
- [Verity Mod Wiki](https://veritymod.blog/)
- [ThatMob on YouTube](https://www.youtube.com/@ThatMob) - original creator
- [VarmiteYT on YouTube](https://www.youtube.com/@varmite) - mod author
- [Discord Server](https://discord.gg/f6DpBDVjMq)
