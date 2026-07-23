# Verity JE Setup (unofficial)

[![CurseForge](https://img.shields.io/badge/CurseForge-Verity_JE-f16436?logo=curseforge)](https://www.curseforge.com/minecraft/mc-mods/verity-je)
[![Modrinth](https://img.shields.io/badge/Modrinth-Verity_JE-1bd96a?logo=modrinth)](https://modrinth.com/mod/verity-je-official)
[![Discord](https://img.shields.io/badge/Discord-join-5865f2?logo=discord)](https://discord.gg/f6DpBDVjMq)

One-click installer and control panel for the AI backend used by the **Verity JE** Minecraft mod: local Text-to-Speech, Speech-to-Text and an LLM gateway, all on your PC.

> **Disclaimer: this project is unofficial.** It has **no affiliation** with the Verity JE mod, with [VarmiteYT](https://www.youtube.com/@varmite) (mod author) or with [ThatMob](https://www.youtube.com/@ThatMob) (original Verity creator). I simply noticed that installing and configuring the whole AI backend (Python, CUDA, ffmpeg, models, servers) was a bit complex for the average user, so I built this tool to do it for you. The mod itself is downloaded separately from CurseForge or Modrinth.

---

## Table of contents

1. [Requirements](#requirements)
2. [Quick start (step by step)](#quick-start-step-by-step)
3. [What gets installed and where](#what-gets-installed-and-where)
4. [Services and ports](#services-and-ports)
5. [The Manager](#the-manager)
6. [Configuration guide](#configuration-guide)
7. [setup.ps1 reference](#setupps1-reference)
8. [Updating and uninstalling](#updating-and-uninstalling)
9. [Windows Sandbox](#windows-sandbox)
10. [Troubleshooting](#troubleshooting)
11. [Security and privacy](#security-and-privacy)
12. [How it works](#how-it-works)
13. [FAQ](#faq)
14. [Project structure](#project-structure)
15. [Credits](#credits)

---

## Requirements

- Windows 10 or 11 (64 bit)
- An internet connection for the initial download (about 2 to 8 GB depending on hardware)
- Admin rights help for some system components (a UAC prompt may appear for Git and VC++ Runtime)
- Optional but recommended: winget (present on most Windows 11 machines). If winget is missing, every component falls back to direct downloads from official sources

You do **not** need to install anything else manually: Git, uv, Python, ffmpeg and the Visual C++ Runtime are handled by the installer.

---

## Quick start (step by step)

**1. Get this project**

- Either download the ZIP: [github.com/IDanK0/VerityJE-Setup](https://github.com/IDanK0/VerityJE-Setup) -> Code -> Download ZIP, then extract it
- Or clone it: `git clone https://github.com/IDanK0/VerityJE-Setup.git`

**2. Run the installer**

Double-click **`Setup.bat`** (or run `powershell -ExecutionPolicy Bypass -File setup.ps1`).

The installer walks you through:

| Step | What happens |
|------|--------------|
| System detection | Shows your GPU, RAM, missing tools. `[R]` rescans |
| Service selection | `[Space]` toggles FastKoko, LiteLLM, Whisper |
| System dependencies | Installs VC++ Runtime, Git, uv, ffmpeg as needed (winget first, direct download otherwise) |
| FastKoko | Clones Kokoro-FastAPI (pinned v0.6.0), builds the venv, installs PyTorch matched to your GPU, downloads the model, runs a real boot test |
| LiteLLM | Builds its own venv with litellm 1.91.0 |
| Whisper | Builds the venv, downloads the right model for your hardware |
| Ollama (optional) | `[Y]` installs Ollama and offers RAM-appropriate local models |
| Voice | Pick your default Kokoro voice |
| Done | Everything is written to `config.psd1` |

**3. Configure LiteLLM (once)**

Run **`LiteLLM.bat`**: pick a model (Ollama models are listed first if installed), paste the API key if the provider needs one. Both choices are saved permanently.

**4. Start everything**

Double-click **`Manager.bat`** and press **`S`**.

**5. Point the mod at the services**

In the Verity JE mod configuration, use these endpoints (they are fixed because the mod expects exactly these):

- STT: `http://127.0.0.1:9000/v1` (OpenAI compatible, `/audio/transcriptions`)
- TTS: `http://127.0.0.1:8880/v1` (OpenAI compatible, `/audio/speech`)
- LLM: `http://127.0.0.1:4000/v1` (OpenAI compatible, `/chat/completions`)

Set your microphone as the **Windows default recording device** (the mod captures audio through Java, see [Microphone](#microphone)).

---

## What gets installed and where

| Component | Location | Approx. size |
|-----------|----------|--------------|
| Kokoro-FastAPI + model | `Kokoro-FastAPI\` inside this folder | about 1.5 GB |
| LiteLLM venv | `LiteLLM\` | about 500 MB |
| Whisper venv | `WhisperServer\.venv\` | about 1 GB (CPU) to 3 GB (CUDA) |
| Whisper model | `~\.cache\whisper` | 75 MB to 3 GB depending on model |
| ffmpeg (if missing) | winget package or `tools\ffmpeg\` | about 100 MB |
| Git, uv, VC++ Runtime | system-wide (winget or official installers) | small |
| Ollama (optional) | `~\AppData\Local\Programs\Ollama` | 1.4 GB + models |

Everything inside this folder is self-contained. Nothing writes outside of it except the Whisper cache, API keys (user environment variables) and the system tools above.

---

## Services and ports

| Service | Purpose | Port | Technology |
|---------|---------|------|------------|
| FastKoko | Text-to-Speech | **8880** | Kokoro-82M via Kokoro-FastAPI v0.6.0 (pinned) |
| LiteLLM | LLM gateway | **4000** | litellm 1.91.0 proxy (Groq, OpenAI, Anthropic, Gemini, Ollama, 100+ providers) |
| WhisperServer | Speech-to-Text | **9000** | openai-whisper, model auto-selected by hardware |
| Ollama | Local LLM runtime | 11434 | optional, for offline LLMs |

The ports are **fixed on purpose**: the Verity JE mod expects exactly these endpoints. All services bind to `127.0.0.1` only (your PC, never the network).

Hardware detection picks:

| Hardware | Whisper model | PyTorch build |
|----------|---------------|---------------|
| NVIDIA GPU 6+ GB VRAM | large-v3-turbo | CUDA matched to your driver (including Blackwell/RTX 50) |
| NVIDIA GPU 4 to 6 GB | medium | CUDA matched to driver |
| NVIDIA GPU under 4 GB | base | CUDA matched to driver |
| CPU only, 16+ GB RAM | base | CPU |
| CPU only, less RAM | tiny | CPU |

If CUDA turns out to be unusable (VM, old driver, missing nvidia-smi), the installer automatically falls back to the CPU build.

---

## The Manager

`Manager.bat` opens a live dashboard. No Enter needed, single keys, no flicker (it redraws only when something changes).

```
┌────────────────────────────────────────────────────────┐
│  Verity JE - Manager                                   │
│  v2.0.0 - AI backend control panel                     │
└────────────────────────────────────────────────────────┘
├── Services ────────────────────────────────────────────┤
   [F] FastKoko (TTS)  RUNNING   :8880  http://...  im_nicola
   [I] LiteLLM (AI)    off       :4000  http://...  ollama/gemma4:e4b
   [W] Whisper (STT)   off       :9000  http://...  large-v3-turbo
├────────────────────────────────────────────────────────┤
  [S] Start all  [A] Stop all  [R] Restart  [F/I/W] Toggle  [C] Configure  [U] Update  [Q] Quit
```

| Key | Action |
|-----|--------|
| `S` | Start all services |
| `A` | Stop all services |
| `R` | Restart all |
| `F` / `I` / `W` | Toggle one service (start if off, stop if running) |
| `C` | Configuration center (see below) |
| `U` | Check for updates and apply them |
| `Q` | Quit (asks whether to stop services) |

States: `RUNNING` (green), `STARTING` (yellow), `FAILED` (red, with the last log lines shown inline), `off` (installed, not running), `MISSING` (not installed, run Setup.bat).

### Configuration center (`C`)

| Key | What it configures |
|-----|--------------------|
| `F` | FastKoko default voice (full list, grouped IT/EN/other) |
| `I` | LiteLLM model and API key (opens the interactive picker) |
| `W` | Whisper model (size, VRAM hints, cached or "will download") and device (auto/cpu/cuda) |
| `M` | Microphone for the mic test, plus `[T]` test and `[S]` Windows sound settings |
| `G` | FastKoko GPU on/off |

Everything is saved to `config.psd1` and applied on the next service start.

---

## Configuration guide

### FastKoko voice

Three ways, all equivalent (saved permanently):

1. During setup, at the voice picker
2. Manager -> `[C]` -> `[F]`
3. `FastKoko.bat` after the server starts (includes a generation test saved to your Desktop)

Note: the mod sends its own voice parameter with every API request. The configured voice is the local default used by the test tools.

### Whisper model and device

Manager -> `[C]` -> `[W]`:

- Models from `tiny` (fast, least accurate) to `large-v3` (slow, most accurate). The screen shows download size, VRAM needs and whether the model is already cached
- Device: `[A]` auto (GPU if available), `[C]` cpu, `[G]` cuda. Use cpu if you ever see CUDA errors
- Changes apply on the next Whisper start (toggle `[W]` to apply immediately)

### Microphone

The Whisper **server** never touches your microphone. The mod records audio itself through the Java Sound API, which means it always uses the **Windows default recording device**. There is no mic selector inside the mod.

- Set the default mic: Settings -> System -> Sound -> Input, or classic `control mmsys.cpl,,1`
- Per-app routing (Windows 11): Settings -> System -> Sound -> Volume mixer -> javaw/Minecraft -> Input device
- If the mod cannot hear you: Settings -> Privacy and security -> Microphone -> allow desktop apps

To verify the full chain (mic -> wav -> transcription): Manager -> `[C]` -> `[M]`, pick a device, press `[T]`, speak for 5 seconds, read what Whisper heard. The chosen device is saved for future tests.

### LiteLLM (models and API keys)

Run `LiteLLM.bat` (or Manager -> `[C]` -> `[I]`):

- Installed Ollama models appear first in the list, then cloud models
- `[P]` pulls a new Ollama model, `[C]` accepts any custom model id (for example `openrouter/auto`)
- The model is saved and used automatically next time (including Manager starts)

API keys are requested once and stored in your user environment:

| Provider | Variable |
|----------|----------|
| OpenAI | `OPENAI_API_KEY` |
| Anthropic | `ANTHROPIC_API_KEY` |
| Google | `GEMINI_API_KEY` |
| Groq | `GROQ_API_KEY` |

Ollama models need no key. If Ollama is installed but stopped, the launcher starts the daemon for you.

### Ollama (offline LLMs)

Offered at the end of setup (explicit `[Y]`/`[N]`), or install it later from [ollama.com](https://ollama.com). Model suggestions are RAM-aware (1B models under 8 GB, 3B to 4B at 10+ GB, 7B and Gemma 3n at 14 to 18+ GB). A freshly pulled model becomes LiteLLM's default automatically, so the whole stack works with zero API keys.

### GPU on/off (FastKoko)

Manager -> `[C]` -> `[G]` toggles GPU acceleration for Kokoro. Use CPU if you see CUDA errors or want to free VRAM for the game.

### config.psd1 reference

| Key | Meaning |
|-----|---------|
| `WhisperModel` | tiny / base / small / medium / large-v3 / large-v3-turbo |
| `WhisperDevice` | auto / cpu / cuda |
| `KokoroVoice` | default TTS voice id |
| `KokoroUseGpu` | `$true` / `$false` |
| `LiteLLMModel` | saved LiteLLM model id |
| `OllamaModel` | last pulled Ollama model |
| `MicDevice` | DirectShow device used by the mic test |
| `FfmpegBin` | ffmpeg folder (added to PATH for Whisper) |
| `EspeakLibrary`, `EspeakDataPath` | bundled eSpeak for TTS phonemes |
| `CudaIndex`, `PythonVersion`, `UvBin`, `LiteLLMExe`, `InstallPath` | detection results |

Delete `config.psd1` and re-run `setup.ps1` to regenerate everything.

---

## setup.ps1 reference

```
.\setup.ps1                          interactive install
.\setup.ps1 -Yes                     unattended, all services, defaults
.\setup.ps1 -Yes -Services K,W       only FastKoko + Whisper
.\setup.ps1 -Yes -WithOllama -OllamaModel llama3.2:3b
.\setup.ps1 -Yes -KokoroVoice if_sara
.\setup.ps1 -SelfTest                detection only, changes nothing
.\setup.ps1 -Path D:\Verity          install into a custom folder
.\setup.ps1 -SkipOllama              never ask about Ollama
```

Re-running is always safe: existing work is skipped or repaired (broken clones, partial venvs, truncated downloads are detected and fixed).

---

## Updating and uninstalling

**Update**: Manager -> `[U]` checks `VERSION` against GitHub. If newer, it applies via `git pull` (clones) or downloads the latest scripts (ZIP installs). Your `config.psd1` and installed components are never touched. Restart the Manager afterwards.

**Uninstall**: run **`Uninstall.bat`**. It stops services, deletes the venvs, models, tools, logs and config, and optionally the Whisper cache. Git, uv, ffmpeg, VC++ and Ollama stay (remove them with `winget uninstall` if you want, the commands are printed at the end).

---

## Windows Sandbox

Perfect for a clean test:

1. Open Windows Sandbox
2. Copy this folder into it (or download the ZIP there)
3. Run `Setup.bat` and go through the prompts, or for a fully unattended run open PowerShell and:

```powershell
cd "$env:USERPROFILE\Desktop\VerityJE-Setup-master"
.\setup.ps1 -Yes
```

Sandbox specifics that are handled automatically: no winget (direct downloads used), no VC++ Runtime (installed), paravirtualized GPU without CUDA (CPU mode, no wasted 3 GB download), 4 GB RAM (Whisper tiny model, 1B Ollama suggestions).

---

## Troubleshooting

Everything logs to `logs\` (setup.log, per-service server logs, launcher transcripts). Check there first.

| Problem | Solution |
|---------|----------|
| "stuck" until you press Enter | Fixed in v2: QuickEdit is now disabled. Update with `[U]` if you see this |
| Service shows FAILED | The last log lines appear right in the dashboard. Port busy? Close the other app, then toggle the service |
| LiteLLM MISSING or refuses to start | Not configured yet: Manager -> `[C]` -> `[I]`, pick model + key once |
| Ollama model selected but no answer | Daemon down: start `LiteLLM.bat` once (it auto-starts Ollama), or run `ollama serve` |
| "ffmpeg not found" during transcription | Re-run `setup.ps1`, ffmpeg was missing or removed |
| CUDA errors / no kernel image | Manager -> `[C]` -> `[W]` -> device cpu, and `[G]` for FastKoko CPU. Update GPU drivers for CUDA |
| WinError 206 (path too long) | Fixed by installing via uv. Move the folder closer to the drive root if you renamed it very deep |
| winget missing or failing | Automatic fallback to official direct downloads, nothing to do |
| Model download interrupted | Re-run `setup.ps1`, it resumes and repairs |
| Mod cannot hear the mic | See [Microphone](#microphone): Windows default device + privacy settings |
| Python/Store stub opens Microsoft Store | Ignore it, the installer uses uv-managed Python |

---

## Security and privacy

- All services listen on `127.0.0.1` only, nothing is exposed to your network
- API keys live in your user environment variables, never in files, never sent anywhere except to their provider
- No telemetry, no accounts, no background services: everything runs only when you start it from the Manager
- Speech-to-Text and Text-to-Speech are fully local; only the LLM call leaves your PC (unless you use Ollama, then everything is offline)

---

## How it works

```
You talk (mic, Windows default device)
   -> Verity JE mod records and POSTs audio
   -> WhisperServer :9000 (STT, local Whisper model)
   -> text -> LiteLLM :4000 (gateway: Groq / OpenAI / Claude / Gemini / Ollama)
   -> answer text -> FastKoko :8880 (TTS, Kokoro-82M)
   -> audio played in game
```

All three services expose OpenAI-compatible APIs, so you can also reuse them from your own scripts (see the curl examples in each launcher).

---

## FAQ

**Is this the official Verity JE installer?**
No. It is an unofficial community tool (see the disclaimer on top). The mod itself comes from CurseForge or Modrinth.

**Does it work offline?**
After install: TTS, STT and Ollama LLMs yes, cloud LLMs obviously need internet.

**Can I use it without a GPU?**
Yes, everything falls back to CPU automatically (slower but fully working).

**Can I move the folder?**
Yes, but re-run `setup.ps1` afterwards so paths in `config.psd1` are refreshed.

**Where are the logs?**
`logs\` inside this folder: setup.log, fastkoko-server.err.log, whisper-server.err.log, litellm-server.err.log, launcher transcripts.

---

## Project structure

```
Setup.bat                 double-click installer
setup.ps1                 installer (flags above)
VerityUI.ps1              shared terminal UI library
Manager.bat / .ps1        live control panel
FastKoko.bat / .ps1       TTS launcher + voice test
LiteLLM.bat / .ps1        LLM gateway launcher + model/key picker
WhisperServer.bat         STT launcher
WhisperLauncher.ps1
WhisperServer/server.py   OpenAI-compatible Whisper API
Uninstall.bat / .ps1      clean removal
VERSION                   current version (used by Manager [U])
config.psd1               generated machine config (gitignored)
logs\                     all logs (gitignored)
```

---

## Credits

- [Verity JE](https://www.curseforge.com/minecraft/mc-mods/verity-je) by [VarmiteYT](https://www.youtube.com/@varmite), official adaptation of [ThatMob](https://www.youtube.com/@ThatMob)'s Verity (this project is not affiliated with them)
- [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) by remsky (TTS server, pinned v0.6.0)
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (TTS model)
- [OpenAI Whisper](https://github.com/openai/whisper) (STT)
- [LiteLLM](https://github.com/BerriAI/litellm) (LLM gateway)
- [Ollama](https://ollama.com) (local LLMs), [uv](https://github.com/astral-sh/uv) (Python tooling), [ffmpeg](https://ffmpeg.org) (audio)

Made with love for the average user who just wants to talk to Verity.
