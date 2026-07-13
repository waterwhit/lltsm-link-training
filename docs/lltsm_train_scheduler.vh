/*
插入通信控制器 TOP，作为 C_LINK_TRAIN 状态中的训练调度逻辑。
本文件不是独立 module，不需要单独实例化，应放在 TOP module 内部。

TOP 控制输入：
input clk,                                      // 控制器工作时钟
input rst_n,                                    // 低电平异步复位
input [31:0] time_now,                          // 自由运行时间计数器
input controller_in_link_train,                 // 主状态机处于 C_LINK_TRAIN
input lltsm_scheduler_clear,                    // 清除调度状态和已有训练结果
input topology_changed,                         // 启动拓扑或链路配置发生变化
input bootstrap_cfg_valid,                      // 最小启动拓扑配置已经有效
input network_training_done,                    // 全网训练阶段已经结束
input [LLTSM_ENTRY_NUM-1:0] phy_link_up,         // 每个训练项的 PHY 状态

主机启动配置输入：
input [LLTSM_ENTRY_NUM-1:0] train_required,     // 必需训练项位图
input [7:0] train_peer_node_id [0:LLTSM_ENTRY_NUM-1], // 对端节点编号表
input [7:0] train_link_id [0:LLTSM_ENTRY_NUM-1],      // 链路编号表
input train_channel_id [0:LLTSM_ENTRY_NUM-1],         // 通道编号表

输出到通信控制器主状态机和结果寄存器：
output link_up,                                 // 本节点必需路径训练完成
output lltsm_training_complete,                 // 本地和全网训练条件均满足
output lltsm_training_fault,                    // 训练重试耗尽
output [LLTSM_ENTRY_NUM-1:0] delay_valid,       // 时延结果有效位图
output [31:0] link_delay [0:LLTSM_ENTRY_NUM-1], // 训练路径时延表

输出到 lltsm_link 配置端口：
output [7:0] lltsm_neighbor_node_id,            // 当前训练对端节点编号
output [7:0] lltsm_selected_link_id,            // 当前训练链路编号
output lltsm_selected_channel_id,               // 当前训练通道编号
output [7:0] lltsm_training_round_id,           // 当前训练轮次编号

lltsm_fsm 输出到 lltsm_link：
output lltsm_link_clear,                        // 清除 LINK 训练上下文
output lltsm_link_tx_req_valid,                 // 请求训练帧发送有效
output lltsm_link_tx_rsp_valid,                 // 应答训练帧发送有效
output lltsm_link_expect_rsp,                   // 当前等待预期应答帧
output [7:0] lltsm_link_training_sequence,      // 当前重复测量序号

lltsm_link 输出到 lltsm_fsm：
input lltsm_link_tx_req_ready,                  // 请求训练帧发送可接受
input lltsm_link_tx_rsp_ready,                  // 应答训练帧发送可接受
input lltsm_link_rx_req_valid,                  // 收到有效训练请求
input lltsm_link_rx_rsp_valid,                  // 收到有效预期应答
input [31:0] lltsm_link_rx_rsp_timestamp        // 有效应答接收时间戳
 */

localparam integer LLTSM_ENTRY_NUM = 16;
localparam [7:0] LLTSM_LAST_ENTRY = LLTSM_ENTRY_NUM - 1;
localparam [7:0] LLTSM_MAX_RETRIES = 3;
localparam [31:0] LLTSM_TIMEOUT_LOAD = 32'd1000000;

localparam [2:0] TP_SELECT         = 3'd0;
localparam [2:0] TP_START          = 3'd1;
localparam [2:0] TP_WAIT_RESULT    = 3'd2;
localparam [2:0] TP_ABORT          = 3'd3;
localparam [2:0] TP_RESPONDER_WAIT = 3'd4;

reg [2:0] train_phase;
reg [2:0] train_phase_next;
reg [7:0] train_entry_index;
reg [7:0] train_retry_count;
reg [7:0] lltsm_training_round_id;
reg [31:0] train_timeout_count;

reg link_up;
reg lltsm_training_fault;
reg [LLTSM_ENTRY_NUM-1:0] delay_valid;
reg [31:0] link_delay [0:LLTSM_ENTRY_NUM-1];

/* Written by the host bootstrap-configuration logic. */
reg [LLTSM_ENTRY_NUM-1:0] train_required;
reg [7:0] train_peer_node_id [0:LLTSM_ENTRY_NUM-1];
reg [7:0] train_link_id [0:LLTSM_ENTRY_NUM-1];
reg train_channel_id [0:LLTSM_ENTRY_NUM-1];

/* Supplied by the PHY status logic, one bit for each training entry. */
wire [LLTSM_ENTRY_NUM-1:0] phy_link_up;

wire all_required_phy_up;
wire all_required_delay_valid;
wire selected_entry_required;
wire selected_entry_ready;

assign all_required_phy_up =
    ((train_required & ~phy_link_up) == {LLTSM_ENTRY_NUM{1'b0}});
assign all_required_delay_valid =
    ((train_required & ~delay_valid) == {LLTSM_ENTRY_NUM{1'b0}});
assign selected_entry_required = train_required[train_entry_index];
assign selected_entry_ready = delay_valid[train_entry_index];

/* These three signals connect to the configuration ports of lltsm_link. */
wire [7:0] lltsm_neighbor_node_id;
wire [7:0] lltsm_selected_link_id;
wire lltsm_selected_channel_id;

assign lltsm_neighbor_node_id = train_peer_node_id[train_entry_index];
assign lltsm_selected_link_id = train_link_id[train_entry_index];
assign lltsm_selected_channel_id = train_channel_id[train_entry_index];

reg lltsm_train_enable;
reg lltsm_train_start;
reg lltsm_train_abort;
reg lltsm_training_complete;

wire lltsm_train_start_ready;
wire lltsm_train_busy;
wire lltsm_train_done;
wire [2:0] lltsm_train_state;
wire lltsm_result_valid;
wire lltsm_result_ok;
wire [31:0] lltsm_result_rtt_average;
wire [31:0] lltsm_result_mean_delay;

wire lltsm_link_clear;
wire lltsm_link_tx_req_valid;
wire lltsm_link_tx_req_ready;
wire lltsm_link_tx_rsp_valid;
wire lltsm_link_tx_rsp_ready;
wire lltsm_link_expect_rsp;
wire [7:0] lltsm_link_training_sequence;
wire lltsm_link_rx_req_valid;
wire lltsm_link_rx_rsp_valid;
wire [31:0] lltsm_link_rx_rsp_timestamp;

lltsm_fsm u_lltsm_fsm (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .train_enable            (lltsm_train_enable),
    .train_start             (lltsm_train_start),
    .train_abort             (lltsm_train_abort),
    .train_start_ready       (lltsm_train_start_ready),
    .train_busy              (lltsm_train_busy),
    .train_done              (lltsm_train_done),
    .train_state             (lltsm_train_state),
    .time_now                (time_now),
    .link_clear              (lltsm_link_clear),
    .link_tx_req_valid       (lltsm_link_tx_req_valid),
    .link_tx_req_ready       (lltsm_link_tx_req_ready),
    .link_tx_rsp_valid       (lltsm_link_tx_rsp_valid),
    .link_tx_rsp_ready       (lltsm_link_tx_rsp_ready),
    .link_expect_rsp         (lltsm_link_expect_rsp),
    .link_training_sequence  (lltsm_link_training_sequence),
    .link_rx_req_valid       (lltsm_link_rx_req_valid),
    .link_rx_rsp_valid       (lltsm_link_rx_rsp_valid),
    .link_rx_rsp_timestamp   (lltsm_link_rx_rsp_timestamp),
    .result_valid            (lltsm_result_valid),
    .result_ok               (lltsm_result_ok),
    .result_rtt_average      (lltsm_result_rtt_average),
    .result_mean_delay       (lltsm_result_mean_delay)
);

/* Phase register update. */
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        train_phase <= TP_SELECT;
    else if (!controller_in_link_train ||
             lltsm_scheduler_clear ||
             topology_changed ||
             !bootstrap_cfg_valid ||
             !all_required_phy_up)
        train_phase <= TP_SELECT;
    else
        train_phase <= train_phase_next;
end

/* Phase transition conditions inside the TOP C_LINK_TRAIN state. */
always @* begin
    train_phase_next = train_phase;

    if (lltsm_training_fault && (train_phase != TP_ABORT)) begin
        train_phase_next = train_phase;
    end else begin
        case (train_phase)
            TP_SELECT: begin
                if (all_required_delay_valid)
                    train_phase_next = TP_RESPONDER_WAIT;
                else if (selected_entry_required &&
                         !selected_entry_ready &&
                         phy_link_up[train_entry_index])
                    train_phase_next = TP_START;
            end

            TP_START: begin
                if (lltsm_train_start_ready)
                    train_phase_next = TP_WAIT_RESULT;
            end

            TP_WAIT_RESULT: begin
                if (lltsm_train_done && lltsm_result_valid) begin
                    if (lltsm_result_ok)
                        train_phase_next = TP_SELECT;
                    else if (train_retry_count >= LLTSM_MAX_RETRIES)
                        train_phase_next = TP_SELECT;
                    else
                        train_phase_next = TP_START;
                end else if (train_timeout_count >= LLTSM_TIMEOUT_LOAD) begin
                    train_phase_next = TP_ABORT;
                end
            end

            TP_ABORT: begin
                if (train_retry_count >= LLTSM_MAX_RETRIES)
                    train_phase_next = TP_SELECT;
                else
                    train_phase_next = TP_START;
            end

            TP_RESPONDER_WAIT: begin
                train_phase_next = TP_RESPONDER_WAIT;
            end

            default: begin
                train_phase_next = TP_SELECT;
            end
        endcase
    end
end

/* Registered scheduler data and training results. */
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        train_entry_index       <= 8'd0;
        train_retry_count       <= 8'd0;
        lltsm_training_round_id <= 8'd0;
        train_timeout_count     <= 32'd0;
        delay_valid             <= {LLTSM_ENTRY_NUM{1'b0}};
        link_up                 <= 1'b0;
        lltsm_training_fault    <= 1'b0;
    end else if (lltsm_scheduler_clear ||
                 topology_changed ||
                 !bootstrap_cfg_valid) begin
        train_entry_index    <= 8'd0;
        train_retry_count    <= 8'd0;
        train_timeout_count  <= 32'd0;
        delay_valid          <= {LLTSM_ENTRY_NUM{1'b0}};
        link_up              <= 1'b0;
        lltsm_training_fault <= 1'b0;
    end else if (!all_required_phy_up) begin
        train_entry_index       <= 8'd0;
        train_retry_count       <= 8'd0;
        lltsm_training_round_id <= lltsm_training_round_id + 1'b1;
        train_timeout_count     <= 32'd0;
        delay_valid             <= delay_valid & phy_link_up;
        link_up                 <= 1'b0;
        lltsm_training_fault    <= 1'b0;
    end else if (controller_in_link_train) begin
        case (train_phase)
            TP_SELECT: begin
                train_timeout_count <= 32'd0;

                if (all_required_delay_valid) begin
                    link_up <= 1'b1;
                end else if (selected_entry_required &&
                             !selected_entry_ready) begin
                    train_retry_count <= 8'd0;
                end else if (train_entry_index == LLTSM_LAST_ENTRY) begin
                    train_entry_index <= 8'd0;
                end else begin
                    train_entry_index <= train_entry_index + 1'b1;
                end
            end

            TP_START: begin
                train_timeout_count <= 32'd0;
            end

            TP_WAIT_RESULT: begin
                if (lltsm_train_done && lltsm_result_valid) begin
                    train_timeout_count <= 32'd0;
                    lltsm_training_round_id <=
                        lltsm_training_round_id + 1'b1;

                    if (lltsm_result_ok) begin
                        link_delay[train_entry_index] <=
                            lltsm_result_mean_delay;
                        delay_valid[train_entry_index] <= 1'b1;
                        train_retry_count <= 8'd0;

                        if (train_entry_index == LLTSM_LAST_ENTRY)
                            train_entry_index <= 8'd0;
                        else
                            train_entry_index <= train_entry_index + 1'b1;
                    end else if (train_retry_count >=
                                 LLTSM_MAX_RETRIES) begin
                        lltsm_training_fault <= 1'b1;
                    end else begin
                        train_retry_count <= train_retry_count + 1'b1;
                    end
                end else if (train_timeout_count >= LLTSM_TIMEOUT_LOAD) begin
                    train_timeout_count <= 32'd0;
                    lltsm_training_round_id <=
                        lltsm_training_round_id + 1'b1;

                    if (train_retry_count >= LLTSM_MAX_RETRIES)
                        lltsm_training_fault <= 1'b1;
                    else
                        train_retry_count <= train_retry_count + 1'b1;
                end else begin
                    train_timeout_count <= train_timeout_count + 1'b1;
                end
            end

            TP_ABORT: begin
                train_timeout_count <= 32'd0;
            end

            default: begin
            end
        endcase
    end
end

/* Combinational scheduler outputs. */
always @* begin
    lltsm_train_enable = 1'b0;
    lltsm_train_start = 1'b0;
    lltsm_train_abort = 1'b0;
    lltsm_training_complete = 1'b0;

    if (controller_in_link_train && bootstrap_cfg_valid &&
        all_required_phy_up) begin
        case (train_phase)
            TP_SELECT: begin
                if (!lltsm_training_fault)
                    lltsm_train_enable = 1'b1;
            end

            TP_START: begin
                if (!lltsm_training_fault) begin
                    lltsm_train_enable = 1'b1;
                    lltsm_train_start = 1'b1;
                end
            end

            TP_WAIT_RESULT: begin
                if (!lltsm_training_fault)
                    lltsm_train_enable = 1'b1;
            end

            TP_ABORT: begin
                lltsm_train_enable = 1'b1;
                lltsm_train_abort = 1'b1;
            end

            TP_RESPONDER_WAIT: begin
                if (!lltsm_training_fault) begin
                    lltsm_train_enable = 1'b1;
                    lltsm_training_complete =
                        link_up && network_training_done;
                end
            end

            default: begin
            end
        endcase
    end
end
