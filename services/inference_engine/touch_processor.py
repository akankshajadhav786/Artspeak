"""
Touch & Rhythm Interaction Feature Extractor for ArtSpeak
=========================================================
Extracts 13 kinematic & rhythm features from session touch events for Model 3.
"""

import numpy as np
import pandas as pd


class TouchFeatureExtractor:
    def __init__(self):
        self.feature_names = [
            "avg_pressure",
            "avg_speed_px_s",
            "avg_curvature",
            "avg_pressure_variance",
            "avg_tap_interval_ms",
            "avg_tap_regularity",
            "stereotypy_burst_present",
            "tap_cadence_hz",
            "kinetic_touch_intensity",
            "rhythm_stability_index",
            "motor_fluidity_score",
            "dysregulation_ratio",
            "pressure_velocity_ratio",
        ]

    def extract_features(self, touch_events: list[dict]) -> dict:
        """
        Processes touch pointer events (e.g. from Supabase session_events or canvas).
        Each event: {"x": float, "y": float, "t": float (ms/sec), "pressure": float}
        """
        if not touch_events:
            # Baseline gentle interaction fallback
            return {
                "avg_pressure": 0.50,
                "avg_speed_px_s": 140.0,
                "avg_curvature": 0.55,
                "avg_pressure_variance": 0.08,
                "avg_tap_interval_ms": 380.0,
                "avg_tap_regularity": 0.68,
                "stereotypy_burst_present": 0.0,
                "tap_cadence_hz": 2.63,
                "kinetic_touch_intensity": 0.70,
                "rhythm_stability_index": 0.62,
                "motor_fluidity_score": 0.37,
                "dysregulation_ratio": 0.11,
                "pressure_velocity_ratio": 0.35,
            }

        pressures = [float(e.get("pressure", 0.5)) for e in touch_events]
        xs = [float(e.get("x", 0.0)) for e in touch_events]
        ys = [float(e.get("y", 0.0)) for e in touch_events]
        ts = [float(e.get("t", e.get("timestamp_ms", 0.0))) for e in touch_events]

        avg_pressure = float(np.mean(pressures)) if pressures else 0.50
        avg_pressure_var = float(np.var(pressures)) if pressures else 0.05

        ts_arr = np.array(ts, dtype=float)
        duration = float(ts_arr[-1] - ts_arr[0]) if len(ts_arr) > 1 else 0.0
        # If all timestamps are identical or zero, synthesize realistic continuous timeline (25ms per touch event)
        if len(ts_arr) > 1 and duration <= 0.0:
            ts_arr = np.arange(len(ts_arr), dtype=float) * 25.0
            duration = float(ts_arr[-1] - ts_arr[0])

        raw_dt = np.diff(ts_arr) if len(ts_arr) > 1 else np.array([25.0])
        # Determine if timestamps are milliseconds vs seconds
        is_millis = (duration > 60.0) or (float(np.mean(np.abs(raw_dt))) > 2.0)
        dt_sec = raw_dt / 1000.0 if is_millis else raw_dt.copy()
        dt_sec = np.clip(dt_sec, 0.005, 5.0)

        # Speed calculation
        if len(xs) > 1:
            dx = np.diff(xs)
            dy = np.diff(ys)
            speeds = np.sqrt(dx**2 + dy**2) / dt_sec
            avg_speed = float(np.mean(speeds))
        else:
            avg_speed = 120.0

        # Curvature calculation (smoothness of trajectory angles)
        if len(xs) > 2:
            v1_x, v1_y = np.diff(xs[:-1]), np.diff(ys[:-1])
            v2_x, v2_y = np.diff(xs[1:]), np.diff(ys[1:])
            dots = v1_x * v2_x + v1_y * v2_y
            norms = np.sqrt(v1_x**2 + v1_y**2) * np.sqrt(v2_x**2 + v2_y**2) + 1e-5
            cos_angles = np.clip(dots / norms, -1.0, 1.0)
            angles = np.arccos(cos_angles)
            avg_curvature = float(np.clip(1.0 - (np.mean(angles) / np.pi), 0.0, 1.0))
        else:
            avg_curvature = 0.60

        # Tap intervals & rhythm regularity
        down_events = [e for e in touch_events if e.get("event_type") == "down"]
        if len(down_events) >= 2:
            down_ts = [float(e.get("t", e.get("timestamp_ms", 0.0))) for e in down_events]
            down_arr = np.array(down_ts)
            down_dt = np.diff(down_arr)
            down_dt_ms = down_dt if is_millis else down_dt * 1000.0
            down_dt_ms = np.clip(down_dt_ms, 20.0, 5000.0)
            avg_interval = float(np.mean(down_dt_ms))
            interval_std = float(np.std(down_dt_ms))
            avg_regularity = float(np.clip(1.0 - (interval_std / (avg_interval + 1e-4)), 0.0, 1.0))
            stereotypy = 1.0 if (np.sum(down_dt_ms < 250.0) >= 3 or avg_speed > 300.0) else 0.0
        elif len(ts_arr) > 1:
            # Single continuous stroke or raw pointer stream
            if avg_speed > 300.0:
                avg_interval = 140.0
                avg_regularity = 0.82
                stereotypy = 1.0
            elif avg_speed > 140.0:
                avg_interval = 280.0
                avg_regularity = 0.78
                stereotypy = 0.0
            else:
                avg_interval = 450.0
                avg_regularity = 0.72
                stereotypy = 0.0
        else:
            avg_interval = 400.0
            avg_regularity = 0.70
            stereotypy = 0.0

        # Derived Kinematic Features
        tap_cadence_hz = 1000.0 / (avg_interval + 1e-5)
        kinetic_intensity = avg_pressure * (avg_speed / 100.0)
        rhythm_stability = avg_regularity * np.clip(1.0 - avg_pressure_var, 0.0, 1.0)
        motor_fluidity = avg_curvature * avg_regularity
        dysregulation = avg_pressure_var / (avg_regularity + 1e-4)
        pressure_vel_ratio = avg_pressure / (avg_speed / 100.0 + 1e-4)

        return {
            "avg_pressure": avg_pressure,
            "avg_speed_px_s": avg_speed,
            "avg_curvature": avg_curvature,
            "avg_pressure_variance": avg_pressure_var,
            "avg_tap_interval_ms": avg_interval,
            "avg_tap_regularity": avg_regularity,
            "stereotypy_burst_present": stereotypy,
            "tap_cadence_hz": tap_cadence_hz,
            "kinetic_touch_intensity": kinetic_intensity,
            "rhythm_stability_index": rhythm_stability,
            "motor_fluidity_score": motor_fluidity,
            "dysregulation_ratio": dysregulation,
            "pressure_velocity_ratio": pressure_vel_ratio,
        }
