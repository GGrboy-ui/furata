`timescale 1ns/1ps
// ASCII requests: @TI, @TQ, @TC,id,period, @T,id,mode,ms,dwell,cycles,count,+a,...
// Decimal request values; fixed-width hexadecimal immutable response snapshots.
module trajectory_uart #(
 parameter integer CLK_HZ=50000000,COUNTS_PER_REV=408,LIMIT_COUNTS=4080,MAX_SPEED=30,DEFAULT_PERIOD=50,DEFAULT_OUTER_SPEED=0,MAX_PWM=2500
)(
 input wire clk,rst_n,tick_ms,
 input wire speed_config_allowed,
 input wire signed [31:0] speed_reference_q,speed_target_q,speed_actual_q,speed_angle_offset_q,
 input wire outer_speed,
 input wire [7:0] handover_remaining,
 input wire [95:0] position_defaults,
 output reg signed [31:0] position_kp_q,position_ki_q,position_kd_q,
 output reg [15:0] speed_period_ms,speed_friction_t,
 output reg signed [31:0] speed_kp_q,speed_ki_q,speed_kd_q,speed_kpos_q,
 input wire [7:0] received_byte,input wire received_valid,
 output reg submit,period_request,
 output reg [15:0] request_id,requested_period,
 output reg [2:0] request_mode,
 output reg [31:0] request_time_ms,request_dwell_ms,
 output reg [7:0] request_cycles,
 output reg [3:0] request_count,
 output reg [255:0] request_angles,
 input wire event_valid,started,period_reply,
 input wire [15:0] event_id,active_id,
 output reg [15:0] actual_period,
 input wire [7:0] event_code,period_code,
 input wire [2:0] control_state,phase,mode,
 input wire [3:0] point_index,
 input wire [31:0] elapsed_ms,total_ms,
 input wire signed [31:0] position,target_q,velocity_q,goal_q,
 output wire [7:0] tx_data,output wire tx_valid,tx_pending,tx_active,
 input wire tx_ready,tx_blocked
);
 reg [3:0] parse,kind;
 reg [4:0] field;
 reg [7:0] length;
 reg [31:0] age,number,values[0:13];
 reg digits,negative,sign_seen,cr;
 reg report_dirty,cap_dirty,vel_dirty,vel_cap_dirty;
 reg vel_extended,vel_cap_extended;
 reg pos_dirty,pos_cap_dirty,vel3_dirty,vel3_cap_dirty;
 reg [15:0] pos_id;reg [7:0] pos_code,pos_query_age;
 wire [31:0] config_kpos=kind==9 ? values[5]:number;
 reg [15:0] vel_id;
 reg [7:0] vel_code,vel_query_age;
 reg [15:0] reply_id,config_id,task_period;
 reg [7:0] reply_code;
 reg [7:0] query_age;
 wire digit=received_byte>=48 && received_byte<=57;
 wire [63:0] next_number={32'd0,number}*10+{60'd0,received_byte[3:0]};
 wire signed [31:0] signed_number=negative ? -$signed(number):$signed(number);
 task report;
  input [15:0] id;input [7:0] code;
  begin reply_id<=id;reply_code<=code;report_dirty<=1;end
 endtask
 function [7:0] hx;input [3:0] n;begin hx=n<10 ? 48+{4'd0,n}:55+{4'd0,n};end endfunction
 function [15:0] h2;input [7:0] n;begin h2={hx(n[7:4]),hx(n[3:0])};end endfunction
 function [31:0] h4;input [15:0] n;begin h4={h2(n[15:8]),h2(n[7:0])};end endfunction
 function [63:0] h8;input [31:0] n;begin h8={h4(n[31:16]),h4(n[15:0])};end endfunction
 reg [1023:0] tx_buffer;
 reg [7:0] tx_length,tx_index;
 reg sending,draining;
 assign tx_active=sending;
 assign tx_pending=sending || report_dirty || cap_dirty || vel_dirty || vel_cap_dirty || pos_dirty || pos_cap_dirty || vel3_dirty || vel3_cap_dirty;
 assign tx_valid=sending && !draining && !tx_blocked;
 assign tx_data=tx_buffer[(tx_length-1-tx_index)*8+:8];
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   speed_friction_t<=0;vel_extended<=0;vel_cap_extended<=0;
   position_kp_q<=position_defaults[31:0];position_ki_q<=position_defaults[63:32];position_kd_q<=position_defaults[95:64];actual_period<=DEFAULT_PERIOD;speed_kd_q<=0;
   pos_dirty<=0;pos_cap_dirty<=0;vel3_dirty<=0;vel3_cap_dirty<=0;pos_id<=0;pos_code<=0;pos_query_age<=200;speed_period_ms<=20;speed_kp_q<=6554;speed_ki_q<=1311;speed_kpos_q<=32768;
   vel_dirty<=0;vel_cap_dirty<=0;vel_id<=0;vel_code<=0;vel_query_age<=200;
   parse<=0;kind<=0;field<=0;length<=0;age<=0;number<=0;digits<=0;negative<=0;sign_seen<=0;cr<=0;
   submit<=0;period_request<=0;request_id<=0;requested_period<=0;request_mode<=0;request_time_ms<=0;
   request_dwell_ms<=0;request_cycles<=0;request_count<=0;request_angles<=0;
   report_dirty<=0;cap_dirty<=0;reply_id<=0;config_id<=0;task_period<=DEFAULT_PERIOD;reply_code<=0;
   tx_buffer<=0;tx_length<=0;tx_index<=0;sending<=0;draining<=0;query_age<=200;
   for(i=0;i<14;i=i+1) values[i]<=0;
  end else begin
   submit<=0;period_request<=0;
   if(tick_ms && pos_query_age<200) pos_query_age<=pos_query_age+1'b1;
   if(tick_ms && vel_query_age<200) vel_query_age<=vel_query_age+1'b1;
   if(tick_ms && query_age<200) query_age<=query_age+1'b1;
   if(started) task_period<=actual_period;
   if(!sending && !tx_blocked) begin
    if(cap_dirty) begin
     tx_buffer<={"@I,TRJ1,",h4(COUNTS_PER_REV),8'h2c,h4(LIMIT_COUNTS),8'h2c,h4(MAX_SPEED),8'h2c,h4(DEFAULT_PERIOD),16'h0d0a};
     tx_length<=29;tx_index<=0;sending<=1;draining<=0;cap_dirty<=0;
    end else if(pos_cap_dirty) begin
     tx_buffer<={"@I,POS1",16'h0d0a};tx_length<=9;tx_index<=0;sending<=1;draining<=0;pos_cap_dirty<=0;
    end else if(vel3_cap_dirty) begin
     tx_buffer<={"@I,VEL3,0014,0005,0064,",h4(MAX_PWM),16'h0d0a};tx_length<=29;tx_index<=0;sending<=1;draining<=0;vel3_cap_dirty<=0;
    end else if(pos_dirty) begin
     tx_buffer<={"@P,",h4(pos_id),8'h2c,h2(pos_code),8'h2c,hx({1'b0,control_state}),8'h2c,h4(actual_period),8'h2c,h8(position_kp_q),8'h2c,h8(position_ki_q),8'h2c,h8(position_kd_q),16'h0d0a};
     tx_length<=46;tx_index<=0;sending<=1;draining<=0;pos_dirty<=0;
    end else if(vel3_dirty) begin
     tx_buffer<={"@W,",h4(vel_id),8'h2c,h2(vel_code),8'h2c,hx({1'b0,control_state}),8'h2c,hx({3'd0,outer_speed}),8'h2c,h4({8'd0,handover_remaining}),8'h2c,
      h4(speed_period_ms),8'h2c,h8(speed_kp_q),8'h2c,h8(speed_ki_q),8'h2c,h8(speed_kd_q),8'h2c,h8(speed_kpos_q),8'h2c,h4(speed_friction_t),8'h2c,
      h8(speed_reference_q),8'h2c,h8(speed_target_q),8'h2c,h8(speed_actual_q),8'h2c,h8(speed_angle_offset_q),8'h2c,h4(active_id),8'h2c,h8(elapsed_ms),16'h0d0a};
     tx_length<=117;tx_index<=0;sending<=1;draining<=0;vel3_dirty<=0;
    end else if(vel_cap_dirty) begin
     if(vel_cap_extended) tx_buffer<={"@I,VEL2,0014,0005,0064,",h4(MAX_PWM),16'h0d0a};
     else tx_buffer<={"@I,VEL1,0014,0005,0064",16'h0d0a};
     tx_length<=vel_cap_extended ? 29:24;tx_index<=0;sending<=1;draining<=0;vel_cap_dirty<=0;
    end else if(vel_dirty) begin
     if(vel_extended) begin
     tx_buffer<={"@V,",h4(vel_id),8'h2c,h2(vel_code),8'h2c,hx({1'b0,control_state}),8'h2c,hx({3'd0,outer_speed}),8'h2c,
      h4(speed_period_ms),8'h2c,h8(speed_kp_q),8'h2c,h8(speed_ki_q),8'h2c,h8(speed_kpos_q),8'h2c,
      h8(speed_reference_q),8'h2c,h8(speed_target_q),8'h2c,h8(speed_actual_q),8'h2c,h8(speed_angle_offset_q),8'h2c,
      h4(active_id),8'h2c,h8(elapsed_ms),8'h2c,h4(speed_friction_t),16'h0d0a};
     end else begin
     tx_buffer<={"@V,",h4(vel_id),8'h2c,h2(vel_code),8'h2c,hx({1'b0,control_state}),8'h2c,hx({3'd0,outer_speed}),8'h2c,
      h4(speed_period_ms),8'h2c,h8(speed_kp_q),8'h2c,h8(speed_ki_q),8'h2c,h8(speed_kpos_q),8'h2c,
      h8(speed_reference_q),8'h2c,h8(speed_target_q),8'h2c,h8(speed_actual_q),8'h2c,h8(speed_angle_offset_q),8'h2c,
      h4(active_id),8'h2c,h8(elapsed_ms),16'h0d0a};
     end
     tx_length<=vel_extended ? 103:98;tx_index<=0;sending<=1;draining<=0;vel_dirty<=0;
    end else if(report_dirty) begin
     tx_buffer<={"@T,",h4(reply_id),8'h2c,h2(reply_code),8'h2c,hx({1'b0,control_state}),8'h2c,
      hx({1'b0,phase}),8'h2c,hx({1'b0,mode}),8'h2c,h4(actual_period),8'h2c,
      h8(elapsed_ms),8'h2c,h8(total_ms),8'h2c,h8(position),8'h2c,h8(target_q),8'h2c,
      h8(velocity_q),8'h2c,h8(goal_q),8'h2c,hx(point_index),8'h2c,h4(task_period),8'h2c,h4(active_id),16'h0d0a};
     tx_length<=89;tx_index<=0;sending<=1;draining<=0;report_dirty<=0;
    end
   end else if(!tx_blocked && tx_ready) begin
    if(draining) begin sending<=0;draining<=0;end
    else if(tx_index==tx_length-1) draining<=1;
    else tx_index<=tx_index+1'b1;
   end
   if(parse!=0) begin
    if(age>=CLK_HZ/5) begin parse<=0;report(0,8'h13);end
    else age<=age+1'b1;
   end
   if(received_valid) begin
    if(received_byte==8'h58) begin parse<=0;end
    else if(received_byte==8'h40) begin parse<=1;age<=0;length<=0;field<=0;number<=0;digits<=0;negative<=0;sign_seen<=0;cr<=0;end
    else if(parse!=0) begin
     length<=length+1'b1;
     if(received_byte==10) begin
      parse<=0;
      if(parse==4 && !digits) begin
       if(kind==10) vel3_cap_dirty<=1;
       else if(kind==13) pos_cap_dirty<=1;
       else if(kind==14) begin if(pos_query_age>=200) begin pos_dirty<=1;pos_query_age<=0;end end
       else if(kind==11) begin if(vel_query_age>=200) begin vel3_dirty<=1;vel_query_age<=0;end end
       else if(kind==4 || kind==7) begin vel_cap_dirty<=1;vel_cap_extended<=kind==7;end
       else if(kind==5 || kind==8) begin if(vel_query_age>=200) begin vel_dirty<=1;vel_extended<=kind==8;vel_query_age<=0;end end
       else if(kind==2) cap_dirty<=1;
       else if(query_age>=200) begin report_dirty<=1;query_age<=0;end
      end else if(parse==3 && digits && (kind==1 || kind==6 || kind==9 || kind==12 || kind==15 || (field>=6 && sign_seen))) begin
       if(kind==15) begin
        pos_id<=values[0][15:0];pos_dirty<=1;
        if(field!=4 || values[0]==0 || values[0]>65535 || values[1]<1 || values[1]>1000 || values[2]>4194304 || values[3]>4194304 || number>4194304) pos_code<=8'h12;
        else if(!speed_config_allowed) pos_code<=8'h11;
        else begin actual_period<=values[1][15:0];position_kp_q<=values[2];position_ki_q<=values[3];position_kd_q<=number;pos_code<=4;end
       end else if(kind==12) begin
        vel_id<=values[0][15:0];vel3_dirty<=1;
        if(field!=6 || values[0]==0 || values[0]>65535 || values[1]<5 || values[1]>100 || values[2]>1048576 || values[3]>1048576 || values[4]>1048576 || values[5]>655360 || number>MAX_PWM) vel_code<=8'h12;
        else if(!speed_config_allowed) vel_code<=8'h11;
        else begin speed_period_ms<=values[1][15:0];speed_kp_q<=values[2];speed_ki_q<=values[3];speed_kd_q<=values[4];speed_kpos_q<=values[5];speed_friction_t<=number[15:0];vel_code<=4;end
       end else if(kind==6 || kind==9) begin
        vel_id<=values[0][15:0];vel_dirty<=1;vel_extended<=kind==9;
        if(field!=(kind==9 ? 6:5) || values[0]==0 || values[0]>65535 || values[1]>1 || values[2]<5 || values[2]>100 ||
           values[3]>1048576 || values[4]>1048576 || config_kpos>655360 || (kind==9 && number>MAX_PWM)) vel_code<=8'h12;
        else if(!speed_config_allowed || values[1][0]!=outer_speed) vel_code<=8'h11;
        else begin
         speed_period_ms<=values[2][15:0];
         speed_kp_q<=values[3];speed_ki_q<=values[4];speed_kpos_q<=config_kpos;vel_code<=8'h04;
         if(kind==9) speed_friction_t<=number[15:0];
        end
       end else if(kind==1 && field==1 && values[0]>0 && values[0]<=65535 && number>=1 && number<=1000) begin
        config_id<=values[0][15:0];requested_period<=number[15:0];
        if(!speed_config_allowed) report(values[0][15:0],8'h11);
        else begin actual_period<=number[15:0];report(values[0][15:0],8'h04);end
       end else if(kind==0 && field==5+values[5] && values[0]>0 && values[0]<=65535 &&
        values[1]>=1 && values[1]<=4 && values[2]>=500 && values[2]<=600000 && values[3]<=600000 &&
        values[4]>=1 && values[4]<=100 && values[5]>=1 && values[5]<=8 && number<=36000) begin
        request_id<=values[0][15:0];request_mode<=values[1][2:0];request_time_ms<=values[2];
        request_dwell_ms<=values[3];request_cycles<=values[4][7:0];request_count<=values[5][3:0];
        for(i=0;i<8;i=i+1) request_angles[i*32+:32]<=field==i+6 ? signed_number:values[i+6];
        submit<=1;
       end else report(values[0][15:0],8'h12);
      end else report(0,8'h13);
     end else if(length>=191 || (cr && received_byte!=10)) parse<=7;
     else if(received_byte==13) begin
      if(parse==4 || (parse==3 && digits)) cr<=1;else parse<=7;
     end else case(parse)
      1:if(received_byte=="T") parse<=2;else parse<=7;
      2:if(received_byte=="I" || received_byte=="Q") begin kind<=received_byte=="I" ? 2:3;parse<=4;end
        else if(received_byte=="C") begin kind<=1;parse<=5;end
        else if(received_byte=="V") parse<=6;
        else if(received_byte=="P") parse<=8;
        else if(received_byte==",") begin kind<=0;parse<=3;end
        else parse<=7;
      6:if(received_byte=="I" || received_byte=="Q") begin kind<=received_byte=="I" ? 4:5;parse<=4;end
        else if(received_byte=="3") begin kind<=10;parse<=4;end
        else if(received_byte=="S") begin kind<=11;parse<=4;end
        else if(received_byte=="E") begin kind<=12;parse<=5;end
        else if(received_byte=="2") begin kind<=7;parse<=4;end
        else if(received_byte=="R") begin kind<=8;parse<=4;end
        else if(received_byte=="D") begin kind<=9;parse<=5;end
        else if(received_byte=="C") begin kind<=6;parse<=5;end
        else parse<=7;
      8:if(received_byte=="I" || received_byte=="Q") begin kind<=received_byte=="I" ? 13:14;parse<=4;end
        else if(received_byte=="C") begin kind<=15;parse<=5;end
        else parse<=7;
      5:if(received_byte==",") parse<=3;else parse<=7;
      3:if(digit && next_number<=2147483647) begin number<=next_number[31:0];digits<=1;end
        else if((received_byte=="+" || received_byte=="-") && !digits && !sign_seen && kind==0 && field>=6) begin
         negative<=received_byte=="-";sign_seen<=1;
        end else if(received_byte=="," && digits && field<13 &&
          (kind==1 ? field==0:kind==6 ? field<5:kind==9 || kind==12 ? field<6:kind==15 ? field<4:(field<6 || (sign_seen && number<=36000)))) begin
         values[field]<=signed_number;field<=field+1'b1;number<=0;digits<=0;negative<=0;sign_seen<=0;
        end else parse<=7;
      default:parse<=7;
     endcase
    end
   end
   if(period_reply) report(config_id,period_code);
   if(event_valid) report(event_id,event_code);
  end
 end
endmodule
