#!/bin/bash



# ============================================================

# RISC-V UVM Normal Regression

# PASS/FAIL checking only

# Coverage is handled separately by cov_regress.sh

# ============================================================



NUM_SEEDS=${1:-20}

TEST=${2:-riscv_random_test}     # e.g. ./regress.sh 50 riscv_full_random_test



PASS=0

FAIL=0

FAILED_SEEDS=""



echo "=========================================="

echo " RISC-V RANDOM REGRESSION"

echo " Test  : $TEST"

echo " Seeds : $NUM_SEEDS"

echo "=========================================="



# ------------------------------------------------------------

# Run each random seed

# ------------------------------------------------------------



for seed in $(seq 1 $NUM_SEEDS); do



    LOG="run_seed${seed}.log"



    echo ""

    echo "------------------------------------------"

    echo " Running seed $seed"

    echo " Log : $LOG"

    echo "------------------------------------------"



    # IMPORTANT:

    # No -cm and no -cm_dir here.

    # This is normal functional regression only.



    ./simv +UVM_TESTNAME=$TEST +ntb_random_seed=$seed -no_save -l "$LOG"



    # --------------------------------------------------------

    # Extract scoreboard result

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

    # Extract UVM_ERROR count

    # --------------------------------------------------------



    uvm_err=$(grep "^UVM_ERROR" "$LOG" 2>/dev/null | \

              grep -o "[0-9]*" | \

              head -1)



    # Default values if nothing was found

    sb_fail=${sb_fail:-99}

    sb_pass=${sb_pass:-0}

    uvm_err=${uvm_err:-99}



    # --------------------------------------------------------

    # PASS / FAIL

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



done



# ============================================================

# Final regression summary

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



# ------------------------------------------------------------

# Exit with failure status if any seed failed

# ------------------------------------------------------------



if [ $FAIL -gt 0 ]; then

    exit 1

else

    exit 0

fi
