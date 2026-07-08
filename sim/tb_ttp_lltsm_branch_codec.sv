`timescale 1ns/1ps

module tb_ttp_lltsm_branch_codec;
    logic [1:0] tx_frame_type;
    logic [3:0] tx_src_node_id, tx_dst_node_id, tx_link_id;
    logic tx_channel_id;
    logic [7:0] tx_training_round_id, tx_sequence;
    logic [31:0] tx_turnaround;
    logic [127:0] tx_payload_flat, rx_payload_flat, corrupt_mask;
    logic rx_protocol_ok;
    logic [1:0] rx_frame_type;
    logic [3:0] rx_src_node_id, rx_dst_node_id, rx_link_id;
    logic rx_channel_id;
    logic [7:0] rx_training_round_id, rx_sequence;
    logic [31:0] rx_turnaround;

    assign rx_payload_flat = tx_payload_flat ^ corrupt_mask;

    ttp_lltsm_branch_codec dut (.*);

    task automatic check_common;
        begin
            #1;
            if (!rx_protocol_ok) $fatal(1, "valid branch frame rejected");
            if ((rx_frame_type != tx_frame_type) ||
                (rx_src_node_id != tx_src_node_id) ||
                (rx_dst_node_id != tx_dst_node_id) ||
                (rx_link_id != tx_link_id) ||
                (rx_channel_id != tx_channel_id) ||
                (rx_training_round_id != tx_training_round_id) ||
                (rx_sequence != tx_sequence))
                $fatal(1, "branch codec common-field mismatch");
        end
    endtask

    initial begin
        tx_src_node_id = 4'd2;
        tx_dst_node_id = 4'd3;
        tx_link_id = 4'd2;
        tx_channel_id = 1'b1;
        tx_training_round_id = 8'h44;
        tx_sequence = 8'h02;
        tx_turnaround = 32'h1234_5678;
        corrupt_mask = '0;

        tx_frame_type = 2'd1;
        check_common();
        if (rx_turnaround != 0) $fatal(1, "request carried non-zero turnaround");

        tx_frame_type = 2'd2;
        check_common();
        if (rx_turnaround != tx_turnaround) $fatal(1, "response turnaround mismatch");

        corrupt_mask[15:12] = 4'b0001;
        #1;
        if (rx_protocol_ok) $fatal(1, "bad LLTSM tag accepted");
        corrupt_mask = '0;
        corrupt_mask[1:0] = 2'b01;
        #1;
        if (rx_protocol_ok) $fatal(1, "non-zero reserved field accepted");

        $display("PASS: simplified link training branch codec passed");
        $finish;
    end
endmodule
