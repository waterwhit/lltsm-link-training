`timescale 1ns/1ps

// Resource-minimized trained-path-delay measurement branch called by controller
// TOP.
//
// Frozen timestamp policy:
// - This module measures the delay between two selected controller reference
//   points, not necessarily the pure physical-link propagation delay.
// - In the low-complexity integration, the TX reference may be the moment the
//   training frame is accepted by the controller TX FIFO/frame adapter, and the
//   RX reference may be the moment the controller RX parser presents the
//   decoded training frame to this branch.
// - This is valid only if the controller uses the same reference-point
//   definition for later compensation and training traffic is frozen so FIFO
//   queueing is deterministic or negligible.
// - The external timestamp interface is named train_rx_ref_time to make this
//   boundary explicit. Internal registers also use *_ref_time naming.
//
// TOP responsibilities:
// - freeze business traffic;
// - select one link, direction and A/B channel;
// - keep all local_* configuration inputs stable while busy=1;
// - provide any global watchdog/retry policy and assert abort when required;
// - store result_* and advance to the next training item.
//
// Branch responsibilities:
// - send DELAY_REQ when local_start is accepted;
// - listen for a valid adjacent DELAY_REQ while training_enable=1;
// - return DELAY_RESP after RESPONSE_WAIT cycles;
// - average request/response trained-path RTT samples and report the local
//   result.
//
// There is no start acknowledgement, remote result report, session-owner
// tracking, per-state timeout table, or local result backpressure protocol.

module ttp_lltsm_branch_fsm #(
    parameter integer NODE_COUNT          = 10,
    parameter integer CHANNEL_COUNT       = 2,
    parameter integer TIME_WIDTH          = 32,
    parameter integer DELAY_WIDTH         = 32,
    parameter integer LINK_COUNT          = (NODE_COUNT > 1) ? NODE_COUNT-1 : 1,
    parameter integer MEASURE_REPEATS     = 4,
    parameter integer RESPONSE_WAIT       = 32,
    parameter integer TRAIN_FRAME_WORDS   = 8,
    parameter integer NODE_ID_WIDTH       = (NODE_COUNT <= 2) ? 1 : $clog2(NODE_COUNT),
    parameter integer LINK_ID_WIDTH       = (LINK_COUNT <= 1) ? 1 : $clog2(LINK_COUNT),
    parameter integer CHANNEL_ID_WIDTH    = (CHANNEL_COUNT <= 2) ? 1 : $clog2(CHANNEL_COUNT),
    parameter integer SAMPLE_COUNT_WIDTH  = (MEASURE_REPEATS <= 2) ? 1 : $clog2(MEASURE_REPEATS),
    parameter integer RESPONSE_COUNT_WIDTH= (RESPONSE_WAIT < 1) ? 1 : $clog2(RESPONSE_WAIT+1)
)(
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              training_enable,
    input  logic                              abort,
    input  logic [TIME_WIDTH-1:0]             time_now,

    // TOP -> local branch. local_start means this node is the request node.
    input  logic                              local_start,
    output logic                              local_start_ready,
    input  logic [NODE_ID_WIDTH-1:0]          local_node_id,
    input  logic [NODE_ID_WIDTH-1:0]          local_neighbor_node_id,
    input  logic [LINK_ID_WIDTH-1:0]          local_link_id,
    input  logic [CHANNEL_ID_WIDTH-1:0]       local_channel_id,
    input  logic [7:0]                        local_training_round_id,

    // Local branch -> local training-frame TX adapter.
    // The adapter may enqueue the fixed training payload into the controller
    // TX FIFO/frame builder. The MAC/PHY transmit path is outside this module.
    output logic                              train_tx_valid,
    input  logic                              train_tx_ready,
    output logic [1:0]                        train_tx_frame_type,
    output logic [15:0]                       train_tx_frame_words,
    output logic [NODE_ID_WIDTH-1:0]          train_tx_src_node_id,
    output logic [NODE_ID_WIDTH-1:0]          train_tx_dst_node_id,
    output logic [LINK_ID_WIDTH-1:0]          train_tx_link_id,
    output logic [CHANNEL_ID_WIDTH-1:0]       train_tx_channel_id,
    output logic [7:0]                        train_tx_training_round_id,
    output logic [7:0]                        train_tx_sequence,
    output logic [TIME_WIDTH-1:0]             train_tx_turnaround,

    // Local training-frame RX adapter -> local branch.
    // The adapter provides decoded training fields after link-frame parsing,
    // external CRC/FCS checking, protocol checks, and selected RX timestamping.
    input  logic                              train_rx_valid,
    input  logic                              train_rx_frame_complete,
    input  logic                              train_rx_crc_ok,
    input  logic                              train_rx_protocol_ok,
    input  logic [1:0]                        train_rx_frame_type,
    input  logic [15:0]                       train_rx_frame_words,
    input  logic [NODE_ID_WIDTH-1:0]          train_rx_src_node_id,
    input  logic [NODE_ID_WIDTH-1:0]          train_rx_dst_node_id,
    input  logic [LINK_ID_WIDTH-1:0]          train_rx_link_id,
    input  logic [CHANNEL_ID_WIDTH-1:0]       train_rx_channel_id,
    input  logic [7:0]                        train_rx_training_round_id,
    input  logic [7:0]                        train_rx_sequence,
    input  logic [TIME_WIDTH-1:0]             train_rx_ref_time,
    input  logic [TIME_WIDTH-1:0]             train_rx_turnaround,

    // Local branch -> controller TOP. result_valid/done are one-cycle pulses.
    output logic                              busy,
    output logic                              done,
    output logic                              result_valid,
    output logic                              result_ok,
    output logic [DELAY_WIDTH-1:0]            result_rtt_average,
    output logic [DELAY_WIDTH-1:0]            result_mean_delay,
    output logic [2:0]                        branch_state
);

    localparam logic [1:0] FRAME_DELAY_REQ  = 2'd1;
    localparam logic [1:0] FRAME_DELAY_RESP = 2'd2;

    localparam logic [2:0] S_IDLE          = 3'd0;
    localparam logic [2:0] S_SEND_REQ      = 3'd1;
    localparam logic [2:0] S_WAIT_RESP     = 3'd2;
    localparam logic [2:0] S_RESPONSE_WAIT = 3'd3;
    localparam logic [2:0] S_SEND_RESP     = 3'd4;
    localparam logic [2:0] S_DONE          = 3'd5;

    localparam integer SUM_WIDTH = DELAY_WIDTH + $clog2(MEASURE_REPEATS+1);

    logic [2:0] state;
    logic [SAMPLE_COUNT_WIDTH-1:0] sample_count;
    logic [SUM_WIDTH-1:0] rtt_sum;
    logic [TIME_WIDTH-1:0] request_tx_ref_time;

    // Only fields required to return one adjacent response are registered.
    logic [NODE_ID_WIDTH-1:0] response_dst_node_id;
    logic [LINK_ID_WIDTH-1:0] response_link_id;
    logic [CHANNEL_ID_WIDTH-1:0] response_channel_id;
    logic [7:0] response_round_id;
    logic [7:0] response_sequence;
    logic [TIME_WIDTH-1:0] response_rx_ref_time;
    logic [RESPONSE_COUNT_WIDTH-1:0] response_wait_count;

    logic [DELAY_WIDTH-1:0] current_rtt;
    logic [DELAY_WIDTH-1:0] final_rtt_average;
    logic [DELAY_WIDTH-1:0] final_mean_delay;

    wire tx_fire = train_tx_valid && train_tx_ready;
    wire received_checked_frame = train_rx_valid &&
                                  train_rx_frame_complete &&
                                  train_rx_crc_ok &&
                                  train_rx_protocol_ok &&
                                  (train_rx_frame_words == TRAIN_FRAME_WORDS);

    wire received_delay_req = received_checked_frame &&
                              (train_rx_frame_type == FRAME_DELAY_REQ) &&
                              (train_rx_src_node_id == local_neighbor_node_id) &&
                              (train_rx_dst_node_id == local_node_id) &&
                              (train_rx_link_id == local_link_id) &&
                              (train_rx_channel_id == local_channel_id) &&
                              (train_rx_training_round_id == local_training_round_id);

    wire received_expected_resp = received_checked_frame &&
                                  (train_rx_frame_type == FRAME_DELAY_RESP) &&
                                  (train_rx_src_node_id == local_neighbor_node_id) &&
                                  (train_rx_dst_node_id == local_node_id) &&
                                  (train_rx_link_id == local_link_id) &&
                                  (train_rx_channel_id == local_channel_id) &&
                                  (train_rx_training_round_id == local_training_round_id) &&
                                  (train_rx_sequence == sample_count);

    initial begin
        if (TIME_WIDTH != DELAY_WIDTH)
            $fatal(1, "ttp_lltsm_branch_fsm requires TIME_WIDTH == DELAY_WIDTH");
        if ((MEASURE_REPEATS <= 0) ||
            ((MEASURE_REPEATS & (MEASURE_REPEATS-1)) != 0) ||
            (MEASURE_REPEATS > 256))
            $fatal(1, "ttp_lltsm_branch_fsm requires power-of-two MEASURE_REPEATS <= 256");
        if (RESPONSE_WAIT < 0)
            $fatal(1, "ttp_lltsm_branch_fsm requires RESPONSE_WAIT >= 0");
    end

    always_comb begin
        if (train_rx_ref_time >= request_tx_ref_time)
            current_rtt = train_rx_ref_time - request_tx_ref_time;
        else
            current_rtt = ({TIME_WIDTH{1'b1}} - request_tx_ref_time) +
                          train_rx_ref_time + 1'b1;

        final_rtt_average = (rtt_sum + current_rtt) / MEASURE_REPEATS;
        if (final_rtt_average > train_rx_turnaround)
            final_mean_delay = (final_rtt_average - train_rx_turnaround) >> 1;
        else
            final_mean_delay = '0;
    end

    assign branch_state = state;
    assign busy = (state != S_IDLE) && (state != S_DONE);
    assign done = (state == S_DONE);
    assign result_valid = (state == S_DONE);
    assign local_start_ready = training_enable && (state == S_IDLE) && !received_delay_req;

    always_comb begin
        train_tx_valid             = 1'b0;
        train_tx_frame_type        = 2'd0;
        train_tx_frame_words       = TRAIN_FRAME_WORDS;
        train_tx_src_node_id       = local_node_id;
        train_tx_dst_node_id       = local_neighbor_node_id;
        train_tx_link_id           = local_link_id;
        train_tx_channel_id        = local_channel_id;
        train_tx_training_round_id = local_training_round_id;
        train_tx_sequence          = sample_count;
        train_tx_turnaround        = '0;

        if (state == S_SEND_REQ) begin
            train_tx_valid      = 1'b1;
            train_tx_frame_type = FRAME_DELAY_REQ;
        end else if (state == S_SEND_RESP) begin
            train_tx_valid             = 1'b1;
            train_tx_frame_type        = FRAME_DELAY_RESP;
            train_tx_dst_node_id       = response_dst_node_id;
            train_tx_link_id           = response_link_id;
            train_tx_channel_id        = response_channel_id;
            train_tx_training_round_id = response_round_id;
            train_tx_sequence          = response_sequence;
            // Report the response-node turnaround at the actual TX adapter
            // handshake reference point. If the TX adapter applies
            // backpressure, those wait cycles are part of the deterministic
            // controller path and must be subtracted by the requester.
            train_tx_turnaround        = time_now - response_rx_ref_time;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                    <= S_IDLE;
            sample_count             <= '0;
            rtt_sum                  <= '0;
            request_tx_ref_time      <= '0;
            response_dst_node_id     <= '0;
            response_link_id         <= '0;
            response_channel_id      <= '0;
            response_round_id        <= '0;
            response_sequence        <= '0;
            response_rx_ref_time     <= '0;
            response_wait_count      <= '0;
            result_ok                <= 1'b0;
            result_rtt_average       <= '0;
            result_mean_delay        <= '0;
        end else if (abort || !training_enable) begin
            state        <= S_IDLE;
            sample_count <= '0;
            rtt_sum      <= '0;
            result_ok    <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    sample_count <= '0;
                    rtt_sum      <= '0;
                    result_ok    <= 1'b0;

                    // A received adjacent request has priority. TOP sees
                    // local_start_ready=0 and can retry its local request.
                    if (received_delay_req) begin
                        response_dst_node_id <= train_rx_src_node_id;
                        response_link_id     <= train_rx_link_id;
                        response_channel_id  <= train_rx_channel_id;
                        response_round_id    <= train_rx_training_round_id;
                        response_sequence    <= train_rx_sequence;
                        response_rx_ref_time <= train_rx_ref_time;
                        if (RESPONSE_WAIT == 0) begin
                            response_wait_count <= '0;
                            state <= S_SEND_RESP;
                        end else begin
                            response_wait_count <= RESPONSE_WAIT-1;
                            state <= S_RESPONSE_WAIT;
                        end
                    end else if (local_start && local_start_ready) begin
                        state <= S_SEND_REQ;
                    end
                end

                S_SEND_REQ: begin
                    if (tx_fire) begin
                        request_tx_ref_time <= time_now;
                        state <= S_WAIT_RESP;
                    end
                end

                S_WAIT_RESP: begin
                    if (received_expected_resp) begin
                        if (sample_count == MEASURE_REPEATS-1) begin
                            result_rtt_average <= final_rtt_average;
                            result_mean_delay  <= final_mean_delay;
                            result_ok          <= (final_rtt_average > train_rx_turnaround);
                            state              <= S_DONE;
                        end else begin
                            rtt_sum      <= rtt_sum + current_rtt;
                            sample_count <= sample_count + 1'b1;
                            state        <= S_SEND_REQ;
                        end
                    end
                end

                S_RESPONSE_WAIT: begin
                    if (response_wait_count != 0) begin
                        response_wait_count <= response_wait_count - 1'b1;
                    end else begin
                        state <= S_SEND_RESP;
                    end
                end

                S_SEND_RESP: begin
                    if (tx_fire)
                        state <= S_IDLE;
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

