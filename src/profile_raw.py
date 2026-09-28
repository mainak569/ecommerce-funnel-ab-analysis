"""Quick profile of every raw CSV: shape, dtypes, head, nulls, duplicates, date range."""
from pathlib import Path

import pandas as pd

RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
TABLES = [
    "website_sessions",
    "website_pageviews",
    "orders",
    "order_items",
    "order_item_refunds",
    "products",
]


def profile(name):
    df = pd.read_csv(RAW_DIR / f"{name}.csv")
    print(f"\n==================== {name} ====================")
    print("shape:", df.shape)
    print("\ndtypes:\n", df.dtypes.to_string())
    print("\nhead:\n", df.head(3).to_string())
    print("\nnulls:\n", df.isna().sum().to_string())
    print("\nfull-row duplicates:", df.duplicated().sum())
    id_col = df.columns[0]
    print(f"duplicate {id_col}:", df[id_col].duplicated().sum())
    if "created_at" in df.columns:
        ts = pd.to_datetime(df["created_at"])
        print("date range:", ts.min(), "->", ts.max())
    return df


def url_inventory(pv):
    pv = pv.assign(created_at=pd.to_datetime(pv["created_at"]))
    inv = (
        pv.groupby("pageview_url")
        .agg(
            first_seen=("created_at", "min"),
            last_seen=("created_at", "max"),
            sessions=("website_session_id", "nunique"),
        )
        .sort_values("first_seen")
    )
    print("\n==================== pageview_url inventory ====================")
    print(inv.to_string())

    # landing page = first pageview of each session
    first_pv = pv.sort_values("website_pageview_id").drop_duplicates("website_session_id")
    landing = (
        first_pv.groupby("pageview_url")
        .agg(first_seen=("created_at", "min"), last_seen=("created_at", "max"), sessions=("website_session_id", "count"))
        .sort_values("first_seen")
    )
    print("\nlanding pages:\n", landing.to_string())


def quality_checks(f):
    s, pv, o, oi, r = (f[k] for k in TABLES[:5])
    print("\n==================== data quality ====================")
    print("sessions without pageviews:", (~s["website_session_id"].isin(pv["website_session_id"])).sum())
    print("pageviews without session:", (~pv["website_session_id"].isin(s["website_session_id"])).sum())
    print("orders without session:", (~o["website_session_id"].isin(s["website_session_id"])).sum())
    print("items without order:", (~oi["order_id"].isin(o["order_id"])).sum())
    print("refunds without item:", (~r["order_item_id"].isin(oi["order_item_id"])).sum())
    print("sessions with >1 order:", o["website_session_id"].duplicated().sum())

    item_sum = oi.groupby("order_id").agg(items=("order_item_id", "count"), price=("price_usd", "sum"), cogs=("cogs_usd", "sum"))
    chk = o.set_index("order_id").join(item_sum)
    print("orders where price != sum(items):", ((chk["price_usd"] - chk["price"]).abs() > 0.005).sum())
    print("orders where cogs != sum(items):", ((chk["cogs_usd"] - chk["cogs"]).abs() > 0.005).sum())
    print("orders where items_purchased != item rows:", (chk["items_purchased"] != chk["items"]).sum())

    ri = r.merge(oi[["order_item_id", "order_id", "price_usd"]], on="order_item_id", suffixes=("", "_item"))
    print("refunds above item price:", (ri["refund_amount_usd"] > ri["price_usd"] + 0.005).sum())
    print("refunds with mismatched order_id:", (ri["order_id"] != ri["order_id_item"]).sum())
    print("items refunded more than once:", r["order_item_id"].duplicated().sum())

    so = o.merge(s[["website_session_id", "user_id", "created_at"]], on="website_session_id", suffixes=("", "_s"))
    print("orders whose user_id differs from session user_id:", (so["user_id"] != so["user_id_s"]).sum())
    print("orders placed before session start:", (pd.to_datetime(so["created_at"]) < pd.to_datetime(so["created_at_s"])).sum())

    print("\nprices by product:\n", oi.groupby("product_id")[["price_usd", "cogs_usd"]].agg(["min", "max"]).to_string())
    print("\nitems per order:\n", o["items_purchased"].value_counts().to_string())


def main():
    frames = {name: profile(name) for name in TABLES}

    s = frames["website_sessions"]
    print("\n==================== traffic sources ====================")
    cols = ["utm_source", "utm_campaign", "utm_content", "http_referer"]
    print(s[cols].fillna("NULL").value_counts().to_string())
    print("\ndevice_type:\n", s["device_type"].value_counts().to_string())
    print("\nis_repeat_session:\n", s["is_repeat_session"].value_counts().to_string())

    url_inventory(frames["website_pageviews"])
    quality_checks(frames)


if __name__ == "__main__":
    main()
