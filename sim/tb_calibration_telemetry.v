`timescale 1ns/1ps
module tb_calibration_telemetry;
    reg clk=0,rst_n=0,info_request=0,event_valid=0;
    reg [7:0] legacy_byte=0;
    reg legacy_valid=0,session_active=1,active=1;
    reg [31:0] session_id=32'h12345678;
    reg [15:0] trial_id=16'h0042;
    reg [3:0] phase=2,result=3,fault=4;
    reg [31:0] ms_now=10;
    reg signed [31:0] position=-2;
    reg signed [15:0] requested_pwm=-2500,actual_pwm=17;
    reg [11:0] sample=1005;
    reg sample_ready=0;
    reg [31:0] t_command=1,t_pwm=2,t_edge=3,t_end=4;
    reg signed [31:0] start_position=-2,end_position=5;
    reg [15:0] window1=1,window2=2,window3=3;
    reg tx_ready=1;
    wire [7:0] tx_data;
    wire tx_valid,frame_active,stream_mode;
    integer count=0,cycle_number=0,last_m_cycle=-1,m_count=0,crc_errors=0;
    string current="",frames[0:31],tmp;
    calibration_telemetry #(.CLK_HZ(100000),.BUILD_ID(32'h20261014)) dut(.*);
    always #5 clk=~clk;
    function [7:0] crc8;
        input string s;
        reg [7:0] work;
        integer j,k;
        begin
            work=0;
            for(j=0;j<s.len();j=j+1) begin
                work=work^s[j];
                for(k=0;k<8;k=k+1) work=work[7] ? (work<<1)^8'h07 : work<<1;
            end
            crc8=work;
        end
    endfunction
    function [7:0] hex_ascii;input [3:0] n;begin hex_ascii=n<10 ? "0"+n : "A"+n-10;end endfunction
    function string framed;
        input string body;reg [7:0] crc;
        begin crc=crc8(body);framed=$sformatf("%s,%c%c%c%c",body,hex_ascii(crc[7:4]),hex_ascii(crc[3:0]),8'h0d,8'h0a);end
    endfunction
    always @(posedge clk) begin
        cycle_number=cycle_number+1;
        if(tx_valid && tx_ready) begin
            current=$sformatf("%s%c",current,tx_data);
            if(tx_data==10) begin
                if(current.len()<6) $fatal(1,"FAIL: short frame");
                tmp=current.substr(0,current.len()-6);
                if(current!=framed(tmp)) begin crc_errors=crc_errors+1;$fatal(1,"FAIL: frame CRC len=%0d [%s] body=[%s] expected=[%s]",current.len(),current,tmp,framed(tmp));end
                frames[count]=current;count=count+1;
                if(current[0]=="M") begin
                    if(current.len()!=63) $fatal(1,"FAIL: M length %0d",current.len());
                    if(last_m_cycle>=0 && m_count>=4 && cycle_number-last_m_cycle!=1000)
                        $fatal(1,"FAIL: 100 Hz period %0d",cycle_number-last_m_cycle);
                    last_m_cycle=cycle_number;m_count=m_count+1;
                end
                current="";
            end
        end
    end
    task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
    task information;begin @(negedge clk);info_request=1;@(negedge clk);info_request=0;end endtask
    task event_pulse;begin @(negedge clk);event_valid=1;@(negedge clk);event_valid=0;end endtask
    task legacy;input [7:0] v;begin @(negedge clk);legacy_byte=v;legacy_valid=1;@(negedge clk);legacy_valid=0;end endtask
    initial begin
        $dumpfile("tb_calibration_telemetry.vcd");$dumpvars(0,clk,rst_n,tx_valid,tx_ready,tx_data,count);
        cycles(4);rst_n=1;cycles(20);if(tx_valid || stream_mode) $fatal(1,"FAIL: disabled initially");
        information();wait(count==1);cycles(3);
        if(frames[0]!=framed("I,DZCAL1,20261014,09C4,0198,000A,0014,0078,0258,00C8,0096"))
            $fatal(1,"FAIL: capability frame [%s]",frames[0]);
        wait(count==2);cycles(3);
        if(frames[1]!=framed("M,0000000A,12345678,0042,2,3,4,FFFFFFFE,-2500,+0017,03ED,6"))
            $fatal(1,"FAIL: M snapshot/invalid ADC [%s]",frames[1]);
        event_pulse();wait(tx_valid && tx_data=="R");@(negedge clk);tx_ready=0;
        trial_id=16'h43;result=7;t_command=10;t_pwm=20;t_edge=30;t_end=40;
        event_pulse();trial_id=16'h44;event_pulse();trial_id=16'h45;event_pulse();
        cycles(60);if(count!=2 || dut.event_count!=3) $fatal(1,"FAIL: buffered events under backpressure");
        tx_ready=1;wait(count==6);cycles(3);
        if(frames[2]!=framed("R,12345678,0042,3,00000001,00000002,00000003,00000004,FFFFFFFE,00000005,0001,0002,0003"))
            $fatal(1,"FAIL: R snapshot [%s]",frames[2]);
        if(frames[3]!=framed("R,12345678,0043,7,0000000A,00000014,0000001E,00000028,FFFFFFFE,00000005,0001,0002,0003") ||
           frames[4]!=framed("R,12345678,0044,7,0000000A,00000014,0000001E,00000028,FFFFFFFE,00000005,0001,0002,0003") ||
           frames[5]!=framed("R,12345678,0045,7,0000000A,00000014,0000001E,00000028,FFFFFFFE,00000005,0001,0002,0003"))
            $fatal(1,"FAIL: R FIFO order");
        // A query is an authoritative result re-emitted through event_valid.
        event_pulse();wait(count==7);cycles(3);
        if(frames[6]!=frames[5]) $fatal(1,"FAIL: query re-emission");
        wait(m_count>=5);legacy("Q");wait(!frame_active);cycles(1200);
        if(stream_mode || tx_valid || current.len()!=0) $fatal(1,"FAIL: Q stops at complete frame");
        information();wait(stream_mode);wait(tx_valid);legacy("P");wait(!frame_active);cycles(1200);
        if(stream_mode || tx_valid) $fatal(1,"FAIL: P deselects calibration stream");
        if(crc_errors!=0) $fatal(1,"FAIL: CRC count");
        $display("TEST PASSED: tb_calibration_telemetry (I/M/R, CRC, snapshot, invalid ADC, FIFO/backpressure, query, 100 Hz, P/Q drain)");$finish;
    end
    initial begin #150000;$fatal(1,"FAIL: telemetry test timeout");end
endmodule
