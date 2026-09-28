import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env")


def get_engine():
    url = "postgresql+psycopg2://{user}:{pw}@{host}:{port}/{db}".format(
        user=os.getenv("DB_USER"),
        pw=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        db=os.getenv("DB_NAME"),
    )
    # hide_parameters keeps values out of error messages
    return create_engine(url, hide_parameters=True)


if __name__ == "__main__":
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
        print("connected")
    except Exception as e:
        # print only the error type so the URL (with password) never shows up
        print("connection failed:", type(e).__name__)
