from pathlib import Path
from textwrap import shorten

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "warranty-forecasting-technical-handbook.pdf"
DEMO_IMAGE = ROOT / "docs" / "assets" / "synthetic_forecast.png"

PAGE_W, PAGE_H = A4
MARGIN_X = 17 * mm
MARGIN_TOP = 18 * mm
MARGIN_BOTTOM = 17 * mm
CONTENT_W = PAGE_W - 2 * MARGIN_X

NAVY = colors.HexColor("#17324D")
BLUE = colors.HexColor("#2878B5")
TEAL = colors.HexColor("#177E89")
CYAN = colors.HexColor("#43A6C6")
INK = colors.HexColor("#24313B")
MUTED = colors.HexColor("#667784")
LINE = colors.HexColor("#CBD8E2")
PALE = colors.HexColor("#F5F9FC")
LIGHT_BLUE = colors.HexColor("#EAF4FA")
LIGHT_GREEN = colors.HexColor("#EAF6F0")
LIGHT_ORANGE = colors.HexColor("#FFF3E8")
WHITE = colors.white

STYLES = getSampleStyleSheet()
BODY = ParagraphStyle(
    "Body",
    parent=STYLES["BodyText"],
    fontName="Helvetica",
    fontSize=9.2,
    leading=14,
    textColor=INK,
    spaceAfter=5,
)
SMALL = ParagraphStyle(
    "Small",
    parent=BODY,
    fontSize=7.7,
    leading=10.5,
    spaceAfter=2,
)
H1 = ParagraphStyle(
    "H1",
    parent=STYLES["Heading1"],
    fontName="Helvetica-Bold",
    fontSize=19,
    leading=24,
    textColor=NAVY,
    spaceAfter=9,
)
H2 = ParagraphStyle(
    "H2",
    parent=STYLES["Heading2"],
    fontName="Helvetica-Bold",
    fontSize=12.5,
    leading=17,
    textColor=BLUE,
    spaceBefore=7,
    spaceAfter=5,
)
TABLE_HEAD = ParagraphStyle(
    "TableHead",
    parent=SMALL,
    fontName="Helvetica-Bold",
    textColor=WHITE,
)
TABLE_BODY = ParagraphStyle(
    "TableBody",
    parent=SMALL,
    fontSize=7.4,
    leading=10.2,
)


def p(text, style=BODY):
    return Paragraph(text, style)


def bullet(text):
    return Paragraph(
        f"- {text}",
        ParagraphStyle(
            "Bullet",
            parent=BODY,
            leftIndent=5 * mm,
            firstLineIndent=-3.5 * mm,
            spaceAfter=3,
        ),
    )


def table(headers, rows, widths, font_size=7.4):
    body_style = ParagraphStyle(
        "DynamicBody",
        parent=TABLE_BODY,
        fontSize=font_size,
        leading=font_size + 2.7,
    )
    data = [[p(str(x), TABLE_HEAD) for x in headers]]
    data.extend([[p(str(x), body_style) for x in row] for row in rows])
    output = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("GRID", (0, 0), (-1, -1), 0.35, LINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]
    for row_index in range(2, len(data), 2):
        commands.append(("BACKGROUND", (0, row_index), (-1, row_index), PALE))
    output.setStyle(TableStyle(commands))
    return output


def callout(title, body, kind="info"):
    palettes = {
        "info": (LIGHT_BLUE, BLUE),
        "good": (LIGHT_GREEN, TEAL),
        "warn": (LIGHT_ORANGE, colors.HexColor("#C46A1A")),
    }
    background, accent = palettes[kind]
    output = Table(
        [[p(f"<b>{title}</b>", BODY)], [p(body, SMALL)]],
        colWidths=[CONTENT_W],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BOX", (0, 0), (-1, -1), 0.6, accent),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        ),
    )
    return output


def header_footer(canvas, doc):
    page = canvas.getPageNumber()
    if page == 1:
        return
    canvas.saveState()
    canvas.setFillColor(WHITE)
    canvas.rect(0, PAGE_H - 13 * mm, PAGE_W, 13 * mm, fill=1, stroke=0)
    canvas.rect(0, 0, PAGE_W, 13 * mm, fill=1, stroke=0)
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.4)
    canvas.line(MARGIN_X, PAGE_H - 11 * mm, PAGE_W - MARGIN_X, PAGE_H - 11 * mm)
    canvas.line(MARGIN_X, 11 * mm, PAGE_W - MARGIN_X, 11 * mm)
    canvas.setFont("Helvetica", 7.2)
    canvas.setFillColor(MUTED)
    canvas.drawString(
        MARGIN_X,
        PAGE_H - 8.2 * mm,
        "Warranty Revenue Forecasting System - Portfolio V2.2",
    )
    canvas.drawString(
        MARGIN_X,
        7 * mm,
        "Synthetic portfolio documentation - no company data",
    )
    canvas.drawRightString(PAGE_W - MARGIN_X, 7 * mm, str(page))
    canvas.restoreState()


class Handbook(BaseDocTemplate):
    def __init__(self, filename):
        super().__init__(
            filename,
            pagesize=A4,
            leftMargin=MARGIN_X,
            rightMargin=MARGIN_X,
            topMargin=MARGIN_TOP,
            bottomMargin=MARGIN_BOTTOM,
            title="Warranty Revenue Forecasting System - Technical Handbook",
            author="William Yang",
            subject="Forecasting metrics, validation, leakage controls, and model governance",
        )
        frame = Frame(
            self.leftMargin,
            self.bottomMargin,
            self.width,
            self.height,
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
            id="body",
        )
        self.addPageTemplates(
            [
                PageTemplate(
                    id="handbook",
                    frames=[frame],
                    onPage=header_footer,
                    onPageEnd=header_footer,
                )
            ]
        )


def story():
    flow = []

    # Cover
    flow.append(Spacer(1, 29 * mm))
    flow.append(
        p(
            "WARRANTY REVENUE FORECASTING",
            ParagraphStyle(
                "Eyebrow",
                parent=BODY,
                fontName="Helvetica-Bold",
                fontSize=10,
                textColor=CYAN,
                alignment=TA_CENTER,
                leading=14,
            ),
        )
    )
    flow.append(Spacer(1, 8 * mm))
    flow.append(
        p(
            "Technical Review Handbook",
            ParagraphStyle(
                "Cover",
                parent=H1,
                fontSize=28,
                leading=36,
                textColor=NAVY,
                alignment=TA_CENTER,
            ),
        )
    )
    flow.append(
        p(
            "Portfolio V2.2",
            ParagraphStyle(
                "Cover2",
                parent=H1,
                fontSize=22,
                leading=29,
                textColor=BLUE,
                alignment=TA_CENTER,
            ),
        )
    )
    flow.append(Spacer(1, 7 * mm))
    flow.append(
        Table(
            [[""]],
            colWidths=[34 * mm],
            rowHeights=[1.5 * mm],
            style=TableStyle([("BACKGROUND", (0, 0), (-1, -1), CYAN)]),
            hAlign="CENTER",
        )
    )
    flow.append(Spacer(1, 11 * mm))
    flow.append(
        p(
            "Metrics, leakage controls, horizon-aware features, walk-forward "
            "validation, Hybrid weighting, uncertainty, and governance",
            ParagraphStyle(
                "Subtitle",
                parent=BODY,
                fontSize=11.2,
                leading=18,
                alignment=TA_CENTER,
                textColor=INK,
            ),
        )
    )
    flow.append(Spacer(1, 20 * mm))
    flow.append(
        table(
            ["Document", "Scope"],
            [
                ("Purpose", "Portfolio review, learning, and technical handoff"),
                ("Data", "Synthetic branch IDs B01-B05 only"),
                ("Models", "ARIMA, ETS, recursive XGBoost, adaptive Hybrid"),
                ("Version", "Portfolio V2.2 - July 2026"),
            ],
            [38 * mm, 100 * mm],
            8,
        )
    )
    flow.append(Spacer(1, 22 * mm))
    flow.append(
        p(
            "From a model that runs to a forecast that can be trusted.",
            ParagraphStyle(
                "Quote",
                parent=BODY,
                fontName="Helvetica-Bold",
                fontSize=11,
                alignment=TA_CENTER,
                textColor=TEAL,
            ),
        )
    )
    flow.append(PageBreak())

    # Summary
    flow.append(p("1  System summary", H1))
    flow.append(
        p(
            "Portfolio V2.2 forecasts monthly warranty revenue by branch for "
            "horizons one through six. The technical emphasis is not algorithm "
            "novelty alone: it is time-valid evaluation, explicit failure "
            "conditions, and traceable model decisions."
        )
    )
    flow.append(
        callout(
            "Trust equation",
            "<b>Trustworthy forecast = valid data x temporal validation x "
            "common samples x stable evidence x auditable fallback.</b>",
            "good",
        )
    )
    flow.append(p("Component roles", H2))
    flow.append(
        table(
            ["Model", "Role", "Main risk"],
            [
                ("ARIMA", "Autocorrelation, differencing, linear time patterns", "Limited nonlinear interactions"),
                ("ETS", "Level, trend, and seasonal smoothing", "May lag structural change"),
                ("XGBoost", "Nonlinear lag and calendar interactions", "Leakage and recursive error"),
                ("Hybrid", "Diversifies model-specific misses", "Optimistic weights if evaluation is not nested"),
            ],
            [30 * mm, 82 * mm, 63 * mm],
        )
    )
    flow.append(p("Pipeline", H2))
    flow.append(
        table(
            ["Stage", "Control"],
            [
                ("Input", "Schema, duplicate-key, missing-value, and open-month checks"),
                ("Features", "Lagged history only; blocked forecast-time fields"),
                ("Backtest", "Expanding origins and h=1,...,6"),
                ("Comparison", "Exactly three component models on common keys"),
                ("Hybrid", "Weights from earlier origins only"),
                ("Interval", "Direct historical Hybrid residual scale"),
                ("Output", "Route, weight source, interval source, and sample counts"),
            ],
            [39 * mm, 136 * mm],
            7.8,
        )
    )
    flow.append(PageBreak())

    # Metrics
    flow.append(p("2  Forecast metrics", H1))
    flow.append(
        table(
            ["Metric", "Formula", "Question answered", "Caution"],
            [
                ("RMSE", "sqrt(mean((Pred - Actual)^2))", "How strongly should large misses be penalized?", "Sensitive to outliers"),
                ("MAE", "mean(abs(Pred - Actual))", "What is a typical absolute miss?", "Does not emphasize spikes"),
                ("MAPE", "mean(abs(error / Actual)) x 100", "How large is error relative to Actual?", "Unstable near zero"),
                ("WAPE", "sum(abs(error)) / sum(abs(Actual)) x 100", "What is aggregate relative error?", "Large months dominate"),
                ("Bias", "mean(Pred - Actual)", "Is the system systematically high or low?", "Positive and negative errors cancel"),
                ("n", "Valid prediction count", "How much evidence supports the score?", "Small n creates unstable rankings"),
            ],
            [24 * mm, 51 * mm, 62 * mm, 38 * mm],
            7.2,
        )
    )
    flow.append(p("Interpretation sequence", H2))
    for item in [
        "First verify no leakage and identical evaluation keys.",
        "Use RMSE as the primary ranking metric.",
        "Use MAE to understand the typical month.",
        "Use MAPE and WAPE to add relative-scale context.",
        "Inspect Bias, sample size, branch, horizon, and worst months.",
        "Confirm improvements with an outer test or bootstrap evidence.",
    ]:
        flow.append(bullet(item))
    flow.append(
        callout(
            "Important",
            "A lower RMSE does not prove the model is deployable. It may still "
            "be caused by target leakage, easier samples, repeated use of the "
            "same test period, or an unavailable feature.",
            "warn",
        )
    )
    flow.append(PageBreak())

    # Leakage
    flow.append(p("3  Leakage and feature availability", H1))
    flow.append(
        table(
            ["Leakage type", "Example", "V2.2 control"],
            [
                ("Target", "Same-month YoY growth algebraically contains revenue", "Explicit blocked-feature list"),
                ("Temporal", "Rolling calculation sees future test rows", "Lag before rolling; fold-local training"),
                ("Availability", "Future claim count used at h=3", "Horizon-aware routes"),
                ("Selection", "Full-history importance chooses features before test", "Nested feature experiments"),
            ],
            [37 * mm, 72 * mm, 66 * mm],
            7.7,
        )
    )
    flow.append(p("Public availability matrix", H2))
    flow.append(
        table(
            ["Feature family", "h=1", "h=2-4", "h=5-6"],
            [
                ("Calendar", "Known", "Known", "Known"),
                ("Revenue lags", "Recursive", "Recursive", "Recursive"),
                ("Rolling revenue", "Recursive", "Recursive", "Recursive"),
                ("Lag-12 revenue", "Known", "Known", "Known"),
                ("Same-month growth", "Blocked", "Blocked", "Blocked"),
                ("Future activity counts", "Blocked", "Blocked", "Blocked"),
            ],
            [58 * mm, 39 * mm, 39 * mm, 39 * mm],
            8,
        )
    )
    flow.append(p("Horizon routes", H2))
    for item in [
        "recursive_core: compact lag, rolling, trend, growth, volatility, and calendar features.",
        "safe_compact: core plus lag-6 and lag-12 signals for longer horizons.",
        "guardrail route: conservative core set when experiments do not justify switching.",
        "short-history route: explicit lower evidence threshold with visible fallback metadata.",
    ]:
        flow.append(bullet(item))
    flow.append(
        callout(
            "Open month rule",
            "The current incomplete month is removed before feature "
            "engineering. Otherwise a partial target contaminates lags, "
            "rolling windows, and the backtest.",
            "info",
        )
    )
    flow.append(PageBreak())

    # Validation
    flow.append(p("4  Time-series validation", H1))
    flow.append(p("Expanding walk-forward"))
    flow.append(
        p(
            "At each origin, the model trains only on earlier months and "
            "predicts h=1,...,6. The origin then advances. Random row splitting "
            "is not used because it would mix past and future."
        )
    )
    flow.append(p("Common-key contract", H2))
    for item in [
        "Every branch-origin-date-h key has ARIMA, ETS, and XGB.",
        "Actual is unique within the key.",
        "Predictions and weights are not missing.",
        "No model appears twice.",
        "The pipeline stops instead of silently dropping incomplete models.",
    ]:
        flow.append(bullet(item))
    flow.append(p("Independent Hybrid evaluation", H2))
    flow.append(
        p(
            "For an evaluation origin t, Hybrid weights are estimated from "
            "origins earlier than t. Evidence priority is prior branch-horizon "
            "errors, then prior branch errors, then equal-weight cold start."
        )
    )
    flow.append(
        table(
            ["Evidence level", "When used", "Output label"],
            [
                ("Branch + horizon", "Enough prior observations for all three models", "prior_branch_h"),
                ("Branch", "Horizon evidence is sparse", "prior_branch"),
                ("Cold start", "No prior residuals exist", "equal_weight_cold_start"),
            ],
            [43 * mm, 80 * mm, 52 * mm],
            7.8,
        )
    )
    flow.append(
        callout(
            "Why this matters",
            "Estimating weights and scoring them on the same residuals makes "
            "Hybrid performance optimistic. Prior-origin weighting separates "
            "the decision from the observation being evaluated.",
            "good",
        )
    )
    flow.append(PageBreak())

    # XGB
    flow.append(p("5  XGBoost configuration", H1))
    flow.append(
        table(
            ["Parameter", "Reference", "Meaning"],
            [
                ("objective", "reg:squarederror", "Squared-error regression"),
                ("eval_metric", "rmse", "Monitoring metric"),
                ("eta", "0.05", "Learning rate per boosting round"),
                ("max_depth", "4", "Maximum tree interaction depth"),
                ("min_child_weight", "3", "Minimum evidence for a child node"),
                ("subsample", "0.8", "Row sampling per tree"),
                ("colsample_bytree", "0.8", "Feature sampling per tree"),
                ("nrounds", "200 production reference", "Maximum boosting rounds"),
                ("seed", "20260717", "Reproducible stochastic sampling"),
            ],
            [44 * mm, 52 * mm, 79 * mm],
            7.7,
        )
    )
    flow.append(p("Feature importance", H2))
    flow.append(
        table(
            ["Field", "Meaning", "Caution"],
            [
                ("Gain", "Average loss reduction from the feature", "Not causality or deployment permission"),
                ("Cover", "Observations affected by splits", "Reach is not predictive gain"),
                ("Frequency", "How often the feature is used", "Frequent use can still be weak"),
            ],
            [34 * mm, 76 * mm, 65 * mm],
            7.8,
        )
    )
    flow.append(p("Parameter governance", H2))
    for item in [
        "Tune only after the final leakage-safe feature set is chosen.",
        "Use nested walk-forward selection rather than random cross-validation.",
        "Compare fixed baseline, selected features, and tuned features separately.",
        "Do not promote a parameter set solely because one holdout month improves.",
    ]:
        flow.append(bullet(item))
    flow.append(PageBreak())

    # Hybrid
    flow.append(p("6  Hybrid and uncertainty", H1))
    flow.append(p("Inverse-RMSE weighting", H2))
    flow.append(
        p(
            "<b>weight_m = (1 / RMSE_m) / sum_j(1 / RMSE_j)</b><br/>"
            "<b>Hybrid prediction = sum_m(weight_m x prediction_m)</b>"
        )
    )
    flow.append(
        p(
            "Weights are normalized and must sum to one. Missing weights are an "
            "error, not a value to be ignored with na.rm."
        )
    )
    flow.append(p("Residual-based interval", H2))
    flow.append(
        p(
            "<b>lower95 = max(0, prediction - 1.96 x Hybrid RMSE)</b><br/>"
            "<b>upper95 = prediction + 1.96 x Hybrid RMSE</b>"
        )
    )
    flow.append(
        p(
            "Hybrid RMSE is calculated from reconstructed historical Hybrid "
            "residuals. This preserves correlation among ARIMA, ETS, and XGB "
            "errors better than summing independent component variances."
        )
    )
    flow.append(
        table(
            ["Interval source", "Use"],
            [
                ("branch_h_residual", "At least three Hybrid residuals at the same branch and horizon"),
                ("branch_residual_fallback", "Horizon evidence is sparse; use the branch-level scale"),
            ],
            [56 * mm, 119 * mm],
            8,
        )
    )
    flow.append(
        callout(
            "Interval limitation",
            "A 1.96 x RMSE interval is an approximation. Production monitoring "
            "should measure empirical coverage and width by branch and horizon.",
            "warn",
        )
    )
    flow.append(PageBreak())

    # Demo image
    flow.append(p("7  Synthetic demonstration", H1))
    flow.append(
        p(
            "The repository includes a reproducible generator for five "
            "synthetic branches. The chart below is created by the same "
            "pipeline used in the automated smoke test. It contains no company "
            "data and is not a performance claim."
        )
    )
    if DEMO_IMAGE.exists():
        image = Image(str(DEMO_IMAGE))
        image.drawWidth = CONTENT_W
        image.drawHeight = CONTENT_W * 7 / 12
        flow.append(image)
    flow.append(Spacer(1, 4 * mm))
    flow.append(
        callout(
            "Reproducibility",
            "Run scripts/run_demo.R from the repository root. The demo "
            "generates input, backtests all models, builds prior-origin Hybrid "
            "weights, forecasts six months, and writes Excel and PNG outputs.",
            "info",
        )
    )
    flow.append(PageBreak())

    # Governance
    flow.append(p("8  Governance checklist", H1))
    flow.append(
        table(
            ["Layer", "Required evidence"],
            [
                ("Data", "Completed months, unique keys, required fields, no missing target"),
                ("Availability", "Every feature known at its forecast horizon"),
                ("Backtest", "Expanding time order and common model keys"),
                ("Selection", "Feature and parameter decisions use earlier data only"),
                ("Performance", "RMSE plus MAE, MAPE, WAPE, Bias, and n"),
                ("Stability", "Branch, horizon, worst-month, and resampling checks"),
                ("Hybrid", "Three models, weights sum to one, visible fallback source"),
                ("Uncertainty", "Residual source and empirical coverage monitoring"),
                ("Operations", "Version, seed, configuration, tests, and rollback"),
            ],
            [41 * mm, 134 * mm],
            7.8,
        )
    )
    flow.append(p("Champion, Challenger, Fallback", H2))
    for item in [
        "Champion: the current evidence-backed production choice.",
        "Challenger: promising, but still under independent evaluation.",
        "Fallback: conservative behavior when history or model components are incomplete.",
    ]:
        flow.append(bullet(item))
    flow.append(p("Remaining research", H2))
    for item in [
        "Empirical interval calibration.",
        "Feature and residual drift monitoring.",
        "Nested feature and hyperparameter selection.",
        "Operational pipeline nowcasting with genuinely available current-period signals.",
        "Formal promotion and rollback thresholds.",
    ]:
        flow.append(bullet(item))
    flow.append(
        callout(
            "Final principle",
            "A model is not permanently good because it once won. Preserve "
            "versions, rerun backtests, monitor drift, and allow a simpler model "
            "to become Champion again.",
            "good",
        )
    )
    flow.append(Spacer(1, 7 * mm))
    flow.append(
        p(
            "Source: Warranty Revenue Forecasting System Portfolio V2.2. "
            "All examples are synthetic and anonymized.",
            ParagraphStyle(
                "EndNote",
                parent=SMALL,
                alignment=TA_CENTER,
                textColor=MUTED,
            ),
        )
    )

    return flow


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    Handbook(str(OUTPUT)).build(story())
    print(OUTPUT)


if __name__ == "__main__":
    main()
