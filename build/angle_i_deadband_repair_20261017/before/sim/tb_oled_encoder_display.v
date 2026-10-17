`timescale 1ns/1ps
module tb_oled_encoder_display;
    reg clk=0, rst_n=0, ack_enable=0;
    reg signed [31:0] raw_count=-32'sd2147483647-1, position_count=32'sd2147483647, relative_count=-16000;
    tri1 scl,sda;
    wire initialized,error,frame_done,active;
    always #500 clk=~clk;
    oled_encoder_display #(.CLK_HZ(1_000_000),.I2C_HZ(100_000),
        .POWER_WAIT_MS(1),.REFRESH_MS(1),.RETRY_MS(2)) dut (
        .clk(clk),.rst_n(rst_n),.raw_count(raw_count),.position_count(position_count),
        .relative_count(relative_count),.scl(scl),.sda(sda),
        .initialized(initialized),.error(error),.frame_done(frame_done));
    model_oled_i2c slave(.scl(scl),.sda(sda),.ack_enable(ack_enable),.stretch(1'b0),.active(active));
    // Independent expected digit glyphs, indexed by column.
    function [39:0] digit_font;
        input [7:0] digit;
        begin
            case(digit)
                "0":digit_font=40'h3e5149453e; "1":digit_font=40'h00427f4000;
                "2":digit_font=40'h4261514946; "3":digit_font=40'h2141454b31;
                "4":digit_font=40'h1814127f10; "5":digit_font=40'h2745454539;
                "6":digit_font=40'h3c4a494930; "7":digit_font=40'h0171090503;
                "8":digit_font=40'h3649494936; "9":digit_font=40'h064949291e;
                "+":digit_font=40'h08083e0808; "-":digit_font=40'h0808080808;
                default:digit_font=0;
            endcase
        end
    endfunction
    task check_number;
        input integer packet;
        input [87:0] text;
        integer ch,col,base;
        reg [39:0] expected;
        begin
            base=slave.packet_begin[packet]+2+24;
            for(ch=0;ch<11;ch=ch+1) begin
                expected=digit_font(text[(10-ch)*8+:8]);
                for(col=0;col<6;col=col+1)
                    if(slave.bytes[base+ch*6+col] !== ((col<5)?((expected>>((4-col)*8))&8'hff):8'h00))
                        $fatal(1,"FAIL: packet %0d character %0d column %0d",packet,ch,col);
            end
        end
    endtask
    reg [199:0] expected_init=200'haed580a83fd30040a1c8da1281cfd9f1db30a4a68d142002af;
    integer first_packet, p, i, b, frame_start;
    initial begin
        $dumpfile("tb_oled_encoder_display.vcd"); $dumpvars(0,tb_oled_encoder_display);
        repeat(5) @(negedge clk); rst_n=1;
        wait(error); #1;
        if(initialized) $fatal(1,"FAIL: missing display marked initialized");
        wait(slave.stop_count==2); // At least one automatic retry while unplugged.
        @(negedge clk); ack_enable=1;
        wait(initialized); first_packet=slave.stop_count-1;
        b=slave.packet_begin[first_packet];
        if(slave.packet_size[first_packet]!=27 || slave.bytes[b]!==8'h78 || slave.bytes[b+1]!==0)
            $fatal(1,"FAIL: init address/control/length");
        for(i=0;i<25;i=i+1)
            if(slave.bytes[b+2+i]!==expected_init[(24-i)*8+:8]) $fatal(1,"FAIL: init byte %0d",i);
        wait(dut.state==5); repeat(40) @(negedge clk);
        // Change live inputs during the first frame: all three lines keep the snapshot.
        raw_count=123; position_count=-456; relative_count=0;
        wait(frame_done); #1;
        frame_start=first_packet+1;
        for(p=0;p<8;p=p+1) begin
            b=slave.packet_begin[frame_start+p*2];
            if(slave.packet_size[frame_start+p*2]!=5 || slave.bytes[b]!==8'h78 ||
                slave.bytes[b+1]!==0 || slave.bytes[b+2]!==8'hb0+p ||
                slave.bytes[b+3]!==8'h10 || slave.bytes[b+4]!==0)
                $fatal(1,"FAIL: page %0d command",p);
            b=slave.packet_begin[frame_start+p*2+1];
            if(slave.packet_size[frame_start+p*2+1]!=130 || slave.bytes[b]!==8'h78 || slave.bytes[b+1]!==8'h40)
                $fatal(1,"FAIL: page data length/control");
            if(p%2==1) for(i=0;i<128;i=i+1)
                if(slave.bytes[b+2+i]!==0) $fatal(1,"FAIL: blank page %0d",p);
            for(i=90;i<128;i=i+1)
                if(slave.bytes[b+2+i]!==0) $fatal(1,"FAIL: trailing pixels");
        end
        check_number(frame_start+5,"-2147483648");
        check_number(frame_start+9,"+2147483647");
        check_number(frame_start+13,"-0000016000");
        wait(!frame_done); wait(frame_done); #1;
        frame_start=frame_start+16;
        check_number(frame_start+5,"+0000000123");
        check_number(frame_start+9,"-0000000456");
        check_number(frame_start+13,"+0000000000");
        // Disconnect during refresh: retry and reinitialize on reconnect.
        ack_enable=0; wait(error); if(initialized) $fatal(1,"FAIL: disconnect status");
        repeat(3000) @(negedge clk); ack_enable=1;
        wait(initialized); wait(frame_done);
        $display("PASS: init/page protocol, signed limits, frame snapshot, refresh, unplug/reconnect");
        $finish;
    end
    initial begin #1000000000; $fatal(1,"FAIL: display timeout"); end
endmodule
