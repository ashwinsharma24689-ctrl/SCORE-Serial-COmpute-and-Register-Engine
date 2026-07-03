
module CommandExecUnit(
    input  wire        clock,
    input  wire        reset_n,

    //  From RxDecoder
    input  wire        cmd_valid,
    input  wire        imm_sel,
    input  wire [3:0]  alu_control,
    input  wire [2:0]  sr1,
    input  wire [2:0]  sr2,
    input  wire [2:0]  wr,
    input  wire [7:0]  immediate,

    //  Register file interface
    output wire [2:0]  regfile_sr1,
    output wire [2:0]  regfile_sr2,
    output reg  [2:0]  regfile_wr,
    output reg         regfile_write_enable,
    output reg  [7:0]  regfile_wd,
    input  wire [7:0]  regfile_rs1,
    input  wire [7:0]  regfile_rs2,

    //  ALU interface
    output wire [7:0]  alu_operand_a,
    output wire [7:0]  alu_operand_b,
    output wire [3:0]  alu_alu_control,
    input  wire [7:0]  alu_result,

    //  To TxFIFOWriteCtrl
    output reg         result_valid,
    output reg  [7:0]  result_data
);

//  Register-file read addresses driven straight from the
//  decoder's held fields — no registration needed here, the
//  register file's own read ports are already combinational.
assign regfile_sr1 = sr1;
assign regfile_sr2 = sr2;

//  Operand mux — operand A is always rs1; operand B is either
//  rs2 or the immediate, per imm_sel (locked design decision).
assign alu_operand_a  = regfile_rs1;
assign alu_operand_b  = imm_sel ? immediate : regfile_rs2;
assign alu_alu_control = alu_control;

always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        regfile_wr           <= 3'd0;
        regfile_write_enable <= 1'b0;
        regfile_wd            <= 8'd0;
        result_valid          <= 1'b0;
        result_data            <= 8'd0;
    end
    else begin
        //  Defaults each cycle — both are strictly one-cycle pulses.
        regfile_write_enable <= 1'b0;
        result_valid          <= 1'b0;

        if (cmd_valid) begin
            //  alu_result is combinationally valid this same cycle,
            //  driven off operands that have been stable since the
            //  decoder's DISPATCH state was entered.
            regfile_wr            <= wr;
            regfile_wd             <= alu_result;
            regfile_write_enable   <= (wr != 3'd0);

            result_valid           <= 1'b1;
            result_data             <= alu_result;
        end
    end
end

endmodule
