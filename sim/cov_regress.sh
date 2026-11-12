[200~#!/bin/bash



# ============================================================

# RISC-V UVM Coverage Regression

# Runs multiple random seeds with coverage enabled

# Creates one VDB per seed and then merges them

# ============================================================



NUM_SEEDS=${1:-20}



CM="line+cond+fsm+tgl+branch"



COV_DIR="seed_cov"

MERGED_DIR="merged.vdb"

REPORT_DIR="cov_urg_report"



PASS=0

FAIL=0

FAILED_SEEDS=""



echo "=========================================="

echo " RISC-V COVERAGE REGRESSION"

echo " Seeds : $NUM_SEEDS"

echo " Coverage : $CM"

echo "=========================================="



# ------------------------------------------------------------

# Clean previous coverage results

# ------------------------------------------------------------



rm -rf "$COV_DIR"

rm -rf "$MERGED_DIR"

rm -rf "$REPORT_DIR"



mkdir -p "$COV_DIR"



# ------------------------------------------------------------

# Run each seed

# ------------------------------------------------------------



for seed in $(seq 1 $NUM_SEEDS); do
	
	
	
	    VDB="$COV_DIR/seed_${seed}.vdb"
	    
	        LOG="cov_seed${seed}.log"
		
		
		
		    echo ""
		    
		        echo "------------------------------------------"
			
			    echo " Running seed $seed"
			    
			        echo " VDB : $VDB"
				
				    echo " LOG : $LOG"
				    
				        echo "------------------------------------------"
					
					
					
					    # IMPORTANT:
					    
					        # Keep the complete ./simv command on ONE LINE.
						
						    ./simv +UVM_TESTNAME=riscv_random_test +ntb_random_seed=$seed -cm "$CM" -cm_dir "$VDB" -l "$LOG"
						    
						    
						    
						        # --------------------------------------------------------
							
							    # Check scoreboard
							    
							        # --------------------------------------------------------
								
								
								
								    sb_fail=$(grep "SCOREBOARD SUMMARY" "$LOG" 2>/dev/null | \
									    
									                  grep -o "[0-9]* FAIL" | \
											  
											                grep -o "[0-9]*" | \
													
													              tail -1)
													
													
													
													    sb_pass=$(grep "SCOREBOARD SUMMARY" "$LOG" 2>/dev/null | \
														    
														                  grep -o "[0-9]* PASS" | \
																  
																                grep -o "[0-9]*" | \
																		
																		              tail -1)
																		
																		
																		
																		    # --------------------------------------------------------
																		    
																		        # Check UVM errors
																			
																			    # --------------------------------------------------------
																			    
																			    
																			    
																			        uvm_err=$(grep "^UVM_ERROR" "$LOG" 2>/dev/null | \
																					
																					              grep -o "[0-9]*" | \
																						      
																						                    head -1)
																						      
																						      
																						      
																						          # Default values if information was not found
																							  
																							      sb_fail=${sb_fail:-99}
																							      
																							          sb_pass=${sb_pass:-0}
																								  
																								      uvm_err=${uvm_err:-99}
																								      
																								      
																								      
																								          # --------------------------------------------------------
																									  
																									      # PASS / FAIL result
																									      
																									          # --------------------------------------------------------
																										  
																										  
																										  
																										      if [ "$sb_fail" = "0" ] && [ "$uvm_err" = "0" ]; then
																											      
																											      
																											      
																											              echo "    Seed $seed : PASS"
																												      
																												              echo "    Scoreboard : $sb_pass PASS / $sb_fail FAIL"
																													      
																													              echo "    UVM_ERROR  : $uvm_err"
																														      
																														      
																														      
																														              PASS=$((PASS+1))
																															      
																															      
																															      
																															          else
																																	  
																																	  
																																	  
																																	          echo "    Seed $seed : FAIL"
																																		  
																																		          echo "    Scoreboard : $sb_pass PASS / $sb_fail FAIL"
																																			  
																																			          echo "    UVM_ERROR  : $uvm_err"
																																				  
																																				  
																																				  
																																				          FAIL=$((FAIL+1))
																																					  
																																					          FAILED_SEEDS="$FAILED_SEEDS $seed"
																																						  
																																						  
																																						  
																																						      fi
																																						      
																																						      
																																						      
																																						          # --------------------------------------------------------
																																							  
																																							      # Check that coverage VDB was actually created
																																							      
																																							          # --------------------------------------------------------
																																								  
																																								  
																																								  
																																								      if [ -d "$VDB" ]; then
																																									      
																																									              echo "    Coverage VDB : CREATED"
																																										      
																																										          else
																																												  
																																												          echo "    Coverage VDB : NOT CREATED"
																																													  
																																													      fi
																																													      
																																													      
																																													      
																																												      done
																																												      
																																												      
																																												      
																																												      # ============================================================
																																												      
																																												      # Regression summary
																																												      
																																												      # ============================================================
																																												      
																																												      
																																												      
																																												      echo ""
																																												      
																																												      echo "=========================================="
																																												      
																																												      echo " REGRESSION RESULT"
																																												      
																																												      echo "=========================================="
																																												      
																																												      
																																												      
																																												      echo " Passed : $PASS"
																																												      
																																												      echo " Failed : $FAIL"
																																												      
																																												      echo " Total  : $NUM_SEEDS"
																																												      
																																												      
																																												      
																																												      if [ $FAIL -gt 0 ]; then
																																													      
																																													          echo ""
																																														  
																																														      echo " Failed seeds:$FAILED_SEEDS"
																																														      
																																														      fi
																																														      
																																														      
																																														      
																																														      echo "=========================================="
																																														      
																																														      
																																														      
																																														      # ============================================================
																																														      
																																														      # Collect all VDBs
																																														      
																																														      # ============================================================
																																														      
																																														      
																																														      
																																														      echo ""
																																														      
																																														      echo "=========================================="
																																														      
																																														      echo " COLLECTING COVERAGE DATABASES"
																																														      
																																														      echo "=========================================="
																																														      
																																														      
																																														      
																																														      VDB_LIST=""
																																														      
																																														      
																																														      
																																														      for seed in $(seq 1 $NUM_SEEDS); do
																																															      
																																															      
																																															      
																																															          VDB="$COV_DIR/seed_${seed}.vdb"
																																																  
																																																  
																																																  
																																																      if [ -d "$VDB" ]; then
																																																	      
																																																	              echo "Found : $VDB"
																																																		      
																																																		              VDB_LIST="$VDB_LIST $VDB"
																																																			      
																																																			          else
																																																					  
																																																					          echo "Missing : $VDB"
																																																						  
																																																						      fi
																																																						      
																																																						      
																																																						      
																																																					      done
																																																					      
																																																					      
																																																					      
																																																					      # ------------------------------------------------------------
																																																					      
																																																					      # Check if at least one VDB exists
																																																					      
																																																					      # ------------------------------------------------------------
																																																					      
																																																					      
																																																					      
																																																					      if [ -z "$VDB_LIST" ]; then
																																																						      
																																																						      
																																																						      
																																																						          echo ""
																																																							  
																																																							      echo "ERROR: No coverage databases found."
																																																							      
																																																							          echo "Coverage merge cannot continue."
																																																								  
																																																								  
																																																								  
																																																								      exit 1
																																																								      
																																																								      
																																																								      
																																																								      fi
																																																								      
																																																								      
																																																								      
																																																								      # ============================================================
																																																								      
																																																								      # Merge coverage databases
																																																								      
																																																								      # ============================================================
																																																								      
																																																								      
																																																								      
																																																								      echo ""
																																																								      
																																																								      echo "=========================================="
																																																								      
																																																								      echo " MERGING COVERAGE DATABASES"
																																																								      
																																																								      echo "=========================================="
																																																								      
																																																								      
																																																								      
																																																								      urg -full64 \
																																																									      
																																																									          -dir $VDB_LIST \
																																																										  
																																																										      -dbname "$MERGED_DIR" \
																																																										      
																																																										          -noreport
																																																										      
																																																										      
																																																										      
																																																										      if [ $? -ne 0 ]; then
																																																											      
																																																											      
																																																											      
																																																											          echo ""
																																																												  
																																																												      echo "ERROR: Coverage database merge failed."
																																																												      
																																																												      
																																																												      
																																																												          exit 1
																																																													  
																																																													  
																																																													  
																																																													  fi
																																																													  
																																																													  
																																																													  
																																																													  echo ""
																																																													  
																																																													  echo "Merged coverage database created:"
																																																													  
																																																													  echo "    $MERGED_DIR"
																																																													  
																																																													  
																																																													  
																																																													  # ============================================================
																																																													  
																																																													  # Generate URG report
																																																													  
																																																													  # ============================================================
																																																													  
																																																													  
																																																													  
																																																													  echo ""
																																																													  
																																																													  echo "=========================================="
																																																													  
																																																													  echo " GENERATING COVERAGE REPORT"
																																																													  
																																																													  echo "=========================================="
																																																													  
																																																													  
																																																													  
																																																													  urg -full64 \
																																																														  
																																																														      -dir "$MERGED_DIR" \
																																																														      
																																																														          -report "$REPORT_DIR" \
																																																															  
																																																															      -format both
																																																															  
																																																															  
																																																															  
																																																															  if [ $? -ne 0 ]; then
																																																																  
																																																																  
																																																																  
																																																																      echo ""
																																																																      
																																																																          echo "ERROR: URG report generation failed."
																																																																	  
																																																																	  
																																																																	  
																																																																	      exit 1
																																																																	      
																																																																	      
																																																																	      
																																																																	      fi
																																																																	      
																																																																	      
																																																																	      
																																																																	      # ============================================================
																																																																	      
																																																																	      # Final result
																																																																	      
																																																																	      # ============================================================
																																																																	      
																																																																	      
																																																																	      
																																																																	      echo ""
																																																																	      
																																																																	      echo "=========================================="
																																																																	      
																																																																	      echo " COVERAGE REGRESSION COMPLETE"
																																																																	      
																																																																	      echo "=========================================="
																																																																	      
																																																																	      
																																																																	      
																																																																	      echo "Passed seeds : $PASS"
																																																																	      
																																																																	      echo "Failed seeds : $FAIL"
																																																																	      
																																																																	      echo ""
																																																																	      
																																																																	      echo "Merged VDB   : $MERGED_DIR"
																																																																	      
																																																																	      echo "Report       : $REPORT_DIR/dashboard.html"
																																																																	      
																																																																	      
																																																																	      
																																																																	      echo "=========================================="=
