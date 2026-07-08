from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "images"


def font(size, bold=False):
    candidates = [
        r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for item in candidates:
        if item and Path(item).exists():
            return ImageFont.truetype(item, size)
    return ImageFont.load_default()


F_TITLE = font(34, True)
F_LAYER = font(24, True)
F_BOX = font(20, True)
F_TEXT = font(16)
F_SMALL = font(14)

COL = {
    "bg": "#F8FAFC",
    "control": "#EAF2FF",
    "lltsm": "#EEF2FF",
    "link": "#ECFDF3",
    "phy": "#FFF7E6",
    "box": "#FFFFFF",
    "stroke": "#1F2937",
    "muted": "#475569",
    "blue": "#2563EB",
    "green": "#059669",
    "orange": "#D97706",
    "red": "#DC2626",
}


def rounded(draw, box, fill, outline="#334155", width=2, radius=18):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def draw_text_center(draw, box, lines, fnt=F_TEXT, fill="#334155"):
    x1, y1, x2, y2 = box
    h = draw.textbbox((0, 0), "Ag", font=fnt)[3] + 6
    y = y1 + ((y2 - y1) - h * len(lines)) / 2
    for line in lines:
        w = draw.textbbox((0, 0), line, font=fnt)[2]
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += h


def box(draw, xy, title, body, fill=COL["box"]):
    rounded(draw, xy, fill)
    draw.text((xy[0] + 16, xy[1] + 12), title, font=F_BOX, fill="#111827")
    draw_text_center(draw, (xy[0] + 12, xy[1] + 45, xy[2] - 12, xy[3] - 10), body.split("\n"))


def arrow(draw, a, b, color, label=None, offset=(0, 0)):
    draw.line([a, b], fill=color, width=4)
    x1, y1 = a
    x2, y2 = b
    import math
    ang = math.atan2(y2 - y1, x2 - x1)
    s = 13
    pts = [
        (x2, y2),
        (x2 - s * math.cos(ang - math.pi / 6), y2 - s * math.sin(ang - math.pi / 6)),
        (x2 - s * math.cos(ang + math.pi / 6), y2 - s * math.sin(ang + math.pi / 6)),
    ]
    draw.polygon(pts, fill=color)
    if label:
        tx = (x1 + x2) / 2 + offset[0]
        ty = (y1 + y2) / 2 + offset[1]
        lines = label.split("\n")
        lh = draw.textbbox((0, 0), "Ag", font=F_SMALL)[3] + 6
        mw = max(draw.textbbox((0, 0), line, font=F_SMALL)[2] for line in lines)
        rounded(draw, (tx - 8, ty - 6, tx + mw + 8, ty + lh * len(lines) + 4), COL["bg"], "#CBD5E1", 1, 7)
        for i, line in enumerate(lines):
            draw.text((tx, ty + i * lh), line, font=F_SMALL, fill=COL["muted"])


def layers(draw, items):
    for name, y1, y2, color in items:
        rounded(draw, (45, y1, 1755, y2), color, "#CBD5E1", 2, 24)
        draw.text((70, y1 + 18), name, font=F_LAYER, fill="#0F172A")


def draw_architecture(path):
    img = Image.new("RGB", (1800, 1120), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "Physical Link Delay Training FSM Integration", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "Reusable branch FSM. Training frames pass through the host controller FIFO/MAC/PHY path.",
              font=F_TEXT, fill=COL["muted"])

    layers(draw, [
        ("Host Control Layer", 125, 330, COL["control"]),
        ("Training Frame Adapter / FIFO / MAC Layer", 370, 735, COL["link"]),
        ("PHY Layer", 775, 1005, COL["phy"]),
    ])

    box(draw, (90, 195, 420, 315), "Host Controller", "freeze traffic\nselect link/channel\nstart/store result")
    box(draw, (570, 180, 880, 300), "Training Branch FSM", "DELAY_REQ / DELAY_RESP\nRTT average\ntrained_path_delay")
    box(draw, (1030, 180, 1360, 300), "Training Frame Codec", "pack/unpack fixed\n8 x 16-bit words\nprotocol tag check")
    box(draw, (170, 480, 420, 585), "TX FIFO / Adapter", "accept train_tx_* fields\nselected TX reference point")
    box(draw, (525, 460, 800, 605), "CRC + Header + MAC TX", "normal controller send path\nEthernet / RS-485 / custom")
    box(draw, (1000, 460, 1275, 605), "MAC RX + CRC Check", "normal controller receive path\nCRC/protocol status")
    box(draw, (1380, 480, 1630, 585), "RX Parser / Adapter", "decoded train_rx_* fields\nselected RX reference time")
    box(draw, (420, 850, 705, 945), "Selected PHY TX", "selected channel output\npoint-to-point segment")
    box(draw, (1095, 850, 1380, 945), "Selected PHY RX", "selected channel input\npoint-to-point segment")

    arrow(draw, (420, 240), (570, 240), COL["blue"], "local_start/config", (0, -42))
    arrow(draw, (570, 270), (420, 270), COL["blue"], "busy/result", (-60, 18))
    arrow(draw, (880, 240), (1030, 240), COL["blue"], "frame fields", (0, -42))
    arrow(draw, (1030, 275), (880, 275), COL["blue"], "decoded fields", (-30, 18))
    arrow(draw, (1180, 300), (295, 480), COL["green"], "tx_payload_flat\ntrain_tx_valid", (-90, -45))
    arrow(draw, (420, 532), (525, 532), COL["green"], "FIFO read", (-15, -42))
    arrow(draw, (662, 605), (562, 850), COL["green"], "MAC frame", (20, 5))
    arrow(draw, (705, 895), (1095, 895), COL["green"], "adjacent point-to-point link", (-90, -42))
    arrow(draw, (1238, 850), (1138, 605), COL["orange"], "raw RX frame", (15, -5))
    arrow(draw, (1275, 532), (1380, 532), COL["orange"], "CRC OK", (-10, -42))
    arrow(draw, (1380, 505), (1180, 300), COL["orange"], "train_rx_* fields\ntrain_rx_ref_time", (-210, -50))
    draw.text((70, 1035), "Rule: the training FSM does not drive PHY pins directly. Host adapters map it to Ethernet, RS-485, or custom links.",
              font=F_TEXT, fill=COL["red"])
    img.save(path)


def draw_external_interface(path):
    img = Image.new("RGB", (1800, 1200), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "External Interface, Layered View", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "Internal FSM and codec hidden. Ports are grouped by host control, TX adapter, RX adapter, and MAC/PHY path.",
              font=F_TEXT, fill=COL["muted"])

    layers(draw, [
        ("Host Control Boundary", 125, 335, COL["control"]),
        ("Training FSM Block", 375, 575, COL["lltsm"]),
        ("Link/MAC Adapter Boundary", 615, 905, COL["link"]),
        ("PHY Boundary", 945, 1120, COL["phy"]),
    ])

    box(draw, (500, 185, 1300, 295), "Host Controller FSM/TOP",
        "clk/rst/training_enable/abort/time_now\nlocal_start + node/link/channel/round config\nresult capture and delay-register update")
    box(draw, (535, 430, 1265, 535), "Training FSM + Codec",
        "generates and receives fixed training frames\nmeasures trained path delay between selected reference points")
    box(draw, (110, 705, 760, 840), "TX Training-Frame Adapter",
        "inputs from FSM: train_tx_valid, frame_type, frame_words,\nsrc/dst/link/channel/round/sequence, turnaround\noutput to FSM: train_tx_ready")
    box(draw, (1040, 705, 1690, 840), "RX Training-Frame Adapter",
        "outputs to FSM: train_rx_valid, frame_complete, crc_ok,\nprotocol_ok, frame_words, src/dst/link/channel/round/sequence,\ntrain_rx_ref_time, train_rx_turnaround")
    box(draw, (325, 985, 690, 1085), "MAC/PHY TX", "normal TX path\nselected channel")
    box(draw, (1110, 985, 1475, 1085), "MAC/PHY RX", "normal RX path\nselected channel")

    arrow(draw, (900, 295), (900, 430), COL["blue"], "control/config", (18, 10))
    arrow(draw, (840, 430), (840, 295), COL["blue"], "status/result", (-135, 0))
    arrow(draw, (535, 505), (445, 705), COL["green"], "train_tx_*", (-95, -20))
    arrow(draw, (445, 840), (500, 985), COL["green"], "payload to normal TX path", (-80, 12))
    arrow(draw, (1300, 985), (1365, 840), COL["orange"], "decoded RX frame", (22, 8))
    arrow(draw, (1365, 705), (1265, 505), COL["orange"], "train_rx_* + ref time", (18, -20))
    draw.text((70, 1142), "Timing rule: train_tx_ready and train_rx_ref_time must use the same documented reference-point definition used later for compensation.",
              font=F_TEXT, fill=COL["red"])
    img.save(path)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    draw_architecture(OUT_DIR / "LLTSM_MAC_based_architecture.png")
    draw_external_interface(OUT_DIR / "LLTSM_MAC_based_external_interface.png")
    draw_architecture(OUT_DIR / "LLTSM_layered_internal_architecture.png")
    draw_external_interface(OUT_DIR / "LLTSM_external_interface_blackbox.png")
    print(f"Generated diagrams in {OUT_DIR}")


if __name__ == "__main__":
    main()
