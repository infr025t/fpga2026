`timescale 1ns/1ps
// Full cropped-output CRCs and a latest-only, nonblocking report mailbox.
// Input acceptance descriptors, the output CRC context, a pending EOF report,
// the latest mailbox and its claimed copy are independent registers.
module core_crc_monitor #(parameter integer W=640,H=480)(
 input wire clk,rst,abort,
 input wire [7:0] out_pixel,out_raw,input wire out_valid,
 input wire [9:0] out_x,input wire [8:0] out_y,
 input wire out_sof,out_eol,out_eof,input wire [31:0] out_frame_id,
 input wire frame_start_valid,input wire [31:0] frame_start_id,
 input video_runtime_pkg::frame_config_t frame_start_config,
 input wire frame_success_valid,input wire [31:0] frame_success_id,
 input wire frame_invalid_valid,input wire [31:0] frame_invalid_id,
 input wire [3:0] frame_invalid_reason,
 input wire [31:0] completed_frames,invalid_frames,accepted_frames,
 output wire core_done_valid,output wire [31:0] core_done_frame_id,
 output wire core_done_ok,
 output reg latest_valid,output video_runtime_pkg::core_report_t latest,
 input wire claim,output reg claimed_valid,
 output video_runtime_pkg::core_report_t claimed_report,
 output reg [31:0] overwrite_count
);
 import video_runtime_pkg::*;
 localparam integer PIXELS=(W-8)*(H-8);
 initial if(W<16 || W>640 || H<16 || H>480)$fatal(1,"illegal CRC monitor dimensions");
 reg input_descriptor_valid,collecting,frame_bad;
 reg [31:0] input_id,output_id,pixel_count,raw_state,selected_state;
 frame_config_t input_config,output_config;
 reg [9:0] expected_x;reg [8:0] expected_y;
 reg success_seen;reg [31:0] success_id;
 reg pending_valid,publish_pending;core_report_t pending_report;
 reg latest_claimed;reg [31:0] diagnostic_seq;
 wire descriptor_match=(frame_start_valid && frame_start_id==out_frame_id) ||
                       (input_descriptor_valid && input_id==out_frame_id);
 wire [31:0] current_id=collecting?output_id:out_frame_id;
 wire [31:0] current_count=collecting?pixel_count:0;
 wire [9:0] current_x=collecting?expected_x:10'd4;
 wire [8:0] current_y=collecting?expected_y:9'd4;
 wire pixel_bad=(!collecting && !descriptor_match) || out_frame_id!=current_id ||
   out_x!=current_x || out_y!=current_y || current_count>=PIXELS ||
   out_sof!=(current_count==0) || out_eol!=(current_x==W-5) ||
   out_eof!=(current_count==PIXELS-1);
 wire [31:0] raw_next,selected_next;
 crc32_byte raw_crc(.state(collecting?raw_state:32'hffffffff),.data(out_raw),.next_state(raw_next));
 crc32_byte selected_crc(.state(collecting?selected_state:32'hffffffff),.data(out_pixel),.next_state(selected_next));
 assign core_done_valid=out_valid && out_eof && !rst && !abort;
 assign core_done_frame_id=out_frame_id;
 assign core_done_ok=core_done_valid && !pixel_bad && !(collecting && frame_bad) &&
                     current_count==PIXELS-1;
 wire matching_success=(success_seen && success_id==current_id) ||
                       (frame_success_valid && frame_success_id==current_id);
 wire lose_latest=latest_valid && !latest_claimed && !claim;
 wire [31:0] next_overwrite=(lose_latest && overwrite_count!=32'hffffffff)?
                            overwrite_count+1'b1:overwrite_count;
 core_report_t publication;
 always @*begin
   publication=pending_report;
   publication.diagnostic_seq=diagnostic_seq+1'b1;
   publication.report_overwrite_count=next_overwrite;
   // These buses have already been updated at the preceding success edge.
   publication.completed_frames=completed_frames;
   publication.invalid_frames=invalid_frames;
   publication.accepted_frames=accepted_frames;
 end
 always @(posedge clk)begin
   if(rst)begin
     input_descriptor_valid<=0;input_id<=0;input_config<='0;
     collecting<=0;frame_bad<=0;output_id<=0;output_config<='0;
     pixel_count<=0;raw_state<=32'hffffffff;selected_state<=32'hffffffff;
     expected_x<=4;expected_y<=4;success_seen<=0;success_id<=0;
     pending_valid<=0;publish_pending<=0;pending_report<='0;
     latest_valid<=0;latest<='0;latest_claimed<=0;
     claimed_valid<=0;claimed_report<='0;overwrite_count<=0;diagnostic_seq<=0;
   end else begin
     claimed_valid<=0;
     // A concurrent publication is later in this block: claim sees old latest,
     // and the newly published report remains unclaimed.
     if(claim && latest_valid)begin
       claimed_report<=latest;claimed_valid<=1;latest_claimed<=1;
     end
     if(publish_pending && pending_valid && !abort &&
        !(frame_invalid_valid && frame_invalid_id==pending_report.frame_id))begin
       latest<=publication;latest_valid<=1;latest_claimed<=0;
       diagnostic_seq<=diagnostic_seq+1'b1;overwrite_count<=next_overwrite;
       pending_valid<=0;publish_pending<=0;
       if(success_seen && success_id==pending_report.frame_id)success_seen<=0;
     end
     if(abort)begin
       input_descriptor_valid<=0;collecting<=0;frame_bad<=0;
       pending_valid<=0;publish_pending<=0;success_seen<=0;
     end else begin
       if(frame_start_valid)begin
         input_descriptor_valid<=1;input_id<=frame_start_id;input_config<=frame_start_config;
       end
       if(frame_success_valid)begin
         if((input_descriptor_valid && input_id==frame_success_id) ||
            (frame_start_valid && frame_start_id==frame_success_id) ||
            (collecting && output_id==frame_success_id))begin
           success_seen<=1;success_id<=frame_success_id;
         end
         if(pending_valid && pending_report.frame_id==frame_success_id)publish_pending<=1;
       end
       if(collecting && !out_valid && (out_sof || out_eol || out_eof))frame_bad<=1;
       if(out_valid)begin
         collecting<=1;pixel_count<=current_count+1'b1;
         raw_state<=raw_next;selected_state<=selected_next;
         frame_bad<=(collecting && frame_bad)||pixel_bad;
         if(!collecting)begin
           output_id<=out_frame_id;
           output_config<=(frame_start_valid && frame_start_id==out_frame_id)?frame_start_config:input_config;
         end
         if(current_x==W-5)begin expected_x<=4;expected_y<=current_y+1'b1;end
         else begin expected_x<=current_x+1'b1;expected_y<=current_y;end
         if(out_eof)begin
           collecting<=0;frame_bad<=0;
           // A simultaneous next input SOF updates only input_config above.
           // The old output descriptor and CRCs are committed independently.
           if(!frame_start_valid && input_id==current_id)input_descriptor_valid<=0;
           if(core_done_ok)begin
             pending_valid<=1;publish_pending<=matching_success;
             pending_report<='0;
             pending_report.frame_id<=current_id;
             pending_report.frame_config<=collecting?output_config:
               ((frame_start_valid && frame_start_id==out_frame_id)?frame_start_config:input_config);
             pending_report.pixel_count<=current_count+1'b1;
             pending_report.raw_crc<=raw_next^32'hffffffff;
             pending_report.selected_crc<=selected_next^32'hffffffff;
           end else begin
             pending_valid<=0;publish_pending<=0;success_seen<=0;
           end
         end
       end
       // Invalid is targeted by frame ID; it cannot discard a different good
       // report or erase a new descriptor accepted on the same edge.
       if(frame_invalid_valid)begin
         if((frame_start_valid && frame_start_id==frame_invalid_id) ||
            (!frame_start_valid && input_descriptor_valid && input_id==frame_invalid_id))
           input_descriptor_valid<=0;
         if((collecting && output_id==frame_invalid_id) ||
            (out_valid && current_id==frame_invalid_id))begin collecting<=0;frame_bad<=0;end
         if(success_seen && success_id==frame_invalid_id)success_seen<=0;
         if((pending_valid && pending_report.frame_id==frame_invalid_id) ||
            (out_valid && out_eof && current_id==frame_invalid_id))begin
           pending_valid<=0;publish_pending<=0;
         end
       end
     end
   end
 end
endmodule
