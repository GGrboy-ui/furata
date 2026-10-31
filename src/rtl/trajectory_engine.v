`timescale 1ns/1ps
module trajectory_engine #(
 parameter integer COUNTS_PER_REV=408,POSITION_LIMIT_COUNTS=4080,CW_POSITIVE=1,MAX_SPEED=30
)(
 input wire clk,rst_n,tick_ms,enable,stop_cmd,external_busy,submit,
 input wire [15:0] request_id,
 input wire [2:0] request_mode,
 input wire [31:0] request_time_ms,request_dwell_ms,
 input wire [7:0] request_cycles,
 input wire [3:0] request_count,
 input wire [255:0] request_angles,
 input wire signed [31:0] position,
 output wire busy,
 output reg started,event_valid,
 output reg [15:0] active_id,event_id,
 output reg [7:0] event_code,status_code,
 output reg [2:0] mode,phase,
 output reg [3:0] point_index,
 output reg [31:0] elapsed_ms,total_ms,
 output reg signed [31:0] target_q,goal_q,velocity_q
);
 localparam signed [31:0] ONE=16777216;
 reg [5:0] calc;
 reg [31:0] duration,dwell,segment_ms,cycle_ms,next_elapsed;
 reg [7:0] cycles;
 reg [3:0] count,validation_index;
 reg [255:0] angles;
 reg signed [31:0] origin_q,start_q,delta_q,points[0:7];
 reg signed [31:0] previous_angle,offset_q,norm_phase,norm_envelope;
 reg signed [1:0] envelope_direction;
 reg have_id;
 reg [15:0] last_accepted_id;
 reg signed [63:0] converted;
 reg signed [31:0] checked_angle;
 reg [31:0] angle_abs_q;
 reg signed [32:0] distance_q;
 reg [32:0] distance_abs_q;
 reg [63:0] peak_left_q,peak_right_q,conversion_numerator;
 wire signed [31:0] raw_angle=$signed(angles[validation_index*32+:32]);
 wire signed [63:0] candidate=$signed(origin_q)+converted;
 wire signed [63:0] lower_sine=$signed(origin_q)-converted;
 wire signed [63:0] LIMIT=POSITION_LIMIT_COUNTS*64'sd65536;
 // sine A(deg)*2*pi/P <= MAX_SPEED; quintic 1.875*D/T; S curve 1.6*D/T.
 wire signed [63:0] arrival_error=$signed(goal_q)-$signed(position)*64'sd65536;
 reg [8:0] settled;
 assign busy=(phase==1 || phase==2 || phase==3);
 reg div_start;
 reg [63:0] numerator,denominator;
 wire div_busy,div_done;
 wire [63:0] quotient,remainder_unused;
 wire arithmetic_reset=rst_n && enable && !stop_cmd;
 divider_seq #(.WIDTH(64)) divide(.clk(clk),.rst_n(arithmetic_reset),.start(div_start),
  .num(numerator),.den(denominator),.busy(div_busy),.done(div_done),.q(quotient),.r(remainder_unused));
 reg math_start;
 wire math_busy,math_done;
 wire signed [31:0] fraction,derivative;
 trajectory_math math(.clk(clk),.rst_n(arithmetic_reset),.start(math_start),.mode(mode),
  .phase_q(norm_phase),.envelope_q(norm_envelope),.envelope_direction(envelope_direction),
  .busy(math_busy),.done(math_done),.fraction_q(fraction),.derivative_q(derivative));
 wire signed [63:0] position_product=$signed(delta_q)*$signed(fraction);
 wire signed [63:0] velocity_product=$signed(delta_q)*$signed(derivative);
 reg signed [31:0] velocity_scaled;
 reg velocity_negative;
 reg [31:0] velocity_magnitude;reg [63:0] velocity_milli;
 task report;
  input [15:0] id;input [7:0] code;
  begin event_id<=id;event_code<=code;event_valid<=1;end
 endtask
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   calc<=0;duration<=0;dwell<=0;segment_ms<=0;cycle_ms<=0;next_elapsed<=0;cycles<=0;count<=0;
   validation_index<=0;angles<=0;origin_q<=0;start_q<=0;delta_q<=0;previous_angle<=0;
   offset_q<=0;norm_phase<=0;norm_envelope<=0;envelope_direction<=0;have_id<=0;last_accepted_id<=0;converted<=0;
   checked_angle<=0;angle_abs_q<=0;distance_q<=0;distance_abs_q<=0;peak_left_q<=0;peak_right_q<=0;conversion_numerator<=0;
   div_start<=0;numerator<=0;denominator<=1;math_start<=0;velocity_scaled<=0;velocity_negative<=0;velocity_magnitude<=0;velocity_milli<=0;
   started<=0;event_valid<=0;active_id<=0;event_id<=0;event_code<=0;status_code<=0;
   mode<=0;phase<=0;point_index<=0;elapsed_ms<=0;total_ms<=0;target_q<=0;goal_q<=0;velocity_q<=0;settled<=0;
   for(i=0;i<8;i=i+1) points[i]<=0;
  end else begin
   div_start<=0;math_start<=0;event_valid<=0;started<=0;
   case(calc)
    10:begin checked_angle<=raw_angle;calc<=14;end
    14:begin
     if(checked_angle>36000 || checked_angle< -36000 || (mode==2 && checked_angle<=0)) begin
      phase<=0;calc<=0;report(active_id,8'h12);status_code<=8'h12;
     end else begin
      angle_abs_q<=checked_angle<0 ? -checked_angle:checked_angle;
      distance_q<=$signed({checked_angle[31],checked_angle})-$signed({previous_angle[31],previous_angle});calc<=15;
     end
    end
    15:begin distance_abs_q<=distance_q<0 ? -distance_q:distance_q;calc<=16;end
    16:begin
     peak_left_q<=mode==2 ? angle_abs_q*64'd6284:distance_abs_q*(mode==4 ? 64'd1600:64'd1875);
     peak_right_q<=duration*MAX_SPEED*64'd10;
     conversion_numerator<=angle_abs_q*COUNTS_PER_REV*64'd65536+64'd1800;calc<=17;
    end
    17:begin
     if(peak_left_q>peak_right_q) begin phase<=0;calc<=0;report(active_id,8'h12);status_code<=8'h12;end
     else begin numerator<=conversion_numerator;denominator<=3600;div_start<=1;calc<=11;end
    end
    11:if(div_done) begin converted<=(checked_angle<0) ^ (CW_POSITIVE==0) ? -$signed(quotient):$signed(quotient);calc<=12;end
    12:begin
     if(candidate>LIMIT || candidate< -LIMIT || (mode==2 && (lower_sine>LIMIT || lower_sine< -LIMIT))) begin
      phase<=0;calc<=0;report(active_id,8'h12);status_code<=8'h12;
     end else begin
      points[validation_index]<=candidate[31:0];previous_angle<=checked_angle;
      if(validation_index+1<count) begin validation_index<=validation_index+1'b1;calc<=10;end
      else begin calc<=13;end
     end
    end
    13:begin
     start_q<=origin_q;delta_q<=points[0]-origin_q;target_q<=origin_q;
     goal_q<=mode==2 ? origin_q:points[count-1];velocity_q<=0;
     total_ms<=mode==2 ? duration*cycles:mode==3 ? (duration+dwell)*count:duration;
     elapsed_ms<=0;segment_ms<=0;cycle_ms<=0;point_index<=0;settled<=0;
     phase<=2;calc<=0;started<=1;have_id<=1;last_accepted_id<=active_id;status_code<=1;report(active_id,1);
    end
    20:if(div_done) begin
     norm_phase<=quotient[31:0];
     if(mode==2 && {1'b0,next_elapsed}*2<duration) begin norm_envelope<=quotient[31:0]*2;envelope_direction<=1;end
     else if(mode==2 && ({1'b0,total_ms}-{1'b0,next_elapsed})*2<duration) begin
      norm_envelope<=2*(ONE-$signed(quotient[31:0]));envelope_direction<=-1;
     end else begin norm_envelope<=ONE;envelope_direction<=0;end
     calc<=21;
    end
    21:begin math_start<=1;calc<=22;end
    22:if(math_done) begin offset_q<=position_product[55:24];velocity_scaled<=velocity_product[55:24];calc<=23;end
    23:begin
     target_q<=start_q+offset_q;
     velocity_negative<=velocity_scaled<0;
     velocity_magnitude<=velocity_scaled<0 ? -velocity_scaled:velocity_scaled;calc<=25;
    end
    25:begin velocity_milli<=velocity_magnitude*64'd1000;calc<=26;end
    26:begin numerator<=velocity_milli+{32'd0,duration[31:1]};denominator<=duration;div_start<=1;calc<=24;
    end
    24:if(div_done) begin velocity_q<=velocity_negative ? -$signed(quotient[31:0]):$signed(quotient[31:0]);calc<=0;end
    default:begin end
   endcase
   if(phase==2 && tick_ms && calc==0) begin
    next_elapsed<=elapsed_ms+1;elapsed_ms<=elapsed_ms+1;
    if(elapsed_ms+1>=total_ms) begin target_q<=goal_q;velocity_q<=0;phase<=3;settled<=0;end
    else if(mode==3 && segment_ms+1>=duration+dwell) begin
     segment_ms<=0;point_index<=point_index+1'b1;start_q<=points[point_index];
     delta_q<=points[point_index+1]-points[point_index];target_q<=points[point_index];velocity_q<=0;
    end else begin
     if(mode==2) begin
      cycle_ms<=cycle_ms+1>=duration ? 0:cycle_ms+1;
      numerator<=((cycle_ms+1>=duration ? 64'd0:{32'd0,cycle_ms}+1)*64'd16777216);
      denominator<=duration;div_start<=1;calc<=20;
     end else begin
      segment_ms<=segment_ms+1;
      if(segment_ms+1>=duration) begin target_q<=points[point_index];velocity_q<=0;end
      else begin numerator<=({32'd0,segment_ms}+1)*64'd16777216;denominator<=duration;div_start<=1;calc<=20;end
     end
    end
   end
   if(phase==3 && tick_ms) begin
    if(arrival_error<=64'sd131072 && arrival_error>=-64'sd131072) begin
     if(settled==199) begin phase<=4;status_code<=2;report(active_id,2);end
     else settled<=settled+1'b1;
    end else settled<=0;
   end
   if(submit) begin
    if(busy || external_busy || div_busy) report(request_id,8'h10);
    else if(!enable || stop_cmd) report(request_id,8'h11);
    else if(have_id && request_id==last_accepted_id) report(request_id,8'h14);
    else if(request_id==0 || request_mode<1 || request_mode>4 || request_time_ms<500 || request_time_ms>600000 ||
      request_dwell_ms>600000 || request_cycles<1 || request_cycles>100 || request_count<1 || request_count>8 ||
      (request_mode!=3 && request_count!=1) || (request_mode!=2 && request_cycles!=1) ||
      (request_mode!=3 && request_dwell_ms!=0)) report(request_id,8'h12);
    else if($signed(position)>POSITION_LIMIT_COUNTS || $signed(position)< -POSITION_LIMIT_COUNTS) report(request_id,8'h12);
    else begin
     active_id<=request_id;mode<=request_mode;duration<=request_time_ms;dwell<=request_dwell_ms;
     cycles<=request_cycles;count<=request_count;angles<=request_angles;phase<=1;calc<=10;
     origin_q<=position*32'sd65536;validation_index<=0;previous_angle<=0;
    end
   end
   if(!enable || stop_cmd) begin
    if(busy) begin phase<=5;status_code<=3;report(active_id,3);end
    calc<=0;div_start<=0;math_start<=0;velocity_q<=0;started<=0;
   end
  end
 end
endmodule
