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
    "fifo": "#ECFDF3",
    "mac": "#F0F9FF",
    "phy": "#FFF7E6",
    "box": "#FFFFFF",
    "muted": "#475569",
    "blue": "#2563EB",
    "green": "#059669",
    "orange": "#D97706",
    "red": "#DC2626",
}


def rounded(draw, xy, fill, outline="#334155", width=2, radius=18):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def draw_text_center(draw, xy, lines, fnt=F_TEXT, fill="#334155"):
    x1, y1, x2, y2 = xy
    line_h = draw.textbbox((0, 0), "Ag", font=fnt)[3] + 6
    y = y1 + ((y2 - y1) - line_h * len(lines)) / 2
    for line in lines:
        w = draw.textbbox((0, 0), line, font=fnt)[2]
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += line_h


def box(draw, xy, title, body, fill=COL["box"]):
    rounded(draw, xy, fill)
    draw.text((xy[0] + 16, xy[1] + 12), title, font=F_BOX, fill="#111827")
    draw_text_center(draw, (xy[0] + 12, xy[1] + 45, xy[2] - 12, xy[3] - 10), body.split("\n"))


def container(draw, xy, title, fill, outline="#94A3B8"):
    rounded(draw, xy, fill, outline, 2, 22)
    draw.text((xy[0] + 18, xy[1] + 14), title, font=F_LAYER, fill="#0F172A")


def arrow(draw, a, b, color, label=None, offset=(0, 0)):
    draw.line([a, b], fill=color, width=4)
    x1, y1 = a
    x2, y2 = b
    import math

    ang = math.atan2(y2 - y1, x2 - x1)
    size = 13
    pts = [
        (x2, y2),
        (x2 - size * math.cos(ang - math.pi / 6), y2 - size * math.sin(ang - math.pi / 6)),
        (x2 - size * math.cos(ang + math.pi / 6), y2 - size * math.sin(ang + math.pi / 6)),
    ]
    draw.polygon(pts, fill=color)
    if label:
        tx = (x1 + x2) / 2 + offset[0]
        ty = (y1 + y2) / 2 + offset[1]
        lines = label.split("\n")
        line_h = draw.textbbox((0, 0), "Ag", font=F_SMALL)[3] + 6
        width = max(draw.textbbox((0, 0), line, font=F_SMALL)[2] for line in lines)
        rounded(draw, (tx - 8, ty - 6, tx + width + 8, ty + line_h * len(lines) + 4), COL["bg"], "#CBD5E1", 1, 7)
        for i, line in enumerate(lines):
            draw.text((tx, ty + i * line_h), line, font=F_SMALL, fill=COL["muted"])


def draw_architecture(path):
    img = Image.new("RGB", (1800, 1120), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "物理链路时延训练状态机集成", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "LLTSM 是通信控制器内部训练子状态机；训练帧先经 FIFO/适配，再进入链路帧处理层。",
              font=F_TEXT, fill=COL["muted"])

    container(draw, (45, 125, 1755, 350), "通信控制层", COL["control"])
    container(draw, (85, 178, 1715, 325), "通信控制器 FSM/TOP", "#FFFFFF", "#64748B")
    box(draw, (120, 225, 420, 305), "业务通信主状态机", "冻结业务流量\n选择训练链路/通道")
    box(draw, (570, 205, 925, 320), "LLTSM 链路训练子状态机", "DELAY_REQ / DELAY_RESP\nRTT 均值统计\n训练路径时延")
    box(draw, (1120, 205, 1475, 320), "训练帧编解码子模块", "固定格式封装/解析\n8 x 16-bit 字\n协议标识检查")
    arrow(draw, (420, 250), (570, 250), COL["blue"], "控制器 -> LLTSM\n启动/配置/时间基准", (-75, -58))
    arrow(draw, (570, 292), (420, 292), COL["blue"], "LLTSM -> 控制器\n状态/结果", (-190, 14))
    arrow(draw, (925, 250), (1120, 250), COL["blue"], "训练帧字段", (20, -42))
    arrow(draw, (1120, 292), (925, 292), COL["blue"], "解析字段", (-60, 14))

    container(draw, (45, 390, 1755, 590), "链路训练帧适配 / FIFO 层", COL["fifo"])
    box(draw, (180, 460, 500, 555), "发送训练帧 FIFO / 适配器", "train_tx_* 字段入队\n等待 train_tx_ready")
    box(draw, (1300, 460, 1620, 555), "接收训练帧解析 / 适配器", "输出 train_rx_* 字段\n接收参考时间")
    arrow(draw, (1265, 320), (340, 460), COL["green"], "发送训练帧总线\ntrain_tx_valid", (-135, -40))
    arrow(draw, (1300, 485), (1280, 320), COL["orange"], "接收训练帧字段\ntrain_rx_ref_time", (-155, -32))

    container(draw, (45, 630, 1755, 925), "链路帧处理层（MAC / RS-485 / 自定义链路）", COL["mac"])
    box(draw, (210, 690, 545, 810), "链路发送帧处理", "封装链路地址/类型/长度\n以太网生成 FCS\nRS-485/自定义链路生成 CRC")
    box(draw, (700, 690, 1070, 810), "选定 PHY 发送端", "链路帧层底部选通\n输出到指定物理通道")
    box(draw, (1225, 690, 1560, 810), "链路接收帧处理", "接收链路帧\n校验 FCS/CRC\n输出 CRC/协议状态")
    box(draw, (700, 835, 1070, 900), "相邻点到点物理链路", "选定 PHY 发送端 -> 相邻节点 -> 选定 PHY 接收端")
    arrow(draw, (500, 508), (325, 690), COL["green"], "FIFO 出队\n训练帧载荷", (-92, 12))
    arrow(draw, (545, 750), (700, 750), COL["green"], "完整链路帧", (-10, -42))
    arrow(draw, (885, 810), (885, 835), COL["green"], "PHY 发送", (18, -8))
    arrow(draw, (1070, 868), (1225, 750), COL["orange"], "PHY 接收帧", (-20, 18))
    arrow(draw, (1225, 725), (1620, 508), COL["orange"], "CRC 正常\n解析后训练帧", (20, -30))

    container(draw, (45, 960, 1755, 1030), "物理介质 / 相邻节点", COL["phy"])
    draw.text((70, 1060), "CRC/FCS 位置：统一放在链路帧处理层；以太网使用 MAC FCS，RS-485/自定义链路使用其帧 CRC。",
              font=F_TEXT, fill=COL["red"])
    img.save(path)


def draw_external_interface(path):
    img = Image.new("RGB", (1800, 1200), COL["bg"])
    draw = ImageDraw.Draw(img)
    draw.text((50, 32), "外部接口分层视图", font=F_TITLE, fill="#111827")
    draw.text((50, 78), "通信控制器包住 LLTSM；训练帧先进入 FIFO/适配层，再进入链路帧处理层完成地址封装和 CRC/FCS。",
              font=F_TEXT, fill=COL["muted"])

    container(draw, (45, 125, 1755, 440), "通信控制器边界", COL["control"])
    box(draw, (100, 225, 520, 365), "业务通信 FSM / 调度器", "正常通信控制\n训练期间冻结业务帧\n选择邻接链路和通道")
    box(draw, (700, 205, 1130, 385), "LLTSM 训练子状态机", "接收控制器启动参数\n生成/接收固定训练帧\n输出训练状态和时延结果")
    box(draw, (1270, 225, 1650, 365), "时延结果寄存器", "result_valid / result_ok\nresult_rtt_average\nresult_mean_delay")
    arrow(draw, (520, 255), (700, 255), COL["blue"],
          "控制器 -> LLTSM 控制接口\ntraining_enable, abort, time_now\nlocal_start, local_node_id\nlocal_neighbor_node_id\nlocal_link_id, local_channel_id\nlocal_training_round_id",
          (-118, -118))
    arrow(draw, (700, 330), (520, 330), COL["blue"],
          "LLTSM -> 控制器状态/结果\nlocal_start_ready, busy, done\nresult_valid, result_ok\nresult_rtt_average, result_mean_delay\nbranch_state",
          (-250, 20))
    arrow(draw, (1130, 300), (1270, 300), COL["blue"], "结果写入", (-20, -42))

    container(draw, (45, 475, 1755, 700), "链路训练帧适配 / FIFO 层", COL["fifo"])
    box(draw, (120, 545, 760, 655), "发送训练帧 FIFO / 适配器",
        "来自 LLTSM：train_tx_valid、帧类型、帧字、源/目的节点\n链路/通道/轮次、序号、周转时间\n返回 LLTSM：train_tx_ready")
    box(draw, (1040, 545, 1680, 655), "接收训练帧解析 / 适配器",
        "送往 LLTSM：train_rx_valid、整帧完成、CRC 正常、协议正常\n帧字、源/目的节点、链路/通道/轮次、序号\n接收参考时间、响应周转时间")
    arrow(draw, (835, 385), (440, 545), COL["green"], "发送训练帧接口", (-120, -12))
    arrow(draw, (1360, 545), (1015, 385), COL["orange"], "接收训练帧接口 + 参考时间", (18, -30))

    container(draw, (45, 735, 1755, 1040), "链路帧处理层（MAC / RS-485 / 自定义链路）", COL["mac"])
    box(draw, (170, 805, 520, 925), "链路发送帧处理", "封装链路地址/类型/长度\n以太网生成 FCS\nRS-485/自定义链路生成 CRC")
    box(draw, (705, 805, 1095, 925), "选定 PHY 发送端", "链路帧层底部选通\n连接指定物理通道")
    box(draw, (1280, 805, 1630, 925), "链路接收帧处理", "接收链路帧\n校验 FCS/CRC\n输出 CRC/协议状态")
    arrow(draw, (440, 655), (345, 805), COL["green"], "训练帧载荷出队", (-80, 6))
    arrow(draw, (520, 865), (705, 865), COL["green"], "完整链路帧", (-20, -42))
    arrow(draw, (1095, 865), (1280, 865), COL["orange"], "来自选定接收通道", (-30, -42))
    arrow(draw, (1280, 835), (1360, 655), COL["orange"], "CRC 正常后上送", (24, -12))

    container(draw, (45, 1070, 1755, 1140), "物理介质 / 相邻节点", COL["phy"])
    draw.text((70, 1160), "CRC/FCS：以太网覆盖目的/源 MAC、Length/Type、Payload/Padding；RS-485 覆盖自定义地址/类型/长度/载荷；SOF/EOF/静默间隔/CRC 本身不参与。",
              font=F_TEXT, fill=COL["red"])
    img.save(path)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    draw_architecture(OUT_DIR / "LLTSM_MAC_based_architecture.png")
    draw_external_interface(OUT_DIR / "LLTSM_MAC_based_external_interface.png")
    print(f"Generated diagrams in {OUT_DIR}")


if __name__ == "__main__":
    main()
