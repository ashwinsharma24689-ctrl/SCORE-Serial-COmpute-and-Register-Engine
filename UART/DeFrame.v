module DeFrame(
    input wire  [10:0]  data_parll,     
    input wire          recieved_flag,

    output reg          parity_bit,     
    output reg          start_bit,      
    output reg          stop_bit,       
    output reg          done_flag,     
    output reg  [7:0]   raw_data        
);

//  Deframing 
always @(*) 
begin
  start_bit       = data_parll[0];
  raw_data[7:0]   = data_parll[8:1];
  parity_bit      = data_parll[9];
  stop_bit        = data_parll[10];
  done_flag       = recieved_flag;
end

endmodule
