module RxUnit(
    input wire         reset_n,   
    input wire         data_tx,   
    input wire         clock,     
    input wire  [1:0]  parity_type, 
    input wire  [1:0]  baud_rate,    

    output             active_flag,
    output             done_flag,
    output      [2:0]  error_flag,
    output      [7:0]  data_out
);

//  Intermediate wires
wire baud_clk_w;          
wire [10:0] data_parll_w; 
wire recieved_flag_w;     
wire def_par_bit_w;   
wire def_strt_bit_w;  
wire def_stp_bit_w;   

//  clocking Unit Instance
BaudGenR Unit1(
    //  Inputs
    .reset_n(reset_n),
    .clock(clock),
    .baud_rate(baud_rate),

    //  Output
    .baud_clk(baud_clk_w)
);

//  Shift Register Unit Instance
SIPO Unit2(
    //  Inputs
    .reset_n(reset_n),
    .data_tx(data_tx),
    .baud_clk(baud_clk_w),

    //  Outputs
    .active_flag(active_flag),
    .recieved_flag(recieved_flag_w),
    .data_parll(data_parll_w)
);

//  DeFramer Unit Instance
DeFrame Unit3(
    //  Inputs
    .data_parll(data_parll_w),
    .recieved_flag(recieved_flag_w),
    
    //  Outputs
    .parity_bit(def_par_bit_w),
    .start_bit(def_strt_bit_w),
    .stop_bit(def_stp_bit_w),
    .done_flag(done_flag),
    .raw_data(data_out)
);

//  Error Checking Unit Instance
ErrorCheck Unit4(
    //  Inputs
    .reset_n(reset_n),
    .recieved_flag(done_flag),
    .parity_bit(def_par_bit_w),
    .start_bit(def_strt_bit_w),
    .stop_bit(def_stp_bit_w),
    .parity_type(parity_type),
    .raw_data(data_out),

    //  Output
    .error_flag(error_flag)
);

endmodule