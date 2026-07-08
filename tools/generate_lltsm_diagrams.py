from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math


ROOT = Path(r"C:\Users\Autol\Desktop\ttp-project")
OUT_DIR = ROOT / "TTP审查交付" / "LLTSM_Architecture_Images_2026-07-07"


FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
    r"C:\Windows\Fonts\arial.ttf",
]

BOLD_FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
]


def pick_font(candidates):
    for item in candidates:
        if Path(item).exists():
            return item
    return None


FONT_PATH = pick_font(FONT_CANDIDATES)
BOLD_FONT_PATH = pick_font(BOLD_FONT_CANDIDATES) or FONT_PATH


def font(size, bold=False):
    path = BOLD_FONT_PATH if bold else FONT_PATH
    if path:
        return ImageFont.truetype(path, size)
    return ImageFont.load_default()


F_TITLE = font(34, True)
F_LAYER = font(25, True)
F_BOX = font(21, True)
F_TEXT = font(17)
F_SMALL = font(15)

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


def text_size(draw, text, fnt):
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def wrap_text(draw, text, fnt, max_width):
    lines = []
    for para in text.split("\n"):
        words = para.split(" ")
        current = ""
        for word in words:
            test = word if not current else current + " " + word
            if text_size(draw, test, fnt)[0] <= max_width or not current:
                current = test
            else:
                lines.append(current)
                current = word
        if current:
            lines.append(current)
    return lines


def rounded_box(draw, box, fill, outline=COL["stroke"], width=2, radius=18):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def draw_centered(draw, box, lines, fnt, fill="#111827", line_gap=5):
    x1, y1, x2, y2 = box
    line_h = text_size(draw, "Ag", fnt)[1] + 4
    total_h = len(lines) * line_h + max(0, len(lines) - 1) * line_gap
    y = y1 + (y2 - y1 - total_h) / 2
    for line in lines:
        w, _ = text_size(draw, line, fnt)
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += line_h + line_gap


def draw_box(draw, box, title, body, fill=COL["box"]):
    rounded_box(draw, box, fill, "#334155", 2, 18)
    draw.text((box[0] + 16, box[1] + 14), title, font=F_BOX, fill="#111827")
    lines = wrap_text(draw, body, F_TEXT, box[2] - box[0] - 32)
    draw_centered(draw, (box[0] + 16, box[1] + 48, box[2] - 16, box[3] - 12), lines, F_TEXT, "#334155")


def arrow(draw, start, end, color=COL["stroke"], width=3, label=None, label_offset=(0, 0), label_t=0.5):
    draw.line([start, end], fill=color, width=width)
    x1, y1 = start
    x2, y2 = end
    angle = math.atan2(y2 - y1, x2 - x1)
    size = 13
    pts = [
        (x2, y2),
        (x2 - size * math.cos(angle - math.pi / 6), y2 - size * math.sin(angle - math.pi / 6)),
        (x2 - size * math.cos(angle + math.pi / 6), y2 - size * math.sin(angle + math.pi / 6)),
    ]
    draw.polygon(pts, fill=color)
    if label:
        tx = x1 + (x2 - x1) * label_t + label_offset[0]
        ty = y1 + (y2 - y1) * label_t + label_offset[1]
        lines = label.split("\n")
        line_h = text_size(draw, "Ag", F_SMALL)[1] + 5
        max_w = max(text_size(draw, line, F_SMALL)[0] for line in lines)
        draw.rounded_rectangle((tx - 8, ty - 6, tx + max_w + 8, ty + line_h * len(lines) + 6),
                               radius=6, fill=COL["bg"], outline="#CBD5E1")
        for i, line in enumerate(lines):
            draw.text((tx, ty + i * line_h), line, font=F_SMALL, fill=COL["muted"])


def draw_layer_headers(draw, layers):
    for title, y1, y2, fill in layers:
        rounded_box(draw, (45, y1, 1755, y2), fill, "#CBD5E1", 2, 24)
        draw.text((70, y1 + 18), title, font=F_LAYER, fill="#0F172A")


def draw_mac_based_architecture(path):
    img = Image.new("RGB", (1800, 1120), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "LLTSM MAC/FIFO-based Integration Architecture", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "The LLTSM generates fixed training frames. CRC, address/header insertion, MAC framing and PHY transfer stay in the normal controller path.",
              font=F_TEXT, fill=COL["muted"])

    layers = [
        ("Control Layer", 125, 330, COL["control"]),
        ("Training Frame Adapter / FIFO / MAC Layer", 370, 735, COL["link"]),
        ("PHY Layer", 775, 1005, COL["phy"]),
    ]
    draw_layer_headers(draw, layers)

    boxes = {
        "top": (90, 195, 420, 315),
        "fsm": (570, 180, 880, 300),
        "codec": (1030, 180, 1360, 300),
        "tx_fifo": (170, 480, 420, 585),
        "tx_mac": (525, 460, 800, 605),
        "rx_mac": (1000, 460, 1275, 605),
        "rx_parser": (1380, 480, 1630, 585),
        "phy_tx": (420, 850, 705, 945),
        "phy_rx": (1095, 850, 1380, 945),
    }

    draw_box(draw, boxes["top"], "Controller TOP", "freeze traffic\nselect link/channel\nstart/store result")
    draw_box(draw, boxes["fsm"], "LLTSM Branch FSM", "DELAY_REQ / DELAY_RESP\nRTT average\ntrained_path_delay")
    draw_box(draw, boxes["codec"], "Training Frame Codec", "pack/unpack fixed\n8 x 16-bit words\nprotocol tag check")
    draw_box(draw, boxes["tx_fifo"], "TX FIFO / Adapter", "accept train_tx_* fields\nselected TX reference point")
    draw_box(draw, boxes["tx_mac"], "CRC + Header + MAC TX", "normal controller send path\nEthernet or RS-485 framing")
    draw_box(draw, boxes["rx_mac"], "MAC RX + CRC Check", "normal controller receive path\nCRC/protocol status")
    draw_box(draw, boxes["rx_parser"], "RX Parser / Adapter", "decoded train_rx_* fields\nselected RX reference time")
    draw_box(draw, boxes["phy_tx"], "Selected PHY TX", "A/B channel output\npoint-to-point segment")
    draw_box(draw, boxes["phy_rx"], "Selected PHY RX", "A/B channel input\npoint-to-point segment")

    arrow(draw, (420, 240), (570, 240), COL["blue"], 3, "local_start/config", (0, -34), 0.20)
    arrow(draw, (570, 270), (420, 270), COL["blue"], 3, "busy/result", (-10, 20), 0.05)
    arrow(draw, (880, 240), (1030, 240), COL["blue"], 3, "frame fields", (0, -34), 0.12)
    arrow(draw, (1030, 275), (880, 275), COL["blue"], 3, "decoded fields", (-5, 20), 0.10)

    arrow(draw, (1180, 300), (295, 480), COL["green"], 4, "tx_payload_flat\ntrain_tx_valid", (-80, -45), 0.45)
    arrow(draw, (420, 532), (525, 532), COL["green"], 4, "FIFO read", (0, -35), 0.20)
    arrow(draw, (662, 605), (562, 850), COL["green"], 4, "MAC frame", (20, 10), 0.40)
    arrow(draw, (705, 895), (1095, 895), COL["green"], 4, "adjacent point-to-point link", (-40, -36), 0.40)
    arrow(draw, (1238, 850), (1138, 605), COL["orange"], 4, "raw RX frame", (24, 0), 0.35)
    arrow(draw, (1275, 532), (1380, 532), COL["orange"], 4, "CRC OK", (0, -35), 0.20)
    arrow(draw, (1380, 505), (1180, 300), COL["orange"], 4, "train_rx_* fields\ntrain_rx_ref_time", (-210, -50), 0.35)

    draw.text((70, 1035), "Rule: LLTSM does not drive the PHY directly. It connects to the training-frame adapter; MAC/PHY are selected by the normal controller path.",
              font=F_TEXT, fill=COL["red"])
    img.save(path)


def draw_external_interface(path):
    img = Image.new("RGB", (1800, 1200), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "LLTSM External Interface, Layered View", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "Internal FSM and codec are hidden. Ports are grouped by Control, TX training-frame adapter, RX training-frame adapter, and MAC/PHY path.",
              font=F_TEXT, fill=COL["muted"])

    layers = [
        ("Control Layer Boundary", 125, 335, COL["control"]),
        ("LLTSM Branch Block", 375, 575, COL["lltsm"]),
        ("Link/MAC Adapter Boundary", 615, 905, COL["link"]),
        ("PHY Boundary", 945, 1120, COL["phy"]),
    ]
    draw_layer_headers(draw, layers)

    draw_box(draw, (500, 185, 1300, 295), "Controller TOP",
             "clk/rst/training_enable/abort/time_now\nlocal_start + node/link/channel/round config\nresult capture and delay-register update")
    draw_box(draw, (535, 430, 1265, 535), "LLTSM Branch FSM + Codec",
             "generates and receives fixed training frames\nmeasures trained path delay between selected reference points")
    draw_box(draw, (110, 705, 760, 840), "TX Training-Frame Adapter",
             "inputs from LLTSM: train_tx_valid, frame_type, frame_words,\nsrc/dst/link/channel/round/sequence, turnaround\noutput to LLTSM: train_tx_ready")
    draw_box(draw, (1040, 705, 1690, 840), "RX Training-Frame Adapter",
             "outputs to LLTSM: train_rx_valid, frame_complete, crc_ok,\nprotocol_ok, frame_words, src/dst/link/channel/round/sequence,\ntrain_rx_ref_time, train_rx_turnaround")
    draw_box(draw, (325, 985, 690, 1085), "MAC/PHY TX", "normal TX path\nselected A/B channel")
    draw_box(draw, (1110, 985, 1475, 1085), "MAC/PHY RX", "normal RX path\nselected A/B channel")

    arrow(draw, (900, 295), (900, 430), COL["blue"], 4, "control/config", (18, 10), 0.35)
    arrow(draw, (840, 430), (840, 295), COL["blue"], 4, "status/result", (-135, 0), 0.45)
    arrow(draw, (535, 505), (445, 705), COL["green"], 4, "train_tx_*", (-95, -20), 0.40)
    arrow(draw, (445, 840), (500, 985), COL["green"], 4, "payload to normal TX path", (-80, 12), 0.45)
    arrow(draw, (1300, 985), (1365, 840), COL["orange"], 4, "decoded RX frame", (22, 8), 0.42)
    arrow(draw, (1365, 705), (1265, 505), COL["orange"], 4, "train_rx_* + ref time", (18, -20), 0.38)

    draw.text((70, 1142), "Timing rule: train_tx_ready and train_rx_ref_time must use the same documented controller reference-point definition used later for compensation.",
              font=F_TEXT, fill=COL["red"])
    img.save(path)


def draw_layered_internal(path):
    img = Image.new("RGB", (1800, 1180), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "Current LLTSM Internal Architecture", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "Top-to-bottom structure: control layer, independent TX/RX link paths, and physical transceiver layer.",
              font=F_TEXT, fill=COL["muted"])

    layers = [
        ("Control Layer", 125, 430, COL["control"]),
        ("Link Layer: independent TX and RX paths", 470, 790, COL["link"]),
        ("Physical Transceiver Layer", 830, 1060, COL["phy"]),
    ]
    draw_layer_headers(draw, layers)

    draw_box(draw, (90, 210, 420, 345), "Controller TOP", "freeze business frames\nselect one adjacent link\nselect A/B channel")
    draw_box(draw, (560, 190, 880, 365), "LLTSM Branch FSM", "start/response branch\nDELAY_REQ/DELAY_RESP\naverage RTT")
    draw_box(draw, (1030, 190, 1360, 365), "Training Codec", "fixed frame fields\nprotocol tag/type check")
    draw_box(draw, (1450, 210, 1710, 345), "Adjacent Node", "no direct FSM-to-FSM wires\nonly training frames")
    draw_box(draw, (200, 570, 720, 705), "TX Link Path", "TX FIFO/frame builder\nCRC/FCS/header/MAC control")
    draw_box(draw, (1080, 570, 1600, 705), "RX Link Path", "MAC RX/parser/CRC check\nRX reference timestamp")
    draw_box(draw, (200, 910, 720, 1005), "PHY TX", "selected channel A/B")
    draw_box(draw, (1080, 910, 1600, 1005), "PHY RX", "selected channel A/B")

    arrow(draw, (420, 255), (560, 255), COL["blue"], 3, "control", (0, -34), 0.15)
    arrow(draw, (560, 320), (420, 320), COL["blue"], 3, "result", (-20, 20), 0.10)
    arrow(draw, (880, 255), (1030, 255), COL["blue"], 3, "fields", (0, -34), 0.12)
    arrow(draw, (1030, 320), (880, 320), COL["blue"], 3, "decoded", (-5, 20), 0.10)
    arrow(draw, (1160, 365), (460, 570), COL["green"], 4, "TX training frame", (-80, -45), 0.45)
    arrow(draw, (460, 705), (460, 910), COL["green"], 4, "normal TX path", (20, 0), 0.40)
    arrow(draw, (720, 955), (1450, 285), COL["green"], 4, "point-to-point link", (-35, -45), 0.44)
    arrow(draw, (1450, 310), (1600, 955), COL["orange"], 4, "return direction", (20, -10), 0.38)
    arrow(draw, (1340, 910), (1340, 705), COL["orange"], 4, "normal RX path", (18, -10), 0.40)
    arrow(draw, (1210, 570), (1210, 365), COL["orange"], 4, "RX frame + ref time", (18, -20), 0.35)

    img.save(path)


def draw_external_blackbox(path):
    img = Image.new("RGB", (1800, 1120), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "LLTSM External Interface Blackbox", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "Signal groups and direction relative to the LLTSM branch module.",
              font=F_TEXT, fill=COL["muted"])

    draw_box(draw, (660, 410, 1140, 645), "LLTSM Branch Block",
             "ttp_lltsm_branch_fsm.sv\n+ ttp_lltsm_branch_codec.sv")
    draw_box(draw, (80, 140, 560, 330), "Control Inputs",
             "clk, rst_n, training_enable, abort, time_now\nlocal_start, local_node_id,\nlocal_neighbor_node_id, local_link_id,\nlocal_channel_id, local_training_round_id")
    draw_box(draw, (1240, 140, 1720, 330), "Control Outputs",
             "local_start_ready, busy, done,\nresult_valid, result_ok,\nresult_rtt_average, result_mean_delay,\nbranch_state")
    draw_box(draw, (80, 735, 560, 970), "TX Adapter Interface",
             "LLTSM outputs: train_tx_valid,\ntrain_tx_frame_type, train_tx_frame_words,\ntrain_tx_src/dst_node_id, train_tx_link_id,\ntrain_tx_channel_id, train_tx_training_round_id,\ntrain_tx_sequence, train_tx_turnaround\nAdapter input: train_tx_ready")
    draw_box(draw, (1240, 735, 1720, 970), "RX Adapter Interface",
             "Adapter outputs: train_rx_valid,\ntrain_rx_frame_complete, train_rx_crc_ok,\ntrain_rx_protocol_ok, train_rx_frame_type,\ntrain_rx_frame_words, train_rx_src/dst_node_id,\ntrain_rx_link_id, train_rx_channel_id,\ntrain_rx_training_round_id, train_rx_sequence,\ntrain_rx_ref_time, train_rx_turnaround")

    arrow(draw, (560, 235), (660, 455), COL["blue"], 4, "TOP -> LLTSM", (8, -20), 0.36)
    arrow(draw, (1140, 455), (1240, 235), COL["blue"], 4, "LLTSM -> TOP", (-110, -20), 0.40)
    arrow(draw, (660, 580), (560, 850), COL["green"], 4, "LLTSM -> TX adapter", (-170, -20), 0.45)
    arrow(draw, (1240, 850), (1140, 580), COL["orange"], 4, "RX adapter -> LLTSM", (18, -20), 0.45)

    img.save(path)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    draw_mac_based_architecture(OUT_DIR / "LLTSM_MAC_based_architecture.png")
    draw_external_interface(OUT_DIR / "LLTSM_MAC_based_external_interface.png")
    draw_layered_internal(OUT_DIR / "LLTSM_layered_internal_architecture.png")
    draw_external_blackbox(OUT_DIR / "LLTSM_external_interface_blackbox.png")
    print(f"Generated LLTSM diagrams in {OUT_DIR}")


if __name__ == "__main__":
    main()
