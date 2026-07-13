`timescale 1ns/1ps

// Boundary and fault tests for the LLTSM ready/valid and RX record interfaces.
module tb_lltsm_boundary;
    localparam integer TIME_WIDTH = 8;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [TIME_WIDTH-1:0] time_now;

    always #5 clk = ~clk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            time_now <= '0;
        else
            time_now <= time_now + 1'b1;
    end

    logic train_enable, train_start, train_abort;
    logic train_start_ready, train_busy, train_done;
    logic [2:0] train_state;
    logic link_clear, link_tx_req_valid, link_tx_req_ready;
    logic link_tx_rsp_valid, link_tx_rsp_ready, link_expect_rsp;
    logic [7:0] link_training_sequence;
    logic link_rx_req_valid, link_rx_rsp_valid;
    logic [TIME_WIDTH-1:0] link_rx_rsp_timestamp;
    logic result_valid, result_ok;
    logic [TIME_WIDTH-1:0] result_rtt_average, result_mean_delay;

    logic tx_fifo_full, tx_fifo_wr_en;
    logic [127:0] tx_fifo_wr_data;
    logic [7:0] tx_fifo_link_id;
    logic tx_fifo_channel_id;
    logic rx_fifo_empty, rx_fifo_rd_en;
    logic [127:0] rx_fifo_rd_data;
    logic rx_fifo_crc_ok;
    logic [TIME_WIDTH-1:0] rx_fifo_timestamp;
    logic rx_rejected;

    logic [127:0] accepted_request;
    logic [127:0] held_payload;
    integer hold_cycles;
    integer observed_rtt;
    integer test_phase;

    lltsm_fsm #(
        .TIME_WIDTH(TIME_WIDTH),
        .DELAY_WIDTH(TIME_WIDTH),
        .MEASURE_REPEATS(1),
        .RSP_WAIT(2),
        .RSP_COMPENSATION_CYCLES(0)
    ) u_fsm (
        .clk,
        .rst_n,
        .train_enable,
        .train_start,
        .train_abort,
        .train_start_ready,
        .train_busy,
        .train_done,
        .train_state,
        .time_now,
        .link_clear,
        .link_tx_req_valid,
        .link_tx_req_ready,
        .link_tx_rsp_valid,
        .link_tx_rsp_ready,
        .link_expect_rsp,
        .link_training_sequence,
        .link_rx_req_valid,
        .link_rx_rsp_valid,
        .link_rx_rsp_timestamp,
        .result_valid,
        .result_ok,
        .result_rtt_average,
        .result_mean_delay
    );

    lltsm_link #(
        .TIME_WIDTH(TIME_WIDTH)
    ) u_link (
        .clk,
        .rst_n,
        .clear(link_clear),
        .local_node_id(8'h01),
        .neighbor_node_id(8'h02),
        .selected_link_id(8'h05),
        .selected_channel_id(1'b1),
        .training_round_id(8'h34),
        .training_sequence(link_training_sequence),
        .tx_req_valid(link_tx_req_valid),
        .tx_req_ready(link_tx_req_ready),
        .tx_rsp_valid(link_tx_rsp_valid),
        .tx_rsp_ready(link_tx_rsp_ready),
        .expect_rsp(link_expect_rsp),
        .rx_req_valid(link_rx_req_valid),
        .rx_req_timestamp(),
        .rx_rsp_valid(link_rx_rsp_valid),
        .rx_rsp_timestamp(link_rx_rsp_timestamp),
        .rx_rejected,
        .tx_fifo_full,
        .tx_fifo_wr_en,
        .tx_fifo_wr_data,
        .tx_fifo_link_id,
        .tx_fifo_channel_id,
        .rx_fifo_empty,
        .rx_fifo_rd_en,
        .rx_fifo_rd_data,
        .rx_fifo_crc_ok,
        .rx_fifo_timestamp
    );

    task automatic pulse_start;
        begin
            wait (train_start_ready);
            @(negedge clk);
            train_start = 1'b1;
            @(negedge clk);
            train_start = 1'b0;
        end
    endtask

    task automatic push_rx_record(
        input logic [127:0] payload,
        input logic crc_ok
    );
        begin
            @(negedge clk);
            rx_fifo_rd_data = payload;
            rx_fifo_crc_ok = crc_ok;
            rx_fifo_timestamp = time_now;
            rx_fifo_empty = 1'b0;
            @(posedge clk);
            if (!rx_fifo_rd_en)
                $fatal(1, "RX FWFT record was not accepted");
            @(negedge clk);
            rx_fifo_empty = 1'b1;
            rx_fifo_crc_ok = 1'b0;
        end
    endtask

    function automatic [127:0] remote_request;
        input [7:0] sequence_id;
        reg [127:0] frame;
        begin
            frame = 128'd0;
            frame[15:0]   = 16'hD15A;
            frame[23:16]  = 8'h01;
            frame[31:24]  = 8'h02;
            frame[39:32]  = sequence_id;
            frame[47:40]  = 8'h34;
            frame[55:48]  = 8'h05;
            frame[56]     = 1'b1;
            frame[127:64] = 64'hA55A_C33C_5AA5_3CC3;
            remote_request = frame;
        end
    endfunction

    initial begin
        train_enable = 1'b0;
        train_start = 1'b0;
        train_abort = 1'b0;
        tx_fifo_full = 1'b0;
        rx_fifo_empty = 1'b1;
        rx_fifo_rd_data = 128'd0;
        rx_fifo_crc_ok = 1'b0;
        rx_fifo_timestamp = '0;
        accepted_request = 128'd0;
        test_phase = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        train_enable = 1'b1;
        repeat (2) @(posedge clk);

        // TX ready/valid boundary: valid and payload must remain stable while
        // the width-converting FIFO applies backpressure.
        tx_fifo_full = 1'b1;
        test_phase = 1;
        pulse_start();
        wait (link_tx_req_valid);
        held_payload = tx_fifo_wr_data;
        for (hold_cycles = 0; hold_cycles < 5; hold_cycles = hold_cycles + 1) begin
            @(posedge clk);
            if (!link_tx_req_valid || link_tx_req_ready)
                $fatal(1, "request valid/ready violated during backpressure");
            if (tx_fifo_wr_data !== held_payload)
                $fatal(1, "request payload changed during backpressure");
        end
        @(negedge clk);
        tx_fifo_full = 1'b0;
        wait (tx_fifo_wr_en);
        accepted_request = tx_fifo_wr_data;
        if ((tx_fifo_link_id != 8'h05) || !tx_fifo_channel_id)
            $fatal(1, "TX metadata mismatch");
        wait (train_state == 3'd2);

        // CRC failure and a field mismatch are consumed and rejected without
        // completing the local measurement.
        push_rx_record(accepted_request, 1'b0);
        test_phase = 2;
        wait (rx_rejected);
        if (train_state != 3'd2)
            $fatal(1, "bad CRC changed WAIT_RSP state");

        push_rx_record(accepted_request ^ 128'h1, 1'b1);
        test_phase = 3;
        wait (rx_rejected);
        if (train_state != 3'd2)
            $fatal(1, "bad payload changed WAIT_RSP state");

        // The branch has no internal response timeout by design. It must hold
        // state and outputs until TOP scheduler aborts it.
        repeat (20) @(posedge clk);
        test_phase = 4;
        if ((train_state != 3'd2) || !train_busy || !link_expect_rsp)
            $fatal(1, "WAIT_RSP did not hold without a response");

        push_rx_record(accepted_request, 1'b1);
        test_phase = 5;
        wait (train_done);
        if (!result_valid || !result_ok || (result_rtt_average == 0))
            $fatal(1, "valid response did not produce a result");

        // Controller-owned abort must cancel an outstanding measurement and
        // clear link context so a new train can start.
        wait (train_state == 3'd0);
        test_phase = 6;
        pulse_start();
        wait (train_state == 3'd2);
        @(negedge clk);
        train_abort = 1'b1;
        @(negedge clk);
        train_abort = 1'b0;
        wait (train_state == 3'd0);
        if (train_busy)
            $fatal(1, "abort left train_busy asserted");

        // Remote responder path: response valid and exact echo must remain
        // stable while TX FIFO is full.
        push_rx_record(remote_request(8'h77), 1'b1);
        test_phase = 7;
        wait (link_rx_req_valid);
        tx_fifo_full = 1'b1;
        wait (link_tx_rsp_valid);
        #1;
        held_payload = tx_fifo_wr_data;
        repeat (4) begin
            @(posedge clk);
            if (!link_tx_rsp_valid || link_tx_rsp_ready)
                $fatal(1, "response valid/ready violated during backpressure");
            if (tx_fifo_wr_data !== held_payload)
                $fatal(1, "response payload changed during backpressure got=%032h held=%032h",
                       tx_fifo_wr_data, held_payload);
        end
        if (held_payload !== remote_request(8'h77))
            $fatal(1, "response is not an exact echo got=%032h expected=%032h",
                   held_payload, remote_request(8'h77));
        @(negedge clk);
        tx_fifo_full = 1'b0;
        wait (tx_fifo_wr_en);
        wait (train_state == 3'd0);

        // Counter wrap: accept a request near 8-bit rollover, then return the
        // exact frame after rollover. The modular RTT must remain non-zero.
        wait (time_now >= 8'hF8);
        test_phase = 8;
        pulse_start();
        wait (tx_fifo_wr_en);
        accepted_request = tx_fifo_wr_data;
        wait (time_now < 8'h10);
        push_rx_record(accepted_request, 1'b1);
        wait (train_done);
        observed_rtt = result_rtt_average;
        if (!result_ok || (observed_rtt <= 0) || (observed_rtt >= 32))
            $fatal(1, "counter-wrap RTT invalid: %0d", observed_rtt);

        // Dropping train_enable is equivalent to leaving C_LINK_TRAIN.
        wait (train_state == 3'd0);
        test_phase = 9;
        pulse_start();
        wait (train_state == 3'd2);
        @(negedge clk);
        train_enable = 1'b0;
        @(posedge clk);
        #1;
        if ((train_state != 3'd0) || train_busy)
            $fatal(1, "train_enable removal did not return to IDLE");

        $display("PASS: LLTSM boundary, validation, backpressure, wrap and abort tests");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "boundary simulation timeout phase=%0d state=%0d time=%0d",
               test_phase, train_state, time_now);
    end

endmodule
