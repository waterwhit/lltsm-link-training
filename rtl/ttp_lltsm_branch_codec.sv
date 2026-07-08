`timescale 1ns/1ps

// Resource-minimized codec for the host-controller-controlled link training
// branch FSM.
// Eight 16-bit payload words are retained so the common CRC/MFM envelope does
// not change. Only two frame subtypes are active:
//   1 = DELAY_REQ, 2 = DELAY_RESP.
// The existing CRC path appends one CRC word after these eight payload words.

module ttp_lltsm_branch_codec #(
    parameter integer NODE_COUNT       = 10,
    parameter integer CHANNEL_COUNT    = 2,
    parameter integer LINK_COUNT       = (NODE_COUNT > 1) ? NODE_COUNT-1 : 1,
    parameter integer NODE_ID_WIDTH    = (NODE_COUNT <= 2) ? 1 : $clog2(NODE_COUNT),
    parameter integer LINK_ID_WIDTH    = (LINK_COUNT <= 1) ? 1 : $clog2(LINK_COUNT),
    parameter integer CHANNEL_ID_WIDTH = (CHANNEL_COUNT <= 2) ? 1 : $clog2(CHANNEL_COUNT),
    parameter logic [3:0] PROTOCOL_TAG = 4'hD
)(
    input  logic [1:0]                        tx_frame_type,
    input  logic [NODE_ID_WIDTH-1:0]          tx_src_node_id,
    input  logic [NODE_ID_WIDTH-1:0]          tx_dst_node_id,
    input  logic [LINK_ID_WIDTH-1:0]          tx_link_id,
    input  logic [CHANNEL_ID_WIDTH-1:0]       tx_channel_id,
    input  logic [7:0]                        tx_training_round_id,
    input  logic [7:0]                        tx_sequence,
    input  logic [31:0]                       tx_turnaround,
    output logic [127:0]                      tx_payload_flat,

    input  logic [127:0]                      rx_payload_flat,
    output logic                              rx_protocol_ok,
    output logic [1:0]                        rx_frame_type,
    output logic [NODE_ID_WIDTH-1:0]          rx_src_node_id,
    output logic [NODE_ID_WIDTH-1:0]          rx_dst_node_id,
    output logic [LINK_ID_WIDTH-1:0]          rx_link_id,
    output logic [CHANNEL_ID_WIDTH-1:0]       rx_channel_id,
    output logic [7:0]                        rx_training_round_id,
    output logic [7:0]                        rx_sequence,
    output logic [31:0]                       rx_turnaround
);

    localparam logic [1:0] FRAME_DELAY_REQ  = 2'd1;
    localparam logic [1:0] FRAME_DELAY_RESP = 2'd2;

    localparam integer EXPECTED_LINK_COUNT = (NODE_COUNT > 1) ? NODE_COUNT-1 : 1;
    localparam integer EXPECTED_NODE_ID_WIDTH = (NODE_COUNT <= 2) ? 1 : $clog2(NODE_COUNT);
    localparam integer EXPECTED_LINK_ID_WIDTH = (LINK_COUNT <= 1) ? 1 : $clog2(LINK_COUNT);
    localparam integer EXPECTED_CHANNEL_ID_WIDTH = (CHANNEL_COUNT <= 2) ? 1 : $clog2(CHANNEL_COUNT);

    logic [3:0] rx_tag;
    logic [3:0] rx_type_field;

    initial begin
        if (NODE_COUNT < 2)
            $fatal(1, "Link training branch codec requires NODE_COUNT >= 2");
        if (LINK_COUNT != EXPECTED_LINK_COUNT)
            $fatal(1, "Link training branch codec LINK_COUNT must equal NODE_COUNT-1");
        if ((NODE_ID_WIDTH != EXPECTED_NODE_ID_WIDTH) ||
            (LINK_ID_WIDTH != EXPECTED_LINK_ID_WIDTH) ||
            (CHANNEL_ID_WIDTH != EXPECTED_CHANNEL_ID_WIDTH))
            $fatal(1, "Link training branch codec count/width mismatch");
        if ((NODE_ID_WIDTH > 8) || (LINK_ID_WIDTH > 4))
            $fatal(1, "Link training branch codec wire-format width exceeded");
        if ((CHANNEL_COUNT != 2) || (CHANNEL_ID_WIDTH != 1))
            $fatal(1, "Link training branch codec requires exactly two channels");
    end

    always_comb begin
        tx_payload_flat = 128'd0;
        tx_payload_flat[15:12]  = PROTOCOL_TAG;
        tx_payload_flat[11:8]   = {2'b00, tx_frame_type};
        tx_payload_flat[7]      = 1'b0;
        tx_payload_flat[6]      = tx_channel_id[0];
        tx_payload_flat[5:2]    = tx_link_id;
        tx_payload_flat[1:0]    = 2'b00;
        tx_payload_flat[31:24]  = tx_src_node_id;
        tx_payload_flat[23:16]  = tx_dst_node_id;
        tx_payload_flat[47:40]  = tx_training_round_id;
        tx_payload_flat[39:32]  = tx_sequence;

        // Words 3 and 4 carry turnaround only in a response frame.
        if (tx_frame_type == FRAME_DELAY_RESP) begin
            tx_payload_flat[63:48] = tx_turnaround[31:16];
            tx_payload_flat[79:64] = tx_turnaround[15:0];
        end
    end

    always_comb begin
        rx_tag               = rx_payload_flat[15:12];
        rx_type_field        = rx_payload_flat[11:8];
        rx_frame_type        = rx_type_field[1:0];
        rx_channel_id        = rx_payload_flat[6];
        rx_link_id           = rx_payload_flat[5:2];
        rx_src_node_id       = rx_payload_flat[31:24];
        rx_dst_node_id       = rx_payload_flat[23:16];
        rx_training_round_id = rx_payload_flat[47:40];
        rx_sequence          = rx_payload_flat[39:32];
        rx_turnaround        = (rx_frame_type == FRAME_DELAY_RESP) ?
                               {rx_payload_flat[63:48], rx_payload_flat[79:64]} : 32'd0;

        rx_protocol_ok = (rx_tag == PROTOCOL_TAG) &&
                         (rx_type_field[3:2] == 2'b00) &&
                         ((rx_frame_type == FRAME_DELAY_REQ) ||
                          (rx_frame_type == FRAME_DELAY_RESP)) &&
                         (rx_payload_flat[7] == 1'b0) &&
                         (rx_payload_flat[1:0] == 2'b00);
    end

endmodule
