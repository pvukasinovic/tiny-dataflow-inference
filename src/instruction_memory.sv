module instruction_memory (
    input clk,
    input rst_n,
    input ena,
    input host_we,
    input [2:0] host_addr,
    input [3:0] host_byte_offset,
    input [7:0] host_wdata,
    input [2:0]  pc,
    input busy,
    output logic [7:0] host_rdata,
    output logic [71:0] instruction_bundle,
    output logic bad_field,
    output logic bad_address
);

    logic [71:0] instruction_mem [7:0];
    
    assign instruction_bundle = instruction_mem[pc];

    always_comb begin
        if(host_byte_offset <= 8) begin
            host_rdata = instruction_mem[host_addr][(host_byte_offset*8)+:8];
        end else begin
            host_rdata = 8'd0;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bad_field <= 1'b0;
            bad_address <= 1'b0;

            for (int i = 0; i < 8; i++) begin
                instruction_mem[i] <= 72'd0;
            end
        end else if (ena) begin
            bad_field <= 1'b0;
            bad_address <= 1'b0;
            
            if(host_we) begin
                if(busy) begin
                    // Ignore writes when busy
                end else if(host_byte_offset > 8) begin
                    bad_address <= 1'b1;
                end else if(host_byte_offset == 8) begin
                    if(host_wdata[7:5] != 0)
                        bad_field <= 1'b1;
                    else
                        instruction_mem[host_addr][71:64] <= host_wdata;
                end else if(host_byte_offset[0]) begin
                    if(host_wdata[7:5] != 0)
                        bad_field <= 1'b1;
                    else
                        instruction_mem[host_addr][(host_byte_offset*8)+:8] <= host_wdata;
                end else begin
                    instruction_mem[host_addr][(host_byte_offset*8)+:8] <= host_wdata;
                end
            end
        end
    end

endmodule