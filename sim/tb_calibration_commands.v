`timescale 1ns/1ps
module tb_calibration_commands;
    reg clk=0,rst_n=0,received_valid=0;
    reg [7:0] received_byte=0;
    wire [7:0] legacy_byte;
    wire legacy_valid,emergency_stop,info_request,request_valid,parse_error;
    wire [2:0] request_kind;
    wire [31:0] request_session;
    wire [15:0] request_trial;
    wire signed [31:0] request_a,request_b,request_c;
    integer requests=0,infos=0,stops=0,errors=0,legacy=0;
    calibration_commands #(.CLK_HZ(1000)) dut(.*);
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(request_valid) requests=requests+1;
        if(info_request) infos=infos+1;
        if(emergency_stop) stops=stops+1;
        if(parse_error) errors=errors+1;
        if(legacy_valid) legacy=legacy+1;
    end
    task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
    task byte_in;input [7:0] v;begin
        @(negedge clk);received_byte=v;received_valid=1;
        @(negedge clk);received_valid=0;
    end endtask
    task text_in;input string s;integer j;begin
        for(j=0;j<s.len();j=j+1) byte_in(s[j]);cycles(3);
    end endtask
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
    task command;input string body;begin text_in($sformatf("!%s,%02X%c%c",body,crc8(body),8'h0d,8'h0a));end endtask
    initial begin
        $dumpfile("tb_calibration_commands.vcd");$dumpvars(0,clk,rst_n,request_valid,parse_error);
        cycles(4);rst_n=1;cycles(3);
        text_in("P");if(legacy!=1 || legacy_byte!="P") $fatal(1,"FAIL: outside legacy");
        text_in("!i\n");text_in("!i");byte_in(13);byte_in(10);cycles(3);
        if(infos!=2) $fatal(1,"FAIL: info LF/CRLF infos=%0d errors=%0d state=%0d",infos,errors,dut.state);
        if(crc8("b,1,1,25,0")!=8'hf6) $fatal(1,"FAIL: CRC golden");
        text_in("!b,1,1,25,0,F6\n");
        if(requests!=1 || request_kind!=2 || request_session!=1 || request_trial!=1 || request_a!=25 || request_b!=0)
            $fatal(1,"FAIL: golden burst");
        command("c,12,408,150,-1");
        if(requests!=2 || request_kind!=1 || request_session!=12 || request_trial!=0 || request_a!=408 || request_b!=150 || request_c!=-1)
            $fatal(1,"FAIL: config mapping");
        command("r,12,2,-125,-75");
        if(requests!=3 || request_kind!=3 || request_trial!=2 || request_a!=-125 || request_b!=-75)
            $fatal(1,"FAIL: run mapping");
        command("h,12");if(requests!=4 || request_kind!=4 || request_trial!=0) $fatal(1,"FAIL: heartbeat");
        command("g,12,2");if(requests!=5 || request_kind!=5 || request_trial!=2) $fatal(1,"FAIL: query");
        command("e,12");if(requests!=6 || request_kind!=6) $fatal(1,"FAIL: exit");
        command("b,4294967295,65535,-2147483648,+2147483647");
        if(requests!=7 || request_session!=32'hffffffff || request_trial!=65535 || request_a!=32'sh80000000 || request_b!=32'sh7fffffff)
            $fatal(1,"FAIL: full integer range");
        text_in("!b,1,1,25,0,00\n");if(requests!=7 || errors!=1) $fatal(1,"FAIL: bad CRC");
        text_in("!c,1,SCDAPQ\n");if(legacy!=1 || requests!=7) $fatal(1,"FAIL: embedded legacy blocked");
        command("b,4294967296,1,25,0");
        command("b,1,65536,25,0");
        command("b,1,1,2147483648,0");
        command("b,1,1,-2147483649,0");
        command("b,1,,25,0");
        command("h,-1");
        if(requests!=7) $fatal(1,"FAIL: integer overflow/empty/unsigned sign accepted");
        text_in("!b,1,1,25,X");if(stops!=1 || requests!=7) $fatal(1,"FAIL: emergency mid-frame");
        text_in("S");if(legacy!=2 || legacy_byte!="S") $fatal(1,"FAIL: emergency parser cleared");
        text_in("!b,1");cycles(105);text_in("A");
        if(legacy!=3 || legacy_byte!="A" || dut.state!=0) $fatal(1,"FAIL: 100 ms timeout recovery");
        text_in("!b,0000000000000000000000000000000000000000000000000000000000000000000000000000000000\n");
        if(requests!=7 || dut.state!=0) $fatal(1,"FAIL: max length recovery");
        text_in("!iQ\n");if(infos!=2 || legacy!=3) $fatal(1,"FAIL: malformed info suppressed");
        command("b,2,3,+25,0");if(requests!=8 || request_a!=25) $fatal(1,"FAIL: next valid frame");
        $display("TEST PASSED: tb_calibration_commands (CRC, fields, split reception, limits, legacy isolation, X, timeout)");$finish;
    end
    initial begin #200000;$fatal(1,"FAIL: parser test timeout");end
endmodule
