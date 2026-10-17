`timescale 1ns/1ps
module tb_uart_telemetry;
    localparam integer DIV=10, BIT_NS=DIV*10;
    reg clk=0, rst_n=0, rx=1;
    reg signed [15:0] angle=-16'sd123, requested=-16'sd2500, actual=-16'sd17;
    reg angle_valid=1;
    wire tx, start_cmd, stop_cmd, clear_cmd, received_valid;
    wire [7:0] received_byte, tx_data;
    wire tx_valid, tx_ready, frame_active;
    integer frame_count=0, byte_count=0, starts=0, stops=0, clears=0;
    integer serial_file;
    reg [247:0] line=0, frames[0:63];
    reg collecting=0;
    reg [7:0] decoded;
    integer bit_index;
    uart_commands #(.CLK_HZ(1000000),.BAUD(100000),.TELEMETRY(1)) uart (
        .clk(clk),.rst_n(rst_n),.rx(rx),.tx(tx),
        .start_cmd(start_cmd),.stop_cmd(stop_cmd),.clear_cmd(clear_cmd),
        .received_byte(received_byte),.received_valid(received_valid),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_frame_active(frame_active),.tx_ready(tx_ready));
    uart_telemetry #(.CLK_HZ(1000000)) dut (
        .clk(clk),.rst_n(rst_n),.received_byte(received_byte),.received_valid(received_valid),
        .angle_tenths(angle),.angle_valid(angle_valid),.requested_pwm(requested),.actual_pwm(actual),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.frame_active(frame_active));
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(start_cmd) starts=starts+1;
        if(stop_cmd) stops=stops+1;
        if(clear_cmd) clears=clears+1;
    end
    // Decode the physical 8N1 TX, not the internal byte handshake.
    initial forever begin
        @(negedge tx); #(BIT_NS/2);
        if(tx!==0) $fatal(1,"FAIL: TX start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            #BIT_NS; decoded[bit_index]=tx;
        end
        #BIT_NS;
        if(tx!==1) $fatal(1,"FAIL: TX stop bit");
        $fwrite(serial_file,"%c",decoded);
        if(decoded=="T") begin collecting=1; line=0; byte_count=0; end
        if(collecting) begin
            line={line[239:0],decoded}; byte_count=byte_count+1;
            if(decoded==10) begin
                if(byte_count!=31) $fatal(1,"FAIL: frame has %0d bytes",byte_count);
                frames[frame_count]=line; frame_count=frame_count+1; collecting=0;
            end
        end
    end
    task cycles; input integer n; integer k;
        begin for(k=0;k<n;k=k+1) @(negedge clk); end
    endtask
    task send_byte; input [7:0] value; input good_stop; integer k;
        begin
            rx=0; cycles(DIV);
            for(k=0;k<8;k=k+1) begin rx=value[k]; cycles(DIV); end
            rx=good_stop; cycles(DIV); rx=1; cycles(DIV);
        end
    endtask
    task await_frames; input integer n; integer k;
        begin
            k=0;
            while(frame_count<n && k<100000) begin cycles(1); k=k+1; end
            if(frame_count<n) $fatal(1,"FAIL: missing telemetry frame %0d",n);
        end
    endtask
    task expect_frame; input integer index; input [247:0] expected;
        begin if(frames[index]!==expected)
            $fatal(1,"FAIL: frame %0d got [%s], expected [%s]",index,frames[index],expected);
        end
    endtask
    initial begin
        $dumpfile("tb_uart_telemetry.vcd"); $dumpvars(0,tb_uart_telemetry);
        // Binary mode prevents Windows text I/O from inserting an extra CR.
        serial_file=$fopen("telemetry_serial.log","wb");
        cycles(4); rst_n=1; cycles(10);
        send_byte("P",0); cycles(12000);
        if(dut.enabled || frame_count) $fatal(1,"FAIL: bad stop bit started telemetry");
        send_byte("P",1);
        wait(frame_active); cycles(20); angle=16'sd9999; requested=2500; actual=0;
        // Commands received in the middle of a frame must never corrupt its bytes.
        send_byte("S",1); send_byte("X",1); send_byte("C",1);
        await_frames(1); expect_frame(0,{"T,00000000,-012.3,-2500,-0017",8'h0d,8'h0a});
        if(starts!=1 || stops!=1 || clears!=1) $fatal(1,"FAIL: RX commands blocked by TX");
        await_frames(2); expect_frame(1,{"T,00000001,+999.9,+2500,+0000",8'h0d,8'h0a});
        send_byte("P",1); // idempotent while enabled
        await_frames(3); expect_frame(2,{"T,00000002,+999.9,+2500,+0000",8'h0d,8'h0a});
        angle_valid=0; cycles(12000);
        if(frame_count!=3) $fatal(1,"FAIL: invalid angle emitted a frame");
        // Restart resets the recording sequence; Q has no stop_cmd side effect.
        send_byte("Q",1); cycles(100); angle_valid=1;
        angle=0; requested=0; actual=0;
        send_byte("P",1); await_frames(4);
        expect_frame(3,{"T,00000000,+000.0,+0000,+0000",8'h0d,8'h0a});
        // A Q received during TX completes exactly this frame, then stays quiet.
        wait(!frame_active); wait(frame_active); send_byte("Q",1); await_frames(5); cycles(12000);
        if(frame_count!=5 || dut.enabled || stops!=1) $fatal(1,"FAIL: Q stop/drain semantics");
        send_byte("P",1);
        // Force only the initial sequence, then let real increments wrap naturally.
        dut.sequence_q=32'hfffffffe;
        await_frames(8);
        expect_frame(5,{"T,FFFFFFFE,+000.0,+0000,+0000",8'h0d,8'h0a});
        expect_frame(6,{"T,FFFFFFFF,+000.0,+0000,+0000",8'h0d,8'h0a});
        expect_frame(7,{"T,00000000,+000.0,+0000,+0000",8'h0d,8'h0a});
        angle_valid=0; cycles(10100); angle_valid=1;
        await_frames(9); expect_frame(8,{"T,00000003,+000.0,+0000,+0000",8'h0d,8'h0a});
        send_byte("Q",1); cycles(12000);
        rst_n=0; cycles(4); rst_n=1; cycles(12000);
        if(dut.enabled || frame_count!=9) $fatal(1,"FAIL: reset did not disable telemetry");
        $fclose(serial_file);
        $display("TEST PASSED: tb_uart_telemetry (physical UART frames, RX, snapshot, gaps, wrap, P/Q)");
        $finish;
    end
    initial begin #3000000; $fatal(1,"FAIL: UART telemetry timeout"); end
endmodule
