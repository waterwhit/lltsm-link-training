`timescale 1ns/1ps

// LLTSM link engine.

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
    input  logic                  tx_req_valid,
    output logic                  tx_req_ready,
    input  logic                  tx_rsp_valid,
    output logic                  tx_rsp_ready,
    input  logic                  expect_rsp,

    output logic                  rx_req_valid,
    output logic [TIME_WIDTH-1:0] rx_req_timestamp,
    output logic                  rx_rsp_valid,
    output logic [TIME_WIDTH-1:0] rx_rsp_timestamp,
    output logic                  rx_rejected,

    // Wide write side of TX width-converting FIFO: 128-bit LLTSM -> MAC width.
    input  logic                  tx_fifo_full,
    output logic                  tx_fifo_wr_en,
    output logic [127:0]          tx_fifo_wr_data,
    output logic [7:0]            tx_fifo_link_id,
    output logic                  tx_fifo_channel_id,

    // Wide read side of RX width-converting FIFO: MAC width -> 128-bit LLTSM.
    // The interface follows first-word-fall-through semantics: data and
    // sidebands are valid while empty=0 and are consumed by rd_en.
    input  logic                  rx_fifo_empty,
    output logic                  rx_fifo_rd_en,
    input  logic [127:0]          rx_fifo_rd_data,
    input  logic                  rx_fifo_crc_ok,
    input  logic [TIME_WIDTH-1:0] rx_fifo_timestamp
);

    logic [127:0] req_frame;
    logic [127:0] expected_rsp_frame;
    logic [127:0] pending_req_frame;
    logic         expected_rsp_valid;
    logic         req_pending;

    wire req_write = tx_req_valid && tx_req_ready;
    wire rsp_write = tx_rsp_valid && tx_rsp_ready;
    wire rsp_selected = tx_rsp_valid && req_pending;

    wire rx_record_fire = !rx_fifo_empty && rx_fifo_rd_en;
    // LLTSM_LINK, rather than the MAC, recognizes the fixed training payload.
    wire rx_checker =
        (rx_fifo_rd_data[15:0] == TRAIN_PAYLOAD_MAGIC) &&
        (rx_fifo_rd_data[63:57] == 7'd0) &&
        (rx_fifo_rd_data[127:64] == TRAIN_PAYLOAD_PATTERN);

    wire rx_common_ok = rx_fifo_crc_ok && rx_checker;

    wire rx_targets_local = (rx_fifo_rd_data[31:24] == neighbor_node_id) &&
                            (rx_fifo_rd_data[23:16] == local_node_id) &&
                            (rx_fifo_rd_data[55:48] == selected_link_id) &&
                            (rx_fifo_rd_data[56] == selected_channel_id) &&
                            (rx_fifo_rd_data[47:40] == training_round_id);

    wire rx_expected_rsp = rx_common_ok &&
                           expected_rsp_valid &&
                           (rx_fifo_rd_data == expected_rsp_frame);

    initial begin
        if (TIME_WIDTH < 1)
            $fatal(1, "lltsm_link requires TIME_WIDTH >= 1");
    end

    always_comb begin
        req_frame = 128'd0;
        req_frame[15:0]   = TRAIN_PAYLOAD_MAGIC;
        req_frame[23:16]  = neighbor_node_id;
        req_frame[31:24]  = local_node_id;
        req_frame[39:32]  = training_sequence;
        req_frame[47:40]  = training_round_id;
        req_frame[55:48]  = selected_link_id;
        req_frame[56]     = selected_channel_id;
        req_frame[127:64] = TRAIN_PAYLOAD_PATTERN;

        tx_rsp_ready = !clear && req_pending && !tx_fifo_full;
        // Response has priority if both commands are asserted unexpectedly.
        tx_req_ready = !clear && !tx_fifo_full &&
                       !(tx_rsp_valid && req_pending);

        tx_fifo_wr_en       = req_write || rsp_write;
        // Payload selection follows valid, not the completed handshake.  This
        // keeps the response payload stable for the complete valid && !ready
        // backpressure interval, as required by the ready/valid contract.
        tx_fifo_wr_data     = rsp_selected ? pending_req_frame : req_frame;
        tx_fifo_link_id     = tx_fifo_wr_data[55:48];
        tx_fifo_channel_id  = tx_fifo_wr_data[56];

        // Stop consuming new requests while one exact echo is pending.
        rx_fifo_rd_en = !clear && !rx_fifo_empty &&
                        (expect_rsp || !req_pending);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_rsp_frame <= 128'd0;
            pending_req_frame  <= 128'd0;
            expected_rsp_valid <= 1'b0;
            req_pending        <= 1'b0;
            rx_req_valid       <= 1'b0;
            rx_req_timestamp   <= '0;
            rx_rsp_valid       <= 1'b0;
            rx_rsp_timestamp   <= '0;
            rx_rejected              <= 1'b0;
        end else if (clear) begin
            expected_rsp_valid <= 1'b0;
            req_pending        <= 1'b0;
            rx_req_valid       <= 1'b0;
            rx_rsp_valid       <= 1'b0;
            rx_rejected        <= 1'b0;
        end else begin
            rx_req_valid <= 1'b0;
            rx_rsp_valid <= 1'b0;
            rx_rejected  <= 1'b0;

            if (req_write) begin
                expected_rsp_frame <= req_frame;
                expected_rsp_valid <= 1'b1;
            end

            if (rsp_write)
                req_pending <= 1'b0;

            if (rx_record_fire) begin
                if (expect_rsp) begin
                    if (rx_expected_rsp) begin
                        rx_rsp_valid       <= 1'b1;
                        rx_rsp_timestamp   <= rx_fifo_timestamp;
                        expected_rsp_valid <= 1'b0;
                    end else begin
                        rx_rejected <= 1'b1;
                    end
                end else if (rx_common_ok && rx_targets_local) begin
                    pending_req_frame <= rx_fifo_rd_data;
                    req_pending       <= 1'b1;
                    rx_req_valid      <= 1'b1;
                    rx_req_timestamp  <= rx_fifo_timestamp;
                end else begin
                    rx_rejected <= 1'b1;
                end
            end
        end
    end

endmodule
