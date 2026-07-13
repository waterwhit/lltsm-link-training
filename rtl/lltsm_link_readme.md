# lltsm_link

时间：2026-07-13

## 模块功能

生成 128 位 LLTSM 固定训练请求，识别并锁存合法远端请求，原样回显该请求，校验本地请求的精确应答，并在完整 RX 记录上锁存 CRC 结果和接收时间戳。

## 输入接口

- `clk/rst_n/clear`：模块时钟、异步低有效复位和训练上下文清除。
- `local_node_id/neighbor_node_id/selected_link_id/selected_channel_id/training_round_id/training_sequence`：稳定的训练上下文。
- `tx_req_valid/tx_rsp_valid/expect_rsp`：来自 `lltsm_fsm` 的请求、应答和接收语义控制。
- `tx_fifo_full`：TX 异宽 FIFO 反压。
- `rx_fifo_empty/rx_fifo_rd_data/rx_fifo_crc_ok/rx_fifo_timestamp`：RX 异宽 FIFO 的 FWFT 完整记录及对齐元数据。

## 输出接口

- `tx_req_ready/tx_rsp_ready`：请求和应答接收能力。
- `rx_req_valid/rx_req_timestamp`：合法远端训练请求事件和时间戳。
- `rx_rsp_valid/rx_rsp_timestamp`：与本地请求逐位一致的合法应答事件和时间戳。
- `rx_rejected`：CRC、固定字段或当前训练上下文不匹配的记录拒绝脉冲。
- `tx_fifo_wr_en/tx_fifo_wr_data/tx_fifo_link_id/tx_fifo_channel_id`：完整 128 位 TX 记录及物理路径元数据。
- `rx_fifo_rd_en`：RX FWFT 记录消费使能。

## 参数语义

- `TIME_WIDTH`：RX 时间戳宽度，必须大于零。
- `TRAIN_PAYLOAD_MAGIC`：训练帧字零协议标识，默认 `16'hD15A`。
- `TRAIN_PAYLOAD_PATTERN`：训练帧字四至字七固定图样，默认 `64'hA55A_C33C_5AA5_3CC3`。

## 本次修改内容

修复远端应答受到 TX FIFO 反压时的数据接口违规。旧逻辑使用 `rsp_write`（valid 与 ready 已握手）选择应答负载，导致 `tx_rsp_valid && !tx_rsp_ready` 期间 `tx_fifo_wr_data` 错误显示本地请求帧。新逻辑使用 `tx_rsp_valid && req_pending` 选择已锁存的远端请求，保证 valid 等待 ready 的全过程中负载稳定且语义正确。

## 状态与工作内容

本模块没有编码 FSM，使用两个上下文标志：

- 空闲：`expected_rsp_valid=0`、`req_pending=0`，允许发送本地请求或接收远端请求。
- 等待本地请求应答：本地请求写入 TX FIFO 后置 `expected_rsp_valid`；`expect_rsp=1` 时只接受与已发送 128 位负载完全一致且 CRC 正确的应答，成功后清除该标志。
- 等待回显远端请求：收到目标、链路、通道、轮次和固定字段均正确的请求后置 `req_pending`；`tx_rsp_valid` 有效时持续输出锁存负载，直到 `tx_rsp_ready` 完成握手后清除。
- 清除：`rst_n=0` 或 `clear=1` 清除两个上下文、事件输出和拒绝标志。

所有 TX valid-ready 接口在 ready 无效期间保持相应负载稳定；RX 采用 FWFT 语义，`empty=0 && rd_en=1` 的时钟沿消费记录。
