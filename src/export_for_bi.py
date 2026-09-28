"""Export the tables Tableau Public needs to data/processed/*.csv (Tableau Public cannot connect to PostgreSQL)."""
import pandas as pd

from ab_testing import load_sessions, rate_ci, summary_table
from db import PROJECT_ROOT, get_engine

OUT_DIR = PROJECT_ROOT / "data" / "processed"

VIEW_EXPORTS = {
    "daily_summary": "SELECT * FROM v_daily_summary ORDER BY session_date",
    "funnel_steps": "SELECT * FROM v_funnel_steps ORDER BY session_month, channel_group, device_type, step_num",
    "product_monthly": "SELECT * FROM v_product_monthly ORDER BY month, product_id",
    "products": "SELECT * FROM products ORDER BY product_id",
}


def ab_variants_long(summary):
    """One row per test and variant, with a 95% CI for each conversion rate (for CI bars in Tableau)."""
    rows = []
    for r in summary.itertuples():
        for v, page, n, orders in [("A", r.page_a, r.sessions_a, r.orders_a), ("B", r.page_b, r.sessions_b, r.orders_b)]:
            low, high = rate_ci(orders, n)
            rows.append({
                "test": r.test,
                "test_name": r.name,
                "variant": v,
                "page": page,
                "sessions": n,
                "orders": orders,
                "conv_rate": orders / n,
                "conv_ci_low": low,
                "conv_ci_high": high,
                "bounce_rate": r.bounce_a if v == "A" else r.bounce_b,
                "revenue_per_session": r.rps_a if v == "A" else r.rps_b,
            })
    return pd.DataFrame(rows)


def main():
    engine = get_engine()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for name, query in VIEW_EXPORTS.items():
        df = pd.read_sql(query, engine)
        df.to_csv(OUT_DIR / f"{name}.csv", index=False)
        print(f"{name}.csv: {len(df):,} rows")

    summary = summary_table(load_sessions(engine))
    summary.round(6).to_csv(OUT_DIR / "ab_test_results.csv", index=False)
    print(f"ab_test_results.csv: {len(summary)} rows")
    variants = ab_variants_long(summary)
    variants.round(6).to_csv(OUT_DIR / "ab_test_variants.csv", index=False)
    print(f"ab_test_variants.csv: {len(variants)} rows")


if __name__ == "__main__":
    main()
