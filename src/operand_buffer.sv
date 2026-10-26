module operand_buffer(
    input clk,
    input rst_n,
    input ena,
    input host_we,
    input [2:0] host_bank_sel,
    input [2:0] host_byte_addr,
    input [7:0] host_wdata,
    input [3:0] stream_idx,
    output logic signed [3:0] input_val,
    output logic [7:0] host_rdata,
    output logic [3:0][3:0] weight_val
);

    logic [15:0][3:0] input_bank;
    logic [15:0][3:0] weight_bank0;
    logic [15:0][3:0] weight_bank1;
    logic [15:0][3:0] weight_bank2;
    logic [15:0][3:0] weight_bank3;

    logic [3:0] even_idx;
    logic [3:0] odd_idx;

    assign even_idx = {host_byte_addr, 1'b0};
    assign odd_idx  = {host_byte_addr, 1'b1};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            input_bank   <= '0;
            weight_bank0 <= '0;
            weight_bank1 <= '0;
            weight_bank2 <= '0;
            weight_bank3 <= '0;
        end else if (ena && host_we) begin
            case (host_bank_sel)
                3'd0: begin
                    input_bank[even_idx] <= host_wdata[3:0];
                    input_bank[odd_idx] <= host_wdata[7:4];
                end
                3'd1: begin
                    weight_bank0[even_idx] <= host_wdata[3:0];
                    weight_bank0[odd_idx] <= host_wdata[7:4];
                end
                3'd2: begin
                    weight_bank1[even_idx] <= host_wdata[3:0];
                    weight_bank1[odd_idx]  <= host_wdata[7:4];
                end
                3'd3: begin
                    weight_bank2[even_idx] <= host_wdata[3:0];
                    weight_bank2[odd_idx]  <= host_wdata[7:4];
                end
                3'd4: begin
                    weight_bank3[even_idx] <= host_wdata[3:0];
                    weight_bank3[odd_idx]  <= host_wdata[7:4];
                end
                default: begin
                    // Ignore writes to invalid bank selections.
                end
            endcase
        end
    end

    always_comb begin
        input_val = input_bank[stream_idx];
        weight_val[0] = weight_bank0[stream_idx];
        weight_val[1] = weight_bank1[stream_idx];
        weight_val[2] = weight_bank2[stream_idx];
        weight_val[3] = weight_bank3[stream_idx];

        case (host_bank_sel)
            3'd0: host_rdata = {input_bank[odd_idx], input_bank[even_idx]};
            3'd1: host_rdata = {weight_bank0[odd_idx], weight_bank0[even_idx]};
            3'd2: host_rdata = {weight_bank1[odd_idx], weight_bank1[even_idx]};
            3'd3: host_rdata = {weight_bank2[odd_idx], weight_bank2[even_idx]};
            3'd4: host_rdata = {weight_bank3[odd_idx], weight_bank3[even_idx]};
            default: host_rdata = 8'd0;
        endcase
    end
endmodule