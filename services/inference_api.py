"""Authenticated worker API for processing Supabase-backed ArtSpeak sessions."""

import os
import tempfile
import math
import traceback
from pathlib import Path

from fastapi import Body, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from supabase import Client, create_client

from services.inference_engine.process_session import process_session

app = FastAPI(title="ArtSpeak Inference API")
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_admin_client() -> Client:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    return create_client(url, key)


def authenticated_user_id(client: Client, authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Bearer token required")
    try:
        user = client.auth.get_user(authorization.removeprefix("Bearer ").strip())
        return user.user.id
    except Exception as error:
        raise HTTPException(status_code=401, detail="Invalid access token") from error


def rows(data):
    return data.data if data and data.data else []


@app.get("/health")
@app.get("/")
def health_check():
    return {
        "status": "healthy",
        "service": "ArtSpeak Multimodal Inference API",
        "llm_configured": bool(os.getenv("LLM_API_KEY") or os.getenv("GEMINI_API_KEY") or os.getenv("OPENAI_API_KEY")),
        "supabase_configured": bool(os.getenv("SUPABASE_URL")),
    }


@app.get("/therapists")
def list_therapists():
    client = get_admin_client()
    result = client.table("therapists").select("id, name, qualification, license_number, verified").order("name").execute()
    return result.data or []


@app.post("/assign-therapist")
def assign_therapist(payload: dict = Body(default={}), authorization: str | None = Header(default=None)):
    client = get_admin_client()
    user_id = authenticated_user_id(client, authorization)
    child_id = payload.get("child_id")
    therapist_id = payload.get("therapist_id")
    if not child_id or not therapist_id:
        raise HTTPException(status_code=400, detail="child_id and therapist_id are required")

    # Verify child belongs to caregiver
    child_res = client.table("children").select("id, caregiver_id").eq("id", child_id).single().execute()
    if not child_res.data or child_res.data["caregiver_id"] != user_id:
        raise HTTPException(status_code=403, detail="Not authorized to assign therapist for this child")

    # Deactivate existing active assignments for this child
    client.table("child_therapist_assignments").update({"active": False}).eq("child_id", child_id).execute()

    # Create new active assignment
    res = client.table("child_therapist_assignments").insert({
        "child_id": child_id,
        "therapist_id": therapist_id,
        "assigned_by": user_id,
        "active": True,
    }).execute()

    # Also try to update assigned_therapist_id column on children table if it exists
    try:
        client.table("children").update({"assigned_therapist_id": therapist_id}).eq("id", child_id).execute()
    except Exception:
        pass

    return {"status": "success", "assignment": res.data[0] if res.data else None}


@app.post("/process/{session_id}")
def process(session_id: str, payload: dict = Body(default={}), authorization: str | None = Header(default=None)):
    client = get_admin_client()
    user_id = authenticated_user_id(client, authorization)
    session_result = client.table("sessions").select("*").eq("id", session_id).single().execute()
    session = session_result.data
    if not session or session["caregiver_id"] != user_id:
        raise HTTPException(status_code=404, detail="Session not found")

    try:
        touch = rows(client.table("session_touch_events").select("*").eq("session_id", session_id).order("timestamp_ms").execute())
        video_rows = rows(client.table("session_video_recordings").select("storage_path").eq("session_id", session_id).execute())

        video_path = None
        with tempfile.TemporaryDirectory() as temp_dir:
            if video_rows:
                video_path = str(Path(temp_dir) / "session.mp4")
                video_bytes = client.storage.from_("session-videos").download(video_rows[0]["storage_path"])
                Path(video_path).write_bytes(video_bytes)

            stim_cat = payload.get("stimulus_category") or session.get("stimulus_category") or "animals"
            stim_img_id = payload.get("stimulus_image_id") or session.get("stimulus_image_id") or "P073"
            stimulus_info = {
                "category": stim_cat,
                "image_id": stim_img_id,
                "duration_seconds": session.get("stimulus_duration_seconds", 10),
            }

            drawing_ref = payload.get("drawing_reference") or "sun"

            report = process_session(
                session_id=session_id,
                video_path=video_path,
                touch_events=[{
                    "x": item["x"], "y": item["y"], "t": item["timestamp_ms"],
                    "pressure": item.get("pressure", 0.5),
                } for item in touch],
                e4_events=[],
                duration_minutes=max(1, math.ceil((session.get("video_duration_seconds", 10) + session.get("art_duration_seconds", 15)) / 60)),
                stimulus_info=stimulus_info,
                drawing_reference=drawing_ref,
            )

        affect = report.get("affect_vector", {})
        valence = float(max(-1.0, min(1.0, affect.get("valence", 0.0))))
        arousal = float(max(0.0, min(1.0, affect.get("arousal", 0.0))))
        dominance = float(max(0.0, min(1.0, affect.get("dominance", 0.0))))

        # 1. Model 1: RAF-DB Facial Emotion
        face_pred = report.get("facial_prediction") or {}
        valid_emotions = {'Surprise', 'Fear', 'Disgust', 'Happiness', 'Sadness', 'Anger', 'Neutral'}
        raw_dominant = face_pred.get("dominant_emotion")
        if raw_dominant not in valid_emotions:
            raw_dominant = "Neutral"

        emotion_probs = face_pred.get("emotion_probabilities") or {e: 0.14 for e in valid_emotions}
        confidence = float(face_pred.get("confidence", 0.85) if face_pred.get("confidence") is not None else 0.85)

        try:
            client.table("predictions_facial_emotion").insert({
                "session_id": session_id,
                "timestamp_sec": 0,
                "dominant_emotion": raw_dominant,
                "confidence": round(max(0.0, min(1.0, confidence)), 3),
                "valence": round(max(-1.0, min(1.0, valence)), 3),
                "arousal": round(max(0.0, min(1.0, arousal)), 3),
                "dominance": round(max(0.0, min(1.0, dominance)), 3),
                "emotion_probabilities": emotion_probs,
            }).execute()
        except Exception as err:
            print("Notice inserting predictions_facial_emotion:", err)

        # 2. Model 3: Touch Rhythm
        touch_prediction = report.get("touch_prediction", {})
        valid_states = {
            'Calm_Regulated', 'Engaged_Focused', 'Excited_Stimming',
            'Anxious_Overstimulated', 'Distressed_PreMeltdown', 'Withdrawn_FlatAffect'
        }
        overall_state = report.get("overall_state")
        if overall_state not in valid_states:
            overall_state = touch_prediction.get("behavioral_state")
        if overall_state not in valid_states:
            overall_state = "Calm_Regulated"

        stroke_speed = touch_prediction.get("stroke_speed_avg")
        if stroke_speed is not None:
            # numeric(6, 2) can hold up to 9999.99
            stroke_speed = round(max(0.0, min(9999.0, float(stroke_speed))), 2)

        pressure_avg = touch_prediction.get("pressure_avg")
        if pressure_avg is not None:
            # numeric(4, 3) can hold up to 9.999
            pressure_avg = round(max(0.0, min(1.0, float(pressure_avg))), 3)

        try:
            client.table("predictions_touch_rhythm").insert({
                "session_id": session_id,
                "window_start_sec": 0,
                "window_end_sec": session.get("video_duration_seconds", 10) + session.get("art_duration_seconds", 15),
                "behavioral_state": overall_state,
                "state_probabilities": report.get("regulation_breakdown", {}) or touch_prediction.get("state_probabilities", {}),
                "touch_valence": round(max(-1.0, min(1.0, valence)), 3),
                "touch_arousal": round(max(0.0, min(1.0, arousal)), 3),
                "touch_dominance": round(max(0.0, min(1.0, dominance)), 3),
                "stroke_speed_avg": stroke_speed,
                "pressure_avg": pressure_avg,
                "stereotypy_detected": bool(touch_prediction.get("features", {}).get("stereotypy_burst_present", False)),
            }).execute()
        except Exception as err:
            print("Notice inserting predictions_touch_rhythm:", err)

        drawing_ref = payload.get("drawing_reference") or "sun"
        drawing_strokes = payload.get("drawing_strokes") or []
        report["drawing_reference"] = drawing_ref
        report["drawing_strokes"] = drawing_strokes
        report["stroke_count"] = len(drawing_strokes) or len(touch)
        report["stimulus_category"] = stim_cat
        report["stimulus_image_id"] = stim_img_id

        reg_score = int(max(0, min(100, round(float(report.get("regulation_score_pct", 85))))))

        # Look up assigned therapist for this child
        assigned_therapist_id = None
        try:
            assign_res = client.table("child_therapist_assignments").select("therapist_id").eq("child_id", session["child_id"]).eq("active", True).execute()
            if assign_res.data:
                assigned_therapist_id = assign_res.data[0]["therapist_id"]
        except Exception as e:
            print("Notice querying assigned therapist:", e)

        report["assigned_therapist_id"] = assigned_therapist_id

        report_data = {
            "session_id": session_id,
            "caregiver_id": session["caregiver_id"],
            "child_id": session["child_id"],
            "overall_state": overall_state,
            "regulation_score_pct": reg_score,
            "valence": round(max(-1.0, min(1.0, valence)), 3),
            "arousal": round(max(0.0, min(1.0, arousal)), 3),
            "dominance": round(max(0.0, min(1.0, dominance)), 3),
            "insights": report.get("insights", []),
            "recommendations": report.get("recommendations", []),
            "distress_alerts": [],
            "report_markdown": report.get("markdown_report", ""),
            "raw_report_json": report,
            "stimulus_category": stim_cat,
            "stimulus_image_id": stim_img_id,
            "stimulus_reaction_summary": report.get("stimulus_reaction_summary"),
            "simple_language_report": report.get("simple_language_report"),
        }
        if assigned_therapist_id:
            report_data["assigned_therapist_id"] = assigned_therapist_id

        try:
            client.table("session_reports").upsert(report_data, on_conflict="session_id").execute()
        except Exception:
            report_data.pop("assigned_therapist_id", None)
            client.table("session_reports").upsert(report_data, on_conflict="session_id").execute()
        client.table("sessions").update({
            "status": "completed",
            "stimulus_category": stim_cat,
            "stimulus_image_id": stim_img_id,
        }).eq("id", session_id).execute()
        return {"session_id": session_id, "status": "completed"}
    except Exception as error:
        client.table("sessions").update({"status": "failed"}).eq("id", session_id).execute()
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Inference processing failed: {type(error).__name__}: {error}",
        ) from error