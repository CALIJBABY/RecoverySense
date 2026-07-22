from fastapi import FastAPI

from app.routes import ema, sensors

app = FastAPI(
    title="RecoverySense API",
    version="0.2.0",
    description="Sensor ingestion, ML risk scoring, and EMA triggering for the RecoverySense prototype.",
)

app.include_router(sensors.router, prefix="/sensors", tags=["sensors"])
app.include_router(ema.router, prefix="/ema", tags=["ema"])


@app.get("/")
def root() -> dict[str, str]:
    return {"status": "ok", "project": "RecoverySense", "version": "0.2.0"}
