module reg_array (
    input  wire        clk,
    input  wire        rst,
    input  wire        write_enable,
    input  wire [2:0]  sr1,
    input  wire [2:0]  sr2,
    input  wire [2:0]  wr,
    input  wire [7:0] wd,
    output wire [7:0] rs1,
    output wire [7:0] rs2
);

    reg [7:0] register_array [0:7];
    integer i;  // loop counter for reset

    // Combinational read ports ? x0 hardwired to zero
    assign rs1 = (sr1 == 3'd0) ? 8'd0 : register_array[sr1];
    assign rs2 = (sr2 == 3'd0) ? 8'd0 : register_array[sr2];

    // Synchronous write with synchronous reset
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1)
                register_array[i] <= 8'd0;
        end
        else if (write_enable && (wr != 3'd0)) begin
            register_array[wr] <= wd;
        end
    end

endmodule
