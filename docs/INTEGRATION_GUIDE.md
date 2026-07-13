LLTSM 接入指南

一、

LLTSM 包含 lltsm_fsm 和 lltsm_link 两个 RTL 模块。

lltsm_fsm 是通信总线控制器 FSM 的分支状态机。

lltsm_link 负责固定训练帧的生成、原样应答、回传帧校验和接收时间戳锁存。固定帧编解码和接收解析均在该模块内部完成。

二、

TOP 应把 LLTSM 当作一个可调用分支，不应把 LLTSM 的内部状态并入控制器状态编码。

这部分控制逻辑建议命名为 lltsm_train_scheduler，不建议命名为 top_lltsm。top_lltsm 容易被理解为完整节点顶层，而该逻辑实际只负责遍历训练项和调用 lltsm_fsm。该逻辑需要状态寄存器、计数器和时延存储，不能只用 function 实现。可嵌入 TOP 的 Verilog 参考代码位于 docs 目录中的 lltsm_train_scheduler.vh。

lltsm_train_scheduler 不建立独立的节点启动状态机。它只在通信控制器主状态机的 C_LINK_TRAIN 状态内工作，并使用 train_phase 区分选择训练项、启动训练、等待结果、超时中止和等待全网训练结束。MEDL 加载、初始化、冷启动、运行和系统故障处理仍由通信控制器主状态机完成。

上电后，控制器先检查 phy_link_up。phy_link_up 表示 PHY 已经建立物理连接，但不表示链路时延已经训练完成。

PHY 可用后，控制器检查 link_trained。link_trained 未置一时进入 LLTSM 分支。建议不要使用同一个 link_up 同时表示物理连接和训练完成。如果现有工程必须保留 link_up 名称，应将其明确定义为所有必需训练路径均已完成，并另设 phy_link_up 表示物理连接状态。

进入训练前，控制器需要取得最小启动拓扑信息，包括本地节点编号、训练对端编号、链路编号、通道编号和是否要求训练。lltsm_link 生成训练帧需要这些信息，因此不能等到训练结束后才加载全部拓扑信息。完整 MEDL 表和运行配置信息可以在训练完成后加载。

控制器处于 LLTSM 分支时，应持续使能 train_enable。收到 train_done 和 result_valid 后，只有 result_ok 有效时才能把结果写入对应时延寄存器并置位 delay_valid，然后决定训练下一条路径。训练失败时不得更新时延有效位，应根据系统要求重试、切换冗余通道或报告启动失败。

所有必需训练项的 delay_valid 均有效后，调度逻辑置位 link_up。全网训练阶段结束后，调度逻辑向通信控制器主状态机置位 lltsm_training_complete。主状态机收到该信号后退出 C_LINK_TRAIN，加载主机配置的 MEDL 表和完整配置信息，然后依次进入初始化、冷启动和运行状态。

本节点完成主动测量后，其他节点可能仍需要本节点应答训练请求。因此 link_up 置位后应继续保持 train_enable，进入仅应答等待阶段。收到中央控制器或启动协调逻辑给出的 network_training_done 后，才能产生 lltsm_training_complete。若系统没有中央协调信号，必须另外规定确定性的全网训练结束条件，不能仅根据本节点的 delay_valid 判断所有节点都已完成。

运行期间如果 PHY 掉线、拓扑配置改变或者训练结果失效，控制器必须清除受影响项的 delay_valid 和 link_trained，并重新进入训练流程。

train_enable 有效期间，TOP 必须保持节点、链路、通道和训练轮次配置稳定，并禁用普通业务流量。

三、

从拓扑角度看，应训练配置表中要求的直接训练路径，不应无条件训练所有节点组合。这里的直接训练路径是指能够完成一次 LLTSM 请求和应答的路径，不一定等于单段物理线缆。

如果两个节点之间没有交换设备，并且训练帧只经过一段物理介质，训练结果可以视为该物理链路时延。如果两个节点之间经过交换设备、TAP 或其他转发单元，训练结果是整条路径的测量值，其中包含多段物理链路和设备转发延迟，不能作为其中某一段物理链路的时延。

同一节点对的不同链路和冗余通道必须作为独立训练项保存。只使用节点编号 i 和 j 索引 delay_ij 无法区分相同节点对之间的不同通道或不同路径。

建议本地时延表按训练项编号索引。每项保存对端节点编号、链路编号、通道编号、测得时延、delay_valid 和是否为启动必需项。这样每个节点只保存与本节点相关的训练路径，不需要保存完整的全网二维矩阵。

如果中央管理设备需要任意节点对之间的端到端时延，可以收集各训练路径的测量结果，再结合实际拓扑和路由计算。存在多条路径时必须同时指定路由，不能只使用一个 delay_ij 表示。

四、

lltsm_fsm 采用四段式状态机结构。

第一段是状态更新时序逻辑。该段只更新 state。复位、train_abort 有效或者 train_enable 无效时，state 返回空闲状态；其他情况下，state 更新为 next_state。state 不允许在其他时序过程中赋值。

第二段是状态转移组合逻辑。该段根据当前 state、握手结果、计数值和接收有效信号计算 next_state。组合逻辑首先令 next_state 等于 state，随后只修改满足跳转条件的分支，从而避免锁存器。

第三段是寄存器型输出和状态数据时序逻辑。该段更新 sample_count、rsp_wait_count、req_tx_timestamp、rtt_sum、result_ok、result_rtt_average 和 result_mean_delay。各寄存器只在对应状态和有效事件下更新。

第四段是组合逻辑型状态输出。该段根据当前 state 产生 train_start_ready、train_busy、train_done、result_valid、link_tx_req_valid、link_tx_rsp_valid 和 link_expect_rsp。所有输出先设置默认值，再按状态覆盖。

请求和应答的 valid 信号由状态译码产生。在 ready 无效时，状态保持不变，因此 valid 会持续有效，直到 valid 和 ready 同时有效后才跳转，不要求 FIFO 立即接收，也不会因为单周期 ready 缺失而丢失请求。

五、FSM 与 LINK 接口

lltsm_fsm 使用以下信号调度 lltsm_link。

link_tx_req_valid 和 link_tx_req_ready 用于发送新的固定训练帧。

link_tx_rsp_valid 和 link_tx_rsp_ready 用于发送 LINK 已锁存的远端训练帧，所有数据位保持不变。

link_expect_rsp 表示当前接收帧应按本地请求的预期应答进行逐位比较。

link_training_sequence 表示每次重复测量的序号。

link_clear 用于在 TOP 中止或退出 LLTSM 分支时清除 LINK 上下文。

lltsm_link 向 lltsm_fsm 提供以下信号。

rx_req_valid 表示收到结构、目标和 CRC 均正确的远端请求。

rx_rsp_valid 表示收到与本地已发送训练负载逐位一致的应答。

rx_rsp_timestamp 表示通过校验后锁存的 MAC 接收时间戳。

rx_rejected 表示收到 CRC 或 LLTSM 负载字段不符合要求的记录，该信号仅用于诊断。

六、TX端 需添加异宽 FIFO

LLTSM 使用 TX FIFO 的宽写口。

tx_fifo_wr_en 表示写入一个完整训练帧记录。

tx_fifo_wr_data[127:0] 表示固定 128 位训练负载。

tx_fifo_full 表示 FIFO 当前不能接受新记录。

tx_fifo_link_id 用于通知 MAC 选择发送链路和 PHY。

tx_fifo_channel_id 用于通知 MAC 选择发送通道。

实际工程应实例化写宽度为 128 位、读宽度为 16 位的异宽 FIFO。MAC 从窄口依次取出八个字并产生 CRC 或 FCS，但不解析字零、保留位或固定训练图样。FIFO IP 及其读控制属于通信控制器或 MAC，不属于 LLTSM RTL。

七、RX端  需添加异宽 FIFO

MAC 完成 CRC 或 FCS 校验后，通过 RX FIFO 向 LINK 提供一个完整负载记录。MAC 不识别该负载是否为训练帧。

rx_fifo_empty 表示当前没有完整接收记录。

rx_fifo_rd_en 表示 LINK 消费当前接收记录。

rx_fifo_rd_data[127:0] 表示 MAC 去除链路字头和 CRC 后的负载。

rx_fifo_crc_ok 表示 MAC 的 CRC 或 FCS 校验结果。

rx_fifo_timestamp 表示 MAC 在规定接收参考点锁存的时间戳。

接口采用首字直通语义。rx_fifo_empty 无效时，数据和附加信息已经有效；rx_fifo_rd_en 有效时消费该记录。若具体 FIFO 只保存负载数据，应在 MAC 侧增加同步元数据 FIFO，保证 CRC 结果和时间戳与 128 位负载一一对齐。

八、固定训练帧格式

字零是固定 LLTSM 负载协议标识 TRAIN_PAYLOAD_MAGIC。

字一包含源节点编号和目的节点编号，各占八位。

字二包含训练轮次编号和训练序号，各占八位。

字三包含保留位、通道号和链路号，保留位必须全部为零。

字四至字七是固定训练图样 TRAIN_PAYLOAD_PATTERN。

远端应答直接使用收到并锁存的 128 位数据，因此协议标识和所有数据位保持不变。lltsm_link 先检查字零、保留位和字四至字七，再结合 MAC 提供的 CRC 结果完成训练帧识别。请求端还会与本次发送负载进行 128 位精确比较，从而拒绝旧轮次、错误序号或内容损坏的应答。

九、CRC 与字头职责

LLTSM 不产生也不计算链路 CRC 或 FCS。

MAC 负责 CRC 或 FCS 的生成与校验，并通过 rx_fifo_crc_ok 上送校验结果。MAC 还负责发送 PHY 和通道选择，以及接收时间戳参考点的实现。

lltsm_link 负责训练帧字段识别，包括检查字零等于 TRAIN_PAYLOAD_MAGIC、保留位全部为零、字四至字七等于 TRAIN_PAYLOAD_PATTERN，以及节点、链路、通道、轮次和应答负载符合当前训练上下文。

十、时延结果限制

训练应答负载必须保持不变，因此目前无法在应答帧内回传远端实际应答处理时间。

result_mean_delay 的计算方法是先用平均往返时间减去 RSP_COMPENSATION_CYCLES，再除以二。

只有远端应答路径固定且已经标定时，RSP_COMPENSATION_CYCLES 才能用于得到补偿后的单向训练路径时延。默认值为零，此时结果包含一半远端处理延迟。
