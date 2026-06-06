module ErrorCheck(
    input wire         reset_n,       
    input wire         recieved_flag, 
    input wire         parity_bit,    
    input wire         start_bit,     
    input wire         stop_bit,      
    input wire  [1:0]  parity_type,   
    input wire  [7:0]  raw_data,      

    output wire [2:0]  error_flag     
);

//  Internal
reg error_parity;
reg parity_flag;
reg start_flag;
reg stop_flag;

//  Encoding for types of the parity
localparam ODD        = 2'b01,
           EVEN       = 2'b10;

//  Parity Check logic
always @(*) 
begin
  case (parity_type)
    ODD:     error_parity = (^raw_data)? 1'b0 : 1'b1;
    EVEN:    error_parity = (^raw_data)? 1'b1 : 1'b0;
    default: error_parity = 1'b1;
  endcase
end

// Error Check logic
always @(*) begin
  parity_flag  = (error_parity ^ parity_bit);
  start_flag   = (start_bit || 1'b0);
  stop_flag    = ~(stop_bit && 1'b1);
end

//  Output logic
assign error_flag = (reset_n && recieved_flag)? {stop_flag,start_flag,parity_flag} : 3'b0;

endmodule
