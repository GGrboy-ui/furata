`timescale 1ns/1ps
// Q8.24 normalized position and derivative. One shared registered multiplier.
// mode 1/3: quintic; 2: envelope*sin; 4: seven jerk stages (1:1:1:2:1:1:1).
module trajectory_math(
 input wire clk,rst_n,start,
 input wire [2:0] mode,
 input wire signed [31:0] phase_q,envelope_q,
 input wire signed [1:0] envelope_direction,
 output reg busy,done,
 output reg signed [31:0] fraction_q,derivative_q
);
 localparam signed [31:0] ONE=16777216;
 reg [5:0] stage;
 reg [2:0] selected;
 reg signed [31:0] s,r,h,d,ss,rr,sine,cosine,work,a,b,mult_q;
 reg signed [1:0] ed;
 reg [3:0] term;
 reg signed [31:0] x,square,sum2,sum3;
 reg signed [31:0] low_s,high_s,low_c,high_c,interpolated_s,interpolated_c;
 reg [13:0] fractional;
 reg negative_s,negative_c;
 wire [23:0] cosine_phase=phase_q[23:0]+24'd4194304;
 wire signed [63:0] product=$signed(a)*$signed(b);
 reg signed [63:0] product_q;
 reg mult_wait;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) product_q<=0;else product_q<=product;
 end
 wire signed [31:0] scaled=product_q[55:24]; // Explicit Q8.24 narrowing.
 function signed [31:0] lut;
  input [8:0] address;
  begin
   case(address)
    9'd0:lut=32'sd0;
    9'd1:lut=32'sd102943;
    9'd2:lut=32'sd205882;
    9'd3:lut=32'sd308814;
    9'd4:lut=32'sd411733;
    9'd5:lut=32'sd514638;
    9'd6:lut=32'sd617523;
    9'd7:lut=32'sd720384;
    9'd8:lut=32'sd823219;
    9'd9:lut=32'sd926023;
    9'd10:lut=32'sd1028791;
    9'd11:lut=32'sd1131521;
    9'd12:lut=32'sd1234209;
    9'd13:lut=32'sd1336849;
    9'd14:lut=32'sd1439440;
    9'd15:lut=32'sd1541976;
    9'd16:lut=32'sd1644455;
    9'd17:lut=32'sd1746871;
    9'd18:lut=32'sd1849222;
    9'd19:lut=32'sd1951503;
    9'd20:lut=32'sd2053710;
    9'd21:lut=32'sd2155841;
    9'd22:lut=32'sd2257890;
    9'd23:lut=32'sd2359854;
    9'd24:lut=32'sd2461729;
    9'd25:lut=32'sd2563511;
    9'd26:lut=32'sd2665197;
    9'd27:lut=32'sd2766783;
    9'd28:lut=32'sd2868265;
    9'd29:lut=32'sd2969638;
    9'd30:lut=32'sd3070900;
    9'd31:lut=32'sd3172046;
    9'd32:lut=32'sd3273072;
    9'd33:lut=32'sd3373976;
    9'd34:lut=32'sd3474752;
    9'd35:lut=32'sd3575398;
    9'd36:lut=32'sd3675909;
    9'd37:lut=32'sd3776281;
    9'd38:lut=32'sd3876512;
    9'd39:lut=32'sd3976596;
    9'd40:lut=32'sd4076531;
    9'd41:lut=32'sd4176312;
    9'd42:lut=32'sd4275936;
    9'd43:lut=32'sd4375399;
    9'd44:lut=32'sd4474698;
    9'd45:lut=32'sd4573827;
    9'd46:lut=32'sd4672785;
    9'd47:lut=32'sd4771567;
    9'd48:lut=32'sd4870169;
    9'd49:lut=32'sd4968587;
    9'd50:lut=32'sd5066819;
    9'd51:lut=32'sd5164860;
    9'd52:lut=32'sd5262706;
    9'd53:lut=32'sd5360355;
    9'd54:lut=32'sd5457801;
    9'd55:lut=32'sd5555042;
    9'd56:lut=32'sd5652074;
    9'd57:lut=32'sd5748893;
    9'd58:lut=32'sd5845495;
    9'd59:lut=32'sd5941878;
    9'd60:lut=32'sd6038037;
    9'd61:lut=32'sd6133968;
    9'd62:lut=32'sd6229669;
    9'd63:lut=32'sd6325135;
    9'd64:lut=32'sd6420363;
    9'd65:lut=32'sd6515349;
    9'd66:lut=32'sd6610090;
    9'd67:lut=32'sd6704582;
    9'd68:lut=32'sd6798821;
    9'd69:lut=32'sd6892805;
    9'd70:lut=32'sd6986529;
    9'd71:lut=32'sd7079990;
    9'd72:lut=32'sd7173184;
    9'd73:lut=32'sd7266109;
    9'd74:lut=32'sd7358759;
    9'd75:lut=32'sd7451133;
    9'd76:lut=32'sd7543226;
    9'd77:lut=32'sd7635036;
    9'd78:lut=32'sd7726557;
    9'd79:lut=32'sd7817788;
    9'd80:lut=32'sd7908725;
    9'd81:lut=32'sd7999364;
    9'd82:lut=32'sd8089701;
    9'd83:lut=32'sd8179734;
    9'd84:lut=32'sd8269459;
    9'd85:lut=32'sd8358873;
    9'd86:lut=32'sd8447972;
    9'd87:lut=32'sd8536753;
    9'd88:lut=32'sd8625213;
    9'd89:lut=32'sd8713348;
    9'd90:lut=32'sd8801154;
    9'd91:lut=32'sd8888630;
    9'd92:lut=32'sd8975771;
    9'd93:lut=32'sd9062573;
    9'd94:lut=32'sd9149035;
    9'd95:lut=32'sd9235152;
    9'd96:lut=32'sd9320922;
    9'd97:lut=32'sd9406340;
    9'd98:lut=32'sd9491405;
    9'd99:lut=32'sd9576112;
    9'd100:lut=32'sd9660458;
    9'd101:lut=32'sd9744441;
    9'd102:lut=32'sd9828057;
    9'd103:lut=32'sd9911303;
    9'd104:lut=32'sd9994176;
    9'd105:lut=32'sd10076672;
    9'd106:lut=32'sd10158790;
    9'd107:lut=32'sd10240524;
    9'd108:lut=32'sd10321873;
    9'd109:lut=32'sd10402834;
    9'd110:lut=32'sd10483403;
    9'd111:lut=32'sd10563577;
    9'd112:lut=32'sd10643353;
    9'd113:lut=32'sd10722729;
    9'd114:lut=32'sd10801701;
    9'd115:lut=32'sd10880266;
    9'd116:lut=32'sd10958422;
    9'd117:lut=32'sd11036165;
    9'd118:lut=32'sd11113493;
    9'd119:lut=32'sd11190402;
    9'd120:lut=32'sd11266890;
    9'd121:lut=32'sd11342953;
    9'd122:lut=32'sd11418590;
    9'd123:lut=32'sd11493797;
    9'd124:lut=32'sd11568571;
    9'd125:lut=32'sd11642909;
    9'd126:lut=32'sd11716809;
    9'd127:lut=32'sd11790268;
    9'd128:lut=32'sd11863283;
    9'd129:lut=32'sd11935852;
    9'd130:lut=32'sd12007971;
    9'd131:lut=32'sd12079638;
    9'd132:lut=32'sd12150850;
    9'd133:lut=32'sd12221604;
    9'd134:lut=32'sd12291899;
    9'd135:lut=32'sd12361731;
    9'd136:lut=32'sd12431097;
    9'd137:lut=32'sd12499995;
    9'd138:lut=32'sd12568423;
    9'd139:lut=32'sd12636378;
    9'd140:lut=32'sd12703856;
    9'd141:lut=32'sd12770857;
    9'd142:lut=32'sd12837376;
    9'd143:lut=32'sd12903413;
    9'd144:lut=32'sd12968963;
    9'd145:lut=32'sd13034026;
    9'd146:lut=32'sd13098597;
    9'd147:lut=32'sd13162675;
    9'd148:lut=32'sd13226258;
    9'd149:lut=32'sd13289343;
    9'd150:lut=32'sd13351928;
    9'd151:lut=32'sd13414009;
    9'd152:lut=32'sd13475586;
    9'd153:lut=32'sd13536656;
    9'd154:lut=32'sd13597215;
    9'd155:lut=32'sd13657263;
    9'd156:lut=32'sd13716797;
    9'd157:lut=32'sd13775814;
    9'd158:lut=32'sd13834313;
    9'd159:lut=32'sd13892291;
    9'd160:lut=32'sd13949745;
    9'd161:lut=32'sd14006675;
    9'd162:lut=32'sd14063077;
    9'd163:lut=32'sd14118950;
    9'd164:lut=32'sd14174291;
    9'd165:lut=32'sd14229098;
    9'd166:lut=32'sd14283370;
    9'd167:lut=32'sd14337104;
    9'd168:lut=32'sd14390298;
    9'd169:lut=32'sd14442951;
    9'd170:lut=32'sd14495059;
    9'd171:lut=32'sd14546622;
    9'd172:lut=32'sd14597637;
    9'd173:lut=32'sd14648103;
    9'd174:lut=32'sd14698017;
    9'd175:lut=32'sd14747378;
    9'd176:lut=32'sd14796184;
    9'd177:lut=32'sd14844432;
    9'd178:lut=32'sd14892122;
    9'd179:lut=32'sd14939251;
    9'd180:lut=32'sd14985817;
    9'd181:lut=32'sd15031819;
    9'd182:lut=32'sd15077256;
    9'd183:lut=32'sd15122124;
    9'd184:lut=32'sd15166424;
    9'd185:lut=32'sd15210152;
    9'd186:lut=32'sd15253308;
    9'd187:lut=32'sd15295889;
    9'd188:lut=32'sd15337895;
    9'd189:lut=32'sd15379323;
    9'd190:lut=32'sd15420172;
    9'd191:lut=32'sd15460440;
    9'd192:lut=32'sd15500126;
    9'd193:lut=32'sd15539229;
    9'd194:lut=32'sd15577747;
    9'd195:lut=32'sd15615678;
    9'd196:lut=32'sd15653022;
    9'd197:lut=32'sd15689776;
    9'd198:lut=32'sd15725939;
    9'd199:lut=32'sd15761510;
    9'd200:lut=32'sd15796488;
    9'd201:lut=32'sd15830871;
    9'd202:lut=32'sd15864658;
    9'd203:lut=32'sd15897848;
    9'd204:lut=32'sd15930439;
    9'd205:lut=32'sd15962431;
    9'd206:lut=32'sd15993821;
    9'd207:lut=32'sd16024610;
    9'd208:lut=32'sd16054795;
    9'd209:lut=32'sd16084375;
    9'd210:lut=32'sd16113350;
    9'd211:lut=32'sd16141719;
    9'd212:lut=32'sd16169479;
    9'd213:lut=32'sd16196631;
    9'd214:lut=32'sd16223173;
    9'd215:lut=32'sd16249104;
    9'd216:lut=32'sd16274424;
    9'd217:lut=32'sd16299131;
    9'd218:lut=32'sd16323224;
    9'd219:lut=32'sd16346702;
    9'd220:lut=32'sd16369565;
    9'd221:lut=32'sd16391812;
    9'd222:lut=32'sd16413442;
    9'd223:lut=32'sd16434454;
    9'd224:lut=32'sd16454846;
    9'd225:lut=32'sd16474620;
    9'd226:lut=32'sd16493773;
    9'd227:lut=32'sd16512305;
    9'd228:lut=32'sd16530216;
    9'd229:lut=32'sd16547504;
    9'd230:lut=32'sd16564169;
    9'd231:lut=32'sd16580211;
    9'd232:lut=32'sd16595628;
    9'd233:lut=32'sd16610420;
    9'd234:lut=32'sd16624588;
    9'd235:lut=32'sd16638129;
    9'd236:lut=32'sd16651044;
    9'd237:lut=32'sd16663331;
    9'd238:lut=32'sd16674992;
    9'd239:lut=32'sd16686025;
    9'd240:lut=32'sd16696429;
    9'd241:lut=32'sd16706205;
    9'd242:lut=32'sd16715352;
    9'd243:lut=32'sd16723869;
    9'd244:lut=32'sd16731757;
    9'd245:lut=32'sd16739015;
    9'd246:lut=32'sd16745643;
    9'd247:lut=32'sd16751640;
    9'd248:lut=32'sd16757007;
    9'd249:lut=32'sd16761743;
    9'd250:lut=32'sd16765847;
    9'd251:lut=32'sd16769321;
    9'd252:lut=32'sd16772163;
    9'd253:lut=32'sd16774374;
    9'd254:lut=32'sd16775953;
    9'd255:lut=32'sd16776900;
    9'd256:lut=32'sd16777216;
    default:lut=ONE;
   endcase
  end
 endfunction
 function [8:0] address_low;
  input [23:0] phase;
  begin
   address_low=phase[22] ? 9'd256-{1'b0,phase[21:14]}:{1'b0,phase[21:14]};
  end
 endfunction
 function [8:0] address_high;
  input [23:0] phase;
  begin
   address_high=phase[22] ? 9'd255-{1'b0,phase[21:14]}:{1'b0,phase[21:14]}+9'd1;
  end
 endfunction
 function signed [31:0] knot;
  input [3:0] index;
  begin case(index)
   0:knot=0;1:knot=2097152;2:knot=4194304;3:knot=6291456;
   4:knot=10485760;5:knot=12582912;6:knot=14680064;default:knot=16777216;
  endcase end
 endfunction
 function positive_term;
  input [3:0] index;
  begin positive_term=(index==0 || index==3 || index==5 || index==6);end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin mult_wait<=0;stage<=0;busy<=0;done<=0;fraction_q<=0;derivative_q<=0;
   selected<=0;s<=0;r<=0;h<=0;d<=0;ss<=0;rr<=0;sine<=0;cosine<=0;work<=0;
   a<=0;b<=0;mult_q<=0;ed<=0;term<=0;x<=0;square<=0;sum2<=0;sum3<=0;
   low_s<=0;high_s<=0;low_c<=0;high_c<=0;interpolated_s<=0;interpolated_c<=0;fractional<=0;negative_s<=0;negative_c<=0;
  end else begin
   done<=0;
   if(start && !busy) begin
    busy<=1;mult_wait<=1;selected<=mode;s<=phase_q;r<=mode==2 ? envelope_q:phase_q;ed<=envelope_direction;
    if(mode==2) begin
     low_s<=lut(address_low(phase_q[23:0]));high_s<=lut(address_high(phase_q[23:0]));
     low_c<=lut(address_low(cosine_phase));high_c<=lut(address_high(cosine_phase));
     fractional<=phase_q[13:0];negative_s<=phase_q[23];negative_c<=cosine_phase[23];
    end
    sum2<=0;sum3<=0;term<=0;
    stage<=mode==4 ? 20:mode==2 ? 30:1;
   end else if(busy) begin
    // One clock captures the multiplier result before any consumer/addition.
    if(mult_wait) mult_wait<=0;
    else begin mult_wait<=1;case(stage)
    1:begin a<=6*ONE;b<=r;stage<=2;end
    2:begin a<=scaled-15*ONE;b<=r;stage<=3;end
    3:begin a<=scaled+10*ONE;b<=r;stage<=4;end
    4:begin a<=scaled;b<=r;stage<=5;end
    5:begin a<=scaled;b<=r;stage<=6;end
    6:begin h<=scaled;a<=r;b<=r;stage<=7;end
    7:begin rr<=scaled;a<=ONE-r;b<=ONE-r;stage<=8;end
    8:begin a<=rr;b<=scaled;stage<=9;end
    9:begin d<=30*scaled;stage<=10;end
    10:if(selected!=2) begin fraction_q<=h;derivative_q<=d;busy<=0;done<=1;stage<=0;end
       else begin a<=h;b<=sine;stage<=11;end
    11:begin fraction_q<=scaled;a<=h;b<=cosine;stage<=12;end
    12:begin a<=scaled;b<=32'sd105414357;stage<=13;end // 2*pi
    13:begin work<=scaled;a<=d;b<=sine;stage<=14;end
    14:begin derivative_q<=work+(ed==1 ? 2*scaled:ed==-1 ? -2*scaled:0);busy<=0;done<=1;stage<=0;end
    20:begin x<=s>knot(term) ? s-knot(term):0;stage<=21;end
    21:begin a<=x;b<=x;stage<=22;end
    22:begin square<=scaled;a<=scaled;b<=x;stage<=23;end
    23:begin
     sum2<=positive_term(term) ? sum2+square:sum2-square;
     sum3<=positive_term(term) ? sum3+scaled:sum3-scaled;
     if(term==7) stage<=24;else begin term<=term+1'b1;stage<=20;end
    end
    24:begin a<=sum3;b<=32'sd143165577;stage<=25;end // 128/15
    25:begin fraction_q<=s>=ONE ? ONE:scaled;a<=sum2;b<=32'sd429496730;stage<=26;end // 128/5
    26:begin derivative_q<=s>=ONE ? 0:scaled;busy<=0;done<=1;stage<=0;end
    30:begin a<=high_s-low_s;b<=$signed({8'd0,fractional,10'd0});stage<=31;end
    31:begin interpolated_s<=low_s+scaled;stage<=32;end
    32:begin sine<=negative_s ? -interpolated_s:interpolated_s;a<=high_c-low_c;b<=$signed({8'd0,fractional,10'd0});stage<=33;end
    33:begin interpolated_c<=low_c+scaled;stage<=34;end
    34:begin cosine<=negative_c ? -interpolated_c:interpolated_c;stage<=1;end
    default:begin busy<=0;stage<=0;end
   endcase end
   end
  end
 end
endmodule
