import whisper
import uvicorn
import tempfile
import os
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse

app = FastAPI(title="Whisper Server")
MODEL = None
MODEL_NAME = os.environ.get("WHISPER_MODEL", "large-v3-turbo")

@app.on_event("startup")
def startup():
    global MODEL
    device = "cuda" if __import__("torch").cuda.is_available() else "cpu"
    print(f"Loading {MODEL_NAME} on {device}...")
    MODEL = whisper.load_model(MODEL_NAME, device=device)
    print("Ready!")

@app.post("/v1/audio/speech")
async def transcribe(
    file: UploadFile = File(...),
    language: str = None,
    task: str = "transcribe",
    temperature: float = 0.0
):
    if MODEL is None:
        return JSONResponse(status_code=503, content={"error": "Model not loaded"})
    suffix = os.path.splitext(file.filename)[1] or ".mp3"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    try:
        result = MODEL.transcribe(tmp_path, language=language, task=task, temperature=temperature)
        return JSONResponse(content={
            "text": result.get("text", ""),
            "language": result.get("language", language or "auto"),
            "segments": result.get("segments", [])
        })
    finally:
        os.unlink(tmp_path)

@app.post("/v1/audio/translations")
async def translate(file: UploadFile = File(...), temperature: float = 0.0):
    if MODEL is None:
        return JSONResponse(status_code=503, content={"error": "Model not loaded"})
    suffix = os.path.splitext(file.filename)[1] or ".mp3"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    try:
        result = MODEL.transcribe(tmp_path, task="translate", temperature=temperature)
        return JSONResponse(content={"text": result.get("text", ""), "language": "en"})
    finally:
        os.unlink(tmp_path)

@app.get("/v1/models")
def get_model():
    return {"object": "list", "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "openai"}]}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=9000)
