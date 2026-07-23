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
.\setup.ps1 -Yes                          # all services, all defaults, zero prompts
.\setup.ps1 -Yes -Services K,W            # only FastKoko + Whisper
.\setup.ps1 -Yes -WithOllama -OllamaModel llama3.2:3b   # + local LLM
.\setup.ps1 -SelfTest                     # hardware/software detection only, changes nothing
```

---

## Services

| Service | Purpose | Port | Model |
|---------|---------|------|-------|
| FastKoko | Text-to-Speech | `8880` | Kokoro-82M (pinned Kokoro-FastAPI v0.6.0) |
| LiteLLM | AI Gateway (100+ LLMs) | `4000` | Groq / OpenAI / Anthropic / Gemini / Ollama (pinned 1.91.0)* |

\* litellm >= 1.92 bundles a Rust component that requires a Rust toolchain to build on Windows (no Windows wheels are published). 1.91.0 is the newest pure-Python release and is installed in its own `LiteLLM/.venv`.
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

Live dashboard (auto-refresh, single-key commands, no Enter needed):

```
┌────────────────────────────────────────────────────────┐
│  Verity JE - Manager                                   │
│  AI backend control panel                              │
└────────────────────────────────────────────────────────┘
├── Services ────────────────────────────────────────────┤
   [F] FastKoko (TTS)  RUNNING   :8880  http://127.0.0.1:8880/v1/
   [I] LiteLLM (AI)    off       :4000  http://127.0.0.1:4000/v1/
   [W] Whisper (STT)   STARTING  :9000  http://127.0.0.1:9000/v1/
├────────────────────────────────────────────────────────┤
  [S] Start all  [A] Stop all  [R] Restart all  [F/I/W] Toggle  [C] Configure  [Q] Quit
```

- **F / I / W** toggle a single service (start if off, stop if running)
- Failed starts show the last log lines right in the dashboard
- **[C]** opens LiteLLM configuration (model + API key) in a new window
- Stopping a service kills its whole process tree - no orphaned servers

### Individual Launchers

```
.\FastKoko.bat       # TTS server + voice picker (saved) + generation test
.\LiteLLM.bat        # model picker (Ollama models first) + API key setup, all saved
.\WhisperServer.bat  # STT server
```

Choices are persisted in `config.psd1`: Kokoro voice, LiteLLM model, API keys (user environment), so the Manager can start everything unattended afterwards.

### Ollama (local LLMs, offline)

Setup asks about Ollama **at the very end** of the install - everything else is already downloaded and configured by then (the core install never stops waiting for input). It offers install via winget or direct download, daemon auto-start, and RAM-aware model suggestions. A freshly pulled model automatically becomes LiteLLM's default, so `Manager -> [S]` works out of the box with zero API keys. Manage models anytime from `LiteLLM.bat` (`[P]` pulls a new one). Use any model id as `ollama/<name>` (e.g. `ollama/llama3.2`, `ollama/gemma3n:e4b`).

### Default TTS voice

Right after Ollama, setup asks for your **default Kokoro voice** (read from the installed voice files, grouped IT/EN/other, saved to `config.psd1`). The Verity mod still sends its own voice per API request; this default is what `FastKoko.bat` uses for its tests. Change it anytime from `FastKoko.bat`.

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
| Service not starting | Manager shows the last log lines inline; full logs in `logs\` |
| LiteLLM won't start from Manager | Not configured yet: press `[C]` (or run `LiteLLM.bat`) once to save model + key |
| "MISSING" in Manager | Run `Setup.bat` |
| Ollama model answers nothing | Daemon not running: it is auto-started by `LiteLLM.bat`, or run `ollama serve` |
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
setup.ps1                 Installer (-Yes / -Services / -WithOllama / -OllamaModel / -SelfTest / -Path)
VerityUI.ps1              Shared terminal UI (banner, keys, config, status)
Manager.bat / .ps1        Live control panel
FastKoko.bat / .ps1       TTS launcher (-ServerOnly for unattended start)
LiteLLM.bat / .ps1        AI Gateway launcher (Ollama-aware, saves model + key)
WhisperServer.bat         STT launcher
WhisperLauncher.ps1
WhisperServer/server.py   OpenAI-compatible Whisper API (transcriptions/translations)
config.psd1               Generated machine config (gitignored)
logs/                     Setup + server + launcher logs (gitignored)
LiteLLM/                  LiteLLM dedicated venv (gitignored)
```

---

## Links

- [Verity JE on CurseForge](https://www.curseforge.com/minecraft/mc-mods/verity-je) - 1.8M+ downloads
- [Verity JE on Modrinth](https://modrinth.com/mod/verity-je-official)
- [Verity Mod Wiki](https://veritymod.blog/)
- [ThatMob on YouTube](https://www.youtube.com/@ThatMob) - original creator
- [VarmiteYT on YouTube](https://www.youtube.com/@varmite) - mod author
- [Discord Server](https://discord.gg/f6DpBDVjMq)
