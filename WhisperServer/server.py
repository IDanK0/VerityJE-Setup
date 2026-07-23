"""WhisperServer - OpenAI-compatible speech-to-text API for Verity JE.

Endpoints:
    GET  /health                      service status
    GET  /v1/models                   model list (OpenAI shape)
    POST /v1/audio/transcriptions     standard OpenAI STT endpoint
    POST /v1/audio/translations       standard OpenAI translation endpoint
    POST /v1/audio/speech             legacy alias -> transcriptions

Config via environment:
    WHISPER_MODEL   model name (default: base)
    WHISPER_DEVICE  auto | cuda | cpu (default: auto)
    WHISPER_PORT    listen port (default: 9000)
"""

import logging
import os
import shutil
import tempfile
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("whisper-server")

MODEL_NAME = os.environ.get("WHISPER_MODEL", "base")
DEVICE_PREF = os.environ.get("WHISPER_DEVICE", "auto").lower()
PORT = int(os.environ.get("WHISPER_PORT", "9000"))

_model = None
_device = "cpu"


def _pick_device() -> str:
    if DEVICE_PREF == "cpu":
        return "cpu"
    try:
        import torch
        if torch.cuda.is_available():
            return "cuda"
        if DEVICE_PREF == "cuda":
            log.warning("WHISPER_DEVICE=cuda but CUDA is not available - using CPU")
    except Exception as exc:  # torch missing/broken
        log.warning("torch check failed (%s) - using CPU", exc)
    return "cpu"


def _load_model():
    global _model, _device
    import whisper

    _device = _pick_device()
    log.info("Loading Whisper model '%s' on %s ...", MODEL_NAME, _device)
    _model = whisper.load_model(MODEL_NAME, device=_device)
    log.info("Model ready (ffmpeg: %s)", "yes" if _has_ffmpeg() else "MISSING!")


@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_model()
    yield


app = FastAPI(title="WhisperServer", version="2.0.0", lifespan=lifespan)


def _has_ffmpeg() -> bool:
    return shutil.which("ffmpeg") is not None


def _err(status: int, msg: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"message": msg, "type": "server_error"}})


def _sanitize_segments(segments):
    """Convert whisper segments to plain JSON-safe dicts (numpy types break json)."""
    out = []
    for s in segments or []:
        out.append({
            "id": int(s.get("id", 0)),
            "start": float(s.get("start", 0.0)),
            "end": float(s.get("end", 0.0)),
            "text": str(s.get("text", "")),
        })
    return out


async def _save_upload(file: UploadFile) -> str:
    suffix = os.path.splitext(file.filename or "")[1] or ".wav"
    fd, path = tempfile.mkstemp(suffix=suffix)
    with os.fdopen(fd, "wb") as tmp:
        tmp.write(await file.read())
    return path


async def _transcribe_impl(file, language, prompt, response_format, temperature, task):
    if _model is None:
        return _err(503, "Model is still loading, retry in a few seconds")
    if not _has_ffmpeg():
        return _err(500, "ffmpeg not found on PATH. Re-run setup.ps1 to install it.")

    tmp_path = await _save_upload(file)
    try:
        result = _model.transcribe(
            tmp_path,
            language=language or None,
            prompt=prompt or None,
            task=task,
            temperature=temperature,
        )
    except Exception as exc:
        log.exception("transcription failed")
        return _err(500, f"Transcription failed: {exc}")
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    text = str(result.get("text", ""))
    fmt = (response_format or "json").lower()
    if fmt == "text":
        return PlainTextResponse(text)
    if fmt == "verbose_json":
        return {
            "task": task,
            "language": str(result.get("language", language or "auto")),
            "text": text,
            "segments": _sanitize_segments(result.get("segments")),
        }
    if fmt in ("srt", "vtt"):
        return _err(400, f"response_format '{fmt}' is not supported (use json, text or verbose_json)")
    return {"text": text}


@app.get("/")
def root():
    return {"service": "WhisperServer", "docs": "/docs", "api": "/v1"}


@app.get("/health")
def health():
    return {
        "status": "ok" if _model is not None else "loading",
        "model": MODEL_NAME,
        "device": _device,
        "ffmpeg": _has_ffmpeg(),
    }


@app.get("/v1/models")
def list_models():
    return {"object": "list", "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "local"}]}


@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model: str = Form(None),
    language: str = Form(None),
    prompt: str = Form(None),
    response_format: str = Form("json"),
    temperature: float = Form(0.0),
):
    return await _transcribe_impl(file, language, prompt, response_format, temperature, "transcribe")


@app.post("/v1/audio/translations")
async def translate(
    file: UploadFile = File(...),
    model: str = Form(None),
    prompt: str = Form(None),
    response_format: str = Form("json"),
    temperature: float = Form(0.0),
):
    return await _transcribe_impl(file, None, prompt, response_format, temperature, "translate")


# Legacy alias kept for older Verity configs that pointed STT at /v1/audio/speech.
@app.post("/v1/audio/speech")
async def transcribe_legacy(
    file: UploadFile = File(...),
    model: str = Form(None),
    language: str = Form(None),
    prompt: str = Form(None),
    response_format: str = Form("json"),
    temperature: float = Form(0.0),
):
    return await _transcribe_impl(file, language, prompt, response_format, temperature, "transcribe")


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=PORT, log_level="info")
