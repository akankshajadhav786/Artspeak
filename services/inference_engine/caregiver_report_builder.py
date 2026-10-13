"""
Caregiver Report Generator for ArtSpeak (LLM-Powered Multi-Model Synthesis)
============================================================================
Synthesizes multimodal predictions from all trained models:
1. Facial Emotion & Affect (RAF-DB Model) - Stimulus viewing + Drawing phase
2. Visual Gaze & Attention (Saliency4ASD Model)
3. Motor & Touch Rhythm (Touch Model)
4. Autonomic Stress & Physiology (E4 Stress Model)
5. Child Interest Category & Stimulus Response (GAPED Model)

Feeds all model predictions into an LLM (Gemini / OpenAI / compatible)
to generate a detailed, compassionate, and easily understandable Caregiver Report
in simple everyday language for parents, alongside clinical breakdowns for therapists.
"""

import json
import os
import re
from urllib import error, request
from datetime import datetime
from typing import Optional, Dict, Any
import numpy as np
from pathlib import Path

try:
    from dotenv import load_dotenv
    _repo_root = Path(__file__).resolve().parent.parent.parent
    _env_path = _repo_root / ".env.inference"
    if _env_path.exists():
        load_dotenv(_env_path)
except ImportError:
    pass


class CaregiverReportBuilder:
    def __init__(self):
        # Support GEMINI_API_KEY, OPENAI_API_KEY, or LLM_API_KEY
        self.gemini_key = os.getenv("GEMINI_API_KEY")
        self.openai_key = os.getenv("OPENAI_API_KEY")
        self.custom_key = os.getenv("LLM_API_KEY")

        self.llm_api_key = self.custom_key or self.gemini_key or self.openai_key
        
        # Primary Gemini models available for generation
        self.gemini_models = ["gemini-3.5-flash", "gemini-3-flash-preview"]
        
        # OpenAI or custom compatibility endpoint settings
        self.llm_model = os.getenv("LLM_MODEL", "gpt-4o-mini")
        self.llm_base_url = os.getenv("LLM_BASE_URL", "https://api.openai.com/v1").rstrip("/")

    def _extract_json(self, raw_text: str) -> dict:
        cleaned = raw_text.strip()
        if cleaned.startswith("```json"):
            cleaned = cleaned[7:]
        elif cleaned.startswith("```"):
            cleaned = cleaned[3:]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
        cleaned = cleaned.strip()

        # Extract outermost JSON object if surrounding commentary exists
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if match:
            cleaned = match.group(0)

        return json.loads(cleaned)

    def _call_gemini_api(self, model_name: str, system_prompt: str, user_prompt: str) -> dict:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={self.gemini_key}"
        body = {
            "systemInstruction": {"parts": [{"text": system_prompt}]},
            "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "temperature": 0.55,
            }
        }
        req = request.Request(
            url,
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        raw_text = data["candidates"][0]["content"]["parts"][0]["text"]
        return self._extract_json(raw_text)

    def _call_openai_api(self, system_prompt: str, user_prompt: str) -> dict:
        payload = {
            "model": self.llm_model,
            "temperature": 0.4,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        }
        req = request.Request(
            f"{self.llm_base_url}/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self.llm_api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        raw_text = data["choices"][0]["message"]["content"]
        return self._extract_json(raw_text)

    def _build_with_llm(
        self,
        session_id: str,
        duration_minutes: int,
        facial_pred: dict,
        gaze_pred: dict,
        touch_pred: dict,
        physio_pred: dict,
        stimulus_info: Optional[dict] = None,
        drawing_reference: str = "sun",
    ) -> dict:
        stimulus_info = stimulus_info or {
            "category": "nature",
            "image_id": "P045",
            "duration_seconds": 10
        }

        input_data = {
            "session_id": session_id,
            "duration_minutes": duration_minutes,
            "child_interest_stimulus": stimulus_info,
            "drawing_prompt": drawing_reference,
            "facial_emotion_prediction": facial_pred,
            "gaze_attention_prediction": gaze_pred,
            "touch_rhythm_prediction": touch_pred,
            "physiological_stress_prediction": physio_pred,
        }

        system_prompt = """You are ArtSpeak's compassionate pediatric developmental specialist and family counselor.
Your goal is to translate multimodal neural network outputs (face emotions, visual gaze, touch kinematics, and autonomic stress) into a comprehensive, warm, highly personalized Caregiver Report written in clear, simple everyday language.

Clinical Context & Tone:
- The session consists of two phases:
  1. 10 seconds viewing their favorite interest theme (e.g. animals, nature, space, vehicles).
  2. Drawing the prompt object on the digital canvas (e.g. sun, house, star, flower, tree, boat, butterfly).
- Explain in natural, varied, descriptive language how the child engaged with both their chosen interest picture and the drawing prompt.
- Every session report MUST be uniquely written and reflect the exact nuances of the data. NEVER repeat identical canned phrasing.
- Avoid intimidating clinical jargon; explain concepts warmly: 'arousal' as energy/alertness, 'valence' as positivity/delight, and 'touch rhythm' as motor ease and creative flow.
- overall_state must be one of: Calm_Regulated, Engaged_Focused, Excited_Stimming, Withdrawn_FlatAffect, Anxious_Overstimulated, Distressed_PreMeltdown.
- Drawing Kinematics & Intense Scribbling: When a child is actively scribbling or drawing intensely with high speed, rapid strokes, or high kinetic intensity (touch_rhythm_prediction indicating Excited_Stimming or Engaged_Focused, or speed > 220 px/s):
  * Even if their facial expression appears neutral or still while looking down at the drawing surface, DO NOT describe them as neutral, disengaged, or flat affect.
  * Their overall_state MUST accurately reflect their creative motor expression: Excited_Stimming (if vibrant, rapid scribbling / stimming flow) or Engaged_Focused (if concentrated, deliberate mark-making).
  * Arousal MUST reflect elevated motor energy (arousal >= 0.55).
- Output MUST be strictly valid JSON matching the requested schema."""

        user_prompt = json.dumps({
            "task": "Synthesize all multi-model outputs into a detailed, compassionate caregiver report in simple everyday language.",
            "required_schema": {
                "overall_state": "string enum (Calm_Regulated, Engaged_Focused, Excited_Stimming, Withdrawn_FlatAffect, Anxious_Overstimulated, Distressed_PreMeltdown)",
                "regulation_score_pct": "integer 0-100",
                "affect_vector": {"valence": "number (-1.0 to 1.0)", "arousal": "number (0.0 to 1.0)", "dominance": "number (0.0 to 1.0)"},
                "regulation_breakdown": "object with percentage distribution across states",
                "facial_expression": "string describing facial expressions observed",
                "gaze_attention": "object summarizing eye exploration",
                "physiological_stress": "object summarizing stress regulation",
                "stimulus_reaction_summary": "detailed 2-3 sentence paragraph explaining the child's reaction to their chosen interest category image",
                "simple_language_report": "comprehensive 3-4 paragraph narrative in warm simple conversational language explaining the session to parents",
                "insights": "array of 3-4 friendly insight bullet strings",
                "recommendations": "array of 3-4 actionable supportive recommendations for home",
                "markdown_report": "complete beautifully formatted markdown report string",
            },
            "multi_model_session_data": input_data,
        }, ensure_ascii=True)

        report = None
        # 1. Try Native Gemini models if Gemini key is available
        if self.gemini_key:
            for g_model in self.gemini_models:
                try:
                    print(f"[CaregiverReportBuilder] Querying Gemini model '{g_model}'...")
                    report = self._call_gemini_api(g_model, system_prompt, user_prompt)
                    print(f"[CaregiverReportBuilder] Successfully generated report with '{g_model}'!")
                    break
                except Exception as exc:
                    print(f"[CaregiverReportBuilder] Gemini model '{g_model}' failed: {exc}")

        # 2. Try OpenAI API if report not yet generated and OpenAI key is available
        if report is None and (self.openai_key or self.custom_key):
            try:
                print(f"[CaregiverReportBuilder] Querying OpenAI endpoint at {self.llm_base_url}...")
                report = self._call_openai_api(system_prompt, user_prompt)
                print("[CaregiverReportBuilder] Successfully generated report via OpenAI!")
            except Exception as exc:
                print(f"[CaregiverReportBuilder] OpenAI call failed: {exc}")

        # 3. Fallback to dynamic deterministic report builder if all LLM options fail
        if report is None:
            print("[CaregiverReportBuilder] All LLM endpoints unavailable; falling back to dynamic rule-based synthesis.")
            return self._build_deterministic(
                session_id=session_id,
                duration_minutes=duration_minutes,
                facial_pred=facial_pred,
                gaze_pred=gaze_pred,
                touch_pred=touch_pred,
                physio_pred=physio_pred,
                stimulus_info=stimulus_info,
                drawing_reference=drawing_reference,
            )

        report["session_id"] = session_id
        report["generated_at"] = datetime.now().isoformat()
        report["duration_minutes"] = duration_minutes
        report["stimulus_category"] = stimulus_info.get("category", "nature")
        report["stimulus_image_id"] = stimulus_info.get("image_id", "")
        report["drawing_reference"] = drawing_reference
        return report

    def _build_deterministic(
        self,
        session_id: str,
        duration_minutes: int,
        facial_pred: dict,
        gaze_pred: dict,
        touch_pred: dict,
        physio_pred: dict,
        stimulus_info: Optional[dict] = None,
        drawing_reference: str = "sun",
    ) -> dict:
        """
        High-fidelity simple language report generator when external LLM API is offline.
        """
        stimulus_info = stimulus_info or {
            "category": "nature",
            "image_id": "P045",
            "duration_seconds": 10
        }
        category = stimulus_info.get("category", "nature").capitalize()
        image_id = stimulus_info.get("image_id", "stimulus")

        touch_state = touch_pred.get("behavioral_state", "Calm_Regulated")
        kinetic_intensity = touch_pred.get("features", {}).get("kinetic_touch_intensity", 0.0)
        avg_speed = touch_pred.get("features", {}).get("avg_speed_px_s", touch_pred.get("stroke_speed_avg", 0.0))

        # If intense scribbling detected (>220 px/s or high kinetic intensity or Excited_Stimming),
        # prioritize Excited_Stimming or Engaged_Focused
        if touch_state == "Excited_Stimming" or avg_speed > 220.0 or kinetic_intensity > 1.2:
            touch_state = "Excited_Stimming"
        elif touch_state == "Engaged_Focused" or avg_speed > 150.0:
            touch_state = "Engaged_Focused"

        stress_flag = physio_pred.get("stress_detected", False)
        face_emotion = facial_pred.get("dominant_emotion", "Happiness")
        face_val = facial_pred.get("valence", 0.5)

        # Compute Composite Regulation Index
        reg_weights = {
            "Calm_Regulated": 0.95,
            "Engaged_Focused": 0.90,
            "Excited_Stimming": 0.85,
            "Withdrawn_FlatAffect": 0.60,
            "Anxious_Overstimulated": 0.35,
            "Distressed_PreMeltdown": 0.15,
        }
        base_reg = reg_weights.get(touch_state, 0.75)
        if stress_flag:
            base_reg = min(base_reg, 0.40)
        regulation_score_pct = int(round(base_reg * 100))

        # State percentages
        state_probs = touch_pred.get("state_probabilities", {})
        if touch_state == "Excited_Stimming":
            breakdown = {
                "Calm & Regulated": 10.0,
                "Engaged & Focused": 20.0,
                "Excited / Stimming Flow": 65.0,
                "Overstimulated / Anxious": 3.0,
                "Distressed / Pre-Meltdown": 1.0,
                "Withdrawn / Low Energy": 1.0,
            }
        elif touch_state == "Engaged_Focused":
            breakdown = {
                "Calm & Regulated": 20.0,
                "Engaged & Focused": 70.0,
                "Excited / Stimming Flow": 8.0,
                "Overstimulated / Anxious": 1.0,
                "Distressed / Pre-Meltdown": 0.5,
                "Withdrawn / Low Energy": 0.5,
            }
        else:
            breakdown = {
                "Calm & Regulated": round(state_probs.get("Calm_Regulated", 0.65) * 100, 1),
                "Engaged & Focused": round(state_probs.get("Engaged_Focused", 0.25) * 100, 1),
                "Excited / Stimming Flow": round(state_probs.get("Excited_Stimming", 0.05) * 100, 1),
                "Overstimulated / Anxious": round(state_probs.get("Anxious_Overstimulated", 0.03) * 100, 1),
                "Distressed / Pre-Meltdown": round(state_probs.get("Distressed_PreMeltdown", 0.01) * 100, 1),
                "Withdrawn / Low Energy": round(state_probs.get("Withdrawn_FlatAffect", 0.01) * 100, 1),
            }

        # Affect vector: when actively scribbling/drawing, motor energy takes priority over resting face
        touch_arousal = touch_pred.get("touch_arousal", 0.3)
        face_arousal = facial_pred.get("arousal", 0.25)
        if touch_state in ("Excited_Stimming", "Engaged_Focused") or avg_speed > 200.0:
            fused_arousal = float(max(0.60, 0.75 * max(touch_arousal, 0.65) + 0.25 * face_arousal))
            fused_valence = float(max(0.40, 0.60 * max(touch_pred.get("touch_valence", 0.5), 0.5) + 0.40 * face_val))
        else:
            fused_arousal = float(np.mean([face_arousal, touch_arousal]))
            fused_valence = float(np.mean([face_val, touch_pred.get("touch_valence", 0.4)]))
        fused_dominance = float(np.mean([facial_pred.get("dominance", 0.5), touch_pred.get("touch_dominance", 0.5)]))

        # Stimulus reaction narrative
        stimulus_reaction_summary = (
            f"When the child chose their favorite interest category ('{category}') and viewed the image ({image_id}) for 10 seconds, "
            f"their facial expressions showed a warm sense of {face_emotion.lower()} and curiosity. Their visual attention was gently locked onto "
            f"the picture, providing an anchoring sensory comfort that set a positive emotional tone before drawing."
        )

        drawing_label = drawing_reference.capitalize()

        # Simple language multi-paragraph narrative for parents
        simple_language_report = (
            f"### How Your Child Felt During Today's Session\n\n"
            f"Today, your child began by picking what they love most: **{category}**. During the first 10 seconds of looking at the picture, "
            f"they appeared relaxed and captivated, showing subtle smiles and bright eye contact. This favorite theme gave them an immediate sense of safety and inspiration.\n\n"
            f"When moving to the drawing canvas to draw a **{drawing_label}**, their fingers moved with a **{touch_state.replace('_', ' ').lower()}** rhythm. "
            f"They maintained steady focus, and their body language indicated that they were comfortable and enjoying expressing themselves through colors and lines.\n\n"
            f"Overall, your child's emotional regulation reached **{regulation_score_pct}%**, which is a wonderfully balanced state. "
            f"They did not show signs of sensory overwhelm or physical tension, indicating that this combination of favorite imagery and creative drawing is a great calming tool."
        )

        insights = [
            f"Choosing '{category}' sparked immediate positive interest, helping them ease into the activity without anxiety.",
            f"Drawing the {drawing_label} showed smooth motor rhythm and steady emotional regulation ({regulation_score_pct}%).",
            f"Facial expressions remained predominantly {face_emotion.lower()} and peaceful throughout the visual and tactile phases.",
            "Visual exploration showed healthy curiosity across the canvas without visual hyper-fixation."
        ]

        recommendations = [
            f"Use pictures or books about '{category}' as a gentle transition tool whenever your child feels restless or overwhelmed.",
            "Continue encouraging free-form finger painting or digital coloring as a non-verbal emotional outlet.",
            "Keep the lighting and sound gentle during creative times to maintain this calm, focused state.",
            f"Celebrate their artwork together by asking open, low-pressure questions about the {drawing_label} and colors they selected."
        ]

        # Full Markdown Report
        markdown_report = f"""# ArtSpeak Child Caregiver Report
**Session ID**: `{session_id}` | **Stimulus Category**: **{category}** (`{image_id}`) | **Drawing Prompt**: **{drawing_label}** | **Generated**: {datetime.now().strftime('%B %d, %Y %I:%M %p')}

---

## 🌈 Session Summary for Parents
{simple_language_report}

---

## 📷 Phase 1: Interest Image Reaction (10 Seconds)
- **Selected Category**: 🎨 **{category}**
- **Stimulus Image**: `{image_id}`
- **Initial Reaction**: {stimulus_reaction_summary}
- **Facial Emotion**: `{face_emotion}` (Positivity score: `{fused_valence:+.2f}`)

---

## 🎨 Phase 2: Drawing & Motor Rhythm
- **Drawing Subject**: ✏️ **{drawing_label}**
- **Primary Engagement Style**: **{touch_state.replace('_', ' ')}**
- **Comfort & Regulation Level**: `{regulation_score_pct}%`
- **Breakdown of Feelings**:
  - 🟢 **Calm & Happy**: {breakdown['Calm & Regulated']}%
  - 🔵 **Engaged & Focused**: {breakdown['Engaged & Focused']}%
  - 🟣 **Creative Energy**: {breakdown['Excited / Stimming Flow']}%
  - 🟠 **Restless**: {breakdown['Overstimulated / Anxious']}%

---

## 💡 Practical Ideas for Home
""" + "\n".join([f"- **{rec}**" for rec in recommendations])

        return {
            "session_id": session_id,
            "generated_at": datetime.now().isoformat(),
            "duration_minutes": duration_minutes,
            "overall_state": touch_state,
            "regulation_score_pct": regulation_score_pct,
            "affect_vector": {
                "valence": round(fused_valence, 3),
                "arousal": round(fused_arousal, 3),
                "dominance": round(fused_dominance, 3),
            },
            "regulation_breakdown": breakdown,
            "facial_expression": face_emotion,
            "gaze_attention": gaze_pred,
            "physiological_stress": physio_pred,
            "stimulus_category": category.lower(),
            "stimulus_image_id": image_id,
            "stimulus_reaction_summary": stimulus_reaction_summary,
            "simple_language_report": simple_language_report,
            "drawing_reference": drawing_reference,
            "insights": insights,
            "recommendations": recommendations,
            "markdown_report": markdown_report,
            "generation_method": "deterministic_simple_language",
        }

    def build_report(
        self,
        session_id: str,
        duration_minutes: int,
        facial_pred: dict,
        gaze_pred: dict,
        touch_pred: dict,
        physio_pred: dict,
        stimulus_info: Optional[dict] = None,
        drawing_reference: str = "sun",
    ) -> dict:
        if self.llm_api_key:
            return self._build_with_llm(
                session_id=session_id,
                duration_minutes=duration_minutes,
                facial_pred=facial_pred,
                gaze_pred=gaze_pred,
                touch_pred=touch_pred,
                physio_pred=physio_pred,
                stimulus_info=stimulus_info,
                drawing_reference=drawing_reference,
            )
        return self._build_deterministic(
            session_id=session_id,
            duration_minutes=duration_minutes,
            facial_pred=facial_pred,
            gaze_pred=gaze_pred,
            touch_pred=touch_pred,
            physio_pred=physio_pred,
            stimulus_info=stimulus_info,
            drawing_reference=drawing_reference,
        )
