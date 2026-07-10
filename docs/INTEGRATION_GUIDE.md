# LLTSM 接入指南

## 1. 模块边界

LLTSM 只包含两个 RTL 模块：

```text
lltsm_fsm  <->  lltsm_link
```

`lltsm_fsm` 是通信总线控制器 FSM 的分支状态机。通信控制器 TOP 决定何时
进入训练分支、何时中止以及何时根据 `train_done` 返回业务状态。

`lltsm_link` 负责固定训练帧的生成、原样应答、回传帧校验和接收时间戳锁存。
固定帧编解码、发送格式化和接收解析均在该模块内部完成，不需要额外适配器。

## 2. 控制器 TOP 中的状态跳转

TOP 应把 LLTSM 当作一个可调用分支，而不是把 LLTSM 状态并入业务状态编码：

```systemverilog
case (controller_state)
    C_NORMAL: begin
        if (start_link_training)
            controller_state <= C_LLTSM;
    end

    C_LLTSM: begin
        lltsm_train_enable = 1'b1;
        if (lltsm_train_done) begin
            // 锁存 result_*，再由 TOP 决定下一条链路或返回业务态。
            controller_state <= C_NORMAL;
        end else if (controller_watchdog_timeout) begin
            lltsm_train_abort = 1'b1;
            controller_state <= C_NORMAL;
        end
    end
endcase
```

TOP 在 `train_enable=1` 期间必须保持节点、链路、通道和训练轮次配置稳定，并
冻结会影响训练 FIFO 排队时间的普通业务流量。

## 3. FSM 与 LINK 接口

`lltsm_fsm` 使用以下命令调度 `lltsm_link`：

- `link_tx_req_valid/ready`：发送新的固定训练帧；
- `link_tx_rsp_valid/ready`：发送 LINK 已锁存的远端训练帧，所有位保持不变；
- `link_expect_rsp`：当前接收帧按本地请求的预期应答进行逐位比较；
- `link_training_sequence`：每次重复测量的序号；
- `link_clear`：TOP 中止或退出 LLTSM 分支时清除 LINK 上下文。

`lltsm_link` 向 FSM 提供：

- `rx_req_valid`：收到结构、目标和 CRC 均正确的远端请求；
- `rx_rsp_valid`：收到与本地已发送训练负载逐位一致的应答；
- `rx_rsp_timestamp`：通过校验后锁存的 MAC 接收时间戳；
- `rx_rejected`：收到 CRC 或 LLTSM 负载字段不符合要求的记录，仅用于诊断。

## 4. TX 异宽 FIFO

LLTSM 使用 TX FIFO 的宽写口：

| 信号 | 含义 |
|---|---|
| `tx_fifo_wr_en` | 写入一个完整训练帧记录 |
| `tx_fifo_wr_data[127:0]` | 固定 128-bit `TRAIN_FRAME` 负载 |
| `tx_fifo_full` | FIFO 不能接受新记录 |
| `tx_fifo_link_id` | MAC 选择发送链路/PHY |
| `tx_fifo_channel_id` | MAC 选择 A/B 通道 |

实际工程应实例化类似 `128-bit write / 16-bit read` 的异宽 FIFO。MAC 从窄口
取出 8 个字并产生 CRC/FCS，但不解析字 0、保留位或固定训练图样。FIFO IP
及其读控制属于通信控制器/MAC，不属于 LLTSM RTL。

## 5. RX 异宽 FIFO

MAC 完成 CRC/FCS 校验后，通过 RX FIFO 向 LINK 提供一个完整负载记录。MAC 不
识别该负载是否为训练帧：

| 信号 | 含义 |
|---|---|
| `rx_fifo_empty` | 无完整训练帧记录 |
| `rx_fifo_rd_en` | LINK 读取当前记录 |
| `rx_fifo_rd_data[127:0]` | MAC 去除链路字头和 CRC 后的负载 |
| `rx_fifo_crc_ok` | MAC 的 CRC/FCS 校验结果 |
| `rx_fifo_timestamp` | MAC 选定接收参考点的时间戳 |

接口采用 FWFT 语义：`empty=0` 时数据和 sideband 已有效，`rd_en` 消费该记录。
若具体 FIFO 只有负载数据，应在 MAC 侧用同步元数据 FIFO 保证 CRC 结果和时间戳
与 128-bit 负载一一对齐。

## 6. 固定训练帧格式

| 16-bit 字 | 内容 |
|---:|---|
| 0 | 固定 LLTSM 负载协议标识 `TRAIN_PAYLOAD_MAGIC` |
| 1 | `source_node_id[7:0]`, `destination_node_id[7:0]` |
| 2 | `training_round_id[7:0]`, `training_sequence[7:0]` |
| 3 | 保留位、通道号、链路号 |
| 4..7 | 固定训练图样 `TRAIN_PAYLOAD_PATTERN` |

远端应答直接使用收到并锁存的 128-bit 数据，因此协议标识和所有数据位不变。
LLTSM_LINK 先检查字 0、保留位和字 4～7，再结合 MAC 的 CRC 结果完成训练帧
识别；请求端还会与本次发送负载进行 128-bit 精确比较，可拒绝旧轮次、错误序号
或内容损坏的应答。

## 7. CRC 与字头职责

LLTSM 不产生也不计算链路 CRC/FCS。MAC 负责：

- CRC/FCS 生成与校验，并上送 `rx_fifo_crc_ok`；
- 发送 PHY/通道选择；
- 接收时间戳参考点的实现。

LLTSM_LINK 负责训练帧字段识别：

- 字 0 等于 `TRAIN_PAYLOAD_MAGIC`；
- 保留位 `[63:57]` 全部为 0；
- 字 4～7 等于 `TRAIN_PAYLOAD_PATTERN`；
- 节点、链路、通道、轮次和应答负载符合当前训练上下文。

## 8. 时延结果限制

训练应答负载必须保持不变，因此无法在应答帧内回传远端实际 turnaround。
`lltsm_fsm` 使用：

```text
result_mean_delay =
    (average_RTT - RSP_COMPENSATION_CYCLES) / 2
```

只有远端应答路径固定且已标定时，`RSP_COMPENSATION_CYCLES` 才能把结果解释
为补偿后的单向训练路径时延。默认值为 0，此时结果包含一半远端处理延迟。
