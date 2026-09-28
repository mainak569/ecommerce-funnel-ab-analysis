"""Shared colors and matplotlib settings so every chart in the project looks the same."""
import matplotlib.pyplot as plt

SURFACE = "#fcfcfb"
TEXT = "#0b0b0b"
TEXT_MUTED = "#52514e"
GRID = "#e4e3df"

# colors follow the entity, so a channel keeps its color in every chart
CHANNEL_COLORS = {
    "paid_nonbrand": "#2a78d6",
    "paid_brand": "#eb6834",
    "organic_search": "#1baf7a",
    "direct_type_in": "#eda100",
    "paid_social": "#e87ba4",
}
DEVICE_COLORS = {"desktop": "#2a78d6", "mobile": "#eb6834"}
VARIANT_COLORS = {"A": "#8a8984", "B": "#2a78d6"}
PRODUCT_COLORS = {
    "The Original Mr. Fuzzy": "#2a78d6",
    "The Forever Love Bear": "#eb6834",
    "The Birthday Sugar Panda": "#1baf7a",
    "The Hudson River Mini bear": "#eda100",
}
FUNNEL_BLUE = "#2a78d6"
HIGHLIGHT = "#e34948"


def apply_style():
    plt.rcParams.update({
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
        "axes.edgecolor": GRID,
        "axes.labelcolor": TEXT_MUTED,
        "axes.titlecolor": TEXT,
        "axes.titlesize": 12,
        "axes.titleweight": "bold",
        "axes.titlelocation": "left",
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "axes.axisbelow": True,
        "grid.color": GRID,
        "grid.linewidth": 0.8,
        "xtick.color": TEXT_MUTED,
        "ytick.color": TEXT_MUTED,
        "legend.frameon": False,
        "lines.linewidth": 2,
        "font.size": 10,
        "figure.dpi": 110,
        "savefig.dpi": 150,
        "savefig.bbox": "tight",
    })
