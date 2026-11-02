`timescale 1ns/1ps
// uint8 激活、int8 权重、int32 累加；每个 tap 读 RAM / 乘 / 加三拍。
module cnn_core #(
  parameter WEIGHTS_FILE="model/weights.hex",
  parameter BIASES_FILE="model/biases.hex"
)(
  input wire clk,rst,start,in_we,
  input wire [9:0] in_addr,
  input wire [7:0] in_data,
  output reg busy=0,done=0,score_valid=0,
  output reg [5:0] score_index=0,
  output reg signed [31:0] score_data=0,
  output reg [31:0] cycles=0
);
  localparam IDLE=0, BIAS_READ=1, BIAS_LOAD=2, TAP_READ=3,
             TAP_MUL=4, TAP_ACC=5, QUANT=6, STORE=7, SCORE=8;
  reg [3:0] state=IDLE;
  reg [1:0] layer=0;
  reg [5:0] oc=0;
  reg [2:0] ic=0;
  reg [1:0] ky=0,kx=0,subpixel=0;
  reg [3:0] py=0,px=0;
  reg [9:0] fc_index=0;
  reg [10:0] out_addr=0;
  reg [7:0] pool_max=0;
  (* use_dsp="no" *) reg signed [31:0] acc=0;
  (* use_dsp="yes" *) reg signed [16:0] product=0;
  reg pad_q=0;
  reg [14:0] weight_base=0,weight_ptr=0;

  // 同步 ROM/RAM 不复位内容；新任务覆盖所需工作区。
  (* rom_style="distributed" *) reg signed [31:0] biases [0:59];
  (* ram_style="block" *) reg [7:0] ram_a [0:2047];
  (* ram_style="block" *) reg [7:0] ram_b [0:2047];
  wire signed [7:0] weight_q;
  reg signed [31:0] bias_q;
  reg [7:0] a_q,b_q;
  initial begin
    $readmemh(BIASES_FILE,biases);
  end

  reg [5:0] iy,ix;
  (* use_dsp="no" *) reg [10:0] act_addr;
  wire [14:0] weight_addr=weight_ptr;
  reg [5:0] bias_addr;
  reg padding;
  // 负一在六位坐标中回绕到 63，由 padding 屏蔽。
  always_comb begin
    iy={1'b0,py,1'b0}+subpixel[1]+ky-6'd1;
    ix={1'b0,px,1'b0}+subpixel[0]+kx-6'd1;
    padding=0;
    if (layer==0) begin
      act_addr=iy*11'd24+ix;
      bias_addr=oc;
      padding=(iy>=32 || ix>=24);
    end else if (layer==1) begin
      act_addr=ic*11'd192+iy*11'd12+ix;
      bias_addr=6'd8+oc;
      padding=(iy>=16 || ix>=12);
    end else begin
      act_addr={1'b0,fc_index};
      bias_addr=6'd24+oc;
    end
  end
  // 写地址先合并成单口，避免推断成两个写口加一个读口。
  wire load_input=!busy && in_we && in_addr<768;
  wire a_we=!rst && (load_input || (state==STORE && layer==1));
  wire [10:0] a_write_addr=load_input ? {1'b0,in_addr} : out_addr;
  wire [7:0] a_write_data=load_input ? in_data : pool_max;
  cnn_weight_rom #(.FILE(WEIGHTS_FILE)) weight_rom (
    .clk(clk),.addr(weight_addr),.data(weight_q)
  );
  always @(posedge clk) bias_q<=biases[bias_addr];
  always @(posedge clk) begin
    a_q<=ram_a[act_addr];
    if (a_we) ram_a[a_write_addr]<=a_write_data;
  end
  always @(posedge clk) begin
    b_q<=ram_b[act_addr];
    if (!rst && state==STORE && layer==0) ram_b[out_addr]<=pool_max;
  end

  reg [7:0] quantized;
  reg signed [31:0] rounded;
  always_comb begin
    rounded=(layer==0) ? ((acc+32'sd128)>>>8) : ((acc+32'sd512)>>>10);
    if (rounded<0) quantized=0;
    else if (rounded>255) quantized=255;
    else quantized=rounded[7:0];
  end

  always @(posedge clk) begin
    if (rst) begin
      state<=IDLE; busy<=0; done<=0; score_valid<=0; cycles<=0;
      score_index<=0; score_data<=0; layer<=0; oc<=0; ic<=0;
      ky<=0; kx<=0; subpixel<=0; py<=0; px<=0;
      fc_index<=0; out_addr<=0; pool_max<=0; acc<=0; product<=0; pad_q<=0;
      weight_base<=0; weight_ptr<=0;
    end else begin
      done<=0; score_valid<=0;
      if (busy) cycles<=cycles+1'b1;
      case (state)
        IDLE: if (start) begin
          busy<=1; cycles<=0; layer<=0; oc<=0; py<=0; px<=0;
          subpixel<=0; out_addr<=0; pool_max<=0; state<=BIAS_READ;
          weight_base<=0;
        end
        BIAS_READ: state<=BIAS_LOAD;
        BIAS_LOAD: begin
          acc<=bias_q; ic<=0; ky<=0; kx<=0; fc_index<=0; state<=TAP_READ;
          weight_ptr<=weight_base;
        end
        TAP_READ: begin pad_q<=padding; state<=TAP_MUL; end
        TAP_MUL: begin
          if (pad_q) product<=0;
          else product<=$signed({1'b0,(layer==1 ? b_q : a_q)}) * $signed(weight_q);
          state<=TAP_ACC;
        end
        TAP_ACC: begin
          acc<=acc+{{15{product[16]}},product};
          weight_ptr<=weight_ptr+1'b1;
          if (layer==2) begin
            if (fc_index==767) state<=SCORE;
            else begin fc_index<=fc_index+1'b1; state<=TAP_READ; end
          end else if (kx==2) begin
            kx<=0;
            if (ky==2) begin
              ky<=0;
              if (layer==0 || ic==7) state<=QUANT;
              else begin ic<=ic+1'b1; state<=TAP_READ; end
            end else begin ky<=ky+1'b1; state<=TAP_READ; end
          end else begin kx<=kx+1'b1; state<=TAP_READ; end
        end
        QUANT: begin
          if (subpixel==0 || quantized>pool_max) pool_max<=quantized;
          if (subpixel==3) state<=STORE;
          else begin subpixel<=subpixel+1'b1; state<=BIAS_READ; end
        end
        STORE: begin
          subpixel<=0; out_addr<=out_addr+1'b1; state<=BIAS_READ;
          if (px==(layer==0 ? 11 : 5)) begin
            px<=0;
            if (py==(layer==0 ? 15 : 7)) begin
              py<=0;
              if (oc==(layer==0 ? 7 : 15)) begin
                layer<=layer+1'b1; oc<=0; out_addr<=0;
                weight_base<=(layer==0 ? 15'd72 : 15'd1224);
              end else begin
                oc<=oc+1'b1;
                weight_base<=weight_base+(layer==0 ? 15'd9 : 15'd72);
              end
            end else py<=py+1'b1;
          end else px<=px+1'b1;
        end
        SCORE: begin
          score_valid<=1; score_index<=oc; score_data<=acc;
          if (oc==35) begin busy<=0; done<=1; state<=IDLE; end
          else begin
            oc<=oc+1'b1; weight_base<=weight_base+15'd768; state<=BIAS_READ;
          end
        end
        default: begin state<=IDLE; busy<=0; end
      endcase
    end
  end
endmodule
