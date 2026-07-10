`timescale 1ns/1ps

// Generic LLTSM RX payload parser.
//
// This module consumes a link-independent 16-bit payload word stream and
// converts it into the train_rx_* interface expected by the LLTSM branch FSM.
// The MAC/link-frame layer must perform PHY/channel selection, address
// filtering, SOF/EOF handling, and CRC/FCS checking before this module.

module lltsm_rx_payload_parser #(
    parameter integer NODE_COUNT        = 10,
    parameter integer CHANNEL_COUNT     = 2,
    parameter integer LINK_COUNT        = (NODE_COUNT > 1) ? NODE_COUNT-1 : 1,
    parameter integer NODE_ID_WIDTH     = (NODE_COUNT <= 2) ? 1 : $clog2(NODE_COUNT),
    parameter integer LINK_ID_WIDTH     = (LINK_COUNT <= 1) ? 1 : $clog2(LINK_COUNT),
    parameter integer CHANNEL_ID_WIDTH  = (CHANNEL_COUNT <= 2) ? 1 : $clog2(CHANNEL_COUNT),
    parameter integer TIME_WIDTH        = 32,
    parameter integer TRAIN_FRAME_WORDS = 8,
    parameter logic [3:0] PROTOCOL_TAG  = 4'hD
)(
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              lltsm_rx_payload_valid,
    output logic                              lltsm_rx_payload_ready,
    input  logic                              lltsm_rx_payload_start,
    input  logic                              lltsm_rx_payload_last,
    input  logic [15:0]                       lltsm_rx_payload_word,
    input  logic                              lltsm_rx_payload_frame_complete,
    input  logic                              lltsm_rx_payload_crc_ok,
    input  logic [TIME_WIDTH-1:0]             lltsm_rx_payload_ref_time,

    output logic                              train_rx_valid,
    output logic                              train_rx_frame_complete,
    output logic                              train_rx_crc_ok,
    output logic                              train_rx_protocol_ok,
    output logic [1:0]                        train_rx_frame_type,
    output logic [15:0]                       train_rx_frame_words,
    output logic [NODE_ID_WIDTH-1:0]          train_rx_src_node_id,
    output logic [NODE_ID_WIDTH-1:0]          train_rx_dst_node_id,
    output logic [LINK_ID_WIDTH-1:0]          train_rx_link_id,
    output logic [CHANNEL_ID_WIDTH-1:0]       train_rx_channel_id,
    output logic [7:0]                        train_rx_training_round_id,
    output logic [7:0]                        train_rx_sequence,
    output logic [TIME_WIDTH-1:0]             train_rx_ref_time,
    output logic [TIME_WIDTH-1:0]             train_rx_turnaround
);

    localparam integer WORD_COUNT_WIDTH = 16;
    localparam integer WORD_INDEX_WIDTH = (TRAIN_FRAME_WORDS <= 2) ? 1 : $clog2(TRAIN_FRAME_WORDS);

    logic [127:0] rx_payload_flat;
    logic [127:0] rx_payload_flat_next;
    logic [WORD_COUNT_WIDTH-1:0] word_count;
    logic [TIME_WIDTH-1:0] captured_ref_time;
    logic collecting;

    logic codec_rx_protocol_ok;
    logic [1:0] codec_rx_frame_type;
    logic [NODE_ID_WIDTH-1:0] codec_rx_src_node_id;
    logic [NODE_ID_WIDTH-1:0] codec_rx_dst_node_id;
    logic [LINK_ID_WIDTH-1:0] codec_rx_link_id;
    logic [CHANNEL_ID_WIDTH-1:0] codec_rx_channel_id;
    logic [7:0] codec_rx_training_round_id;
    logic [7:0] codec_rx_sequence;
    logic [31:0] codec_rx_turnaround;

    wire payload_fire = lltsm_rx_payload_valid && lltsm_rx_payload_ready;
    wire [WORD_INDEX_WIDTH-1:0] payload_word_index = word_count[WORD_INDEX_WIDTH-1:0];

    initial begin
        if (TRAIN_FRAME_WORDS != 8)
            $fatal(1, "lltsm_rx_payload_parser requires TRAIN_FRAME_WORDS == 8");
        if (TIME_WIDTH < 32)
            $fatal(1, "lltsm_rx_payload_parser requires TIME_WIDTH >= 32");
    end

    function automatic [TIME_WIDTH-1:0] extend_turnaround(input logic [31:0] value);
        begin
            extend_turnaround = '0;
            extend_turnaround[31:0] = value;
        end
    endfunction

    always_comb begin
        rx_payload_flat_next = rx_payload_flat;

        if (payload_fire) begin
            if (lltsm_rx_payload_start || !collecting) begin
                rx_payload_flat_next = 128'd0;
                rx_payload_flat_next[15:0] = lltsm_rx_payload_word;
            end else if (word_count < TRAIN_FRAME_WORDS[15:0]) begin
                rx_payload_flat_next[payload_word_index*16 +: 16] = lltsm_rx_payload_word;
            end
        end
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
        .tx_frame_type(2'd0),
        .tx_src_node_id('0),
        .tx_dst_node_id('0),
        .tx_link_id('0),
        .tx_channel_id('0),
        .tx_training_round_id(8'd0),
        .tx_sequence(8'd0),
        .tx_turnaround(32'd0),
        .tx_payload_flat(),
        .rx_payload_flat(rx_payload_flat_next),
        .rx_protocol_ok(codec_rx_protocol_ok),
        .rx_frame_type(codec_rx_frame_type),
        .rx_src_node_id(codec_rx_src_node_id),
        .rx_dst_node_id(codec_rx_dst_node_id),
        .rx_link_id(codec_rx_link_id),
        .rx_channel_id(codec_rx_channel_id),
        .rx_training_round_id(codec_rx_training_round_id),
        .rx_sequence(codec_rx_sequence),
        .rx_turnaround(codec_rx_turnaround)
    );

    assign lltsm_rx_payload_ready = !train_rx_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_payload_flat            <= 128'd0;
            word_count                 <= 16'd0;
            captured_ref_time          <= '0;
            collecting                 <= 1'b0;
            train_rx_valid             <= 1'b0;
            train_rx_frame_complete    <= 1'b0;
            train_rx_crc_ok            <= 1'b0;
            train_rx_protocol_ok       <= 1'b0;
            train_rx_frame_type        <= 2'd0;
            train_rx_frame_words       <= 16'd0;
            train_rx_src_node_id       <= '0;
            train_rx_dst_node_id       <= '0;
            train_rx_link_id           <= '0;
            train_rx_channel_id        <= '0;
            train_rx_training_round_id <= 8'd0;
            train_rx_sequence          <= 8'd0;
            train_rx_ref_time          <= '0;
            train_rx_turnaround        <= '0;
        end else begin
            train_rx_valid <= 1'b0;

            if (payload_fire) begin
                rx_payload_flat <= rx_payload_flat_next;

                if (lltsm_rx_payload_start || !collecting) begin
                    word_count        <= 16'd1;
                    captured_ref_time <= lltsm_rx_payload_ref_time;
                    collecting        <= !lltsm_rx_payload_last;
                end else begin
                    word_count <= word_count + 1'b1;
                    if (lltsm_rx_payload_last) begin
                        collecting <= 1'b0;
                    end
                end

                if (lltsm_rx_payload_last) begin
                    train_rx_valid             <= 1'b1;
                    train_rx_frame_complete    <= lltsm_rx_payload_frame_complete;
                    train_rx_crc_ok            <= lltsm_rx_payload_crc_ok;
                    train_rx_protocol_ok       <= codec_rx_protocol_ok;
                    train_rx_frame_type        <= codec_rx_frame_type;
                    train_rx_frame_words       <= lltsm_rx_payload_start ? 16'd1 : (word_count + 1'b1);
                    train_rx_src_node_id       <= codec_rx_src_node_id;
                    train_rx_dst_node_id       <= codec_rx_dst_node_id;
                    train_rx_link_id           <= codec_rx_link_id;
                    train_rx_channel_id        <= codec_rx_channel_id;
                    train_rx_training_round_id <= codec_rx_training_round_id;
                    train_rx_sequence          <= codec_rx_sequence;
                    train_rx_ref_time          <= lltsm_rx_payload_start ? lltsm_rx_payload_ref_time : captured_ref_time;
                    train_rx_turnaround        <= extend_turnaround(codec_rx_turnaround);
                end
            end
        end
    end

endmodule
