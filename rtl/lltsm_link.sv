`timescale 1ns/1ps

// LLTSM link engine.
//
// The TX interface is the wide write side of a width-converting FIFO. The MAC
// reads the same FIFO through its native narrow data width, adds its own link
// header, padding and CRC/FCS, and selects the requested PHY/channel.
//
// The RX interface is the wide read side of the corresponding receive path.
// MAC-side frame classification, CRC status and timestamp are aligned with the
// 128-bit payload record. This module never creates or checks a link CRC.
//
// A response is an exact echo: the MAC training-frame class is unchanged and
// every bit of the 128-bit TRAIN_FRAME payload is returned unchanged.

module lltsm_link #(
    parameter integer TIME_WIDTH = 32,
    parameter logic [15:0] TRAIN_PAYLOAD_MAGIC = 16'hD15A,
    parameter logic [63:0] TRAIN_PAYLOAD_PATTERN = 64'hA55A_C33C_5AA5_3CC3
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  clear,

    // Stable branch configuration from the communication-controller TOP.
    input  logic [7:0]            local_node_id,
    input  logic [7:0]            neighbor_node_id,
    input  logic [7:0]            selected_link_id,
    input  logic                  selected_channel_id,
    input  logic [7:0]            training_round_id,
    input  logic [7:0]            training_sequence,

    // LLTSM FSM command interface.
    input  logic                  tx_request_valid,
    output logic                  tx_request_ready,
    input  logic                  tx_echo_valid,
    output logic                  tx_echo_ready,
    input  logic                  expect_response,

    output logic                  rx_request_valid,
    output logic [TIME_WIDTH-1:0] rx_request_timestamp,
    output logic                  rx_response_valid,
    output logic [TIME_WIDTH-1:0] rx_response_timestamp,
    output logic                  rx_rejected,

    // Wide write side of TX width-converting FIFO: 128-bit LLTSM -> MAC width.
    input  logic                  tx_fifo_full,
    output logic                  tx_fifo_wr_en,
    output logic [127:0]          tx_fifo_wr_data,
    output logic                  tx_fifo_train_frame,
    output logic [7:0]            tx_fifo_link_id,
    output logic                  tx_fifo_channel_id,

    // Wide read side of RX width-converting FIFO: MAC width -> 128-bit LLTSM.
    // The interface follows first-word-fall-through semantics: data and
    // sidebands are valid while empty=0 and are consumed by rd_en.
    input  logic                  rx_fifo_empty,
    output logic                  rx_fifo_rd_en,
    input  logic [127:0]          rx_fifo_rd_data,
    input  logic                  rx_fifo_train_frame,
    input  logic                  rx_fifo_crc_ok,
    input  logic [TIME_WIDTH-1:0] rx_fifo_timestamp
);

    logic [127:0] request_frame;
    logic [127:0] expected_response_frame;
    logic [127:0] pending_request_frame;
    logic         expected_response_valid;
    logic         request_pending;

    wire request_write = tx_request_valid && tx_request_ready;
    wire echo_write    = tx_echo_valid && tx_echo_ready;

    wire rx_record_fire = !rx_fifo_empty && rx_fifo_rd_en;
    wire rx_common_ok = rx_fifo_train_frame &&
                        rx_fifo_crc_ok &&
                        (rx_fifo_rd_data[15:0] == TRAIN_PAYLOAD_MAGIC) &&
                        (rx_fifo_rd_data[63:57] == 7'd0) &&
                        (rx_fifo_rd_data[127:64] == TRAIN_PAYLOAD_PATTERN);

    wire rx_targets_local = (rx_fifo_rd_data[31:24] == neighbor_node_id) &&
                            (rx_fifo_rd_data[23:16] == local_node_id) &&
                            (rx_fifo_rd_data[55:48] == selected_link_id) &&
                            (rx_fifo_rd_data[56] == selected_channel_id) &&
                            (rx_fifo_rd_data[47:40] == training_round_id);

    wire rx_expected_response = rx_common_ok &&
                                expected_response_valid &&
                                (rx_fifo_rd_data == expected_response_frame);

    initial begin
        if (TIME_WIDTH < 1)
            $fatal(1, "lltsm_link requires TIME_WIDTH >= 1");
    end

    always_comb begin
        request_frame = 128'd0;
        request_frame[15:0]   = TRAIN_PAYLOAD_MAGIC;
        request_frame[23:16]  = neighbor_node_id;
        request_frame[31:24]  = local_node_id;
        request_frame[39:32]  = training_sequence;
        request_frame[47:40]  = training_round_id;
        request_frame[55:48]  = selected_link_id;
        request_frame[56]     = selected_channel_id;
        request_frame[127:64] = TRAIN_PAYLOAD_PATTERN;

        tx_request_ready = !clear && !tx_fifo_full;
        tx_echo_ready    = !clear && request_pending && !tx_fifo_full;

        tx_fifo_wr_en       = request_write || echo_write;
        tx_fifo_wr_data     = echo_write ? pending_request_frame : request_frame;
        tx_fifo_train_frame = tx_fifo_wr_en;
        tx_fifo_link_id     = tx_fifo_wr_data[55:48];
        tx_fifo_channel_id  = tx_fifo_wr_data[56];

        // Stop consuming new requests while one exact echo is pending.
        rx_fifo_rd_en = !clear && !rx_fifo_empty &&
                        (expect_response || !request_pending);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_response_frame <= 128'd0;
            pending_request_frame    <= 128'd0;
            expected_response_valid <= 1'b0;
            request_pending          <= 1'b0;
            rx_request_valid         <= 1'b0;
            rx_request_timestamp     <= '0;
            rx_response_valid        <= 1'b0;
            rx_response_timestamp    <= '0;
            rx_rejected              <= 1'b0;
        end else if (clear) begin
            expected_response_valid <= 1'b0;
            request_pending          <= 1'b0;
            rx_request_valid         <= 1'b0;
            rx_response_valid        <= 1'b0;
            rx_rejected              <= 1'b0;
        end else begin
            rx_request_valid  <= 1'b0;
            rx_response_valid <= 1'b0;
            rx_rejected       <= 1'b0;

            if (request_write) begin
                expected_response_frame <= request_frame;
                expected_response_valid <= 1'b1;
            end

            if (echo_write)
                request_pending <= 1'b0;

            if (rx_record_fire) begin
                if (expect_response) begin
                    if (rx_expected_response) begin
                        rx_response_valid        <= 1'b1;
                        rx_response_timestamp    <= rx_fifo_timestamp;
                        expected_response_valid <= 1'b0;
                    end else begin
                        rx_rejected <= 1'b1;
                    end
                end else if (rx_common_ok && rx_targets_local) begin
                    pending_request_frame <= rx_fifo_rd_data;
                    request_pending       <= 1'b1;
                    rx_request_valid      <= 1'b1;
                    rx_request_timestamp  <= rx_fifo_timestamp;
                end else begin
                    rx_rejected <= 1'b1;
                end
            end
        end
    end

endmodule
