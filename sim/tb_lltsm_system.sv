`timescale 1ns/1ps

module tb_lltsm_system;
    localparam integer FWD_DELAY = 4;
    localparam integer REV_DELAY = 6;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [31:0] time_now;

    always #5 clk = ~clk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            time_now <= 32'd0;
        else
            time_now <= time_now + 1'b1;
    end

    logic enable_a, start_a, abort_a;
    logic enable_b, start_b, abort_b;
    logic start_ready_a, busy_a, done_a;
    logic start_ready_b, busy_b, done_b;
    logic [2:0] state_a, state_b;
    logic result_valid_a, result_ok_a;
    logic result_valid_b, result_ok_b;
    logic [31:0] result_rtt_a, result_delay_a;
    logic [31:0] result_rtt_b, result_delay_b;

    logic clear_a, request_valid_a, request_ready_a;
    logic echo_valid_a, echo_ready_a, expect_response_a;
    logic [7:0] sequence_a;
    logic rx_request_valid_a, rx_response_valid_a, rx_rejected_a;
    logic [31:0] rx_request_timestamp_a, rx_response_timestamp_a;

    logic clear_b, request_valid_b, request_ready_b;
    logic echo_valid_b, echo_ready_b, expect_response_b;
    logic [7:0] sequence_b;
    logic rx_request_valid_b, rx_response_valid_b, rx_rejected_b;
    logic [31:0] rx_request_timestamp_b, rx_response_timestamp_b;

    logic tx_wr_a, tx_wr_b;
    logic [127:0] tx_data_a, tx_data_b;
    logic tx_train_a, tx_train_b;
    logic [7:0] tx_link_a, tx_link_b;
    logic tx_channel_a, tx_channel_b;

    logic rx_empty_a, rx_empty_b;
    logic rx_rd_a, rx_rd_b;
    logic [127:0] rx_data_a, rx_data_b;
    logic rx_train_a, rx_train_b;
    logic rx_crc_a, rx_crc_b;
    logic [31:0] rx_timestamp_a, rx_timestamp_b;

    lltsm_fsm #(
        .MEASURE_REPEATS(2),
        .RESPONSE_WAIT(3),
        .RESPONSE_COMPENSATION_CYCLES(0)
    ) fsm_a (
        .clk,
        .rst_n,
        .branch_enable(enable_a),
        .branch_start(start_a),
        .branch_abort(abort_a),
        .branch_start_ready(start_ready_a),
        .branch_busy(busy_a),
        .branch_done(done_a),
        .branch_state(state_a),
        .time_now,
        .link_clear(clear_a),
        .link_tx_request_valid(request_valid_a),
        .link_tx_request_ready(request_ready_a),
        .link_tx_echo_valid(echo_valid_a),
        .link_tx_echo_ready(echo_ready_a),
        .link_expect_response(expect_response_a),
        .link_training_sequence(sequence_a),
        .link_rx_request_valid(rx_request_valid_a),
        .link_rx_request_timestamp(rx_request_timestamp_a),
        .link_rx_response_valid(rx_response_valid_a),
        .link_rx_response_timestamp(rx_response_timestamp_a),
        .result_valid(result_valid_a),
        .result_ok(result_ok_a),
        .result_rtt_average(result_rtt_a),
        .result_mean_delay(result_delay_a)
    );

    lltsm_link link_a (
        .clk,
        .rst_n,
        .clear(clear_a),
        .local_node_id(8'h01),
        .neighbor_node_id(8'h02),
        .selected_link_id(8'h05),
        .selected_channel_id(1'b1),
        .training_round_id(8'h34),
        .training_sequence(sequence_a),
        .tx_request_valid(request_valid_a),
        .tx_request_ready(request_ready_a),
        .tx_echo_valid(echo_valid_a),
        .tx_echo_ready(echo_ready_a),
        .expect_response(expect_response_a),
        .rx_request_valid(rx_request_valid_a),
        .rx_request_timestamp(rx_request_timestamp_a),
        .rx_response_valid(rx_response_valid_a),
        .rx_response_timestamp(rx_response_timestamp_a),
        .rx_rejected(rx_rejected_a),
        .tx_fifo_full(1'b0),
        .tx_fifo_wr_en(tx_wr_a),
        .tx_fifo_wr_data(tx_data_a),
        .tx_fifo_train_frame(tx_train_a),
        .tx_fifo_link_id(tx_link_a),
        .tx_fifo_channel_id(tx_channel_a),
        .rx_fifo_empty(rx_empty_a),
        .rx_fifo_rd_en(rx_rd_a),
        .rx_fifo_rd_data(rx_data_a),
        .rx_fifo_train_frame(rx_train_a),
        .rx_fifo_crc_ok(rx_crc_a),
        .rx_fifo_timestamp(rx_timestamp_a)
    );

    lltsm_fsm #(
        .MEASURE_REPEATS(2),
        .RESPONSE_WAIT(3),
        .RESPONSE_COMPENSATION_CYCLES(0)
    ) fsm_b (
        .clk,
        .rst_n,
        .branch_enable(enable_b),
        .branch_start(start_b),
        .branch_abort(abort_b),
        .branch_start_ready(start_ready_b),
        .branch_busy(busy_b),
        .branch_done(done_b),
        .branch_state(state_b),
        .time_now,
        .link_clear(clear_b),
        .link_tx_request_valid(request_valid_b),
        .link_tx_request_ready(request_ready_b),
        .link_tx_echo_valid(echo_valid_b),
        .link_tx_echo_ready(echo_ready_b),
        .link_expect_response(expect_response_b),
        .link_training_sequence(sequence_b),
        .link_rx_request_valid(rx_request_valid_b),
        .link_rx_request_timestamp(rx_request_timestamp_b),
        .link_rx_response_valid(rx_response_valid_b),
        .link_rx_response_timestamp(rx_response_timestamp_b),
        .result_valid(result_valid_b),
        .result_ok(result_ok_b),
        .result_rtt_average(result_rtt_b),
        .result_mean_delay(result_delay_b)
    );

    lltsm_link link_b (
        .clk,
        .rst_n,
        .clear(clear_b),
        .local_node_id(8'h02),
        .neighbor_node_id(8'h01),
        .selected_link_id(8'h05),
        .selected_channel_id(1'b1),
        .training_round_id(8'h34),
        .training_sequence(sequence_b),
        .tx_request_valid(request_valid_b),
        .tx_request_ready(request_ready_b),
        .tx_echo_valid(echo_valid_b),
        .tx_echo_ready(echo_ready_b),
        .expect_response(expect_response_b),
        .rx_request_valid(rx_request_valid_b),
        .rx_request_timestamp(rx_request_timestamp_b),
        .rx_response_valid(rx_response_valid_b),
        .rx_response_timestamp(rx_response_timestamp_b),
        .rx_rejected(rx_rejected_b),
        .tx_fifo_full(1'b0),
        .tx_fifo_wr_en(tx_wr_b),
        .tx_fifo_wr_data(tx_data_b),
        .tx_fifo_train_frame(tx_train_b),
        .tx_fifo_link_id(tx_link_b),
        .tx_fifo_channel_id(tx_channel_b),
        .rx_fifo_empty(rx_empty_b),
        .rx_fifo_rd_en(rx_rd_b),
        .rx_fifo_rd_data(rx_data_b),
        .rx_fifo_train_frame(rx_train_b),
        .rx_fifo_crc_ok(rx_crc_b),
        .rx_fifo_timestamp(rx_timestamp_b)
    );

    logic [FWD_DELAY-1:0] fwd_valid;
    logic [REV_DELAY-1:0] rev_valid;
    logic [127:0] fwd_data [0:FWD_DELAY-1];
    logic [127:0] rev_data [0:REV_DELAY-1];
    logic [127:0] last_request_frame;
    logic inject_bad_to_b;
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fwd_valid     <= '0;
            rev_valid     <= '0;
            rx_empty_a    <= 1'b1;
            rx_empty_b    <= 1'b1;
            rx_data_a     <= 128'd0;
            rx_data_b     <= 128'd0;
            rx_train_a    <= 1'b0;
            rx_train_b    <= 1'b0;
            rx_crc_a      <= 1'b0;
            rx_crc_b      <= 1'b0;
            rx_timestamp_a <= 32'd0;
            rx_timestamp_b <= 32'd0;
            last_request_frame <= 128'd0;
            for (i = 0; i < FWD_DELAY; i = i + 1)
                fwd_data[i] <= 128'd0;
            for (i = 0; i < REV_DELAY; i = i + 1)
                rev_data[i] <= 128'd0;
        end else begin
            fwd_valid[0] <= tx_wr_a;
            rev_valid[0] <= tx_wr_b;
            fwd_data[0]  <= tx_data_a;
            rev_data[0]  <= tx_data_b;

            for (i = 1; i < FWD_DELAY; i = i + 1) begin
                fwd_valid[i] <= fwd_valid[i-1];
                fwd_data[i]  <= fwd_data[i-1];
            end
            for (i = 1; i < REV_DELAY; i = i + 1) begin
                rev_valid[i] <= rev_valid[i-1];
                rev_data[i]  <= rev_data[i-1];
            end

            if (tx_wr_a) begin
                if (!tx_train_a || (tx_link_a != 8'h05) || !tx_channel_a)
                    $fatal(1, "node A TX FIFO metadata mismatch");
                last_request_frame <= tx_data_a;
            end

            if (tx_wr_b) begin
                if (!tx_train_b || (tx_data_b != last_request_frame))
                    $fatal(1, "response payload or training-frame class changed");
            end

            if (!rx_empty_a && rx_rd_a)
                rx_empty_a <= 1'b1;
            if (!rx_empty_b && rx_rd_b)
                rx_empty_b <= 1'b1;

            if (fwd_valid[FWD_DELAY-1]) begin
                rx_empty_b     <= 1'b0;
                rx_data_b      <= fwd_data[FWD_DELAY-1];
                rx_train_b     <= 1'b1;
                rx_crc_b       <= 1'b1;
                rx_timestamp_b <= time_now;
            end

            if (rev_valid[REV_DELAY-1]) begin
                rx_empty_a     <= 1'b0;
                rx_data_a      <= rev_data[REV_DELAY-1];
                rx_train_a     <= 1'b1;
                rx_crc_a       <= 1'b1;
                rx_timestamp_a <= time_now;
            end

            if (inject_bad_to_b) begin
                rx_empty_b     <= 1'b0;
                rx_data_b      <= 128'h1;
                rx_train_b     <= 1'b1;
                rx_crc_b       <= 1'b0;
                rx_timestamp_b <= time_now;
            end
        end
    end

    task automatic pulse_start_a;
        begin
            wait (start_ready_a);
            @(negedge clk);
            start_a = 1'b1;
            @(negedge clk);
            start_a = 1'b0;
        end
    endtask

    initial begin
        enable_a = 1'b0;
        enable_b = 1'b0;
        start_a = 1'b0;
        start_b = 1'b0;
        abort_a = 1'b0;
        abort_b = 1'b0;
        inject_bad_to_b = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        enable_a = 1'b1;
        enable_b = 1'b1;
        repeat (2) @(posedge clk);

        // MAC rejection information and payload checks stay in LLTSM_LINK.
        @(negedge clk);
        inject_bad_to_b = 1'b1;
        @(negedge clk);
        inject_bad_to_b = 1'b0;
        wait (rx_rejected_b);
        if (state_b != 3'd0)
            $fatal(1, "bad frame activated responder FSM");

        pulse_start_a();
        wait (done_a);
        if (!result_valid_a || !result_ok_a ||
            (result_rtt_a == 0) || (result_delay_a == 0))
            $fatal(1, "end-to-end training result invalid");

        // Controller TOP owns branch cancellation and subsequent state change.
        wait ((state_a == 3'd0) && (state_b == 3'd0));
        pulse_start_a();
        wait (state_a == 3'd2);
        @(negedge clk);
        abort_a = 1'b1;
        @(negedge clk);
        abort_a = 1'b0;
        wait (state_a == 3'd0);

        $display("PASS: two-module LLTSM architecture and exact echo verified");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "simulation timeout state_a=%0d state_b=%0d", state_a, state_b);
    end

endmodule
