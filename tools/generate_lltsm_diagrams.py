from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "images"

COLORS = {
    "bg": "#F8FAFC",
    "ink": "#0F172A",
    "muted": "#475569",
    "line": "#334155",
    "blue": "#2563EB",
    "green": "#059669",
    "orange": "#D97706",
    "red": "#DC2626",
    "control": "#EAF2FF",
    "link": "#ECFDF3",
    "mac": "#FFF7E6",
    "white": "#FFFFFF",
}


def font(size, bold=False):
    candidates = [
        Path(r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


TITLE = font(34, True)
LAYER = font(24, True)
BOX_TITLE = font(20, True)
TEXT = font(16)
SMALL = font(14)


def centered_lines(draw, rect, lines, text_font=TEXT, color=COLORS["ink"]):
    x1, y1, x2, y2 = rect
    spacing = 8
    boxes = [draw.textbbox((0, 0), line, font=text_font) for line in lines]
    heights = [box[3] - box[1] for box in boxes]
    total = sum(heights) + spacing * max(0, len(lines) - 1)
    y = y1 + (y2 - y1 - total) / 2
    for line, box, height in zip(lines, boxes, heights):
        width = box[2] - box[0]
        draw.text((x1 + (x2 - x1 - width) / 2, y), line, font=text_font, fill=color)
        y += height + spacing


def box(draw, rect, title, lines, outline=COLORS["line"], fill=COLORS["white"]):
    draw.rounded_rectangle(rect, radius=8, fill=fill, outline=outline, width=3)
    x1, y1, x2, _ = rect
    title_box = draw.textbbox((0, 0), title, font=BOX_TITLE)
    title_width = title_box[2] - title_box[0]
    draw.text((x1 + (x2 - x1 - title_width) / 2, y1 + 14), title, font=BOX_TITLE, fill=COLORS["ink"])
    centered_lines(draw, (x1 + 14, y1 + 52, x2 - 14, rect[3] - 12), lines)


def layer(draw, rect, title, fill):
    draw.rounded_rectangle(rect, radius=12, fill=fill, outline="#94A3B8", width=2)
    draw.text((rect[0] + 18, rect[1] + 14), title, font=LAYER, fill=COLORS["ink"])


def arrow(draw, start, end, color, label=None, label_pos=None, both=False):
    draw.line([start, end], fill=color, width=4)
    import math

    def head(point, angle):
        size = 14
        x, y = point
        points = [
            (x, y),
            (x - size * math.cos(angle - math.pi / 6), y - size * math.sin(angle - math.pi / 6)),
            (x - size * math.cos(angle + math.pi / 6), y - size * math.sin(angle + math.pi / 6)),
        ]
        draw.polygon(points, fill=color)

    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    head(end, angle)
    if both:
        head(start, angle + math.pi)
    if label:
        x, y = label_pos or ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
        bbox = draw.multiline_textbbox((0, 0), label, font=SMALL, spacing=5, align="center")
        width = bbox[2] - bbox[0]
        height = bbox[3] - bbox[1]
        draw.rounded_rectangle((x - width / 2 - 8, y - height / 2 - 5,
                                x + width / 2 + 8, y + height / 2 + 5),
                               radius=5, fill=COLORS["bg"], outline="#CBD5E1", width=1)
        draw.multiline_text((x - width / 2, y - height / 2), label, font=SMALL,
                            fill=COLORS["muted"], spacing=5, align="center")


def header(draw, title, subtitle):
    draw.text((50, 30), title, font=TITLE, fill=COLORS["ink"])
    draw.text((50, 82), subtitle, font=TEXT, fill=COLORS["muted"])


def architecture(path):
    image = Image.new("RGB", (1800, 1200), COLORS["bg"])
    draw = ImageDraw.Draw(image)
    header(draw, "LLTSM 两模块集成架构",
           "控制器 TOP 管理分支跳转；LLTSM_LINK 处理固定训练帧；链路字头与 CRC/FCS 由 MAC 完成。")

    layer(draw, (45, 130, 1755, 470), "通信总线控制器", COLORS["control"])
    box(draw, (100, 220, 520, 405), "控制器 TOP / 主 FSM",
        ["进入/退出训练分支", "冻结业务流量并保持配置", "超时、中止与结果存储"])
    box(draw, (690, 220, 1110, 405), "LLTSM_FSM",
        ["分支状态调度", "重复测量与 RTT 均值", "branch_done 上报 TOP"], COLORS["blue"])
    box(draw, (1280, 220, 1700, 405), "LLTSM_LINK",
        ["生成固定 128-bit TRAIN_FRAME", "原样应答与精确比较", "校验后锁存接收时间戳"], COLORS["green"])
    arrow(draw, (520, 310), (690, 310), COLORS["blue"], "分支控制 / 状态结果", (605, 275), True)
    arrow(draw, (1110, 310), (1280, 310), COLORS["green"], "发送命令 / 接收事件", (1195, 275), True)

    layer(draw, (45, 520, 1755, 805), "FIFO 与 MAC 边界", COLORS["link"])
    box(draw, (100, 610, 500, 750), "TX 异宽 FIFO",
        ["LLTSM：128-bit 宽写口", "MAC：本地位宽读口", "完整负载一次入队"])
    box(draw, (700, 590, 1100, 770), "MAC / 链路帧处理",
        ["添加/识别训练特殊字头", "地址、长度、填充", "CRC/FCS 与 PHY 选择"], COLORS["orange"])
    box(draw, (1300, 610, 1700, 750), "RX 异宽 FIFO",
        ["MAC：本地位宽写口", "LLTSM：128-bit 宽读口", "CRC 状态和时间戳对齐"])
    arrow(draw, (1490, 405), (300, 610), COLORS["green"], "128-bit 宽写", (870, 490))
    arrow(draw, (500, 680), (700, 680), COLORS["green"], "窄口出队")
    arrow(draw, (1100, 680), (1300, 680), COLORS["orange"], "去除字头与 CRC")
    arrow(draw, (1500, 610), (1510, 405), COLORS["orange"], "负载 + 状态 + 时间戳", (1595, 505))

    layer(draw, (45, 850, 1755, 1030), "物理层", COLORS["mac"])
    box(draw, (650, 900, 1150, 995), "选定 PHY 与相邻节点", ["训练帧沿现有业务链路收发"])
    arrow(draw, (900, 770), (900, 900), COLORS["orange"], "完整链路帧", (1000, 835), True)

    note = ("固定应答：训练帧类别不变，128-bit 负载逐位不变。负载中不携带 turnaround；"
            "若需要单向时延，必须标定固定应答补偿参数。")
    draw.text((80, 1080), note, font=TEXT, fill=COLORS["red"])
    image.save(path)


def external_interface(path):
    image = Image.new("RGB", (1800, 1200), COLORS["bg"])
    draw = ImageDraw.Draw(image)
    header(draw, "LLTSM 两模块外部接口",
           "异宽 FIFO 是控制器基础设施，不是额外 LLTSM 收发适配模块。")

    box(draw, (80, 160, 520, 390), "通信控制器 TOP",
        ["branch_enable / start / abort", "time_now 与稳定配置", "接收 branch_done / result_*"] , fill=COLORS["control"])
    box(draw, (680, 140, 1120, 410), "LLTSM_FSM",
        ["request / echo valid-ready", "expect_response", "training_sequence", "接收有效事件与时间戳"], COLORS["blue"])
    box(draw, (1280, 160, 1720, 390), "LLTSM_LINK",
        ["固定帧生成与锁存", "结构/目标/CRC 状态检查", "128-bit 应答精确比较"], COLORS["green"], COLORS["link"])
    arrow(draw, (520, 275), (680, 275), COLORS["blue"], "分支控制 / 结果", (600, 240), True)
    arrow(draw, (1120, 275), (1280, 275), COLORS["green"], "命令 / 校验事件", (1200, 240), True)

    box(draw, (100, 560, 560, 790), "TX FIFO 宽写侧",
        ["tx_fifo_full / wr_en", "tx_fifo_wr_data[127:0]", "train_frame / link_id / channel_id"])
    box(draw, (670, 540, 1130, 810), "MAC / 链路帧处理",
        ["窄口读取/写入 FIFO", "特殊字头、地址、长度与填充", "CRC/FCS、PHY 选择、RX 时间戳"], COLORS["orange"], COLORS["mac"])
    box(draw, (1240, 560, 1700, 790), "RX FIFO 宽读侧（FWFT）",
        ["empty / rd_en", "rx_fifo_rd_data[127:0]", "train_frame / crc_ok / timestamp"])
    arrow(draw, (1500, 390), (330, 560), COLORS["green"], "完整负载宽写", (900, 475))
    arrow(draw, (560, 675), (670, 675), COLORS["green"], "MAC 窄读")
    arrow(draw, (1130, 675), (1240, 675), COLORS["orange"], "MAC 窄写")
    arrow(draw, (1470, 560), (1500, 390), COLORS["orange"], "宽读 + 对齐 sideband", (1580, 475))

    box(draw, (600, 900, 1200, 1080), "固定 128-bit TRAIN_FRAME",
        ["字0：固定协议标识    字1：源/目的节点", "字2：轮次/序号    字3：通道/链路", "字4..7：固定训练图样"])
    draw.text((240, 1135),
              "MAC 链路字头和 CRC/FCS 不属于 TRAIN_FRAME；应答复用相同帧类别，并逐位原样回送全部负载。",
              font=TEXT, fill=COLORS["red"])
    image.save(path)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    architecture(OUT / "LLTSM_MAC_based_architecture.png")
    external_interface(OUT / "LLTSM_MAC_based_external_interface.png")
    print(f"Generated diagrams in {OUT}")


if __name__ == "__main__":
    main()
