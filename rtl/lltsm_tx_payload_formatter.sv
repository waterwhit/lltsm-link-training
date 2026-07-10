`timescale 1ns/1ps

// Generic LLTSM TX payload formatter.
//
// This module converts LLTSM training-frame fields into a reusable 16-bit
// payload word stream. It does not add link headers, SOF/EOF markers, padding,
// or CRC/FCS. The MAC/link-frame layer consumes this stream, selects the
// requested PHY/channel, and performs Ethernet, RS-485, or custom framing.

module lltsm_tx_payload_formatter #(
    parameter integer NODE_COUNT        = 10,
    parameter integer CHANNEL_COUNT     = 2,
    parameter integer LINK_COUNT        = (NODE_COUNT > 1) ? NODE_COUNT-1 : 1,
    parameter integer NODE_ID_WIDTH     = (NODE_COUNT <= 2) ? 1 : $clog2(NODE_COUNT),
    parameter integer LINK_ID_WIDTH     = (LINK_COUNT <= 1) ? 1 : $clog2(LINK_COUNT),
    parameter integer CHANNEL_ID_WIDTH  = (CHANNEL_COUNT <= 2) ? 1 : $clog2(CHANNEL_COUNT),
    parameter integer TRAIN_FRAME_WORDS = 8,
    parameter logic [3:0] PROTOCOL_TAG  = 4'hD
)(
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              train_tx_valid,
    output logic                              train_tx_ready,
    input  logic [1:0]                        train_tx_frame_type,
    input  logic [15:0]                       train_tx_frame_words,
    input  logic [NODE_ID_WIDTH-1:0]          train_tx_src_node_id,
    input  logic [NODE_ID_WIDTH-1:0]          train_tx_dst_node_id,
    input  logic [LINK_ID_WIDTH-1:0]          train_tx_link_id,
    input  logic [CHANNEL_ID_WIDTH-1:0]       train_tx_channel_id,
    input  logic [7:0]                        train_tx_training_round_id,
    input  logic [7:0]                        train_tx_sequence,
    input  logic [31:0]                       train_tx_turnaround,

    output logic                              lltsm_tx_payload_valid,
    input  logic                              lltsm_tx_payload_ready,
    output logic                              lltsm_tx_payload_start,
    output logic                              lltsm_tx_payload_last,
    output logic [15:0]                       lltsm_tx_payload_word,
    output logic [15:0]                       lltsm_tx_payload_words,

    // Metadata for MAC/link-frame routing and PHY/channel selection.
    output logic [1:0]                        lltsm_tx_payload_frame_type,
    output logic [NODE_ID_WIDTH-1:0]          lltsm_tx_payload_src_node_id,
    output logic [NODE_ID_WIDTH-1:0]          lltsm_tx_payload_dst_node_id,
    output logic [LINK_ID_WIDTH-1:0]          lltsm_tx_payload_link_id,
    output logic [CHANNEL_ID_WIDTH-1:0]       lltsm_tx_payload_channel_id,
    output logic [7:0]                        lltsm_tx_payload_training_round_id,
    output logic [7:0]                        lltsm_tx_payload_sequence
);

    localparam integer WORD_INDEX_WIDTH = (TRAIN_FRAME_WORDS <= 2) ? 1 : $clog2(TRAIN_FRAME_WORDS);

    logic sending;
    logic [WORD_INDEX_WIDTH-1:0] word_index;
    logic [127:0] tx_payload_flat;

    wire payload_fire = lltsm_tx_payload_valid && lltsm_tx_payload_ready;
    wire last_payload_fire = payload_fire && (word_index == TRAIN_FRAME_WORDS-1);
    wire [127:0] current_word_shift = tx_payload_flat >> (word_index * 16);

    initial begin
        if (TRAIN_FRAME_WORDS != 8)
            $fatal(1, "lltsm_tx_payload_formatter requires TRAIN_FRAME_WORDS == 8");
    end

    ttp_lltsm_branch_codec #(
        .NODE_COUNT(NODE_COUNT),
        .CHANNEL_COUNT(CHANNEL_COUNT),
        .LINK_COUNT(LINK_COUNT),
        .NODE_ID_WIDTH(NODE_ID_WIDTH),
        .LINK_ID_WIDTH(LINK_ID_WIDTH),
        .CHANNEL_ID_WIDTH(CHANNEL_ID_WIDTH),
        .PROTOCOL_TAG(PROTOCOL_TAG)
    ) u_codec (
        .tx_frame_type(train_tx_frame_type),
        .tx_src_node_id(train_tx_src_node_id),
        .tx_dst_node_id(train_tx_dst_node_id),
        .tx_link_id(train_tx_link_id),
        .tx_channel_id(train_tx_channel_id),
        .tx_training_round_id(train_tx_training_round_id),
        .tx_sequence(train_tx_sequence),
        .tx_turnaround(train_tx_turnaround),
        .tx_payload_flat(tx_payload_flat),
        .rx_payload_flat(128'd0),
        .rx_protocol_ok(),
        .rx_frame_type(),
        .rx_src_node_id(),
        .rx_dst_node_id(),
        .rx_link_id(),
        .rx_channel_id(),
        .rx_training_round_id(),
        .rx_sequence(),
        .rx_turnaround()
    );

    always_comb begin
        lltsm_tx_payload_valid             = sending;
        lltsm_tx_payload_start             = sending && (word_index == '0);
        lltsm_tx_payload_last              = sending && (word_index == TRAIN_FRAME_WORDS-1);
        lltsm_tx_payload_word              = current_word_shift[15:0];
        lltsm_tx_payload_words             = TRAIN_FRAME_WORDS[15:0];
        lltsm_tx_payload_frame_type        = train_tx_frame_type;
        lltsm_tx_payload_src_node_id       = train_tx_src_node_id;
        lltsm_tx_payload_dst_node_id       = train_tx_dst_node_id;
        lltsm_tx_payload_link_id           = train_tx_link_id;
        lltsm_tx_payload_channel_id        = train_tx_channel_id;
        lltsm_tx_payload_training_round_id = train_tx_training_round_id;
        lltsm_tx_payload_sequence          = train_tx_sequence;
        train_tx_ready                     = last_payload_fire &&
                                             (train_tx_frame_words == TRAIN_FRAME_WORDS[15:0]);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending    <= 1'b0;
            word_index <= '0;
        end else begin
            if (!sending) begin
                word_index <= '0;
                if (train_tx_valid) begin
                    sending <= 1'b1;
                end
            end else if (payload_fire) begin
                if (word_index == TRAIN_FRAME_WORDS-1) begin
                    sending    <= 1'b0;
                    word_index <= '0;
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end
        end
    end

endmodule
