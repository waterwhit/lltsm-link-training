# tb_lltsm_boundary

时间：2026-07-13

## 模块功能

验证 `lltsm_fsm` 与 `lltsm_link` 在数据接口反压、CRC/字段错误、无响应、控制器中止、远端应答和时间计数器回卷条件下的边界与故障行为。

## 输入接口

测试平台直接驱动 `train_enable/train_start/train_abort`、TX FIFO `full` 和 RX FIFO 的 128 位记录、CRC 结果及接收时间戳。

## 输出接口

检查 FSM 状态、训练结果、TX FIFO valid-ready 握手、链路元数据、拒绝事件和精确回显负载。

## 参数语义

- `TIME_WIDTH=8`：缩短时间计数器回卷测试。
- `MEASURE_REPEATS=1`：每次场景用单次 RTT 完成。
- `RSP_WAIT=2`：远端收到请求后等待两个时钟周期再应答。
- `RSP_COMPENSATION_CYCLES=0`：不扣除远端固定响应时间。

## 本次修改内容

新增边界和故障测试，不修改被测 RTL。

## 测试阶段、输出和跳转条件

- 复位：释放 `rst_n` 后使能训练分支。
- 请求反压：FIFO 满时要求请求 valid 和 128 位负载保持，FIFO 可用后完成握手。
- 错帧拒绝：分别注入 CRC 错误和字段错误，要求保持 `S_WAIT_RSP`。
- 无响应：确认 `S_WAIT_RSP` 持续等待，由 TOP 负责超时中止。
- 正常响应：注入精确回显，要求进入 `S_DONE` 并产生有效 RTT。
- 控制中止：`train_abort` 或撤销 `train_enable` 后返回 `S_IDLE`。
- 远端应答反压：`S_SEND_RSP` 保持 valid 和原始负载，直到 FIFO ready。
- 计数回卷：请求在计数器回卷前发送、回卷后接收，检查模运算 RTT。
