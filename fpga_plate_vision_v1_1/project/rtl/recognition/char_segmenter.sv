`timescale 1ns/1ps
// 固定 ROI 字符分割；输入为 160x120 灰度图，x1/y1 为右下不含端点。
// flags[0] 定义逻辑图像旋转180度，flags[1] 为灰度反相。
// 同步帧 RAM：先发地址，再等一拍，下一拍使用读数，适配共享归一化存储器。
// 先计算15x15局部均值阈值，再做8连通洪泛；入队时立即清mask，保证每点只入队一次。
// 本模块与相机时序独立，不向视频链路反压。
module char_segmenter #(parameter ENABLE_PREFIX=0,ENABLE_SPLIT=0)(input wire clk,rst,start,skip_prefix,split_touching,
 input wire [7:0] roi_x0,roi_y0,roi_x1,roi_y1,input wire [1:0] flags,
 output reg busy,done,output reg [7:0] error,output reg [31:0] cycles,
 output reg [14:0] frame_read_addr,input wire [7:0] frame_read_data,
 output reg box_we,output reg [5:0] box_index,
 output reg [7:0] box_x,box_y,box_w,box_h,output reg [6:0] box_count);
 localparam [6:0] IDLE=0,CONFIG=1,TH_INIT=2,TH_ISSUE=3,TH_WAIT=4,TH_TAKE=5,
  TH_DIV=6,TH_STORE=7,SCAN_READ=8,SCAN_CHECK=9,SEED_ENQ=10,Q_TEST=11,
  Q_READ=12,Q_TAKE=13,NB_COORD=14,NB_READ=15,NB_CHECK=16,NB_ENQ=17,
  COMP_PREP=18,COMP_CHECK=19,SCAN_NEXT=20,G_BASE=21,G_READ=22,G_CALC=23,
  G_ACC=24,G_NEXT=25,C_BASE=26,C_READ=27,C_CALC=28,C_ACC=29,
  H_INIT=30,H_READ=31,H_COMPARE=32,H_WRITE_A=33,H_WRITE_B=34,H_NEXT=35,
  MED_READ_A=36,MED_READ_B=37,MED_SUM=38,F_READ=39,F_CHECK=40,F_NEXT=41,
  X_INIT=42,X_READ=43,X_COMPARE=44,X_WRITE_A=45,X_WRITE_B=46,X_NEXT=47,
  OUT_READ=48,OUT_WRITE=49,FINISH=50,CONFIG_DIV=51,CONFIG_ROUND=52,
  G_COMPARE=53,C_COMPARE=54,HIST_CLEAR=55,HIST_TEST=56,HIST_READ=57,HIST_TAKE=58,HIST_WRITE=59,
  VAL_INIT=60,VAL_READ=61,VAL_CHECK=62,VAL_FINISH=63,CHILD_TEST=64,CHILD_READ=65,CHILD_TAKE=66,
  CHILD_PREP=67,CHILD_CHECK=68,SAVE_LEFT=69,SAVE_RIGHT=70,SAVE_ORIGINAL=71;
 reg [6:0] state;
 reg [7:0] rx0,ry0,rx1,ry1,min_h,max_h,roi_height;
 reg [1:0] mode;
 // 首位为汉字的版式：在候选入组前排除左1/8内的中心，避免汉字碎片成为伪字母。
 // 边界相对当前动态ROI计算；只锁存任务开始时的策略，人工模式可关闭。
 reg prefix_mode;reg[7:0]prefix_boundary;
 reg split_mode;
 reg [7:0] px,py;
 reg [3:0] kx,ky;
 reg [15:0] sum,div_q;
 reg [8:0] div_r;
 reg [7:0] divisor;
 reg [4:0] div_step;
 reg [7:0] center_pixel;
 wire [7:0] sample_pixel=mode[1] ? (8'd255-frame_read_data) : frame_read_data;
 wire [9:0] div_shift={div_r,div_q[15]};
 wire div_ge=div_shift>={2'b00,divisor};
 wire [9:0] div_next_r=div_ge ? div_shift-{2'b00,divisor} : div_shift;
 wire [15:0] div_next_q={div_q[14:0],div_ge};
 reg signed [9:0] kernel_x,kernel_y;
 reg [7:0] clamp_x,clamp_y;
 wire [14:0] clamp_addr=({7'd0,clamp_y}<<7)+({7'd0,clamp_y}<<5)+{7'd0,clamp_x};
 wire [14:0] pixel_addr=({7'd0,py}<<7)+({7'd0,py}<<5)+{7'd0,px};
 always @* begin
  kernel_x=$signed({2'b00,px})+$signed({6'd0,kx})-10'sd7;
  kernel_y=$signed({2'b00,py})+$signed({6'd0,ky})-10'sd7;
  clamp_x=(kernel_x<$signed({2'b00,rx0})) ? rx0 :
          (kernel_x>=$signed({2'b00,rx1})) ? rx1-1'b1 : kernel_x[7:0];
  clamp_y=(kernel_y<$signed({2'b00,ry0})) ? ry0 :
          (kernel_y>=$signed({2'b00,ry1})) ? ry1-1'b1 : kernel_y[7:0];
 end
 function automatic [7:0] lower_height(input [7:0] h);
  reg [7:0] q;reg [3:0] r;
  begin q=h/8'd10;r=h%8'd10;
   if(r>5 || (r==5 && q[0])) q=q+1'b1;
   lower_height=(q<5) ? 8'd5:q;
  end
 endfunction
 wire [7:0] rounded_upper=div_q[7:0]+((div_r>9'd50 || (div_r==9'd50 && div_q[0])) ? 8'd1:8'd0);

 // 二值mask推断为1个BRAM36；只使用0..19199地址，逐ROI覆盖，无需整块复位。
 (* ram_style="block" *) reg mask[0:19199];
 reg mask_q;
 wire mask_we=(state==TH_STORE)||(state==SEED_ENQ)||(state==NB_ENQ);
 wire mask_d=(state==TH_STORE) && (div_q>=16'd12) && ({8'd0,center_pixel}<=div_q-16'd12);
 reg [7:0] nx,ny,cx,cy;
 wire [14:0] neighbor_addr=({7'd0,ny}<<7)+({7'd0,ny}<<5)+{7'd0,nx};
 wire [14:0] mask_addr=((state==NB_READ)||(state==NB_CHECK)||(state==NB_ENQ)) ? neighbor_addr:pixel_addr;
 always @(posedge clk) begin
  if(mask_we) mask[mask_addr]<=mask_d;
  mask_q<=mask[mask_addr];
 end

 // 显式分为10个2048x16 bank，避免19200深队列被向上取整为32768深而浪费6块BRAM。
 // 指针不环绕，每个连通域重新从0开始；清mask后才推进队尾，最大容纳19200点。
 reg [15:0] qhead,qtail;
 wire queue_we=(state==SEED_ENQ)||(state==NB_ENQ);
 wire [14:0] queue_addr=(state==SEED_ENQ) ? 15'd0 : (state==NB_ENQ) ? qtail[14:0]:qhead[14:0];
 wire [15:0] queue_d=(state==SEED_ENQ) ? {px,py}:{nx,ny};
 wire [15:0] queue_bank_q[0:9];
 reg [3:0] queue_bank_select;
 always @(posedge clk) queue_bank_select<=queue_addr[14:11];
 genvar b;
 generate for(b=0;b<10;b=b+1) begin: queue_banks
  (* ram_style="block" *) reg [15:0] mem[0:2047];
  reg [15:0] read_data;
  always @(posedge clk) if(queue_addr[14:11]==b) begin
   if(queue_we) mem[queue_addr[10:0]]<=queue_d;
   read_data<=mem[queue_addr[10:0]];
  end
  assign queue_bank_q[b]=read_data;
 end endgenerate
 wire [15:0] queue_q=queue_bank_q[queue_bank_select];
 reg [2:0] nb;
 reg signed [8:0] neighbor_x,neighbor_y;
 always @* begin
  neighbor_x=$signed({1'b0,cx});neighbor_y=$signed({1'b0,cy});
  case(nb)
   0:begin neighbor_x=neighbor_x-1;neighbor_y=neighbor_y-1;end
   1:begin neighbor_y=neighbor_y-1;end
   2:begin neighbor_x=neighbor_x+1;neighbor_y=neighbor_y-1;end
   3:begin neighbor_x=neighbor_x-1;end
   4:begin neighbor_x=neighbor_x+1;end
   5:begin neighbor_x=neighbor_x-1;neighbor_y=neighbor_y+1;end
   6:begin neighbor_y=neighbor_y+1;end
   7:begin neighbor_x=neighbor_x+1;neighbor_y=neighbor_y+1;end
  endcase
 end
 wire neighbor_valid=(neighbor_x>=$signed({1'b0,rx0}))&&(neighbor_x<$signed({1'b0,rx1}))&&
                      (neighbor_y>=$signed({1'b0,ry0}))&&(neighbor_y<$signed({1'b0,ry1}));
 reg [7:0] xmin,xmax,ymin,ymax,cw,ch;
 wire[8:0]component_center={xmin,1'b0}+{1'b0,cw};
 wire prefix_keep=!prefix_mode || component_center>={prefix_boundary,1'b0};
 reg [14:0] area;
 // 宽域的中间低墨量谷可解除牌面下沿细线造成的字符粘连。
 // 洪泛结束后复用原队列中的坐标，不保存第二份二值图，也不新增帧缓存。
 (* ram_style="distributed" *) reg[6:0] column_ink[0:159];
 reg[7:0]hist_x,cut_x,best_cut;reg[6:0]hist_old,ink_a,ink_b;
 reg[8:0]best_valley;
 wire[8:0]valley={2'b0,ink_a}+{2'b0,ink_b};
 wire[9:0]cut_times3={2'b0,cut_x-xmin}*10'd3;
 reg[7:0]lx0,lx1,ly0,ly1,rxmin,rxmax,rymin,rymax,lw,lh,rw,rh;
 reg[14:0]left_area,right_area;
 wire parent_valid=(ch>=min_h)&&(ch<=max_h)&&(cw>=2)&&(area>={7'd0,ch});
 wire original_width_valid=({2'd0,cw}*10'd5)<=({2'd0,ch}*10'd7);
 wire left_valid=(lw>=2)&&(lh>=min_h)&&(lh<=max_h)&&({2'd0,lh}*10'd4>={2'd0,ch}*10'd3)&&
                 ({2'd0,lw}*10'd5<={2'd0,ch}*10'd4)&&(left_area>={7'd0,lh})&&
                 (!prefix_mode||({lx0,1'b0}+{1'b0,lw})>={prefix_boundary,1'b0});
 wire right_valid=(rw>=2)&&(rh>=min_h)&&(rh<=max_h)&&({2'd0,rh}*10'd4>={2'd0,ch}*10'd3)&&
                  ({2'd0,rw}*10'd5<={2'd0,ch}*10'd4)&&(right_area>={7'd0,rh})&&
                  (!prefix_mode||({rxmin,1'b0}+{1'b0,rw})>={prefix_boundary,1'b0});
 (* ram_style="distributed" *) reg [31:0] candidates[0:63];
 (* ram_style="distributed" *) reg [7:0] heights[0:63];
 (* ram_style="distributed" *) reg [5:0] members[0:63];
 (* ram_style="distributed" *) reg [31:0] output_boxes[0:63];
 reg [6:0] candidate_count,group_count,keep_count;
 reg [5:0] base_idx,item_idx,best_idx;
 reg [31:0] base_box,item_box;
 reg [13:0] group_score,best_score;
 wire [8:0] base_center={base_box[23:16],1'b0}+{1'b0,base_box[7:0]};
 wire [8:0] item_center={item_box[23:16],1'b0}+{1'b0,item_box[7:0]};
 wire [8:0] center_diff=(base_center>item_center) ? base_center-item_center:item_center-base_center;
 wire [7:0] max_height=(base_box[7:0]>item_box[7:0]) ? base_box[7:0]:item_box[7:0];
 reg group_match;
 reg [8:0] group_center_diff;
 reg [7:0] group_max_height;
 reg group_height_match;
 wire height_pair_match=({base_box[7:0],1'b0}>{1'b0,item_box[7:0]}) &&
                        ({1'b0,base_box[7:0]}<{item_box[7:0],1'b0});
 wire [12:0] center_distance_x10={4'd0,group_center_diff}*13'd10;
 wire [12:0] height_x9={5'd0,group_max_height}*13'd9;
 wire pair_match=(center_distance_x10<height_x9) && group_height_match;
 reg [6:0] sort_limit;
 reg [5:0] sort_pos;
 reg [7:0] height_a,height_b,median_a;
 reg [8:0] median_twice;
 reg [31:0] sort_a,sort_b;
 reg [5:0] filter_member;
 wire [12:0] item_height_x40={5'd0,item_box[7:0]}*13'd40;
 wire [12:0] median_x13={4'd0,median_twice}*13'd13;

 always @(posedge clk) begin
  if(rst) begin
   state<=IDLE;busy<=0;done<=0;error<=0;cycles<=0;frame_read_addr<=0;
   box_we<=0;box_index<=0;box_x<=0;box_y<=0;box_w<=0;box_h<=0;box_count<=0;
   rx0<=0;ry0<=0;rx1<=0;ry1<=0;mode<=0;roi_height<=0;min_h<=0;max_h<=0;prefix_mode<=0;prefix_boundary<=0;split_mode<=0;
   hist_x<=0;cut_x<=0;best_cut<=0;hist_old<=0;ink_a<=0;ink_b<=0;best_valley<=511;
   lx0<=255;lx1<=0;ly0<=255;ly1<=0;rxmin<=255;rxmax<=0;rymin<=255;rymax<=0;
   lw<=0;lh<=0;rw<=0;rh<=0;left_area<=0;right_area<=0;
   px<=0;py<=0;kx<=0;ky<=0;sum<=0;div_q<=0;div_r<=0;div_step<=0;divisor<=225;center_pixel<=0;
   qhead<=0;qtail<=0;nx<=0;ny<=0;cx<=0;cy<=0;nb<=0;
   xmin<=0;xmax<=0;ymin<=0;ymax<=0;cw<=0;ch<=0;area<=0;
   candidate_count<=0;group_count<=0;keep_count<=0;base_idx<=0;item_idx<=0;best_idx<=0;
   base_box<=0;item_box<=0;group_score<=0;best_score<=0;group_match<=0;
   group_center_diff<=0;group_max_height<=0;group_height_match<=0;
   sort_limit<=0;sort_pos<=0;height_a<=0;height_b<=0;median_a<=0;median_twice<=0;
   sort_a<=0;sort_b<=0;filter_member<=0;
  end else begin
   done<=0;box_we<=0;
   if(busy) cycles<=cycles+1'b1;
   case(state)
    IDLE:if(start) begin
     busy<=1;error<=0;cycles<=0;box_count<=0;candidate_count<=0;
     group_count<=0;keep_count<=0;best_score<=0;best_idx<=0;
     rx0<=roi_x0;ry0<=roi_y0;rx1<=roi_x1;ry1<=roi_y1;mode<=flags;
     prefix_mode<=ENABLE_PREFIX&&skip_prefix;prefix_boundary<=roi_x0+((roi_x1-roi_x0)>>3);
     split_mode<=ENABLE_SPLIT&&split_touching;
     roi_height<=roi_y1-roi_y0;px<=roi_x0;py<=roi_y0;
     if(roi_x0>=roi_x1 || roi_y0>=roi_y1 || roi_x1>160 || roi_y1>120) begin error<=1;state<=FINISH;end
     else state<=CONFIG;
    end
    // 复用16拍恢复除法器计算 round-even(85*H/100)。
    // 配置除法按位迭代，避免组合除法形成超过10ns的长路径。
    CONFIG:begin
     min_h<=lower_height(roi_height);div_q<={8'd0,roi_height}*16'd85;
     div_r<=0;div_step<=0;divisor<=100;state<=CONFIG_DIV;
    end
    CONFIG_DIV:begin
     div_q<=div_next_q;div_r<=div_next_r[8:0];
     if(div_step==15) state<=CONFIG_ROUND;else div_step<=div_step+1'b1;
    end
    CONFIG_ROUND:begin max_h<=(rounded_upper<8) ? 8'd8:rounded_upper;state<=TH_INIT;end
    TH_INIT:begin sum<=0;kx<=0;ky<=0;state<=TH_ISSUE;end
    TH_ISSUE:begin frame_read_addr<=mode[0] ? 15'd19199-clamp_addr:clamp_addr;state<=TH_WAIT;end
    TH_WAIT:state<=TH_TAKE;
    TH_TAKE:begin
     sum<=sum+{8'd0,sample_pixel};
     if(kx==7 && ky==7) center_pixel<=sample_pixel;
     if(kx==14 && ky==14) begin
      div_q<=sum+{8'd0,sample_pixel}+16'd112;div_r<=0;div_step<=0;divisor<=225;state<=TH_DIV;
     end else begin
      if(kx==14) begin kx<=0;ky<=ky+1'b1;end else kx<=kx+1'b1;
      state<=TH_ISSUE;
     end
    end
    TH_DIV:begin
     div_q<=div_next_q;div_r<=div_next_r[8:0];
     if(div_step==15) state<=TH_STORE;else div_step<=div_step+1'b1;
    end
    TH_STORE:begin
     if(px==rx1-1'b1) begin
      px<=rx0;
      if(py==ry1-1'b1) begin py<=ry0;state<=SCAN_READ;end
      else begin py<=py+1'b1;state<=TH_INIT;end
     end else begin px<=px+1'b1;state<=TH_INIT;end
    end
    SCAN_READ:state<=SCAN_CHECK;
    SCAN_CHECK:if(mask_q) state<=SEED_ENQ;else state<=SCAN_NEXT;
    SEED_ENQ:begin
     qhead<=0;qtail<=1;area<=1;xmin<=px;xmax<=px;ymin<=py;ymax<=py;state<=Q_TEST;
    end
    Q_TEST:if(qhead<qtail) state<=Q_READ;else state<=COMP_PREP;
    Q_READ:state<=Q_TAKE;
    Q_TAKE:begin cx<=queue_q[15:8];cy<=queue_q[7:0];qhead<=qhead+1'b1;nb<=0;state<=NB_COORD;end
    NB_COORD:begin
     if(neighbor_valid) begin nx<=neighbor_x[7:0];ny<=neighbor_y[7:0];state<=NB_READ;end
     else if(nb==7) state<=Q_TEST;else nb<=nb+1'b1;
    end
    NB_READ:state<=NB_CHECK;
    NB_CHECK:begin
     if(mask_q) begin
      if(qtail>=19200) begin error<=2;box_count<=0;state<=FINISH;end else state<=NB_ENQ;
     end else if(nb==7) state<=Q_TEST;else begin nb<=nb+1'b1;state<=NB_COORD;end
    end
    NB_ENQ:begin
     qtail<=qtail+1'b1;area<=area+1'b1;
     if(nx<xmin) xmin<=nx;if(nx>xmax) xmax<=nx;
     if(ny<ymin) ymin<=ny;if(ny>ymax) ymax<=ny;
     if(nb==7) state<=Q_TEST;else begin nb<=nb+1'b1;state<=NB_COORD;end
    end
    COMP_PREP:begin cw<=xmax-xmin+1'b1;ch<=ymax-ymin+1'b1;state<=COMP_CHECK;end
    COMP_CHECK:begin
     state<=SCAN_NEXT;
     if(prefix_keep && parent_valid) begin
      if(split_mode&&cw>=ch&&{1'b0,cw}<={ch,1'b0})begin hist_x<=xmin;state<=HIST_CLEAR;end
      else if(original_width_valid)state<=SAVE_ORIGINAL;
     end
    end
    HIST_CLEAR:begin
     column_ink[hist_x]<=0;
     if(hist_x==xmax)begin qhead<=0;state<=HIST_TEST;end else hist_x<=hist_x+1'b1;
    end
    HIST_TEST:if(qhead<qtail)state<=HIST_READ;else state<=VAL_INIT;
    HIST_READ:state<=HIST_TAKE;
    HIST_TAKE:begin hist_x<=queue_q[15:8];hist_old<=column_ink[queue_q[15:8]];state<=HIST_WRITE;end
    HIST_WRITE:begin column_ink[hist_x]<=hist_old+1'b1;qhead<=qhead+1'b1;state<=HIST_TEST;end
    VAL_INIT:begin cut_x<=xmin+1'b1;best_valley<=511;best_cut<=0;state<=VAL_READ;end
    VAL_READ:begin ink_a<=column_ink[cut_x-1'b1];ink_b<=column_ink[cut_x];state<=VAL_CHECK;end
    // 只搜索中间1/3；两列总墨量<=高度/8才视为细桥，等分数保留靠左切口。
    VAL_CHECK:begin
     if(cut_times3>={2'b0,cw}&&cut_times3<={1'b0,cw,1'b0}&&valley<best_valley)begin best_valley<=valley;best_cut<=cut_x;end
     if(cut_x==xmax)state<=VAL_FINISH;else begin cut_x<=cut_x+1'b1;state<=VAL_READ;end
    end
    VAL_FINISH:begin
     if(best_valley<={4'b0,ch[7:3]})begin
      qhead<=0;left_area<=0;right_area<=0;
      lx0<=255;lx1<=0;ly0<=255;ly1<=0;rxmin<=255;rxmax<=0;rymin<=255;rymax<=0;state<=CHILD_TEST;
     end else state<=SAVE_ORIGINAL;
    end
    // 第二次遍历同一域的队列，分别收紧两侧包围框；不把别的域计入投影。
    CHILD_TEST:if(qhead<qtail)state<=CHILD_READ;else state<=CHILD_PREP;
    CHILD_READ:state<=CHILD_TAKE;
    CHILD_TAKE:begin
     if(queue_q[15:8]<best_cut)begin
      left_area<=left_area+1'b1;
      if(queue_q[15:8]<lx0)lx0<=queue_q[15:8];if(queue_q[15:8]>lx1)lx1<=queue_q[15:8];
      if(queue_q[7:0]<ly0)ly0<=queue_q[7:0];if(queue_q[7:0]>ly1)ly1<=queue_q[7:0];
     end else begin
      right_area<=right_area+1'b1;
      if(queue_q[15:8]<rxmin)rxmin<=queue_q[15:8];if(queue_q[15:8]>rxmax)rxmax<=queue_q[15:8];
      if(queue_q[7:0]<rymin)rymin<=queue_q[7:0];if(queue_q[7:0]>rymax)rymax<=queue_q[7:0];
     end
     qhead<=qhead+1'b1;state<=CHILD_TEST;
    end
    CHILD_PREP:begin lw<=lx1-lx0+1'b1;lh<=ly1-ly0+1'b1;rw<=rxmax-rxmin+1'b1;rh<=rymax-rymin+1'b1;state<=CHILD_CHECK;end
    CHILD_CHECK:begin
     if(left_area!=0&&right_area!=0&&left_valid&&right_valid)begin
      if(candidate_count>62)begin error<=3;box_count<=0;state<=FINISH;end else state<=SAVE_LEFT;
     end else state<=SAVE_ORIGINAL;
    end
    SAVE_LEFT:begin candidates[candidate_count[5:0]]<={lx0,ly0,lw,lh};candidate_count<=candidate_count+1'b1;state<=SAVE_RIGHT;end
    SAVE_RIGHT:begin candidates[candidate_count[5:0]]<={rxmin,rymin,rw,rh};candidate_count<=candidate_count+1'b1;state<=SCAN_NEXT;end
    SAVE_ORIGINAL:begin
     state<=SCAN_NEXT;
     if(original_width_valid)begin
      if(candidate_count==64)begin error<=3;box_count<=0;state<=FINISH;end
      else begin candidates[candidate_count[5:0]]<={xmin,ymin,cw,ch};candidate_count<=candidate_count+1'b1;end
     end
    end
    SCAN_NEXT:begin
     if(px==rx1-1'b1) begin
      px<=rx0;
      if(py==ry1-1'b1) begin
       if(candidate_count==0) state<=FINISH;else begin base_idx<=0;state<=G_BASE;end
      end else begin py<=py+1'b1;state<=SCAN_READ;end
     end else begin px<=px+1'b1;state<=SCAN_READ;end
    end
    G_BASE:begin base_box<=candidates[base_idx];item_idx<=0;group_score<=0;state<=G_READ;end
    G_READ:begin item_box<=candidates[item_idx];state<=G_CALC;end
    // 中心距离/高度关系与乘常数比较分拍，保留严格不等号并缩短同行筛选路径。
    G_CALC:begin group_center_diff<=center_diff;group_max_height<=max_height;group_height_match<=height_pair_match;state<=G_COMPARE;end
    G_COMPARE:begin group_match<=pair_match;state<=G_ACC;end
    G_ACC:begin if(group_match) group_score<=group_score+{6'd0,item_box[7:0]};
     if({1'b0,item_idx}+7'd1==candidate_count) state<=G_NEXT;
     else begin item_idx<=item_idx+1'b1;state<=G_READ;end
    end
    G_NEXT:begin
     if(group_score>best_score) begin best_score<=group_score;best_idx<=base_idx;end
     if({1'b0,base_idx}+7'd1==candidate_count) state<=C_BASE;
     else begin base_idx<=base_idx+1'b1;state<=G_BASE;end
    end
    C_BASE:begin base_box<=candidates[best_idx];item_idx<=0;group_count<=0;state<=C_READ;end
    C_READ:begin item_box<=candidates[item_idx];state<=C_CALC;end
    C_CALC:begin group_center_diff<=center_diff;group_max_height<=max_height;group_height_match<=height_pair_match;state<=C_COMPARE;end
    C_COMPARE:begin group_match<=pair_match;state<=C_ACC;end
    C_ACC:begin
     if(group_match) begin members[group_count[5:0]]<=item_idx;heights[group_count[5:0]]<=item_box[7:0];group_count<=group_count+1'b1;end
     if({1'b0,item_idx}+7'd1==candidate_count) state<=H_INIT;
     else begin item_idx<=item_idx+1'b1;state<=C_READ;end
    end
    H_INIT:begin sort_pos<=0;sort_limit<=group_count-1'b1;if(group_count<=1) state<=MED_READ_A;else state<=H_READ;end
    H_READ:begin height_a<=heights[sort_pos];height_b<=heights[sort_pos+6'd1];state<=H_COMPARE;end
    H_COMPARE:if(height_a>height_b) state<=H_WRITE_A;else state<=H_NEXT;
    H_WRITE_A:begin heights[sort_pos]<=height_b;state<=H_WRITE_B;end
    H_WRITE_B:begin heights[sort_pos+6'd1]<=height_a;state<=H_NEXT;end
    H_NEXT:begin
     if({1'b0,sort_pos}+7'd1>=sort_limit) begin
      if(sort_limit<=1) state<=MED_READ_A;
      else begin sort_limit<=sort_limit-1'b1;sort_pos<=0;state<=H_READ;end
     end else begin sort_pos<=sort_pos+1'b1;state<=H_READ;end
    end
    MED_READ_A:begin median_a<=heights[(group_count-7'd1)>>1];state<=MED_READ_B;end
    MED_READ_B:begin height_b<=heights[group_count>>1];state<=MED_SUM;end
    // 中位数以2倍整数保存，40*h>=13*M2 精确实现0.65倍筛选，避免浮点误差。
    MED_SUM:begin median_twice<={1'b0,median_a}+{1'b0,height_b};item_idx<=0;keep_count<=0;state<=F_READ;end
    F_READ:begin filter_member<=members[item_idx];state<=F_CHECK;end
    F_CHECK:begin item_box<=candidates[filter_member];state<=F_NEXT;end
    F_NEXT:begin
     if(item_height_x40>=median_x13) begin output_boxes[keep_count[5:0]]<=item_box;keep_count<=keep_count+1'b1;end
     if({1'b0,item_idx}+7'd1==group_count) state<=X_INIT;
     else begin item_idx<=item_idx+1'b1;state<=F_READ;end
    end
    X_INIT:begin
     box_count<=keep_count;sort_pos<=0;sort_limit<=keep_count-1'b1;item_idx<=0;
     if(keep_count==0) state<=FINISH;else if(keep_count==1) state<=OUT_READ;else state<=X_READ;
    end
    X_READ:begin sort_a<=output_boxes[sort_pos];sort_b<=output_boxes[sort_pos+6'd1];state<=X_COMPARE;end
    // 仅在x严格大于时交换，因此相同x保持原候选次序。
    X_COMPARE:if(sort_a[31:24]>sort_b[31:24]) state<=X_WRITE_A;else state<=X_NEXT;
    X_WRITE_A:begin output_boxes[sort_pos]<=sort_b;state<=X_WRITE_B;end
    X_WRITE_B:begin output_boxes[sort_pos+6'd1]<=sort_a;state<=X_NEXT;end
    X_NEXT:begin
     if({1'b0,sort_pos}+7'd1>=sort_limit) begin
      if(sort_limit<=1) state<=OUT_READ;
      else begin sort_limit<=sort_limit-1'b1;sort_pos<=0;state<=X_READ;end
     end else begin sort_pos<=sort_pos+1'b1;state<=X_READ;end
    end
    OUT_READ:begin item_box<=output_boxes[item_idx];state<=OUT_WRITE;end
    OUT_WRITE:begin
     box_we<=1;box_index<=item_idx;{box_x,box_y,box_w,box_h}<=item_box;
     if({1'b0,item_idx}+7'd1==keep_count) state<=FINISH;
     else begin item_idx<=item_idx+1'b1;state<=OUT_READ;end
    end
    FINISH:begin busy<=0;done<=1;state<=IDLE;end
    default:begin error<=4;box_count<=0;state<=FINISH;end
   endcase
  end
 end
endmodule
