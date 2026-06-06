module baudgen_r( 
    input  wire     reset_n, 
    input  wire     clock,
    input  wire     [1:0] baud_rate,
    output reg       baud_clk
        );

reg [9:0]  final_value;  //  Holds the number of ticks for each BaudRate.
reg [9:0]  clock_ticks;  //  Counts untill it equals final_value, Timer principle

localparam BAUD24    = 2'b00,
           BAUD48    = 2'b01,
           BAUD96    = 2'b10,
           BAUD192   = 2'b11;

always @(*) 
begin
    final_value=10'd0;
    case (baud_rate)
      //  For 50MHz Clock
      BAUD24: final_value  = 10'd651;     //  16 * 2400 BaudRate.
      BAUD48: final_value  = 10'd326;     //  16 * 4800 BaudRate.
      BAUD96: final_value  = 10'd162;     //  16 * 9600 BaudRate.
      BAUD192: final_value = 10'd81;      //  16 * 19200 BaudRate.
      default: final_value = 10'd162;     //  16 * 9600 BaudRate.
    endcase
end

always @(negedge reset_n, posedge clock) 
begin
  if(!reset_n) 
  begin
    clock_ticks <= 10'd0;
    baud_clk <= 1'b0;
  end
  else 
  begin
    if(clock_ticks == final_value)
    begin
      baud_clk <= ~baud_clk;
      clock_ticks <= 10'd0;
    end
    else 
    begin
      clock_ticks <= clock_ticks + 1'd1;
    end
  end
end
endmodule