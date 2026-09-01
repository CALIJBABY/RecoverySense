from fastapi import FastAPI

from app.routes import ema, sensors

app = FastAPI(
    title="RecoverySense API",
    version="0.5.3",
    description="Research-prototype sensor ingestion, ML risk scoring, and EMA workflow. Not a clinical decision system.",
)

app.include_router(sensors.router, prefix="/sensors", tags=["sensors"])
app.include_router(ema.router, prefix="/ema", tags=["ema"])


@app.get("/")
def root() -> dict[str, str]:
    return {"status": "ok", "project": "RecoverySense", "version": "0.5.3"}
