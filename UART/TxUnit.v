module TxUnit(
    input wire          reset_n,      
    input wire          send,         
    input wire          clock,        
    input wire  [1:0]   parity_type,  
    input wire  [1:0]   baud_rate,    
    input wire  [7:0]   data_in,      

    output        data_tx,            
    output        active_flag,        
    output        done_flag           
);

//  Interconnections
wire parity_bit_w;
wire baud_clk_w;

//  Baud generator unit instantiation
BaudGenT Unit1(
    //  Inputs
    .reset_n(reset_n),
    .clock(clock),
    .baud_rate(baud_rate),
    
    //  Output
    .baud_clk(baud_clk_w)
);

//Parity unit instantiation 
Parity Unit2(
    //  Inputs
    .reset_n(reset_n),
    .data_in(data_in),
    .parity_type(parity_type),
    
    //  Output
    .parity_bit(parity_bit_w)
);

//  PISO shift register unit instantiation
PISO Unit3(
    //  Inputs
    .reset_n(reset_n),
    .send(send),
    .baud_clk(baud_clk_w),
    .data_in(data_in),
    .parity_bit(parity_bit_w),

    //  Outputs
    .data_tx(data_tx),
    .active_flag(active_flag),
    .done_flag(done_flag)
);

endmodule
