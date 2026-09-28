"""Helpers for the A/B tests: test definitions, SRM check, significance tests, power."""
import numpy as np
import pandas as pd
from scipy import stats
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import confint_proportions_2indep, proportions_ztest

# Test windows found in Phase 1: first day B got traffic to the last day both pages were live.
# segment is a pandas query on v_sessions_enriched columns.
TESTS = [
    {
        "test": "T1", "name": "/home vs /lander-1", "page_col": "landing_page",
        "a": "/home", "b": "/lander-1", "start": "2012-06-19", "end": "2012-07-29",
        "segment": "utm_source == 'gsearch' and channel_group == 'paid_nonbrand'",
        "segment_label": "gsearch nonbrand, all devices",
    },
    {
        "test": "T2", "name": "/lander-1 vs /lander-2", "page_col": "landing_page",
        "a": "/lander-1", "b": "/lander-2", "start": "2013-01-14", "end": "2013-03-10",
        "segment": "channel_group == 'paid_nonbrand'",
        "segment_label": "paid nonbrand, all devices",
    },
    {
        "test": "T3", "name": "/billing vs /billing-2", "page_col": "billing_page",
        "a": "/billing", "b": "/billing-2", "start": "2012-09-10", "end": "2013-01-05",
        "segment": "saw_billing == 1",
        "segment_label": "all sessions that reached billing",
    },
    {
        "test": "T4", "name": "/lander-2 vs /lander-4", "page_col": "landing_page",
        "a": "/lander-2", "b": "/lander-4", "start": "2014-02-02", "end": "2014-04-19",
        "segment": "channel_group == 'paid_nonbrand' and device_type == 'desktop'",
        "segment_label": "paid nonbrand, desktop",
    },
    {
        "test": "T5", "name": "/lander-2 vs /lander-5", "page_col": "landing_page",
        "a": "/lander-2", "b": "/lander-5", "start": "2014-08-02", "end": "2014-11-10",
        "segment": "channel_group == 'paid_nonbrand' and device_type == 'desktop'",
        "segment_label": "paid nonbrand, desktop",
    },
]

SESSIONS_QUERY = """
SELECT
    website_session_id, created_at, channel_group, utm_source, device_type,
    landing_page, billing_page, is_bounce, saw_billing, has_order,
    revenue_usd::FLOAT AS revenue_usd
FROM v_sessions_enriched
"""


def load_sessions(engine):
    return pd.read_sql(SESSIONS_QUERY, engine, parse_dates=["created_at"])


def build_test(sessions, test):
    """Sessions in the test's segment and window that saw page A or page B, labelled A/B."""
    end = pd.Timestamp(test["end"]) + pd.Timedelta(days=1)
    t = sessions.query(test["segment"])
    in_window = (t["created_at"] >= test["start"]) & (t["created_at"] < end)
    t = t[in_window & t[test["page_col"]].isin([test["a"], test["b"]])].copy()
    t["variant"] = np.where(t[test["page_col"]] == test["a"], "A", "B")
    return t


def srm_check(n_a, n_b, expected_share_a=0.5):
    """Chi-square goodness-of-fit: does the observed split match the intended split?"""
    total = n_a + n_b
    expected = [total * expected_share_a, total * (1 - expected_share_a)]
    chi2, p = stats.chisquare([n_a, n_b], f_exp=expected)
    return {"n_a": n_a, "n_b": n_b, "share_a": n_a / total, "chi2": chi2, "p_value": p}


def compare_rates(success_a, n_a, success_b, n_b):
    """Compare two proportions (B vs A) with a z-test, a chi-square test and a 95% CI for the difference."""
    p_a, p_b = success_a / n_a, success_b / n_b
    z, p_z = proportions_ztest([success_b, success_a], [n_b, n_a])
    table = [[success_a, n_a - success_a], [success_b, n_b - success_b]]
    # no Yates correction, so the chi-square p-value matches the z-test (chi2 = z^2)
    chi2, p_chi, _, _ = stats.chi2_contingency(table, correction=False)
    ci_low, ci_high = confint_proportions_2indep(success_b, n_b, success_a, n_a, compare="diff", method="wald")
    return {
        "rate_a": p_a,
        "rate_b": p_b,
        "diff": p_b - p_a,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "rel_lift": (p_b - p_a) / p_a,
        "z": z,
        "p_value_z": p_z,
        "chi2": chi2,
        "p_value_chi2": p_chi,
    }


def rate_ci(successes, n, z=1.96):
    """Normal-approximation 95% CI for a single rate (used for error bars)."""
    p = successes / n
    half = z * np.sqrt(p * (1 - p) / n)
    return p - half, p + half


def mde(p_base, n_per_group, alpha=0.05, power=0.8):
    """Smallest true rate the test could detect 80% of the time, given the baseline and sample size.

    NormalIndPower works in Cohen's h (a scaled difference of arcsine-transformed rates),
    so the result is converted back to a rate.
    """
    h = NormalIndPower().solve_power(effect_size=None, nobs1=n_per_group, alpha=alpha, power=power, ratio=1.0)
    p_detectable = np.sin(np.arcsin(np.sqrt(p_base)) + h / 2) ** 2
    return {
        "baseline": p_base,
        "detectable_rate": p_detectable,
        "mde_abs": p_detectable - p_base,
        "mde_rel": (p_detectable - p_base) / p_base,
    }


def sample_size_needed(p_base, p_target, alpha=0.05, power=0.8):
    """Sessions per variant needed to detect a move from p_base to p_target."""
    h = 2 * np.arcsin(np.sqrt(p_target)) - 2 * np.arcsin(np.sqrt(p_base))
    return NormalIndPower().solve_power(effect_size=abs(h), nobs1=None, alpha=alpha, power=power, ratio=1.0)


def summarize_variants(df, variant_col, metrics):
    """Sessions plus the sum and rate of each 0/1 metric per variant."""
    g = df.groupby(variant_col)
    out = pd.DataFrame({"sessions": g.size()})
    for m in metrics:
        out[m] = g[m].sum()
        out[f"{m}_rate"] = out[m] / out["sessions"]
    return out


def summarize_test(sessions, test):
    """One summary row per test: split, primary metric (order conversion), bounce, power and impact."""
    t = build_test(sessions, test)
    days = (pd.Timestamp(test["end"]) - pd.Timestamp(test["start"])).days + 1
    a, b = t[t["variant"] == "A"], t[t["variant"] == "B"]
    srm = srm_check(len(a), len(b))
    conv = compare_rates(a["has_order"].sum(), len(a), b["has_order"].sum(), len(b))
    # a billing page session can never bounce, so bounce is only meaningful for landing pages
    is_landing = test["page_col"] == "landing_page"
    if is_landing:
        bounce = compare_rates(a["is_bounce"].sum(), len(a), b["is_bounce"].sum(), len(b))
    power = mde(conv["rate_a"], min(len(a), len(b)))
    # after a rollout all of the segment's traffic goes to the winner, so impact uses A + B sessions
    monthly_sessions = len(t) / days * 30.4
    rps_a, rps_b = a["revenue_usd"].mean(), b["revenue_usd"].mean()
    return {
        "test": test["test"],
        "name": test["name"],
        "page_a": test["a"],
        "page_b": test["b"],
        "segment": test["segment_label"],
        "start": test["start"],
        "end": test["end"],
        "days": days,
        "sessions_a": len(a),
        "sessions_b": len(b),
        "srm_p_value": srm["p_value"],
        "orders_a": int(a["has_order"].sum()),
        "orders_b": int(b["has_order"].sum()),
        "conv_a": conv["rate_a"],
        "conv_b": conv["rate_b"],
        "conv_diff": conv["diff"],
        "conv_diff_ci_low": conv["ci_low"],
        "conv_diff_ci_high": conv["ci_high"],
        "conv_rel_lift": conv["rel_lift"],
        "conv_p_value": conv["p_value_z"],
        "mde_rel": power["mde_rel"],
        "bounce_a": bounce["rate_a"] if is_landing else np.nan,
        "bounce_b": bounce["rate_b"] if is_landing else np.nan,
        "bounce_p_value": bounce["p_value_z"] if is_landing else np.nan,
        "rps_a": rps_a,
        "rps_b": rps_b,
        "monthly_sessions": monthly_sessions,
        "incr_orders_month": conv["diff"] * monthly_sessions,
        "incr_revenue_month": (rps_b - rps_a) * monthly_sessions,
    }


def summary_table(sessions):
    """All tests in one table, with Holm-adjusted p-values and a plain decision."""
    df = pd.DataFrame([summarize_test(sessions, t) for t in TESTS])
    df["conv_p_holm"] = holm_adjust(df["conv_p_value"])
    df["decision"] = np.select(
        [(df["conv_p_holm"] < 0.05) & (df["conv_diff"] > 0), (df["conv_p_holm"] < 0.05) & (df["conv_diff"] < 0)],
        ["B wins", "A wins"],
        default="no significant difference",
    )
    return df


def holm_adjust(p_values):
    """Holm-Bonferroni adjusted p-values (controls the chance of any false positive across tests)."""
    p = np.asarray(p_values, dtype=float)
    order = np.argsort(p)
    m = len(p)
    adjusted = np.empty(m)
    running_max = 0.0
    for rank, idx in enumerate(order):
        running_max = max(running_max, (m - rank) * p[idx])
        adjusted[idx] = min(running_max, 1.0)
    return adjusted
