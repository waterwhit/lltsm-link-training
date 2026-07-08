`timescale 1ns/1ps

module tb_ttp_lltsm_branch_fsm;
    localparam integer FWD_DELAY = 5;
    localparam integer REV_DELAY = 9;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [31:0] time_now;
    always #5 clk = ~clk;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) time_now <= 0;
        else time_now <= time_now + 1'b1;
    end

    typedef struct packed {
        logic [1:0] frame_type;
        logic [15:0] frame_words;
        logic src;
        logic dst;
        logic link_id;
        logic channel_id;
        logic [7:0] round_id;
        logic [7:0] seq;
        logic [31:0] turnaround;
    } frame_t;

    logic training_enable, abort0, abort1;
    logic start0, ready0, start1, ready1;
    logic channel0, channel1;
    logic [7:0] round0, round1;
    logic tx_valid0, tx_ready0, tx_valid1, tx_ready1;
    frame_t tx0, tx1, rx0, rx1;
    logic rx_valid0, rx_complete0, rx_crc0, rx_protocol0;
    logic rx_valid1, rx_complete1, rx_crc1, rx_protocol1;
    logic [31:0] rx_ref0, rx_ref1;
    logic busy0, done0, result_valid0, result_ok0;
    logic busy1, done1, result_valid1, result_ok1;
    logic [31:0] result_rtt0, result_delay0, result_rtt1, result_delay1;
    logic [2:0] state0, state1;
    logic inject_bad_protocol_to_node1;

    assign tx_ready0 = 1'b1;
    assign tx_ready1 = 1'b1;

    ttp_lltsm_branch_fsm #(
        .NODE_COUNT(2), .CHANNEL_COUNT(2), .MEASURE_REPEATS(2),
        .RESPONSE_WAIT(10)
    ) node0 (
        .clk, .rst_n, .training_enable, .abort(abort0), .time_now,
        .local_start(start0), .local_start_ready(ready0),
        .local_node_id(1'b0), .local_neighbor_node_id(1'b1),
        .local_link_id(1'b0), .local_channel_id(channel0),
        .local_training_round_id(round0),
        .train_tx_valid(tx_valid0), .train_tx_ready(tx_ready0),
        .train_tx_frame_type(tx0.frame_type), .train_tx_frame_words(tx0.frame_words),
        .train_tx_src_node_id(tx0.src), .train_tx_dst_node_id(tx0.dst),
        .train_tx_link_id(tx0.link_id), .train_tx_channel_id(tx0.channel_id),
        .train_tx_training_round_id(tx0.round_id), .train_tx_sequence(tx0.seq),
        .train_tx_turnaround(tx0.turnaround),
        .train_rx_valid(rx_valid0), .train_rx_frame_complete(rx_complete0),
        .train_rx_crc_ok(rx_crc0), .train_rx_protocol_ok(rx_protocol0),
        .train_rx_frame_type(rx0.frame_type), .train_rx_frame_words(rx0.frame_words),
        .train_rx_src_node_id(rx0.src), .train_rx_dst_node_id(rx0.dst),
        .train_rx_link_id(rx0.link_id), .train_rx_channel_id(rx0.channel_id),
        .train_rx_training_round_id(rx0.round_id), .train_rx_sequence(rx0.seq),
        .train_rx_ref_time(rx_ref0), .train_rx_turnaround(rx0.turnaround),
        .busy(busy0), .done(done0), .result_valid(result_valid0),
        .result_ok(result_ok0), .result_rtt_average(result_rtt0),
        .result_mean_delay(result_delay0), .branch_state(state0)
    );

    ttp_lltsm_branch_fsm #(
        .NODE_COUNT(2), .CHANNEL_COUNT(2), .MEASURE_REPEATS(2),
        .RESPONSE_WAIT(10)
    ) node1 (
        .clk, .rst_n, .training_enable, .abort(abort1), .time_now,
        .local_start(start1), .local_start_ready(ready1),
        .local_node_id(1'b1), .local_neighbor_node_id(1'b0),
        .local_link_id(1'b0), .local_channel_id(channel1),
        .local_training_round_id(round1),
        .train_tx_valid(tx_valid1), .train_tx_ready(tx_ready1),
        .train_tx_frame_type(tx1.frame_type), .train_tx_frame_words(tx1.frame_words),
        .train_tx_src_node_id(tx1.src), .train_tx_dst_node_id(tx1.dst),
        .train_tx_link_id(tx1.link_id), .train_tx_channel_id(tx1.channel_id),
        .train_tx_training_round_id(tx1.round_id), .train_tx_sequence(tx1.seq),
        .train_tx_turnaround(tx1.turnaround),
        .train_rx_valid(rx_valid1), .train_rx_frame_complete(rx_complete1),
        .train_rx_crc_ok(rx_crc1), .train_rx_protocol_ok(rx_protocol1),
        .train_rx_frame_type(rx1.frame_type), .train_rx_frame_words(rx1.frame_words),
        .train_rx_src_node_id(rx1.src), .train_rx_dst_node_id(rx1.dst),
        .train_rx_link_id(rx1.link_id), .train_rx_channel_id(rx1.channel_id),
        .train_rx_training_round_id(rx1.round_id), .train_rx_sequence(rx1.seq),
        .train_rx_ref_time(rx_ref1), .train_rx_turnaround(rx1.turnaround),
        .busy(busy1), .done(done1), .result_valid(result_valid1),
        .result_ok(result_ok1), .result_rtt_average(result_rtt1),
        .result_mean_delay(result_delay1), .branch_state(state1)
    );

    logic [FWD_DELAY-1:0] fwd_valid_pipe;
    logic [REV_DELAY-1:0] rev_valid_pipe;
    frame_t fwd_frame_pipe [0:FWD_DELAY-1];
    frame_t rev_frame_pipe [0:REV_DELAY-1];
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fwd_valid_pipe <= '0;
            rev_valid_pipe <= '0;
            rx_valid0 <= 0; rx_complete0 <= 0; rx_crc0 <= 0; rx_protocol0 <= 0;
            rx_valid1 <= 0; rx_complete1 <= 0; rx_crc1 <= 0; rx_protocol1 <= 0;
            rx0 <= '0; rx1 <= '0; rx_ref0 <= 0; rx_ref1 <= 0;
            for (i=0; i<FWD_DELAY; i=i+1) fwd_frame_pipe[i] <= '0;
            for (i=0; i<REV_DELAY; i=i+1) rev_frame_pipe[i] <= '0;
        end else begin
            fwd_valid_pipe <= {fwd_valid_pipe[FWD_DELAY-2:0], tx_valid0 && tx_ready0};
            rev_valid_pipe <= {rev_valid_pipe[REV_DELAY-2:0], tx_valid1 && tx_ready1};
            fwd_frame_pipe[0] <= tx0;
            rev_frame_pipe[0] <= tx1;
            for (i=1; i<FWD_DELAY; i=i+1) fwd_frame_pipe[i] <= fwd_frame_pipe[i-1];
            for (i=1; i<REV_DELAY; i=i+1) rev_frame_pipe[i] <= rev_frame_pipe[i-1];

            rx_valid1 <= fwd_valid_pipe[FWD_DELAY-1];
            rx_complete1 <= fwd_valid_pipe[FWD_DELAY-1];
            rx_crc1 <= fwd_valid_pipe[FWD_DELAY-1];
            rx_protocol1 <= fwd_valid_pipe[FWD_DELAY-1];
            rx1 <= fwd_frame_pipe[FWD_DELAY-1];
            rx_ref1 <= time_now;

            rx_valid0 <= rev_valid_pipe[REV_DELAY-1];
            rx_complete0 <= rev_valid_pipe[REV_DELAY-1];
            rx_crc0 <= rev_valid_pipe[REV_DELAY-1];
            rx_protocol0 <= rev_valid_pipe[REV_DELAY-1];
            rx0 <= rev_frame_pipe[REV_DELAY-1];
            rx_ref0 <= time_now;

            if (inject_bad_protocol_to_node1) begin
                rx_valid1 <= 1'b1;
                rx_complete1 <= 1'b1;
                rx_crc1 <= 1'b1;
                rx_protocol1 <= 1'b0;
                rx1.frame_type <= 2'd1;
                rx1.frame_words <= 16'd8;
                rx1.src <= 1'b0;
                rx1.dst <= 1'b1;
                rx1.link_id <= 1'b0;
                rx1.channel_id <= channel1;
                rx1.round_id <= round1;
                rx1.seq <= 8'd0;
                rx_ref1 <= time_now;
            end
        end
    end

    task automatic start_node0;
        begin
            wait (ready0);
            @(negedge clk); start0 = 1'b1;
            @(negedge clk); start0 = 1'b0;
        end
    endtask

    task automatic start_node1;
        begin
            wait (ready1);
            @(negedge clk); start1 = 1'b1;
            @(negedge clk); start1 = 1'b0;
        end
    endtask

    initial begin
        training_enable = 1'b0;
        abort0 = 1'b0; abort1 = 1'b0;
        start0 = 1'b0; start1 = 1'b0;
        channel0 = 1'b0; channel1 = 1'b0;
        round0 = 8'h11; round1 = 8'h11;
        inject_bad_protocol_to_node1 = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        training_enable = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk); inject_bad_protocol_to_node1 = 1'b1;
        @(negedge clk); inject_bad_protocol_to_node1 = 1'b0;
        repeat (2) @(posedge clk);
        if (state1 != 3'd0) $fatal(1, "invalid protocol frame activated responder");

        start_node0();
        wait (result_valid0);
        if (!result_ok0 || (result_rtt0 == 0) || (result_delay0 == 0))
            $fatal(1, "node0 request direction failed");

        wait ((state0 == 3'd0) && (state1 == 3'd0));
        channel0 = 1'b1; channel1 = 1'b1;
        round0 = 8'h12; round1 = 8'h12;
        start_node1();
        wait (result_valid1);
        if (!result_ok1 || (result_rtt1 == 0) || (result_delay1 == 0))
            $fatal(1, "node1 reverse direction failed");

        // TOP owns cancellation/watchdog policy.
        wait ((state0 == 3'd0) && (state1 == 3'd0));
        start_node0();
        wait (state0 == 3'd2);
        @(negedge clk); abort0 = 1'b1;
        @(negedge clk); abort0 = 1'b0;
        wait (state0 == 3'd0);

        $display("PASS: simplified host-controller-controlled link training branch passed");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "simulation timeout state0=%0d state1=%0d", state0, state1);
    end
endmodule

