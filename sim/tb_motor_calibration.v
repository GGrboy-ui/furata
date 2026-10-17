`timescale 1ns/1ps
module tb_motor_calibration;
    localparam integer CLK_HZ=10000, MS_CLKS=10;
    reg clk=0, rst_n=0, abort=0, core_stopped=1, permit=1, sample_ready=1;
    reg [3:0] fault=0;
    reg signed [31:0] position=0;
    reg signed [15:0] actual_pwm=0;
    reg request_valid=0;
    reg [2:0] request_kind=0;
    reg [31:0] request_session=0;
    reg [15:0] request_trial=0;
    reg signed [31:0] request_a=0,request_b=0,request_c=0;
    wire session_active,active,drive_allowed,event_valid;
    wire signed [15:0] cmd_counts,raw_cmd_counts;
    wire [31:0] session_id,ms_now,t_command,t_pwm,t_edge,t_end;
    wire [15:0] trial_id,window1,window2,window3;
    wire [3:0] phase,result;
    wire signed [31:0] start_position,end_position;
    reg auto_actual=1, auto_heartbeat=0, captured_event=0;
    integer tests=0,j;
    reg [31:0] mark;
    reg [31:0] bench_session=32'h12345677;

    motor_calibration #(.CLK_HZ(CLK_HZ),.PWM_MAX(2500)) dut(.*);
    always #5 clk=~clk;
    always @(negedge clk) if(auto_actual) actual_pwm=cmd_counts;
    task cycles; input integer n; integer i;
        begin for(i=0;i<n;i=i+1) @(negedge clk); end
    endtask
    task send;
        input [2:0] k; input [31:0] s; input [15:0] tr;
        input signed [31:0] a,b,c;
        begin
            @(negedge clk); request_kind=k;request_session=s;request_trial=tr;
            request_a=a;request_b=b;request_c=c;request_valid=1;
            @(negedge clk); captured_event=event_valid; request_valid=0;
            @(negedge clk);
        end
    endtask
    task heartbeat_if_due;
        begin
            if(auto_heartbeat && session_active && (ms_now-dut.heartbeat_ms)>=50)
                send(4,session_id,0,0,0,0);
        end
    endtask
    task wait_ms;
        input integer n; reg [31:0] base;
        begin
            base=ms_now;
            while((ms_now-base)<n) begin cycles(1); heartbeat_if_due; end
        end
    endtask
    task wait_phase;
        input [3:0] wanted; input integer timeout_ms; reg [31:0] base;
        begin
            base=ms_now;
            while(active && phase!=wanted && (ms_now-base)<timeout_ms) begin cycles(1); heartbeat_if_due; end
            if(!active || phase!=wanted) $fatal(1,"FAIL: phase %0d unavailable actual=%0d result=%0d",wanted,phase,result);
        end
    endtask
    task wait_end;
        input integer timeout_ms; reg [31:0] base;
        begin
            base=ms_now;
            while(active && (ms_now-base)<timeout_ms) begin cycles(1); heartbeat_if_due; end
            if(active) $fatal(1,"FAIL: measurement failed to end in %0d ms",timeout_ms);
            cycles(2);
            if(cmd_counts!==0 || drive_allowed!==0) $fatal(1,"FAIL: end did not immediately inhibit motor");
        end
    endtask
    task wait_window;
        input [1:0] wanted; reg [31:0] base;
        begin
            base=ms_now;
            while(active && dut.window_index!=wanted && (ms_now-base)<110) begin cycles(1); heartbeat_if_due; end
            if(!active || dut.window_index!=wanted) $fatal(1,"FAIL: window boundary %0d",wanted);
        end
    endtask
    task expect_result; input [3:0] wanted;
        begin
            if(result!==wanted) $fatal(1,"FAIL: result=%0d expected=%0d phase=%0d ms=%0d",result,wanted,phase,ms_now);
            tests=tests+1;
        end
    endtask
    task reset_dut;
        begin
            rst_n=0; abort=0;core_stopped=1;permit=1;sample_ready=1;fault=0;
            request_valid=0;actual_pwm=0;auto_actual=1;auto_heartbeat=0;
            cycles(3);rst_n=1;cycles(3);
        end
    endtask
    task configure;
        input integer cpr, travel, sign;
        begin
            bench_session=bench_session+1;
            send(1,bench_session,0,cpr,travel,sign);
            if(!session_active || !captured_event || active || cmd_counts!=0)
                $fatal(1,"FAIL: valid config not accepted");
            auto_heartbeat=1;
        end
    endtask
    task resting; begin wait_ms(1002); end endtask
    task immediate_off;
        begin
            #1;
            if(cmd_counts!==0 || drive_allowed!==0) $fatal(1,"FAIL: asynchronous inhibit missing");
        end
    endtask

    initial begin
        $dumpfile("tb_motor_calibration.vcd"); $dumpvars(0,tb_motor_calibration);
        position=0; reset_dut; resting;
        // Strict ranges and a useful nonzero limit, without admitting motor output.
        send(1,0,0,408,150,1);expect_result(9);
        send(1,1,0,63,150,1);expect_result(9);
        send(1,1,0,65536,150,1);expect_result(9);
        send(1,1,0,408,151,1);expect_result(9);
        send(1,1,0,408,150,0);expect_result(9);
        send(1,1,0,64,5,1);expect_result(9);
        core_stopped=0;send(1,1,0,408,150,1);expect_result(9);core_stopped=1;
        configure(408,150,1);
        if(dut.travel_limit!=17) $fatal(1,"FAIL: configuration floor limit expected 17");
        send(1,bench_session,0,408,150,1);expect_result(9);
        send(2,bench_session,0,100,1,0);expect_result(9);
        send(2,32'h11111111,1,100,1,0);expect_result(9);
        send(2,bench_session,1,501,1,0);expect_result(9);
        send(2,bench_session,1,0,1,0);expect_result(9);
        send(2,bench_session,1,100,2,0);expect_result(9);
        send(3,bench_session,1,100,-50,0);expect_result(9);
        send(3,bench_session,1,100,101,0);expect_result(9);
        // Profile zero is only a bounded wiring check, not a start threshold.
        send(2,bench_session,1,100,0,0);
        if(!active || cmd_counts!=100) $fatal(1,"FAIL: precheck command");
        wait_end(21);expect_result(13);
        if((t_end-t_pwm)>8 || (t_end-t_command)>20 || t_edge!=32'hffffffff)
            $fatal(1,"FAIL: precheck duration or no-edge metadata");
        send(2,bench_session,2,200,1,0);expect_result(12);
        if(active) $fatal(1,"FAIL: immediate restart accepted without rest");
        resting;
        // Full burst succeeds at two signed encoder counts and preserves its data.
        send(2,bench_session,2,250,1,0);wait_phase(3,12);
        send(5,bench_session,2,0,0,0);
        if(captured_event || result!=0 || !active) $fatal(1,"FAIL: active query emitted a final result");
        position=1;wait_ms(2);position=2;wait_end(5);expect_result(1);
        if(start_position!=0 || end_position!=2 || t_edge==32'hffffffff || t_pwm==32'hffffffff)
            $fatal(1,"FAIL: burst snapshot");
        mark=t_command;send(5,bench_session,2,0,0,0);
        if(!captured_event || active || t_command!=mark) $fatal(1,"FAIL: query restarted or rewrote burst");
        send(2,bench_session,2,250,1,0);expect_result(9);
        if(active) $fatal(1,"FAIL: replay restarted motor");
        resting;
        // ADC samples are intentionally absent: the standalone clock still ends
        // a failed start while valid heartbeats arrive every 50 ms.
        send(2,bench_session,3,200,1,0);wait_end(121);expect_result(3);
        if((t_end-t_command)>120 || (t_end-t_command)<100 || !session_active)
            $fatal(1,"FAIL: heartbeat postponed hard burst deadline");
        resting;
        auto_actual=0;actual_pwm=0;
        send(2,bench_session,4,200,1,0);wait_end(12);expect_result(10);
        if(t_pwm!=32'hffffffff || (t_end-t_command)>10) $fatal(1,"FAIL: PWM arrival timeout");
        auto_actual=1;resting;
        // Wrong direction is a rejected measurement rather than a successful
        // motor-shaft movement in the opposite direction.
        send(2,bench_session,5,200,1,0);wait_phase(3,12);
        position=0;wait_end(2);expect_result(11);
        resting;
        // Recent noise with a two-count range fails the 300 ms quiet check.
        position=2;cycles(3);send(2,bench_session,6,200,1,0);expect_result(12);
        wait_ms(302);send(2,bench_session,6,200,1,0);
        if(!active) $fatal(1,"FAIL: independent quiet and rest counters");
        // Travel uses the original SESSION origin, not this trial's position.
        position=18;immediate_off;wait_end(2);expect_result(5);
        if(session_active) $fatal(1,"FAIL: travel did not close session");
        send(1,bench_session,0,408,150,1);expect_result(9);
        if(session_active) $fatal(1,"FAIL: closed-session config replay reopened session");
        // Sample readiness, fault, stop and competing core mode all inhibit
        // combinationally, including before a registered completion event.
        position=0;reset_dut;resting;configure(408,150,1);
        send(2,bench_session,1,200,1,0);sample_ready=0;immediate_off;
        wait_end(2);expect_result(6);if(session_active) $fatal(1,"FAIL: sample fault retained session");
        sample_ready=1;configure(408,150,1);resting;
        send(2,bench_session,1,200,1,0);permit=0;immediate_off;
        wait_end(2);expect_result(6);permit=1;
        configure(408,150,1);resting;
        send(2,bench_session,1,200,1,0);fault=4'd3;immediate_off;
        wait_end(2);expect_result(6);fault=0;
        configure(408,150,1);resting;
        send(2,bench_session,1,200,1,0);core_stopped=0;immediate_off;
        wait_end(2);expect_result(6);core_stopped=1;
        configure(408,150,1);resting;
        send(2,bench_session,1,200,1,0);abort=1;immediate_off;
        wait_end(2);expect_result(7);abort=0;
        // Query and wrong-session heartbeats cannot keep a session alive.
        configure(408,150,1);auto_heartbeat=0;
        wait_ms(70);send(5,bench_session,0,0,0,0);
        wait_ms(70);send(4,32'h11111111,0,0,0,0);
        wait_ms(61);expect_result(8);
        if(session_active) $fatal(1,"FAIL: query/wrong-session heartbeat refreshed lease");
        configure(408,150,1);auto_heartbeat=0;resting;
        expect_result(8); // Quiet/rest do not implicitly revive expired sessions.
        configure(408,150,1);resting;
        send(2,bench_session,1,200,1,0);auto_heartbeat=0;
        dut.heartbeat_ms=ms_now-32'd200;
        request_kind=4;request_session=bench_session;request_valid=1;
        immediate_off;cycles(1);request_valid=0;cycles(2);expect_result(8);
        if(session_active || active) $fatal(1,"FAIL: overdue heartbeat rescued expired trial");
        // Correct modular subtraction across both encoder counter and time wrap.
        position=32'sh7ffffffe;reset_dut;resting;configure(408,150,1);
        send(2,bench_session,1,200,1,0);wait_phase(3,12);
        position=32'sh80000000;wait_end(2);expect_result(1);
        if(end_position!=32'sh80000000) $fatal(1,"FAIL: RAW wrap snapshot");
        send(6,bench_session,0,0,0,0);expect_result(7);
        position=-32'sd2147483647;resting;configure(408,150,-1);
        send(2,bench_session,1,200,1,0);wait_phase(3,12);
        position=32'sh7fffffff;wait_end(2);expect_result(1);
        send(6,bench_session,0,0,0,0);position=0;resting;configure(408,150,1);
        dut.ms_now=32'hfffffff0;dut.heartbeat_ms=32'hfffffff0;
        send(2,bench_session,1,200,1,0);wait_phase(3,12);wait_ms(20);
        position=2;wait_end(2);expect_result(1);
        if((t_end-t_command)>120 || t_end>=t_command) $fatal(1,"FAIL: millisecond wrap arithmetic");
        // Run result needs three sustained windows, not just the initial kick.
        send(6,bench_session,0,0,0,0);position=0;resting;configure(1000,150,1);
        send(3,bench_session,1,250,100,0);wait_phase(4,12);
        position=2;wait_phase(5,12);
        for(j=0;j<15 && active;j=j+1) begin wait_ms(30);position=position+1;end
        wait_end(50);expect_result(2);
        if(window1<1 || window2<1 || window3<1 || window3+1<window1 || (t_end-t_command)>600)
            $fatal(1,"FAIL: sustained run windows");
        resting;
        send(3,bench_session,2,250,100,0);wait_phase(4,12);
        position=position+2;wait_phase(5,12);wait_end(110);expect_result(4);
        if(!session_active) $fatal(1,"FAIL: normal not-sustained ended session");
        resting;
        // Slowly decaying movement still has edges but does not pass the window
        // trend requirement: n1=3, n2=2, n3=1 must fail.
        send(3,bench_session,3,250,100,0);wait_phase(4,12);
        position=position+2;wait_phase(5,12);
        wait_ms(40);position=position+1;wait_ms(40);position=position+1;
        wait_phase(6,30);
        wait_ms(10);position=position+1;wait_ms(25);position=position+1;wait_ms(25);position=position+1;
        wait_window(1);
        wait_ms(10);position=position+1;wait_ms(60);position=position+1;
        wait_window(2);
        wait_ms(50);position=position+1;wait_end(60);expect_result(4);
        if(window1!=3 || window2!=2 || window3!=1) $fatal(1,"FAIL: decay fixture windows %0d/%0d/%0d",window1,window2,window3);
        resting;
        send(3,bench_session,4,-250,-100,0);wait_phase(4,12);
        position=position-2;wait_phase(5,12);
        for(j=0;j<15 && active;j=j+1) begin wait_ms(30);position=position-1;end
        wait_end(50);expect_result(2);
        // Idempotent queries after completion cannot restart either mode.
        mark=t_command;repeat(3)send(5,bench_session,4,0,0,0);
        if(active || cmd_counts!=0 || t_command!=mark || result!=2) $fatal(1,"FAIL: query side effect");
        send(5,bench_session,3,0,0,0);
        if(captured_event || result!=2) $fatal(1,"FAIL: stale query overwrote completed cache");
        resting;
        // Zero hold is a valid baseline in either direction. A rejected request
        // during an active trial cannot restart its timers or consume another ID.
        send(3,bench_session,5,-250,0,0);wait_phase(4,12);mark=t_command;
        send(2,bench_session,99,200,1,0);expect_result(9);
        if(!active || t_command!=mark || trial_id!=5 || cmd_counts!=-250)
            $fatal(1,"FAIL: active rejection changed trial or output");
        position=position-2;wait_phase(5,12);
        if(cmd_counts!=0 || !drive_allowed) $fatal(1,"FAIL: zero-hold baseline was rejected");
        wait_end(110);expect_result(4);
        resting;
        send(2,bench_session,6,200,1,0);wait_phase(3,12);
        // Exit takes priority when encoder success is observed in the SAME cycle.
        position=position+2;request_kind=6;request_session=bench_session;request_valid=1;
        cycles(1);request_valid=0;wait_end(2);expect_result(7);
        if(session_active || phase!=7) $fatal(1,"FAIL: successful burst overrode simultaneous exit");
        // Crossing a millisecond timestamp alone must not qualify a full 1 ms
        // of unchanged actual PWM. Count stable system clocks, including edges
        // immediately before the next ms tick.
        position=0;reset_dut;resting;configure(408,150,1);
        auto_actual=0;actual_pwm=0;send(2,bench_session,1,250,1,0);
        while(dut.ms_counter!=MS_CLKS-2)cycles(1);
        actual_pwm=250;cycles(3);
        if(phase!=1) $fatal(1,"FAIL: fractional ms qualified PWM early");
        cycles(MS_CLKS);if(phase!=3) $fatal(1,"FAIL: stable PWM did not qualify");
        position=2;wait_end(2);expect_result(1);auto_actual=1;
        $display("PASS: motor calibration %0d cases, fixed limits, independent time, signs, leases, run windows",tests);
        $finish;
    end
    initial begin #100000000; $fatal(1,"FAIL: testbench watchdog");end
endmodule
