module fabric(
    input clk,
    input rst_n,
    input ena,
    input execute,
    input signed [3:0] input_val,
    input signed [3:0][3:0] weight_val,
    input [3:0][15:0] inst,
    input [7:0] host_wdata,
    input [3:0][1:0] R_wen,
    input [3:0][1:0] S_wen,
    output signed [3:0][15:0] R_out,
    output signed [3:0][15:0] S_out,
    output overflow
);

    logic [3:0] pe_overflow;

    pe PE0 (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .execute(execute),
        .op_sel(inst[0][2:0]),
        .src_a_sel(inst[0][5:3]),
        .src_b_sel(inst[0][8:6]),
        .shift_amt(inst[0][12:9]),
        .input_val(input_val),
        .weight_val(weight_val[0]),
        .ho_neighbor(R_out[1]),
        .ve_neighbor(R_out[2]),
        .host_wdata(host_wdata),
        .R_wen(R_wen[0]),
        .S_wen(S_wen[0]),
        .R_out(R_out[0]),
        .S_out(S_out[0]),
        .overflow(pe_overflow[0])
    );

    pe PE1 (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .execute(execute),
        .op_sel(inst[1][2:0]),
        .src_a_sel(inst[1][5:3]),
        .src_b_sel(inst[1][8:6]),
        .shift_amt(inst[1][12:9]),
        .input_val(input_val),
        .weight_val(weight_val[1]),
        .ho_neighbor(R_out[0]),
        .ve_neighbor(R_out[3]),
        .host_wdata(host_wdata),
        .R_wen(R_wen[1]),
        .S_wen(S_wen[1]),
        .R_out(R_out[1]),
        .S_out(S_out[1]),
        .overflow(pe_overflow[1])
    );

    pe PE2 (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .execute(execute),
        .op_sel(inst[2][2:0]),
        .src_a_sel(inst[2][5:3]),
        .src_b_sel(inst[2][8:6]),
        .shift_amt(inst[2][12:9]),
        .input_val(input_val),
        .weight_val(weight_val[2]),
        .ho_neighbor(R_out[3]),
        .ve_neighbor(R_out[0]),
        .host_wdata(host_wdata),
        .R_wen(R_wen[2]),
        .S_wen(S_wen[2]),
        .R_out(R_out[2]),
        .S_out(S_out[2]),
        .overflow(pe_overflow[2])
    );

    pe PE3 (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .execute(execute),
        .op_sel(inst[3][2:0]),
        .src_a_sel(inst[3][5:3]),
        .src_b_sel(inst[3][8:6]),
        .shift_amt(inst[3][12:9]),
        .input_val(input_val),
        .weight_val(weight_val[3]),
        .ho_neighbor(R_out[2]),
        .ve_neighbor(R_out[1]),
        .host_wdata(host_wdata),
        .R_wen(R_wen[3]),
        .S_wen(S_wen[3]),
        .R_out(R_out[3]),
        .S_out(S_out[3]),
        .overflow(pe_overflow[3])
    );

    assign overflow = |pe_overflow;

endmodule