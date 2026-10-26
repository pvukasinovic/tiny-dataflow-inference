`default_nettype none

module host_if (
    input clk, rst_n, ena,
    input [7:0] ui_in, uio_in,
    output logic [7:0] uo_out, uio_out, uio_oe,
    input [7:0] instruction_host_rdata, buffer_host_rdata,
    input [3:0][15:0] R_out, S_out,
    input sequencer_busy, sequencer_done,
    input [7:0] sequencer_cycles,
    input [2:0] sequencer_pc,
    input [3:0] sequencer_iter, sequencer_stream_idx,
    input pe_overflow,
    output logic start, abort, clear_status,
    output logic [2:0] program_last,
    output logic instruction_host_we,
    output logic [2:0] instruction_host_addr,
    output logic [3:0] instruction_byte_offset,
    output logic buffer_host_we,
    output logic [2:0] buffer_bank_sel,
    output logic [2:0] buffer_byte_addr,
    output logic [7:0] host_wdata,
    output logic [3:0][1:0] R_wen, S_wen
);

    localparam logic [7:0]
        NONE        = 8'h00,
        BAD_ADDRESS = 8'h01,
        BAD_COMMAND = 8'h02,
        BUSY_WRITE  = 8'h03,
        BAD_FIELD   = 8'h04,
        ABORTED     = 8'h05;

    // Stored state
    logic [8:0] address_reg;
    logic [7:0] error_code;
    logic [7:0] write_error, current_error;
    logic fault, overflow_flag;

    // Combinational control and decoding
    logic req, wr, addr, hi;
    logic ready, request, invalid_mode, address_write, data_write;
    logic invalid_high_byte, invalid_instruction_field;
    logic is_control, is_program_last, is_R, is_S, is_X, is_W;
    logic is_instruction_region, instruction_slot_valid, writable_address;
    logic write_permitted;

    // Continuous assignments: these must follow changes to inputs/state
    assign req  = uio_in[0];
    assign wr   = uio_in[1];
    assign addr = uio_in[2];
    assign hi   = uio_in[3];

    assign ready = ena && rst_n;
    assign request = ready && req;
    assign invalid_mode = (addr && !wr) || (!addr && hi);
    assign address_write = request && addr && wr;
    assign data_write = request && !addr && wr && !hi;
    assign invalid_high_byte = address_write && hi && (ui_in[7:1] != 7'd0);

    assign is_control = (address_reg == 9'h003);
    assign is_program_last = (address_reg == 9'h004);
    assign is_R = (address_reg >= 9'h010 && address_reg <= 9'h017);
    assign is_S = (address_reg >= 9'h018 && address_reg <= 9'h01f);
    assign is_X = (address_reg >= 9'h020 && address_reg <= 9'h027);
    assign is_W = (address_reg >= 9'h030 && address_reg <= 9'h04f);
    assign is_instruction_region = (address_reg >= 9'h100 && address_reg <= 9'h17f);
    assign instruction_slot_valid = is_instruction_region &&
                                    (address_reg[3:0] <= 4'd8);
    assign writable_address = is_control || is_program_last || is_R || is_S ||
                              is_X || is_W || instruction_slot_valid;
    assign invalid_instruction_field = instruction_slot_valid &&
        ((address_reg[3:0] == 4'd1) || (address_reg[3:0] == 4'd3) ||
         (address_reg[3:0] == 4'd5) || (address_reg[3:0] == 4'd7) ||
         (address_reg[3:0] == 4'd8)) && (ui_in[7:5] != 3'b000);

    assign instruction_host_addr = address_reg[6:4];
    assign instruction_byte_offset = address_reg[3:0];
    assign host_wdata = ui_in;

    // Bidirectional GPIO direction and status outputs
    always_comb begin
        uio_oe = ready ? 8'hf0 : 8'h00;
        uio_out = 8'h00;
        if (ready) begin
            uio_out[4] = 1'b1;
            uio_out[5] = sequencer_busy;
            uio_out[6] = sequencer_done;
            uio_out[7] = fault;
        end
    end

    // Operand buffer bank and offset
    always_comb begin
        buffer_bank_sel = 3'd0;
        buffer_byte_addr = 3'd0;
        if (is_X) begin
            buffer_byte_addr = address_reg[2:0];
        end else if (is_W) begin
            buffer_byte_addr = address_reg[2:0];
            case (address_reg[6:3])
                4'h6: buffer_bank_sel = 3'd1;
                4'h7: buffer_bank_sel = 3'd2;
                4'h8: buffer_bank_sel = 3'd3;
                4'h9: buffer_bank_sel = 3'd4;
                default: buffer_bank_sel = 3'd0;
            endcase
        end
    end

    // Validate host data writes; busy restrictions precede address errors.
    always_comb begin
        write_error = NONE;
        write_permitted = 1'b0;
        if (data_write) begin
            if (sequencer_busy && !(is_control && ui_in == 8'h02))
                write_error = BUSY_WRITE;
            else if (!writable_address)
                write_error = BAD_ADDRESS;
            else if (is_control) begin
                case (ui_in)
                    8'h01: if (!fault) write_permitted = 1'b1;
                    8'h02: write_permitted = 1'b1;
                    8'h04: write_permitted = 1'b1;
                    default: write_error = BAD_COMMAND;
                endcase
            end else if (is_program_last && ui_in[7:3] != 5'd0)
                write_error = BAD_FIELD;
            else if (invalid_instruction_field)
                write_error = BAD_FIELD;
            else
                write_permitted = 1'b1;
        end
    end

    // Pulse control outputs and byte write enables during accepted writes.
    always_comb begin
        start = 1'b0;
        abort = 1'b0;
        clear_status = 1'b0;
        instruction_host_we = 1'b0;
        buffer_host_we = 1'b0;
        R_wen = '0;
        S_wen = '0;

        if (write_permitted) begin
            if (is_control) begin
                case (ui_in)
                    8'h01: start = 1'b1;
                    8'h02: abort = 1'b1;
                    8'h04: clear_status = 1'b1;
                    default: ;
                endcase
            end else if (instruction_slot_valid)
                instruction_host_we = 1'b1;
            else if (is_X || is_W)
                buffer_host_we = 1'b1;
            else if (is_R) begin
                case (address_reg[2:0])
                    3'd0: R_wen[0][0] = 1'b1;
                    3'd1: R_wen[0][1] = 1'b1;
                    3'd2: R_wen[1][0] = 1'b1;
                    3'd3: R_wen[1][1] = 1'b1;
                    3'd4: R_wen[2][0] = 1'b1;
                    3'd5: R_wen[2][1] = 1'b1;
                    3'd6: R_wen[3][0] = 1'b1;
                    3'd7: R_wen[3][1] = 1'b1;
                endcase
            end else if (is_S) begin
                case (address_reg[2:0])
                    3'd0: S_wen[0][0] = 1'b1;
                    3'd1: S_wen[0][1] = 1'b1;
                    3'd2: S_wen[1][0] = 1'b1;
                    3'd3: S_wen[1][1] = 1'b1;
                    3'd4: S_wen[2][0] = 1'b1;
                    3'd5: S_wen[2][1] = 1'b1;
                    3'd6: S_wen[3][0] = 1'b1;
                    3'd7: S_wen[3][1] = 1'b1;
                endcase
            end
        end
    end

    // First-error event for this clock cycle
    always_comb begin
        current_error = NONE;
        if (request && invalid_mode)
            current_error = BAD_COMMAND;
        else if (invalid_high_byte)
            current_error = BAD_FIELD;
        else if (write_error != NONE)
            current_error = write_error;
        else if (abort && sequencer_busy)
            current_error = ABORTED;
    end

    // Address latch and auto-increment
    always_ff @(posedge clk) begin
        if (!rst_n)
            address_reg <= 9'd0;
        else if (ena && req && !invalid_mode) begin
            if (addr) begin
                if (!hi)
                    address_reg[7:0] <= ui_in;
                else if (ui_in[7:1] == 7'd0)
                    address_reg[8] <= ui_in[0];
            end else
                address_reg <= address_reg + 9'd1;
        end
    end

    // Sticky status and program configuration
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            program_last <= 3'd0;
            fault <= 1'b0;
            overflow_flag <= 1'b0;
            error_code <= NONE;
        end else if (ena) begin
            if (write_permitted && is_program_last)
                program_last <= ui_in[2:0];
            if (clear_status) begin
                fault <= 1'b0;
                error_code <= NONE;
                overflow_flag <= 1'b0;
            end else begin
                if (start)
                    overflow_flag <= 1'b0;
                else if (pe_overflow)
                    overflow_flag <= 1'b1;
                if (current_error != NONE) begin
                    if (!fault)
                        error_code <= current_error;
                    fault <= 1'b1;
                end
            end
        end
    end

    // Combinational, little-endian register/memory readback
    always_comb begin
        uo_out = 8'h00;
        if (ready) begin
            case (address_reg)
                9'h000: uo_out = 8'hc1;
                9'h001: uo_out = 8'h10;
                9'h002: uo_out = {4'b0000, overflow_flag, fault,
                                    sequencer_done, sequencer_busy};
                9'h003: uo_out = 8'h00;
                9'h004: uo_out = {5'b0, program_last};
                9'h005: uo_out = sequencer_cycles;
                9'h006: uo_out = {5'b0, sequencer_pc};
                9'h007: uo_out = {4'b0, sequencer_iter};
                9'h008: uo_out = {4'b0, sequencer_stream_idx};
                9'h009: uo_out = error_code;
                default: begin
                    if (is_R) begin
                        case (address_reg[2:0])
                            3'd0: uo_out = R_out[0][7:0];
                            3'd1: uo_out = R_out[0][15:8];
                            3'd2: uo_out = R_out[1][7:0];
                            3'd3: uo_out = R_out[1][15:8];
                            3'd4: uo_out = R_out[2][7:0];
                            3'd5: uo_out = R_out[2][15:8];
                            3'd6: uo_out = R_out[3][7:0];
                            3'd7: uo_out = R_out[3][15:8];
                        endcase
                    end else if (is_S) begin
                        case (address_reg[2:0])
                            3'd0: uo_out = S_out[0][7:0];
                            3'd1: uo_out = S_out[0][15:8];
                            3'd2: uo_out = S_out[1][7:0];
                            3'd3: uo_out = S_out[1][15:8];
                            3'd4: uo_out = S_out[2][7:0];
                            3'd5: uo_out = S_out[2][15:8];
                            3'd6: uo_out = S_out[3][7:0];
                            3'd7: uo_out = S_out[3][15:8];
                        endcase
                    end else if (is_X || is_W)
                        uo_out = buffer_host_rdata;
                    else if (instruction_slot_valid)
                        uo_out = instruction_host_rdata;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
