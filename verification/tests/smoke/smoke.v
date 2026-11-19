// Harness smoke DUT: an 8-bit free-running counter with an active-low
// asynchronous reset. Not design RTL -- it exists only so the harness has
// something self-contained to simulate. No design RTL is added to this repo
// through this file.
`default_nettype none
module smoke (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] count
);
    reg [7:0] count_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count_r <= 8'd0;
        else
            count_r <= count_r + 8'd1;
    end
    assign count = count_r;
endmodule
`default_nettype wire
