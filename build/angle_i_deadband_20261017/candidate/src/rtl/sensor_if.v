`timescale 1ns/1ps
// Scheduled ADC128S102 channel-0 sampler. The converter data bus is latched
// locally and sample_valid is delayed one clock, making sample/data ownership explicit.
module sensor_if #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer SAMPLE_HZ=1000,
    parameter integer ADC_HALF_DIV=2,
    parameter integer RAIL_LIMIT_SAMPLES=500
) (
    input wire clk, rst_n, dout,
    output wire cs_n, sclk, din,
    output wire [11:0] sample,
    output wire sample_valid,
    output reg ready,
    output wire [3:0] error_code
);
    localparam integer PERIOD=CLK_HZ/SAMPLE_HZ;
    localparam integer TIMEOUT=PERIOD*5;
    reg [31:0] count, age, rails, frame_age;
    reg [11:0] sample_q;
    reg sample_valid_q;
    wire busy;
    wire request=(count==PERIOD-1) && !busy;
    wire [11:0] adc_data;
    wire adc_valid;

    assign sample=sample_q;
    assign sample_valid=sample_valid_q;
    // 3: no completed conversion; 4: analogue input at a rail; 5: SPI frame timeout.
    assign error_code=(frame_age>=TIMEOUT) ? 4'd5 :
                      (age>=TIMEOUT) ? 4'd3 :
                      (rails>=RAIL_LIMIT_SAMPLES) ? 4'd4 : 4'd0;

    adc128s102_reader #(.HALF_DIV(ADC_HALF_DIV)) adc (
        .clk(clk),.rst_n(rst_n),.start(request),.channel(3'd0),.dout(dout),
        .cs_n(cs_n),.sclk(sclk),.din(din),.busy(busy),.data(adc_data),.valid(adc_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count<=0; age<=0; rails<=0; frame_age<=0; sample_q<=0;
            sample_valid_q<=0; ready<=0;
        end else begin
            sample_valid_q<=0;
            count <= (count==PERIOD-1) ? 0 : count+1;
            if (busy) begin
                if (frame_age<TIMEOUT) frame_age<=frame_age+1;
            end else frame_age<=0;
            if (adc_valid) begin
                sample_q<=adc_data;
                sample_valid_q<=1;
                age<=0; ready<=1;
                if ((adc_data!=0) && (adc_data!=4095)) rails<=0;
                else if (rails<RAIL_LIMIT_SAMPLES) rails<=rails+1;
            end else if (age<TIMEOUT) age<=age+1;
        end
    end
endmodule
