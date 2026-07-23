# Verity JE Setup

[![CurseForge](https://img.shields.io/badge/CurseForge-Verity_JE-f16436?logo=curseforge)](https://www.curseforge.com/minecraft/mc-mods/verity-je)
[![Modrinth](https://img.shields.io/badge/Modrinth-Verity_JE-1bd96a?logo=modrinth)](https://modrinth.com/mod/verity-je-official)
[![Discord](https://img.shields.io/badge/Discord-join-5865f2?logo=discord)](https://discord.gg/f6DpBDVjMq)

One-click AI backend installer for the [Verity JE](https://www.curseforge.com/minecraft/mc-mods/verity-je) Minecraft mod by [VarmiteYT](https://www.youtube.com/@varmite), official adaptation of [ThatMob](https://www.youtube.com/@ThatMob)'s Verity.

---

## Quick Start

1. Download this repo (Code -> Download ZIP, or `git clone`).
2. Double-click **`Setup.bat`** (or run `powershell -ExecutionPolicy Bypass -File setup.ps1`).
3. Double-click **`Manager.bat`** to start/stop everything.

The installer detects your hardware, asks which services you want, and handles everything automatically: Git, uv, Python, ffmpeg, models, configuration. No Docker, no manual steps. If winget is unavailable (e.g. Windows Sandbox), everything is downloaded directly from official sources.

Unattended mode (great for testing / Windows Sandbox):

```powershell
.\setup.ps1 -Yes              # all services, all defaults, zero prompts
.\setup.ps1 -Yes -Services K,W   # only FastKoko + Whisper
.\setup.ps1 -SelfTest         # hardware/software detection only, changes nothing
```

---

## Services

| Service | Purpose | Port | Model |
|---------|---------|------|-------|
| FastKoko | Text-to-Speech | `8880` | Kokoro-82M (pinned Kokoro-FastAPI v0.6.0) |
| LiteLLM | AI Gateway (100+ LLMs) | `4000` | Groq / OpenAI / Anthropic / Gemini / Ollama |
| WhisperServer | Speech-to-Text | `9000` | auto-selected by hardware |
| Ollama | Local LLM runner | optional | llama3.2, mistral, qwen, etc. |

All services listen on `127.0.0.1` only and expose OpenAI-compatible APIs:

- TTS: `POST http://127.0.0.1:8880/v1/audio/speech`
- STT: `POST http://127.0.0.1:9000/v1/audio/transcriptions`
- LLM: `POST http://127.0.0.1:4000/v1/chat/completions`

---

## Architecture

```
Microphone -> Whisper (STT) -> text -> LiteLLM -> Groq / Ollama -> text -> Kokoro (TTS) -> Speakers
```

- **Cloud mode**: LiteLLM routes to a cloud provider (Groq, OpenAI, ...). Requires an API key, asked once and stored per-user.
- **Local mode**: LiteLLM routes to Ollama running a local model. Fully offline.

---

## Hardware Detection

| Hardware | Whisper Model | Torch Build |
|----------|--------------|-------------|
| NVIDIA GPU (6+ GB VRAM) | `large-v3-turbo` | CUDA matched to driver |
| NVIDIA GPU (4-6 GB VRAM) | `medium` | CUDA matched to driver |
| NVIDIA GPU (<4 GB VRAM) | `base` | CUDA matched to driver |
| CPU only, 16+ GB RAM | `base` | CPU |
| CPU only, <16 GB RAM | `tiny` | CPU |

The PyTorch CUDA build is matched to your actual NVIDIA driver (`nvidia-smi`). If CUDA turns out to be unusable (old driver, sandboxed VM), the installer automatically falls back to the CPU build. Nothing is hardcoded; everything is re-verified after install.

---

## Usage

### Manager

```
.\Manager.bat
```

```
[S] Start all    [A] Stop all    [R] Restart all
[F] FastKoko     [I] LiteLLM     [W] Whisper
[Q] Quit (stops services)
```

Status is read live from the listening ports; MISSING means "run Setup.bat".

### Individual Launchers

```
.\FastKoko.bat       # TTS: http://127.0.0.1:8880/v1/  (+ interactive voice test)
.\LiteLLM.bat        # AI:  http://127.0.0.1:4000/v1/  (model + key picker, saved)
.\WhisperServer.bat  # STT: http://127.0.0.1:9000/v1/
```

Launchers read `config.psd1` (written by setup) for the Whisper model, ffmpeg location, eSpeak library, GPU flags and saved LiteLLM model. Deleting `config.psd1` and re-running `setup.ps1` regenerates it.

---

## Requirements

- Windows 10 or 11
- Internet connection
- Admin rights help (Git install via winget triggers a UAC prompt) but most components install per-user.

Installed automatically when missing: **Git**, **uv** (with a managed Python 3.10-3.13), **ffmpeg** (required by Whisper), **Visual C++ Runtime** (required by torch), plus all Python dependencies in isolated venvs. eSpeak NG comes bundled via the `espeakng-loader` pip package - no system install needed.

Notes for clean/VM environments (Windows Sandbox included):
- No winget? Everything falls back to direct downloads from official URLs.
- Paravirtualized GPU without `nvidia-smi`? Treated as CPU-only (no useless 3 GB CUDA download).
- Kokoro is installed with `misaki[en]` (English/Italian voices). The full `misaki[en,ja,ko,zh]` requires compiling C++ extensions (Visual Studio Build Tools); re-enable it in `Kokoro-FastAPI/pyproject.toml` if you ever need JA/KO/ZH.

---

## Troubleshooting

Everything logs to the `logs\` folder - check there first (`setup.log`, `fastkoko-server.err.log`, `whisper-server.err.log`, ...).

| Problem | Solution |
|---------|----------|
| Service not starting | Check `logs\*.err.log`, make sure the port is free, restart via Manager |
| "not installed" in Manager | Run `Setup.bat` |
| Model download failed | Installer retries 3x. Re-run `setup.ps1` (it resumes/skips what exists) |
| CUDA not available | Update NVIDIA drivers. Installer falls back to CPU automatically |
| Transcription fails with "ffmpeg not found" | Re-run `setup.ps1` - ffmpeg was missing |
| winget not found | Everything falls back to direct downloads from official URLs |
| Broken/partial install | Re-run `setup.ps1` - it verifies and repairs every step |
| LiteLLM asks for a key every time | Keys are stored in your user environment after the first run |

---

## Project Structure

```
Setup.bat                 Double-click installer entry point
setup.ps1                 Installer (-Yes / -Services / -SelfTest / -Path / -SkipOllama)
Manager.bat / .ps1        Master control panel
FastKoko.bat / .ps1       TTS launcher (-ServerOnly for unattended start)
LiteLLM.bat / .ps1        AI Gateway launcher (saves model + API key)
WhisperServer.bat         STT launcher
WhisperLauncher.ps1
WhisperServer/server.py   OpenAI-compatible Whisper API (transcriptions/translations)
config.psd1               Generated machine config (gitignored)
logs/                     Setup + server logs (gitignored)
```

---

## Links

- [Verity JE on CurseForge](https://www.curseforge.com/minecraft/mc-mods/verity-je) - 1.8M+ downloads
- [Verity JE on Modrinth](https://modrinth.com/mod/verity-je-official)
- [Verity Mod Wiki](https://veritymod.blog/)
- [ThatMob on YouTube](https://www.youtube.com/@ThatMob) - original creator
- [VarmiteYT on YouTube](https://www.youtube.com/@varmite) - mod author
- [Discord Server](https://discord.gg/f6DpBDVjMq)
