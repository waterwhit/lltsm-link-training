`timescale 1ns/1ps

// LLTSM train FSM.

module lltsm_fsm #(
    parameter integer TIME_WIDTH = 32,
    parameter integer DELAY_WIDTH = 32,
    parameter integer MEASURE_REPEATS = 4,
    parameter integer RSP_WAIT = 32,
    parameter integer RSP_COMPENSATION_CYCLES = 0,
    parameter integer SAMPLE_COUNT_WIDTH =
        (MEASURE_REPEATS <= 1) ? 1 : $clog2(MEASURE_REPEATS),
    parameter integer RSP_COUNT_WIDTH =
        (RSP_WAIT < 1) ? 1 : $clog2(RSP_WAIT + 1)
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Communication-controller TOP train control.
    input  logic                   train_enable,
    input  logic                   train_start,
    input  logic                   train_abort,

    output logic                   train_start_ready,
    output logic                   train_busy,
    output logic                   train_done,
    output logic [2:0]             train_state,

    input  logic [TIME_WIDTH-1:0]  time_now,

    // Command/status connection to lltsm_link.
    output logic                   link_clear,
    output logic                   link_tx_req_valid,
    input  logic                   link_tx_req_ready,
    output logic                   link_tx_rsp_valid,

    input  logic                   link_tx_rsp_ready,
    output logic                   link_expect_rsp,
    output logic [7:0]             link_training_sequence,
    input  logic                   link_rx_req_valid,
    input  logic                   link_rx_rsp_valid,
    input  logic [TIME_WIDTH-1:0]  link_rx_rsp_timestamp,

    // Result is presented for one cycle with train_done.
    output logic                   result_valid,
    output logic                   result_ok,
    output logic [DELAY_WIDTH-1:0] result_rtt_average,
    output logic [DELAY_WIDTH-1:0] result_mean_delay
);

    localparam logic [2:0] S_IDLE      = 3'd0;
    localparam logic [2:0] S_SEND_REQ  = 3'd1;
    localparam logic [2:0] S_WAIT_RSP  = 3'd2;
    localparam logic [2:0] S_RSP_WAIT  = 3'd3;
    localparam logic [2:0] S_SEND_RSP  = 3'd4;
    localparam logic [2:0] S_DONE      = 3'd5;

    localparam integer SUM_WIDTH = DELAY_WIDTH + $clog2(MEASURE_REPEATS + 1);
    localparam integer AVG_SHIFT = $clog2(MEASURE_REPEATS);
    localparam logic [DELAY_WIDTH-1:0] RSP_COMPENSATION =
        RSP_COMPENSATION_CYCLES;
    localparam logic [SAMPLE_COUNT_WIDTH-1:0] LAST_SAMPLE =
        MEASURE_REPEATS - 1;
    localparam logic [RSP_COUNT_WIDTH-1:0] RSP_WAIT_LOAD =
        (RSP_WAIT > 0) ? RSP_WAIT - 1 : '0;

    logic [2:0] state;
    logic [2:0] next_state;
    logic [SAMPLE_COUNT_WIDTH-1:0] sample_count;
    logic [RSP_COUNT_WIDTH-1:0] rsp_wait_count;
    logic [TIME_WIDTH-1:0] req_tx_timestamp;
    logic [SUM_WIDTH-1:0] rtt_sum;

    logic [DELAY_WIDTH-1:0] current_rtt;
    logic [DELAY_WIDTH-1:0] final_rtt_average;
    logic [DELAY_WIDTH-1:0] compensated_rtt;

    wire req_fire    = link_tx_req_valid && link_tx_req_ready;
    wire rsp_fire    = link_tx_rsp_valid && link_tx_rsp_ready;

    // Parameter checks.
    initial begin
        if (TIME_WIDTH != DELAY_WIDTH)
            $fatal(1, "lltsm_fsm requires TIME_WIDTH == DELAY_WIDTH");
        if ((MEASURE_REPEATS <= 0) ||
            ((MEASURE_REPEATS & (MEASURE_REPEATS - 1)) != 0) ||
            (MEASURE_REPEATS > 256))
            $fatal(1, "lltsm_fsm requires a power-of-two MEASURE_REPEATS <= 256");
        if (RSP_WAIT < 0)
            $fatal(1, "lltsm_fsm requires RSP_WAIT >= 0");
        if (RSP_COMPENSATION_CYCLES < 0)
            $fatal(1, "lltsm_fsm requires RSP_COMPENSATION_CYCLES >= 0");
    end

    // Calculate the RTT and compensated mean delay.
    logic [SUM_WIDTH-1:0] final_rtt_average_wide;
    always_comb begin
        if (link_rx_rsp_timestamp >= req_tx_timestamp) begin
            current_rtt = link_rx_rsp_timestamp - req_tx_timestamp;
        end else begin // Counter wraparound.
            current_rtt = ({TIME_WIDTH{1'b1}} - req_tx_timestamp) +
                          link_rx_rsp_timestamp + 1'b1;
        end
        final_rtt_average_wide =
            (rtt_sum + current_rtt) >> AVG_SHIFT;
        final_rtt_average =
            final_rtt_average_wide[DELAY_WIDTH-1:0];
        if (final_rtt_average > RSP_COMPENSATION) begin
            compensated_rtt = final_rtt_average - RSP_COMPENSATION;
        end else begin
            compensated_rtt = '0;
        end
    end

    // 1. State register update.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else if (train_abort || !train_enable) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 2. Next-state transition conditions.
    always_comb begin
        next_state = state;

        case (state)
            S_IDLE: begin
                // A remote request wins arbitration over a local start.
                if (link_rx_req_valid) begin
                    if (RSP_WAIT == 0) begin
                        next_state = S_SEND_RSP;
                    end else begin
                        next_state = S_RSP_WAIT;
                    end
                end else if (train_start && train_start_ready) begin
                    next_state = S_SEND_REQ;
                end
            end

            S_SEND_REQ: begin
                if (req_fire) begin
                    next_state = S_WAIT_RSP;
                end
            end

            S_WAIT_RSP: begin
                if (link_rx_rsp_valid) begin
                    if (sample_count == LAST_SAMPLE) begin
                        next_state = S_DONE;
                    end else begin
                        next_state = S_SEND_REQ;
                    end
                end
            end

            S_RSP_WAIT: begin
                if (rsp_wait_count == '0) begin
                    next_state = S_SEND_RSP;
                end
            end

            S_SEND_RSP: begin
                if (rsp_fire) begin
                    next_state = S_IDLE;
                end
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // 3. Registered state data and registered result outputs.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count         <= '0;
            rsp_wait_count       <= '0;
            req_tx_timestamp     <= '0;
            rtt_sum              <= '0;
            result_ok            <= 1'b0;
            result_rtt_average   <= '0;
            result_mean_delay    <= '0;
        end else if (train_abort || !train_enable) begin
            sample_count <= '0;
            rtt_sum      <= '0;
            result_ok    <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    sample_count <= '0;
                    rtt_sum      <= '0;
                    result_ok    <= 1'b0;

                    if (link_rx_req_valid) begin
                        if (RSP_WAIT == 0) begin
                            rsp_wait_count <= '0;
                        end else begin
                            rsp_wait_count <= RSP_WAIT_LOAD;
                        end
                    end
                end

                S_SEND_REQ: begin
                    if (req_fire) begin
                        // Frozen reference point: accepted wide TX FIFO write.
                        req_tx_timestamp <= time_now;
                    end
                end

                S_WAIT_RSP: begin
                    if (link_rx_rsp_valid) begin
                        if (sample_count == LAST_SAMPLE) begin
                            result_rtt_average <= final_rtt_average;
                            result_mean_delay  <= compensated_rtt >> 1;
                            result_ok          <=
                                (final_rtt_average > RSP_COMPENSATION);
                        end else begin
                            rtt_sum      <= rtt_sum + current_rtt;
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                S_RSP_WAIT: begin
                    if (rsp_wait_count != '0) begin
                        rsp_wait_count <= rsp_wait_count - 1'b1;
                    end
                end

                default: begin
                    // No registered data updates in other states.
                end
            endcase
        end
    end

    // 4. Combinational Moore outputs.
    always_comb begin
        train_state       = state;
        train_start_ready = 1'b0;
        train_busy        = (state != S_IDLE) && (state != S_DONE);
        train_done        = (state == S_DONE);
        result_valid      = (state == S_DONE);

        link_clear        = train_abort || !train_enable;
        link_tx_req_valid = 1'b0;
        link_tx_rsp_valid = 1'b0;
        link_expect_rsp   = 1'b0;
        link_training_sequence =
            {{(8-SAMPLE_COUNT_WIDTH){1'b0}}, sample_count};

        case (state)
            S_IDLE: begin
                train_start_ready = train_enable && !link_rx_req_valid;
            end

            S_SEND_REQ: begin
                link_tx_req_valid = 1'b1;
            end

            S_WAIT_RSP: begin
                link_expect_rsp = 1'b1;
            end

            S_SEND_RSP: begin
                link_tx_rsp_valid = 1'b1;
            end

            default: begin
                // Keep all state-specific outputs inactive.
            end
        endcase
    end

endmodule
