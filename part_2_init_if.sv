/* verilator lint_off WIDTH */
/* verilator lint_off UNUSED */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNOPTFLAT */
/* verilator lint_off IMPLICIT */
/* verilator lint_off MULTIDRIVEN */
`include "../../include/cs_common.svh"
interface part_2_init_if (
                           input   clk_i,     //  utility clock
		                   input   clk_0_h,	 //  mission/functional clocks	      
		                   input   clk_1_h,	 //	      
		                   input   clk_2_h,	 //	      
		                   input   clk_3_h,   //
		      
		                   output  freeze_clk, // block/release mission
                                              // clock generator, if 
                                              // data is not received
		      		  
		                   input wen0,             // signals exported to target
		                   input [7:0] i_data0,    //
		      
		                   input wen1,             //
		                   input [7:0] i_data1,    //
		      
		                   input wen2,             //
		                   input [7:0] i_data2,    //
		      
		                   output valid,           //  imported from target
		                   output [7:0] o_data     //
		                 );
		      
parameter N = 9;
parameter wait_event = 0;
parameter send_vector = 1;
parameter  check_lut = 2;
parameter   empty_state = 3;
		      
bit        valid;
bit  [7:0] o_data;
bit  [8:0] joined_rcv_data[3:0];
bit  [3:0] rcv_valid;
bit  [3:0] freeze_clk = 0;
bit  [8:0] joined_sut_data[3:0];
string     source;      // will use later to compare   
string     event_name;  // will use later to compare 
integer    event_no;
integer    watchdog;
reg   [1:0]     fsm_get;
reg        fsm_get_enable;

reg    clk_0_en = 1;
reg    clk_1_en = 0;
reg    clk_2_en = 0;
reg    clk_3_en = 0;

reg    get_run_en = 0;
reg    put_run_en = 1;
reg        clk_0_h_d;


   import shunt_dpi_pkg::*;
   shunt_fringe_if I_if; 
   bit 	   Result;
   cs_header_t      h;
   string  S;
   real    Temp;
   
   
   string 	target_db_name;  

   initial
     begin: registration
	longint Temp1;
	bit 	is_free_entry;
	int 	index;
	bit [7:0] data_in;
	
	$display("Initiator registration: START");
	//TCP INIT
	is_free_entry = 0;
	Result = I_if.set_iam("INITIATOR");
	Result = I_if.set_simid(`SIM_ID);
	Result = I_if.init_targets_db();
	//REGISTRATION
	I_if.Target.n_signals = 10;
	Result = I_if.print_targets_db();
	I_if.init_signals_db();
	I_if.print_signals_db();
	$display("i am : %s",I_if.who_iam());
	I_if.tcp_init();

	//Target registration
	index =  I_if.check_idle_entry_targets_db();
	//$display("i am : %s free_entry index=%0d ,",I_if.who_iam(),index);
	//if(is_free_entry && I_if.check_free_entry_targets_db()>=0)  
	//
	while(index >= 0)
	  begin
	     Result=0;
	     Result = I_if.initiator_registration(h);
	     if (Result) I_if.print_reg_header(h);
	     else begin
	        index = -1;
		$display("REGISTRATION ERROR : %s,",I_if.who_iam());
	     end
	     if(index>=0) index =  I_if.check_idle_entry_targets_db();
	     //
	  end // while (index >= 0)
	Result = I_if.print_targets_db();
	$display("Initiator registration: End");
	//
     end : registration
   
   
//----------------------------------------------------------
//  Export related partiotion inputs to target


// Every mission clock retreive data from target 
/* verilator lint_off COMBDLY */


always @(posedge clk_i) begin
   clk_0_h_d <= clk_0_h;
   fsm_get_enable <= clk_0_h & !clk_0_h_d;
   source <= "TARGET";
   event_name <= "data_clk_0";
   event_no <= I_if.get_index_by_name_signals_db(source,event_name);
   $display ("INITIATOR indexed clk_0 with %d", event_no);
   if (get_run_en)
     $display ("---------------TARGET CLK_0 clock is togling---------------");
end     


always @(posedge clk_i) begin
$display ("------------INITIATOR PROCEEDS ------event name %s fsm_get %h ", event_name,fsm_get); 
   case(fsm_get)
     wait_event :   begin
        watchdog <= 0;
        rcv_valid[event_no] <= 0;
        fsm_get <= fsm_get_enable & put_run_en ? send_vector :
                   fsm_get_enable & get_run_en ? check_lut   :	 fsm_get;	
     end				 
     send_vector :  begin
        $display ( "INITIATOR to TARGET  send data_clk_0 vector = %h", joined_sut_data[0]);
	put_data( event_no, event_name, source);
        fsm_get <= get_run_en ? check_lut   :	 wait_event;
     end           
     check_lut   :   begin
        I_if.fringe_get();
        if  (I_if.signals_db[event_no].data_valid) begin
           joined_rcv_data[event_no] <= I_if.data_payloads_db[event_no];
           rcv_valid[event_no] <= 1;
           I_if.signals_db[event_no].data_valid <= 0;
           fsm_get <=  wait_event; 
	   freeze_clk[event_no] <= 0;
           $display( "------------ INITIATOR got data = %h from %s clocked with %s", joined_rcv_data[event_no], source, event_name);                                         
        end
        else  begin  
	   freeze_clk[event_no] <= 1;
           if (watchdog > 10000) begin
              $display ("watchdog error");
              $finish;
           end
           else begin
              watchdog<=watchdog+1;
	      $display ("----------INITIATOR STILL WAITING TRANSACTION ---- watchdog counter = %d", watchdog);
	      // $finish;
           end	
           fsm_get <= check_lut;
        end // else: !if(I_if.signals_db[event_no].data_valid)
     end // case: check_lut
  
endcase
  
end
//----------------------------------------------------------


// on the edge of utility clock build array for further export to target
always @(posedge clk_i)
   begin
    joined_sut_data[0]  = {wen0, i_data0};
    joined_sut_data[1]  = {wen1, i_data1};
    joined_sut_data[2]  = {wen2, i_data2};
    joined_sut_data[2]  = 0;
   end

//...extract partial signal values from received array(s)
always @(posedge clk_i)
    {valid, o_data} = rcv_valid[3] ? joined_rcv_data[3] :  {valid, o_data};                                    



//==============================================================
 /*
   task get_data (input string     source,      // will use later to compare   
                  input string     event_name,  // will use later to compare 
		              input integer    event_no);
   
   bit error = 0;
   integer watchdog = 0;
   rcv_valid[event_no] = 0;
   
   forever
     begin
         fringe_get();                
         if  (I_if.signals_db[event_no].data_valid)	begin
             I_if.signals_db[event_no].data_valid = 1'b1;
             joined_rcv_data[event_no] = I_if.data_payloads[event_no];
             rcv_valid[event_no] = 1;
             break;
         end else
         begin
            if (watchdog > 100) begin
                $display ("watchdog error");
                $finish;
            end
            watchdog++;   
            @(posedge  clk_i);
        end 
     end
     $display( "Get data = %h from %s clocked with %s", joined_rcv_data[event_no], source, event_name);
    endtask
   */            
//=============================================================================
 /* verilator lint_off VARHIDDEN */
 
   task put_data ( 
                   input int      event_no,
		   input string   event_name,
		   input string   destination
                   );
      string 			  s_me = "put_data()";
      
      $display ("%s data= %h to %s.%s event_no = %0d data_payloads_db[%0d]",s_me,joined_sut_data[event_no], destination, event_name, event_no,I_if.get_index_by_name_signals_db(destination,event_name));
      
      if (I_if.get_index_by_name_signals_db(destination,event_name) >= 0)
	begin
	   I_if.data_payloads_db[I_if.get_index_by_name_signals_db(destination,event_name)] = joined_sut_data[event_no];
	   I_if.fringe_put ( destination, event_name);
	   $display ("%s data = %h to %s clocked with %s event_no=%0d",s_me,joined_sut_data[event_no], destination, event_name, event_no );	           
	end
      else $display ("ERROR: %s data= %h to %s.%s event_no = %0d data_payloads_db[%0d]",s_me,joined_sut_data[event_no], destination, event_name, event_no,I_if.get_index_by_name_signals_db(destination,event_name));
   endtask : put_data
   
   //==============================================================
   /*
    task wait_clk_i(input integer clock_num, input integer current_cnt);
    forever
    if (current_cnt + clock_num > i_clk_cnt)
    break;
    
    endtask: wait_clk_i
    */		 		      		      
   
		      
endinterface : part_2_init_if
