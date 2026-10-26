`default_nettype none
module sequencer (
    input wire clk, rst_n, ena,
    input wire start, abort, clear_status,
    input wire [7:0] metadata,
    input wire [2:0] program_last,
    output logic [2:0] pc,
    output logic [3:0] iter, stream_idx,
    output logic [7:0] cycles,
    output logic done, busy, aborted, execute
);
    // Direct BUSY state eliminates an extra DONE/ABORTED dead cycle.
    logic running;
    assign busy=running;
    assign execute=ena && rst_n && running && !abort;
    assign aborted=ena && rst_n && running && abort;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            running<=1'b0;
            pc<=3'd0;
            iter<=4'd0;
            stream_idx<=4'd0;
            cycles<=8'd0;
            done<=1'b0;
        end else if (ena) begin
            if (running) begin
                if (abort) begin
                    running<=1'b0;
                    done<=1'b0;
                end else begin
                    cycles<=cycles+8'd1;
                    if (metadata[4]) stream_idx<=stream_idx+4'd1;
                    if (iter < metadata[3:0]) begin
                        iter<=iter+4'd1;
                    end else if (pc < program_last) begin
                        pc<=pc+3'd1;
                        iter<=4'd0;
                    end else begin
                        running<=1'b0;
                        done<=1'b1;
                    end
                end
            end else if (start) begin
                running<=1'b1;
                pc<=3'd0;
                iter<=4'd0;
                stream_idx<=4'd0;
                cycles<=8'd0;
                done<=1'b0;
            end else if (clear_status) begin
                done<=1'b0;
            end
        end
    end
endmodule
`default_nettype wire
