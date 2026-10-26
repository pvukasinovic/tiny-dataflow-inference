`default_nettype none
module tt_um_dataflow (
    input wire ena, clk, rst_n,
    input wire [7:0] ui_in, uio_in,
    output wire [7:0] uio_oe, uo_out, uio_out
);
    wire start, abort, clear_status;
    wire [2:0] program_last;
    wire [2:0] pc;
    wire [3:0] iter, stream_idx;
    wire [7:0] cycles;
    wire busy, done, aborted, execute;
    wire instruction_host_we;
    wire [2:0] instruction_host_addr;
    wire [3:0] instruction_byte_offset;
    wire [7:0] instruction_host_rdata;
    wire [71:0] instruction_bundle;
    wire instruction_bad_field, instruction_bad_address;
    wire buffer_host_we;
    wire [2:0] buffer_bank_sel, buffer_byte_addr;
    wire [7:0] buffer_host_rdata, host_wdata;
    wire signed [3:0] input_val;
    wire [3:0][3:0] weight_val;
    wire [3:0][15:0] pe_instructions;
    wire [7:0] metadata;
    wire [3:0][1:0] R_wen, S_wen;
    wire signed [3:0][15:0] R_out, S_out;
    wire pe_overflow;
    assign pe_instructions=instruction_bundle[63:0];
    assign metadata=instruction_bundle[71:64];

    host_if HOST (
        .clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(ui_in),.uio_in(uio_in),
        .uo_out(uo_out),.uio_out(uio_out),.uio_oe(uio_oe),
        .instruction_host_rdata(instruction_host_rdata),.buffer_host_rdata(buffer_host_rdata),
        .R_out(R_out),.S_out(S_out),.sequencer_busy(busy),.sequencer_done(done),
        .sequencer_cycles(cycles),.sequencer_pc(pc),.sequencer_iter(iter),
        .sequencer_stream_idx(stream_idx),.pe_overflow(pe_overflow),
        .start(start),.abort(abort),.clear_status(clear_status),.program_last(program_last),
        .instruction_host_we(instruction_host_we),.instruction_host_addr(instruction_host_addr),
        .instruction_byte_offset(instruction_byte_offset),.buffer_host_we(buffer_host_we),
        .buffer_bank_sel(buffer_bank_sel),.buffer_byte_addr(buffer_byte_addr),
        .host_wdata(host_wdata),.R_wen(R_wen),.S_wen(S_wen)
    );
    instruction_memory MEMORY (
        .clk(clk),.rst_n(rst_n),.ena(ena),.host_we(instruction_host_we),
        .host_addr(instruction_host_addr),.host_byte_offset(instruction_byte_offset),
        .host_wdata(host_wdata),.pc(pc),.busy(busy),.host_rdata(instruction_host_rdata),
        .instruction_bundle(instruction_bundle),.bad_field(instruction_bad_field),
        .bad_address(instruction_bad_address)
    );
    operand_buffer BUFFER (
        .clk(clk),.rst_n(rst_n),.ena(ena),.host_we(buffer_host_we),
        .host_bank_sel(buffer_bank_sel),.host_byte_addr(buffer_byte_addr),
        .host_wdata(host_wdata),.stream_idx(stream_idx),.input_val(input_val),
        .host_rdata(buffer_host_rdata),.weight_val(weight_val)
    );
    sequencer SEQUENCER (
        .clk(clk),.rst_n(rst_n),.ena(ena),.start(start),.abort(abort),
        .clear_status(clear_status),.metadata(metadata),.program_last(program_last),
        .pc(pc),.iter(iter),.stream_idx(stream_idx),.cycles(cycles),
        .done(done),.busy(busy),.aborted(aborted),.execute(execute)
    );
    fabric FABRIC (
        .clk(clk),.rst_n(rst_n),.ena(ena),.execute(execute),
        .input_val(input_val),.weight_val(weight_val),.inst(pe_instructions),
        .host_wdata(host_wdata),.R_wen(R_wen),.S_wen(S_wen),
        .R_out(R_out),.S_out(S_out),.overflow(pe_overflow)
    );
endmodule
`default_nettype wire
