`timescale 1ns/1ps
module tb_oled_i2c_writer;
    reg clk=0, rst_n=0, start=0, first_byte=0, last_byte=0;
    reg [7:0] data=0;
    reg ack_enable=1, stretch=0;
    tri1 scl, sda;
    wire busy, done, error, active;
    always #10 clk=~clk;
    oled_i2c_writer #(.CLK_HZ(50_000_000),.I2C_HZ(100_000),.TIMEOUT_MS(2)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.data(data),
        .first_byte(first_byte),.last_byte(last_byte),.scl(scl),.sda(sda),
        .busy(busy),.done(done),.error(error));
    model_oled_i2c slave(.scl(scl),.sda(sda),.ack_enable(ack_enable),.stretch(stretch),.active(active));
    task send;
        input [7:0] value;
        input first, last, expected_error;
        begin
            @(negedge clk); data=value; first_byte=first; last_byte=last; start=1;
            @(negedge clk); start=0;
            wait(done); #1;
            if (error!==expected_error || busy!==0) $fatal(1,"FAIL: byte completion");
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        $dumpfile("tb_oled_i2c_writer.vcd"); $dumpvars(0,tb_oled_i2c_writer);
        repeat(5) @(negedge clk); rst_n=1;
        send(8'h78,1,0,0); send(8'h00,0,0,0); send(8'hae,0,1,0);
        if (slave.start_count!=1 || slave.stop_count!=1 || slave.packet_size[0]!=3 ||
            slave.bytes[0]!==8'h78 || slave.bytes[1]!==0 || slave.bytes[2]!==8'hae)
            $fatal(1,"FAIL: START/bytes/STOP");
        ack_enable=0; send(8'h78,1,0,1);
        if (slave.stop_count!=2 || scl!==1 || sda!==1) $fatal(1,"FAIL: NACK STOP");
        ack_enable=1;
        fork
            send(8'h55,1,1,0);
            begin wait(dut.state==4); @(negedge clk); stretch=1;
                repeat(500) @(negedge clk); stretch=0; end
        join
        if (slave.bytes[4]!==8'h55) $fatal(1,"FAIL: clock stretching data");
        stretch=1; send(8'h78,1,1,1); stretch=0;
        repeat(5) @(negedge clk);
        if (dut.scl_low!==0 || dut.sda_low!==0) $fatal(1,"FAIL: timeout release");
        // A fresh transaction must work after a held-low bus is released.
        send(8'h78,1,1,0);
        $display("PASS: byte order, chained transaction, ACK/NACK, stretching, timeout/recovery");
        $finish;
    end
    initial begin #20000000; $fatal(1,"FAIL: test timeout"); end
    // Check Standard-mode timing on real 50 MHz / nominal 100 kHz settings.
    time last_rise=0,last_fall=0,last_start=0,last_stop=0;
    reg saw_start=0;
    always @(negedge sda) if (scl===1'b1) begin
        if (last_stop!=0 && $time-last_stop<4700) $fatal(1,"FAIL: I2C bus free time");
        last_start=$time;saw_start=1;
    end
    always @(posedge sda) if (scl===1'b1 && dut.busy) begin
        if ($time-last_rise<4000) $fatal(1,"FAIL: I2C STOP setup time");
        last_stop=$time;
    end
    always @(negedge scl) begin
        if (saw_start) begin
            if ($time-last_start<4000) $fatal(1,"FAIL: I2C START hold time");
            saw_start=0;
        end else if(active && $time-last_rise<4000) $fatal(1,"FAIL: I2C high time");
        last_fall=$time;
    end
    always @(posedge scl) begin
        if(active && $time-last_fall<4700) $fatal(1,"FAIL: I2C low time");
        last_rise=$time;
    end
endmodule
