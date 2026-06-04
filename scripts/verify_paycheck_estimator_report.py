#!/usr/bin/env python3
"""Static verifier for the Paycheck Estimator report slice."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "AnesPayTracker" / "Views" / "Report" / "ReportView.swift"
ENGINE = ROOT / "AnesPayTracker" / "Engine" / "StreakEngine.swift"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    report = REPORT.read_text()
    engine = ENGINE.read_text()
    failures: list[str] = []

    require('case paycheckEstimator = "Paycheck Estimator"' in report, "Reports must expose Paycheck Estimator mode", failures)
    require("@State private var paycheckDateRange" in report, "Paycheck estimator must have its own date range state", failures)
    require("currentPaycheckBounds" in report, "Paycheck estimator must filter by paycheck date range", failures)
    require("paycheckRows" in report and "StreakEngine.paycheckAggregationRows" in report, "Report must use engine aggregation rows", failures)
    require("paycheckDate >= start && $0.paycheckDate <= end" in report, "Estimator rows must be filtered by paycheck date", failures)
    require("site?.employer?.paycheckAnchorDate != nil" in report, "Estimator must include only anchored employers", failures)
    require("PaycheckAnchorWarningCard" in report, "Estimator must warn when employer anchors are missing", failures)
    require("PaycheckEstimatorSummaryCard" in report, "Estimator summary card is required", failures)
    require("PaycheckEstimatorBreakdownCard" in report, "Estimator breakdown card is required", failures)
    require("PaycheckEstimatorTableCard" in report, "Estimator table card is required", failures)
    require("struct PaycheckGroup" in report, "Estimator must group rows by paycheck date", failures)
    require("Dictionary(grouping: paycheckRows, by: { $0.paycheckDate })" in report, "Estimator grouping must use paycheck date", failures)
    require("Base Pay" in engine and "On-Call Bonus" in engine and "Streak Bonus" in engine, "Engine rows must include base/on-call/streak components", failures)
    require("bonus.payoutSchedule.payoutDate" in engine, "Engine rows must respect custom bonus payout schedules before paycheck aggregation", failures)

    if failures:
        print("Paycheck estimator report verifier failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Paycheck estimator report verifier passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
