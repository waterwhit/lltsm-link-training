`timescale 1ns/1ps

// LLTSM branch FSM.
//
// The communication-controller TOP owns the transition into and out of this
// branch. It asserts branch_enable while LLTSM is selected, pulses branch_start
// for a local measurement, and leaves the branch when branch_done is observed.
// This FSM schedules lltsm_link but contains no MAC framing or CRC logic.

module lltsm_fsm #(
    parameter integer TIME_WIDTH = 32,
    parameter integer DELAY_WIDTH = 32,
    parameter integer MEASURE_REPEATS = 4,
    parameter integer RESPONSE_WAIT = 32,
    parameter integer RESPONSE_COMPENSATION_CYCLES = 0,
    parameter integer SAMPLE_COUNT_WIDTH =
        (MEASURE_REPEATS <= 1) ? 1 : $clog2(MEASURE_REPEATS),
    parameter integer RESPONSE_COUNT_WIDTH =
        (RESPONSE_WAIT < 1) ? 1 : $clog2(RESPONSE_WAIT + 1)
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Communication-controller TOP branch control.
    input  logic                   branch_enable,
    input  logic                   branch_start,
    input  logic                   branch_abort,
    output logic                   branch_start_ready,
    output logic                   branch_busy,
    output logic                   branch_done,
    output logic [2:0]             branch_state,

    input  logic [TIME_WIDTH-1:0]  time_now,

    // Command/status connection to lltsm_link.
    output logic                   link_clear,
    output logic                   link_tx_request_valid,
    input  logic                   link_tx_request_ready,
    output logic                   link_tx_echo_valid,
    input  logic                   link_tx_echo_ready,
    output logic                   link_expect_response,
    output logic [7:0]             link_training_sequence,
    input  logic                   link_rx_request_valid,
    input  logic [TIME_WIDTH-1:0]  link_rx_request_timestamp,
    input  logic                   link_rx_response_valid,
    input  logic [TIME_WIDTH-1:0]  link_rx_response_timestamp,

    // Result is presented for one cycle with branch_done.
    output logic                   result_valid,
    output logic                   result_ok,
    output logic [DELAY_WIDTH-1:0] result_rtt_average,
    output logic [DELAY_WIDTH-1:0] result_mean_delay
);

    localparam logic [2:0] S_IDLE          = 3'd0;
    localparam logic [2:0] S_SEND_REQUEST  = 3'd1;
    localparam logic [2:0] S_WAIT_RESPONSE = 3'd2;
    localparam logic [2:0] S_RESPONSE_WAIT = 3'd3;
    localparam logic [2:0] S_SEND_ECHO     = 3'd4;
    localparam logic [2:0] S_DONE          = 3'd5;

    localparam integer SUM_WIDTH = DELAY_WIDTH + $clog2(MEASURE_REPEATS + 1);
    localparam logic [DELAY_WIDTH-1:0] RESPONSE_COMPENSATION =
        RESPONSE_COMPENSATION_CYCLES;

    logic [2:0] state;
    logic [SAMPLE_COUNT_WIDTH-1:0] sample_count;
    logic [RESPONSE_COUNT_WIDTH-1:0] response_wait_count;
    logic [TIME_WIDTH-1:0] request_tx_timestamp;
    logic [SUM_WIDTH-1:0] rtt_sum;

    logic [DELAY_WIDTH-1:0] current_rtt;
    logic [DELAY_WIDTH-1:0] final_rtt_average;
    logic [DELAY_WIDTH-1:0] compensated_rtt;

    wire request_fire = link_tx_request_valid && link_tx_request_ready;
    wire echo_fire    = link_tx_echo_valid && link_tx_echo_ready;

    initial begin
        if (TIME_WIDTH != DELAY_WIDTH)
            $fatal(1, "lltsm_fsm requires TIME_WIDTH == DELAY_WIDTH");
        if ((MEASURE_REPEATS <= 0) ||
            ((MEASURE_REPEATS & (MEASURE_REPEATS - 1)) != 0) ||
            (MEASURE_REPEATS > 256))
            $fatal(1, "lltsm_fsm requires a power-of-two MEASURE_REPEATS <= 256");
        if (RESPONSE_WAIT < 0)
            $fatal(1, "lltsm_fsm requires RESPONSE_WAIT >= 0");
        if (RESPONSE_COMPENSATION_CYCLES < 0)
            $fatal(1, "lltsm_fsm requires RESPONSE_COMPENSATION_CYCLES >= 0");
    end

    always_comb begin
        if (link_rx_response_timestamp >= request_tx_timestamp)
            current_rtt = link_rx_response_timestamp - request_tx_timestamp;
        else
            current_rtt = ({TIME_WIDTH{1'b1}} - request_tx_timestamp) +
                          link_rx_response_timestamp + 1'b1;

        final_rtt_average = (rtt_sum + current_rtt) / MEASURE_REPEATS;
        if (final_rtt_average > RESPONSE_COMPENSATION)
            compensated_rtt = final_rtt_average - RESPONSE_COMPENSATION;
        else
            compensated_rtt = '0;
    end

    always_comb begin
        branch_state             = state;
        branch_start_ready       = branch_enable && (state == S_IDLE) &&
                                   !link_rx_request_valid;
        branch_busy              = (state != S_IDLE) && (state != S_DONE);
        branch_done              = (state == S_DONE);
        result_valid             = (state == S_DONE);

        link_clear               = branch_abort || !branch_enable;
        link_tx_request_valid    = (state == S_SEND_REQUEST);
        link_tx_echo_valid       = (state == S_SEND_ECHO);
        link_expect_response     = (state == S_WAIT_RESPONSE);
        link_training_sequence   = sample_count;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= S_IDLE;
            sample_count         <= '0;
            response_wait_count  <= '0;
            request_tx_timestamp <= '0;
            rtt_sum              <= '0;
            result_ok            <= 1'b0;
            result_rtt_average   <= '0;
            result_mean_delay    <= '0;
        end else if (branch_abort || !branch_enable) begin
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

                    // A remote request wins arbitration over a local start.
                    if (link_rx_request_valid) begin
                        if (RESPONSE_WAIT == 0) begin
                            response_wait_count <= '0;
                            state <= S_SEND_ECHO;
                        end else begin
                            response_wait_count <= RESPONSE_WAIT - 1;
                            state <= S_RESPONSE_WAIT;
                        end
                    end else if (branch_start && branch_start_ready) begin
                        state <= S_SEND_REQUEST;
                    end
                end

                S_SEND_REQUEST: begin
                    if (request_fire) begin
                        // Frozen reference point: accepted wide TX FIFO write.
                        request_tx_timestamp <= time_now;
                        state <= S_WAIT_RESPONSE;
                    end
                end

                S_WAIT_RESPONSE: begin
                    if (link_rx_response_valid) begin
                        if (sample_count == MEASURE_REPEATS - 1) begin
                            result_rtt_average <= final_rtt_average;
                            result_mean_delay  <= compensated_rtt >> 1;
                            result_ok          <=
                                (final_rtt_average > RESPONSE_COMPENSATION);
                            state <= S_DONE;
                        end else begin
                            rtt_sum      <= rtt_sum + current_rtt;
                            sample_count <= sample_count + 1'b1;
                            state        <= S_SEND_REQUEST;
                        end
                    end
                end

                S_RESPONSE_WAIT: begin
                    if (response_wait_count != 0)
                        response_wait_count <= response_wait_count - 1'b1;
                    else
                        state <= S_SEND_ECHO;
                end

                S_SEND_ECHO: begin
                    if (echo_fire)
                        state <= S_IDLE;
                end

                S_DONE: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

    // Exposed by lltsm_link for controller observability. Response scheduling
    // itself uses the deterministic wait counter.
    wire unused_request_timestamp = ^link_rx_request_timestamp;

endmodule
