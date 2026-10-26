//A compute cell that selects two operands, performs an operation, and stores the result
module pe (
    input clk,
    input rst_n,
    input ena, // project enable
    input execute, // execute operation
    input [2:0] op_sel, // operation select
    input [2:0] src_a_sel, // source a select
    input [2:0] src_b_sel, // source b select
    input [3:0] shift_amt, // shift amount
    input signed [3:0] input_val, // input value A
    input signed [3:0] weight_val, // weight value
    input signed [15:0] ho_neighbor, // neighbor value A
    input signed [15:0] ve_neighbor, // neighbor value B
    input [7:0] host_wdata, // host write data byte
    input [1:0] R_wen, // register write enable
    input [1:0] S_wen, // register write enable
    output logic signed [15:0] R_out, // register output
    output logic signed [15:0] S_out, // register readback
    output logic overflow // overflow output
);

    logic signed [15:0] A;
    logic signed [15:0] B;
    logic signed [3:0] mul_a;
    logic signed [3:0] mul_b;
    logic signed [7:0] mul_result;
    logic signed [16:0] add_a;
    logic signed [16:0] add_b;
    logic signed [16:0] add_result;

    always_comb begin
        overflow = 1'b0;

        case( src_a_sel )
            3'b000: A = 16'sd0;
            3'b001: A = R_out;
            3'b010: A = S_out;
            3'b011: A = {{12{input_val[3]}}, input_val};
            3'b100: A = {{12{weight_val[3]}}, weight_val};
            3'b101: A = ho_neighbor;
            3'b110: A = ve_neighbor;
            3'b111: A = 16'sd1;
            default: A = 16'sd0; // default case
        endcase

        case( src_b_sel )
            3'b000: B = 16'sd0;
            3'b001: B = R_out;
            3'b010: B = S_out;
            3'b011: B = {{12{input_val[3]}}, input_val};
            3'b100: B = {{12{weight_val[3]}}, weight_val};
            3'b101: B = ho_neighbor;
            3'b110: B = ve_neighbor;
            3'b111: B = 16'sd1;
            default: B = 16'sd0; // default case
        endcase

        mul_a = A[3:0];
        mul_b = B[3:0];
        mul_result = mul_a * mul_b;

        case (op_sel)
            3'b010: begin // ADD
                add_a = {A[15], A};
                add_b = {B[15], B};
            end
            3'b100: begin // MAC
                add_a = {R_out[15], R_out};
                add_b = {{9{mul_result[7]}}, mul_result};
            end
            default: begin
                add_a = 17'sd0;
                add_b = 17'sd0;
            end
        endcase

        add_result = add_a + add_b;

        if (rst_n && ena && execute &&
            ((op_sel == 3'b010) || (op_sel == 3'b100))) begin
            overflow = add_result[16] ^ add_result[15];
        end
    end

    always_ff @( posedge clk ) begin
        if( rst_n == 1'b0 ) begin
            R_out <= 16'sd0;
            S_out <= 16'sd0;
        end else if( ena == 1'b1 ) begin
            if( execute == 1'b1 ) begin
                case( op_sel )
                    3'b000: R_out <= R_out;
                    3'b001: R_out <= A;
                    3'b010: R_out <= add_result[15:0];
                    3'b011: R_out <= mul_result;
                    3'b100: R_out <= add_result[15:0];
                    3'b101: R_out <= A >= B ? A : B;
                    3'b110: R_out <= A >>> shift_amt;
                    3'b111: begin
                        if((A >>> shift_amt) > 16'sd7)
                            R_out <= 16'sd7;
                        else if((A >>> shift_amt) < -16'sd8)
                            R_out <= -16'sd8;
                        else
                            R_out <= A >>> shift_amt;
                    end
                    default: R_out <= 16'sd0; // default case
                endcase
            end else begin
                // write to registers based on write enable signals
                if( R_wen[0] == 1'b1 ) begin
                    R_out[7:0] <= host_wdata;
                end

                if( R_wen[1] == 1'b1 ) begin
                    R_out[15:8] <= host_wdata;
                end

                if( S_wen[0] == 1'b1 ) begin
                    S_out[7:0] <= host_wdata;
                end
                
                if( S_wen[1] == 1'b1 ) begin
                    S_out[15:8] <= host_wdata;
                end
            end
        end
    end

endmodule