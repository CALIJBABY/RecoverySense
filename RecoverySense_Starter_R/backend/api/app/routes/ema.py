from fastapi import APIRouter
from app.models.schemas import EmaAnswerIn

router = APIRouter()

# Temporary in-memory store for early testing only.
EMA_ANSWERS: list[EmaAnswerIn] = []


@router.post("/answer")
def create_ema_answer(answer: EmaAnswerIn) -> dict[str, str]:
    EMA_ANSWERS.append(answer)
    return {"status": "saved"}


@router.get("/answers", response_model=list[EmaAnswerIn])
def list_ema_answers() -> list[EmaAnswerIn]:
    return EMA_ANSWERS
